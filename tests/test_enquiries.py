"""Voice and shopping integration, with HTTP/model providers simulated explicitly."""
from dataclasses import replace
import json
from types import SimpleNamespace
import sys

import httpx
import pytest
from fastapi.testclient import TestClient

from test_whatsapp import env, incoming, webhook
from whatsapp.app import create_apps
from whatsapp.service import Service
from whatsapp.transport import ChannelError, IntakeModel, IntakeResult, MetaClient, Transcriber
from whatsapp.worker import Worker


def shopping(env, monkeypatch, ids):
    _, store, service, _ = env
    store.db.products.update_one({"_id": "demo-laptop-01"}, {"$set": {
        "quantity_available": 2, "unit_price_minor": 18990000, "currency": "LKR", "synthetic": True}})
    store.db.inventory.insert_many([
        {"_id": "keyboard", "sku": "KEY-100", "part_type": "keyboard", "compatible_model_ids": ["demo-laptop-01"],
         "quantity_available": 0, "unit_price_minor": 950000, "currency": "LKR"},
        {"_id": "mouse", "sku": "USB-MOUSE", "category": "accessory", "display_name": "USB mouse",
         "quantity_available": 6, "unit_price_minor": 250000, "currency": "LKR"}])
    seen = []
    def parse(text, case, products, history, catalogue=None):
        seen.append({"text": text, "history": history, "catalogue": catalogue})
        return IntakeResult(intent="catalogue", catalogue_ids=ids)
    monkeypatch.setattr(service.intake, "parse", parse)
    return seen


def receive(env, mid, text="", kind="text"):
    _, store, _, worker = env
    store.ingest(webhook(mid, text=text, kind=kind))
    assert worker.work("wa_inbox")
    store.publish()


@pytest.mark.parametrize("ids,expected", [
    (["products:demo-laptop-01"], ["In stock (2 available)", "LKR 189,900.00", "DEMO DATA"]),
    (["inventory:keyboard"], ["Out of stock", "LKR 9,500.00", "FD-100"]),
    (["inventory:mouse"], ["USB mouse", "LKR 2,500.00", "In stock (6 available)"]),
])
def test_shopping_answers_saved_product_part_and_accessory_facts_without_case(env, monkeypatch, ids, expected):
    shopping(env, monkeypatch, ids)
    receive(env, "buy", "Do you have this item and how much is it?")
    _, store, service, worker = env
    answer = store.db.wa_chat_messages.find_one({"role": "assistant"})["text"]
    assert all(value in answer for value in expected)
    assert store.db.cases.count_documents({}) == 0
    assert not service.jac.calls
    assert worker.deliver()
    assert service.meta.sent[0][1] == answer


def test_ambiguous_unknown_and_missing_catalogue_facts_are_not_invented(env, monkeypatch):
    shopping(env, monkeypatch, [])
    _, store, service, _ = env
    assert "Which product" in service.catalogue.answer([])
    assert "exact catalogue match" in service.catalogue.answer(["inventory:invented"])
    store.db.inventory.update_one({"_id": "mouse"}, {"$unset": {"quantity_available": "", "unit_price_minor": ""}})
    answer = service.catalogue.answer(["inventory:keyboard", "inventory:mouse"])
    assert "Which model or SKU" in answer
    assert "Stock not confirmed" in answer and "Price not confirmed" in answer
    assert store.db.inventory.find_one({"_id": "keyboard"})["quantity_available"] == 0
    store.db.inventory.update_one({"_id": "mouse"}, {"$set": {"retail_enabled": False}})
    assert "USB mouse" not in service.catalogue.answer(["inventory:mouse"])


def test_shopping_during_repair_does_not_modify_case_or_start_assessment(env, monkeypatch):
    case = incoming(env, "repair", "Screen cracked")
    env[1].publish()
    case = env[1].case(case["_id"])
    shopping(env, monkeypatch, ["inventory:mouse"])
    receive(env, "shop", "How much is a mouse?")
    _, store, _, _ = env
    assert store.case(case["_id"]) == case
    assert store.db.wa_jobs.count_documents({}) == 0


