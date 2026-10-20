"""Transport/worker integration tests; no Meta or model requests are made."""
import base64
import copy
import hashlib
import hmac
import json
import time
import sys
from types import SimpleNamespace
from uuid import uuid4

import httpx
import mongomock
import pytest
from fastapi.testclient import TestClient

from whatsapp.app import create_apps
from whatsapp.config import Settings
from whatsapp.service import Service
from whatsapp.store import Store, stamp
from whatsapp.transport import ChannelError, IntakeModel, IntakeResult, JacClient, MetaClient, Transcriber, request_id
from whatsapp.views import case_view
from whatsapp.worker import Worker


class FakeJac:
    """Only the Jac HTTP boundary is simulated; the real worker and Mongo flow run."""
    def __init__(self, store):
        self.store, self.db = store, store.db
        self.calls = []
        self.failure = False
        self.block = False

    def call(self, operation, **p):
        self.calls.append(operation)
        if operation == "create_case":
            row = self.db.cases.find_one({"submission_id": p["submission_id"]})
            if not row:
                row = {"_id": uuid4().hex, "shop_id": self.store.settings.shop_id, "submission_id": p["submission_id"],
                    "description": p["description"], "claimed_model_id": "", "status": "draft", "revision": 0,
                    "created_at": stamp(), "updated_at": stamp(), "evidence_ids": [], "assessment": None,
                    "active_assessment_id": None, "stage_lease": None, "assessment_number": 0}
                self.db.cases.insert_one(copy.deepcopy(row))
            return {"case": {"id": row["_id"]}}
        row = self.db.cases.find_one({"_id": p["case_id"]})
        self.store.check_revision(row, p.get("expected_revision", row["revision"]))
        updates = {}
        if operation == "update_case":
            updates = {"description": p["description"], "claimed_model_id": p["claimed_model_id"],
                       "status": "draft", "assessment": None, "review_status": "unreviewed"}
        elif operation == "upload_evidence":
            old = self.db.evidence.find_one({"case_id": row["_id"], "request_id": p["request_id"]})
            if old:
                return {"case": {"id": row["_id"]}}
            n = self.db.evidence.count_documents({"case_id": row["_id"], "kind": p["kind"]})
            if n >= (1 if p["kind"] == "invoice" else 3):
                raise ChannelError("VALIDATION_ERROR", "Evidence limit reached.")
            eid = uuid4().hex
            self.db.evidence.insert_one({"_id": eid, "case_id": row["_id"], "request_id": p["request_id"],
                "filename": p["filename"], "kind": p["kind"], "mime_type": "image/png", "size_bytes": 32})
            updates = {"evidence_ids": row["evidence_ids"] + [eid], "status": "draft", "assessment": None}
        elif operation == "start_assessment":
            aid = uuid4().hex
            updates = {"status": "processing", "active_assessment_id": aid, "assessment": {
                "_id": aid, "request_id": p["request_id"], "next_stage": 0, "stages": {}}}
        elif operation == "advance_case":
            names = ["document", "vision", "coverage", "repair_parts", "resolution"]
            assessment = row["assessment"]
            stage = names[assessment["next_stage"]]
            if self.failure:
                updates = {"status": "failed"}
            elif self.block:
                updates = {"status": "needs_inspection"}
            else:
                values = {
                    "document": {"invoice": {"invoice_number": "INV-123", "model_code": "FD-100", "amount_minor": 89900, "currency": "USD"}, "analysis_mode": "live_model"},
                    "vision": {"observations": [{"description": "Visible screen crack"}]},
                    "coverage": {"coverage": {"outcome": "potentially_covered", "explanation": "Saved policy result."}},
                    "repair_parts": {"options": [{"title": "Screen repair", "availability": "in_stock", "explanation": "Saved catalogue match", "parts": [
                        {"sku": "S-1", "quantity_available": 4, "unit_price_minor": 1500}],
                        "estimate": {"currency": "USD", "parts_cost_minor": 1500, "labour_cost_minor": 350, "total_cost_minor": 1850}}]},
                    "resolution": {"report": {"headline": "Provisional repair assessment ready"}},
                }
                assessment["stages"][stage] = {"status": "completed", "findings": values[stage]}
                assessment["next_stage"] += 1
                updates = {"assessment": assessment, "status": "completed" if assessment["next_stage"] == 5 else "processing"}
        elif operation == "remove_evidence":
            updates = {"evidence_ids": [e for e in row["evidence_ids"] if e != p["evidence_id"]], "status": "draft", "assessment": None}
        else:
            raise AssertionError(operation)
        self.db.cases.update_one({"_id": row["_id"]}, {"$set": {**updates, "updated_at": stamp()}, "$inc": {"revision": 1}})
        return {"case": {"id": row["_id"]}}


class FakeMeta:
    def __init__(self):
        self.sent = []
        self.downloads = []
        self.error = None

    def download(self, media_id):
        self.downloads.append(media_id)
        return "image/png", base64.b64encode(b"synthetic image").decode()

    def send(self, recipient, text=None, template=False):
        self.sent.append((recipient, text, template))
        if self.error:
            raise self.error
        return "wamid.out." + str(len(self.sent))


class FakeIntake:
    def __init__(self):
        self.failed = False

    def parse(self, text, case, products, history, catalogue=None):
        if self.failed:
            raise ChannelError("INTAKE_FAILED", "Please RETRY; your message is saved.")
        return IntakeResult(description=text, model_id="demo-laptop-01")


@pytest.fixture
def env():
    settings = Settings(mongodb_uri="mongodb://localhost", app_secret="synthetic-app-secret", verify_token="synthetic-verify",
        access_token="synthetic-fixora-token", owner_password="synthetic-owner-password", phone_number_id="12345",
        graph_version="v26.0", whatsapp_token="synthetic-meta-token")
    store = Store(settings, mongomock.MongoClient().fixora_test)
    store.db.products.insert_one({"_id": "demo-laptop-01", "display_name": "Demo Laptop", "model_code": "FD-100"})
    jac, meta, intake = FakeJac(store), FakeMeta(), FakeIntake()
    service = Service(store, jac, meta, intake)
    return settings, store, service, Worker(service)


def webhook(mid="in-1", sender="94770000001", text="My screen is cracked", kind="text", **media):
    content = {"body": text} if kind == "text" else {"id": "456", "mime_type": "image/png", **media}
    return {"object": "whatsapp_business_account", "entry": [{"changes": [{"field": "messages", "value": {
        "metadata": {"phone_number_id": "12345"}, "contacts": [{"wa_id": sender, "profile": {"name": "Test customer"}}],
        "messages": [{"from": sender, "id": mid, "timestamp": str(int(time.time())), "type": kind, kind: content}]}}]}]}


def incoming(env, mid, text="", kind="text", sender="94770000001", **media):
    _, store, _, worker = env
    store.ingest(webhook(mid, sender, text, kind, **media))
    assert worker.work("wa_inbox")
    conversation = store.conversation(sender)
    return store.case(conversation["active_case_id"])


def complete_inputs(env):
    incoming(env, "issue", "My screen is cracked")
    incoming(env, "invoice", kind="image", caption="INVOICE")
    return incoming(env, "device", kind="image", caption="DEVICE")


def test_webhook_signature_challenge_dedup_and_public_boundary(env):
    settings, store, service, _ = env
    public, owner = create_apps(settings, store, service)
    with TestClient(public) as client:
        assert client.get("/webhooks/whatsapp", params={"hub.mode": "subscribe", "hub.verify_token": settings.verify_token, "hub.challenge": "42"}).text == "42"
        assert client.get("/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=wrong").status_code == 403
        data = json.dumps(webhook()).encode()
        assert client.post("/webhooks/whatsapp", content=data).status_code == 403
        signature = "sha256=" + hmac.new(settings.app_secret.encode(), data, hashlib.sha256).hexdigest()
        for _ in range(2):
            assert client.post("/webhooks/whatsapp", content=data, headers={"X-Hub-Signature-256": signature}).status_code == 200
        assert store.db.wa_inbox.count_documents({}) == 1
        assert store.db.cases.count_documents({}) == 0  # no agent work in HTTP request
        assert client.get("/owner/cases").status_code == 404
        assert client.get("/docs").status_code == 404