def test_shopping_reloads_changed_stock_and_keeps_private_and_other_sender_history_out_of_model(env, monkeypatch):
    seen = shopping(env, monkeypatch, ["inventory:mouse"])
    _, store, service, _ = env
    own = store.conversation("94770000001")
    other = store.conversation("94770000002")
    store.chat_message(own, "private", "shop", "Secret wholesale cost", internal=True)
    store.chat_message(other, "other", "customer", "Other customer's private details")
    original = service.intake.parse
    def parse(*args, **kwargs):
        result = original(*args, **kwargs)
        store.db.inventory.update_one({"_id": "mouse"}, {"$set": {"quantity_available": 0}})
        return result
    monkeypatch.setattr(service.intake, "parse", parse)
    receive(env, "query", "Is the mouse available?")
    assert "Secret wholesale" not in json.dumps(seen)
    assert "Other customer's" not in json.dumps(seen)
    assert "Out of stock" in store.db.wa_chat_messages.find_one({"role": "assistant"})["text"]


class Voice:
    def __init__(self, text="Is the FD-100 in stock and how much?"):
        self.calls, self.text, self.failed = 0, text, False

    def transcribe(self, mime, content):
        self.calls += 1
        if self.failed:
            raise ChannelError("TRANSCRIPTION_FAILED", "Could not transcribe. Reply RETRY or type your question.")
        return self.text


def voice(env, monkeypatch, transcript=None):
    _, _, service, _ = env
    transcription = Voice() if transcript is None else Voice(transcript)
    downloads = []
    def download(mid):
        downloads.append(mid)
        return "audio/ogg", b"OggS synthetic fixture"
    monkeypatch.setattr(service.meta, "download_audio", download, raising=False)
    service.transcriber = transcription
    return transcription, downloads


def test_voice_transcript_is_cached_across_model_failure_restart_and_duplicate_webhook(env, monkeypatch):
    seen = shopping(env, monkeypatch, ["products:demo-laptop-01"])
    transcriber, downloads = voice(env, monkeypatch)
    _, store, service, worker = env
    good_parse = service.intake.parse
    monkeypatch.setattr(service.intake, "parse", lambda *a, **kw: (_ for _ in ()).throw(ChannelError("INTAKE_FAILED", "Reply RETRY")))
    receive(env, "voice", kind="audio")
    assert store.db.wa_inbox.find_one({"message_id": "voice"})["transcript"] == transcriber.text
    assert store.db.cases.count_documents({}) == 0
    monkeypatch.setattr(service.intake, "parse", good_parse)
    restarted = Worker(Service(store, service.jac, service.meta, service.intake, transcriber))
    store.ingest(webhook("retry-voice", text="RETRY"))
    restarted.work("wa_inbox")
    store.ingest(webhook("voice", kind="audio"))
    assert not restarted.work("wa_inbox")
    assert transcriber.calls == 1 and len(downloads) == 1
    assert seen[0]["text"] == transcriber.text
    assert store.db.wa_inbox.find_one({"message_id": "voice"})["status"] == "done"
    assert store.db.wa_chat_messages.count_documents({"role": "customer", "input_kind": "audio"}) == 1
    store.publish()
    assert store.db.wa_outbox.count_documents({"text": {"$regex": "Current catalogue"}}) == 1


def test_transcription_failure_is_saved_and_explicitly_retryable(env, monkeypatch):
    shopping(env, monkeypatch, ["inventory:mouse"])
    transcriber, downloads = voice(env, monkeypatch)
    transcriber.failed = True
    receive(env, "bad-voice", kind="audio")
    _, store, _, _ = env
    assert store.db.wa_inbox.find_one({"message_id": "bad-voice"})["error"] == "TRANSCRIPTION_FAILED"
    transcriber.failed = False
    receive(env, "retry", "RETRY")
    assert store.db.wa_inbox.find_one({"message_id": "bad-voice"})["status"] == "done"
    assert len(downloads) == 2


def test_voice_repair_intake_and_explicit_typed_confirmation(env, monkeypatch):
    _, store, _, _ = env
    voice(env, monkeypatch, "The screen is cracked")
    receive(env, "complaint", kind="audio")
    case = store.db.cases.find_one({})
    assert case["description"] == "The screen is cracked"
    assert any("[Voice transcript]" in m["text"] for m in case["messages"])
    voice(env, monkeypatch, "READY")
    receive(env, "spoken-ready", kind="audio")
    assert store.db.wa_jobs.count_documents({}) == 0
    assert store.db.wa_chat_messages.find_one({"text": {"$regex": "type that command"}})


def test_enquiry_opt_out_stops_transcription_and_does_not_create_case(env, monkeypatch):
    transcriber, downloads = voice(env, monkeypatch)
    receive(env, "stop", "STOP")
    receive(env, "ignored-voice", kind="audio")
    _, store, _, _ = env
    assert not downloads and transcriber.calls == 0
    assert store.db.cases.count_documents({}) == 0