def test_webhook_never_acknowledges_failed_storage(env, monkeypatch):
    settings, store, service, _ = env
    public, _ = create_apps(settings, store, service)
    def unavailable(payload):
        raise RuntimeError("synthetic database failure")
    monkeypatch.setattr(store, "ingest", unavailable)
    data = json.dumps(webhook()).encode()
    signature = "sha256=" + hmac.new(settings.app_secret.encode(), data, hashlib.sha256).hexdigest()
    with TestClient(public) as client:
        assert client.post("/webhooks/whatsapp", content=data, headers={"X-Hub-Signature-256": signature}).status_code == 503


def test_owner_session_origin_cookie_and_logout(env):
    settings, store, service, _ = env
    _, owner = create_apps(settings, store, service)
    headers = {"Origin": "http://localhost:8000"}
    with TestClient(owner, base_url="http://localhost:8011") as client:
        assert client.get("/owner/cases").status_code == 401
        assert client.post("/owner/login", json={"password": settings.owner_password}).status_code == 403
        assert client.post("/owner/login", json={"password": "wrong"}, headers=headers).status_code == 401
        response = client.post("/owner/login", json={"password": settings.owner_password}, headers=headers)
        assert response.status_code == 200
        assert "HttpOnly" in response.headers["set-cookie"]
        assert "SameSite=strict" in response.headers["set-cookie"]
        assert client.get("/owner/cases").json() == {"cases": []}
        assert client.post("/owner/logout", json={}, headers={"Origin": "https://untrusted.example"}).status_code == 403
        assert client.post("/owner/logout", json={}, headers=headers).status_code == 200
        assert client.get("/owner/cases").status_code == 401


def test_intake_evidence_labels_confirmation_and_background_assessment(env):
    _, store, service, worker = env
    case = incoming(env, "issue", "My screen is cracked")
    incoming(env, "early-ready", "READY")
    assert store.db.wa_jobs.count_documents({}) == 0
    incoming(env, "unlabelled", kind="image")
    assert not service.meta.downloads
    incoming(env, "label", "INVOICE")
    case = incoming(env, "photo", kind="image", caption="DEVICE")
    assert len(case["evidence_ids"]) == 2
    assert store.db.wa_jobs.count_documents({}) == 0
    case = incoming(env, "ready", "READY")
    assert store.db.wa_jobs.count_documents({"status": "queued"}) == 1
    assert worker.work("wa_jobs")
    case = store.case(case["_id"])
    assert case["status"] == "completed"
    assert service.jac.calls.count("advance_case") == 5
    view = case_view(store, case)
    assert view["status"] == "awaiting_approval"
    assert view["findings"]["invoice"] == "INV-123"
    assert view["availability"]["labour_minor"] == 350
    assert "USD 18.50" in view["findings"]["next_action"]
    assert view["findings"]["invoice_total"] == "USD 899.00"
    assert all(not e["preview"] for e in view["evidence"])
    store.publish()
    while worker.deliver():
        pass
    assert any("shop must review" in text.lower() for _, text, _ in service.meta.sent)


def test_replayed_event_does_not_duplicate_case_message_or_upload(env):
    _, store, service, worker = env
    case = complete_inputs(env)
    event = store.db.wa_inbox.find_one({"message_id": "device"})
    store.db.wa_inbox.update_one({"_id": event["_id"]}, {"$set": {"status": "processing", "lease_until": 0}})
    restarted = Worker(Service(store, service.jac, service.meta, service.intake))
    assert restarted.work("wa_inbox")
    assert store.db.evidence.count_documents({"case_id": case["_id"]}) == 2
    assert len(service.meta.downloads) == 2
    messages = store.case(case["_id"])["messages"]
    assert len({m["id"] for m in messages}) == len(messages)


def test_conversation_lock_serializes_workers_and_expired_work_recovers(env):
    _, store, _, worker = env
    store.ingest(webhook())
    conversation = store.conversation("94770000001")
    with store.lock(conversation["_id"]):
        assert not worker.work("wa_inbox")
        with pytest.raises(ChannelError, match="being processed"):
            with store.lock(conversation["_id"]):
                pass
    assert worker.work("wa_inbox")


def test_customer_cannot_open_or_list_another_customers_case(env):
    _, store, _, _ = env
    first = incoming(env, "first", "Private first complaint")
    second = incoming(env, "second", "Different issue", sender="94770000002")
    incoming(env, "attempt", "OPEN " + first["_id"], sender="94770000002")
    assert store.conversation("94770000002")["active_case_id"] == second["_id"]
    second = incoming(env, "list", "CASES", sender="94770000002")
    reply = second["messages"][-1]["text"]
    assert first["_id"] not in reply
    assert "Private first complaint" not in reply


def test_provider_failure_is_persisted_and_explicit_retry_reprocesses(env):
    _, store, service, worker = env
    service.intake.failed = True
    store.ingest(webhook("failure", text="The hinge is loose"))
    worker.work("wa_inbox")
    assert store.db.wa_inbox.find_one({"message_id": "failure"})["status"] == "failed"
    assert store.db.cases.count_documents({}) == 0  # Failed routing must not create a warranty case.
    assert "hinge is loose" in " ".join(m["text"] for m in store.db.wa_chat_messages.find({}))
    service.intake.failed = False
    case = incoming(env, "retry", "RETRY")
    assert case["description"] == "The hinge is loose"
    assert store.db.wa_inbox.find_one({"message_id": "failure"})["status"] == "done"


def test_assessment_failure_stops_and_explicit_retry_resumes(env):
    _, store, service, worker = env
    complete_inputs(env)
    service.jac.failure = True
    case = incoming(env, "ready", "READY")
    worker.work("wa_jobs")
    assert store.case(case["_id"])["status"] == "failed"
    assert service.jac.calls.count("advance_case") == 1
    service.jac.failure = False
    incoming(env, "retry", "RETRY")
    worker.work("wa_jobs")
    assert store.case(case["_id"])["status"] == "completed"


def test_inspection_blocks_workflow_without_guessing_a_fault(env):
    _, store, service, worker = env
    complete_inputs(env)
    service.jac.block = True
    case = incoming(env, "ready", "READY")
    worker.work("wa_jobs")
    assert store.case(case["_id"])["status"] == "needs_inspection"
    assert service.jac.calls.count("advance_case") == 1
    assert "inspect" in store.case(case["_id"])["messages"][-1]["text"]


def test_new_inputs_supersede_a_queued_assessment(env):
    _, store, service, worker = env
    complete_inputs(env)
    case = incoming(env, "ready", "READY")
    incoming(env, "correction", "Actually the hinge is damaged")
    worker.work("wa_jobs")
    assert service.jac.calls.count("advance_case") == 0
    assert store.db.wa_jobs.find_one({"case_id": case["_id"]})["error"] == "STALE_REVISION"


@pytest.mark.parametrize("kind,mime", [("video", "video/mp4"), ("document", "application/pdf")])
def test_unsupported_media_does_not_reach_model_or_agent(env, kind, mime):
    _, store, service, worker = env
    store.ingest(webhook("unsupported", kind=kind, mime_type=mime))
    worker.work("wa_inbox")
    assert not service.meta.downloads
    assert store.db.cases.count_documents({}) == 0
    assert "not supported" in store.db.wa_chat_messages.find_one({"role": "assistant"})["text"]