def test_owner_can_read_enquiry_transcripts_and_message_but_private_notes_never_publish(env, monkeypatch):
    shopping(env, monkeypatch, ["inventory:mouse"])
    voice(env, monkeypatch)
    receive(env, "voice", kind="audio")
    settings, store, service, _ = env
    _, owner = create_apps(settings, store, service)
    with TestClient(owner) as client:
        assert client.get("/owner/conversations").status_code == 401
        assert client.get("/owner/catalogue").status_code == 401
        headers = {"Origin": "http://localhost:8000"}
        client.post("/owner/login", headers=headers, json={"password": settings.owner_password})
        rows = client.get("/owner/conversations").json()["conversations"]
        assert rows[0]["messages"][0]["input_kind"] == "audio"
        assert len(client.get("/owner/catalogue").json()["items"]) == 3
        path = "/owner/conversations/" + rows[0]["id"] + "/messages"
        for private in (True, False):
            response = client.post(path, headers=headers, json={"request_id": "private-note" if private else "public-reply", "text": "Private cost notes" if private else "Please visit our shop", "internal": private})
            assert response.status_code == 200
        assert not store.db.wa_outbox.find_one({"text": "Private cost notes"})
        assert store.db.wa_outbox.count_documents({"text": "Please visit our shop"}) == 1
        assert client.post(path, headers=headers, json={"request_id": "public-reply", "text": "Please visit our shop"}).status_code == 200
        assert store.db.wa_outbox.count_documents({"text": "Please visit our shop"}) == 1


def test_audio_download_validates_meta_url_mime_and_stream_limit(env):
    settings, _, _, _ = env
    requests = []
    def handler(request):
        requests.append(request)
        if request.url.host == "graph.facebook.com":
            return httpx.Response(200, json={"url": "https://lookaside.fbsbx.com/audio", "mime_type": "audio/ogg; codecs=opus", "file_size": 6})
        return httpx.Response(200, content=b"OggSxx")
    meta = MetaClient(settings, httpx.Client(transport=httpx.MockTransport(handler)))
    assert meta.download_audio("123") == ("audio/ogg", b"OggSxx")
    assert len(requests) == 2
    with pytest.raises(ChannelError):
        meta.download("123")  # Audio must never enter the evidence-image path.
    def oversized(request):
        if request.url.host == "graph.facebook.com":
            return handler(request)
        return httpx.Response(200, content=b"x" * (16 * 1024 * 1024 + 1))
    meta.client = httpx.Client(transport=httpx.MockTransport(oversized))
    with pytest.raises(ChannelError, match="16 MB"):
        meta.download_audio("123")


@pytest.mark.parametrize("status,body", [(200, {"text": "Is FD-100 available?"}), (200, {"text": ""}), (500, {"error": "provider-secret"})])
def test_transcriber_real_multipart_boundary_and_safe_failures(env, status, body):
    settings, _, _, _ = env
    settings = replace(settings, transcription_key="synthetic-only")
    requests = []
    def handler(request):
        requests.append(request)
        assert request.url == "https://api.openai.com/v1/audio/transcriptions"
        assert b'filename="voice.ogg"' in request.content
        return httpx.Response(status, json=body)
    transcriber = Transcriber(settings, httpx.Client(transport=httpx.MockTransport(handler)))
    if status == 200 and body["text"]:
        assert transcriber.transcribe("audio/ogg", b"OggSxx") == body["text"]
    else:
        with pytest.raises(ChannelError) as error:
            transcriber.transcribe("audio/ogg", b"OggSxx")
        assert "provider-secret" not in str(error.value)
    with pytest.raises(ChannelError):
        transcriber.transcribe("audio/amr", b"unsupported")
    assert len(requests) == 1


def test_model_cannot_select_unknown_catalogue_ids_or_invent_prices(env, monkeypatch):
    settings, store, _, _ = env
    settings = replace(settings, model="synthetic/test-model")
    for content in ({"intent": "catalogue", "catalogue_ids": ["inventory:invented"]},
                    {"intent": "catalogue", "catalogue_ids": [], "price": 1}):
        monkeypatch.setitem(sys.modules, "litellm", SimpleNamespace(completion=lambda **kw: SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(content)))])))
        with pytest.raises(ChannelError):
            IntakeModel(settings).parse("Price?", {}, store.products(), [], catalogue=[])