def test_internal_notes_never_enter_outbox_and_publication_recovers(env):
    _, store, _, _ = env
    case = incoming(env, "issue", "Visible damage")
    private_id = store.message(case["_id"], "private", "shop", "Internal diagnostic note", internal=True)
    public_id = store.message(case["_id"], "public", "shop", "Please visit the shop")
    store.publish()
    store.publish()
    assert store.db.wa_outbox.count_documents({"_id": public_id}) == 1
    assert not store.db.wa_outbox.find_one({"_id": private_id})


def test_window_expiry_withholds_text_and_new_customer_message_releases_it(env):
    _, store, service, worker = env
    case = incoming(env, "issue", "Visible damage")
    conversation = store.conversation(case["sender_id"])
    store.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {"last_inbound_at": time.time() - 90000}})
    store.publish()
    while worker.deliver():
        pass
    assert service.meta.sent == []
    assert store.db.wa_outbox.count_documents({"status": "pending_window"}) > 0
    incoming(env, "reopen-window", "STATUS")
    store.publish()
    worker.deliver()
    assert service.meta.sent


def test_approved_template_requires_opt_in_and_does_not_publish_withheld_text(env):
    settings, store, service, worker = env
    object.__setattr__(settings, "template_name", "case_update_ready")
    case = incoming(env, "issue", "Visible damage")
    incoming(env, "opt-in", "UPDATES")
    conversation = store.conversation(case["sender_id"])
    store.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {"last_inbound_at": time.time() - 90000}})
    store.publish()
    while worker.deliver():
        pass
    assert len(service.meta.sent) == 1
    assert service.meta.sent[0][2] is True
    assert store.db.wa_outbox.count_documents({"status": "awaiting_reply"}) == 1
    assert store.db.wa_outbox.count_documents({"status": "sent"}) == 0


def test_opt_out_cancels_automation_until_explicit_start(env):
    _, store, service, worker = env
    incoming(env, "issue", "Visible damage")
    incoming(env, "stop", "STOP")
    while worker.deliver():
        pass
    assert len(service.meta.sent) == 1
    assert "stopped" in service.meta.sent[0][1]
    incoming(env, "ignored", "More details")
    store.publish()
    worker.deliver()
    assert len(service.meta.sent) == 1
    incoming(env, "resume", "START")
    store.publish()
    worker.deliver()
    assert len(service.meta.sent) == 2


def test_uncertain_delivery_is_not_automatically_resent(env):
    _, store, service, worker = env
    incoming(env, "issue", "Visible damage")
    store.publish()
    service.meta.error = httpx.ReadTimeout("synthetic timeout")
    worker.deliver()
    assert store.db.wa_outbox.count_documents({"status": "uncertain"}) == 1
    # Other distinct queued messages can still send; this uncertain message cannot.
    row = store.db.wa_outbox.find_one({"status": "uncertain"})
    worker.deliver()
    assert store.db.wa_outbox.find_one({"_id": row["_id"]})["attempts"] == 1


def test_delivery_receipts_do_not_regress_read_to_sent(env):
    _, store, _, worker = env
    incoming(env, "issue", "Visible damage")
    store.publish()
    worker.deliver()
    row = store.db.wa_outbox.find_one({"status": "sent"})
    for name in ("read", "sent", "failed"):
        worker.delivery_status({"payload": {"id": row["provider_id"], "status": name}})
    assert store.db.wa_outbox.find_one({"_id": row["_id"]})["status"] == "read"


@pytest.mark.parametrize("metadata", [
    {"url": "http://127.0.0.1/private", "mime_type": "image/png"},
    {"url": "https://untrusted.example/file", "mime_type": "image/png"},
    {"url": "https://lookaside.fbsbx.com/file", "mime_type": "application/pdf"},
    {"url": "https://lookaside.fbsbx.com/file", "mime_type": "image/png", "file_size": 5242881},
])
def test_media_download_rejects_untrusted_urls_and_unsupported_files(env, metadata):
    settings, _, _, _ = env
    requests = []
    def handler(request):
        requests.append(request)
        return httpx.Response(200, json=metadata)
    meta = MetaClient(settings, httpx.Client(transport=httpx.MockTransport(handler)))
    with pytest.raises(ChannelError):
        meta.download("123")
    assert len(requests) == 1


def test_jac_client_unwraps_actual_http_envelope_and_hides_secrets(env):
    settings, _, _, _ = env
    def handler(request):
        assert json.loads(request.content)["access_token"] == settings.access_token
        return httpx.Response(200, json={"ok": True, "data": {"result": {"ok": True, "data": {"case": {"id": "example"}}}}})
    client = JacClient(settings, httpx.Client(transport=httpx.MockTransport(handler)))
    assert client.call("get_case", case_id="example")["case"]["id"] == "example"
    client.client = httpx.Client(transport=httpx.MockTransport(lambda req: httpx.Response(500, text="synthetic-secret")))
    with pytest.raises(ChannelError) as error:
        client.call("get_case", case_id="example")
    assert "synthetic-secret" not in str(error.value)


def test_natural_intake_validates_the_real_structured_model_boundary(env, monkeypatch):
    settings, store, _, _ = env
    object.__setattr__(settings, "model", "synthetic/test-model")
    seen = []
    def completion(**kwargs):
        seen.append(kwargs)
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps({
            "intent": "details", "description": "Screen is cracked", "model_id": "demo-laptop-01", "evidence_kind": ""})))])
    monkeypatch.setitem(sys.modules, "litellm", SimpleNamespace(completion=completion))
    result = IntakeModel(settings).parse("Screen cracked, FD-100", {}, store.products(), [])
    assert result.model_id == "demo-laptop-01"
    assert seen[0]["response_format"] == {"type": "json_object"}
    assert "Never diagnose" in seen[0]["messages"][0]["content"]


@pytest.mark.parametrize("output", ['{"model_id":"invented-model"}', '{"intent":"approve"}', '{"description":{"$ne":null}}', 'invalid-json'])
def test_invalid_intake_output_cannot_change_cases(env, monkeypatch, output):
    settings, store, _, _ = env
    object.__setattr__(settings, "model", "synthetic/test-model")
    monkeypatch.setitem(sys.modules, "litellm", SimpleNamespace(completion=lambda **kw: SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(content=output))])))
    with pytest.raises(ChannelError) as error:
        IntakeModel(settings).parse("message", {}, store.products(), [])
    assert error.value.code == "INTAKE_FAILED"
    assert store.db.cases.count_documents({}) == 0


def test_first_new_command_creates_only_one_case(env):
    _, store, _, _ = env
    incoming(env, "first-new", "NEW")
    assert store.db.cases.count_documents({}) == 1


def test_outgoing_delivery_waits_for_the_conversation_lock(env):
    _, store, service, worker = env
    case = incoming(env, "issue", "Visible damage")
    store.publish()
    with store.lock(store.conversation_id(case["sender_id"])):
        assert not worker.deliver()
    assert not service.meta.sent
    assert worker.deliver()


def test_partial_assessment_resumes_after_a_worker_restart(env):
    _, store, service, worker = env
    complete_inputs(env)
    case = incoming(env, "ready", "READY")
    job = store.db.wa_jobs.find_one({"case_id": case["_id"]})
    service.jac.call("start_assessment", case_id=case["_id"], expected_revision=case["revision"], request_id=request_id("start:" + job["_id"]))
    case = store.case(case["_id"])
    store.db.wa_jobs.update_one({"_id": job["_id"]}, {"$set": {"assessment_id": case["active_assessment_id"], "status": "processing", "lease_until": 0}})
    for _ in range(2):
        case = store.case(case["_id"])
        service.jac.call("advance_case", case_id=case["_id"], expected_revision=case["revision"], assessment_id=case["active_assessment_id"], request_id=uuid4().hex)
    restarted = Worker(Service(store, service.jac, service.meta, service.intake))
    assert restarted.work("wa_jobs")
    assert store.case(case["_id"])["status"] == "completed"
    assert service.jac.calls.count("start_assessment") == 1
    assert service.jac.calls.count("advance_case") == 5
