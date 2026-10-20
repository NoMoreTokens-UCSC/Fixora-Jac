"""Real MongoDB + Jac HTTP verification with synthetic transport/model fixtures.

Run from the project root: python scripts/verify-whatsapp.py
Creates and removes its own temporary database. Never contacts Meta or a model.
"""
import base64
from dataclasses import replace
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time
from uuid import uuid4

import httpx
from fastapi.testclient import TestClient
from pymongo.errors import OperationFailure

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from whatsapp.app import create_apps
from whatsapp.config import Settings
from whatsapp.service import Service
from whatsapp.store import Store
from whatsapp.transport import IntakeResult, JacClient
from whatsapp.worker import Worker


class FixtureTransport:
    def __init__(self):
        self.images, self.sent = {}, []

    def download(self, media_id):
        return "image/png", base64.b64encode(self.images[media_id].read_bytes()).decode()

    def send(self, recipient, text=None, template=False):
        self.sent.append(text)
        return "synthetic-outgoing-" + str(len(self.sent))

    def download_audio(self, media_id):
        return "audio/ogg", b"OggS synthetic verifier audio"


class FixtureTranscriber:
    def transcribe(self, mime, content):
        return "Catalogue accessory"


class FixtureIntake:
    def parse(self, text, case, products, history, catalogue=None):
        selected = {"Catalogue product": "products:demo-laptop-01", "Catalogue part": "inventory:demo-stock-1-keyboard",
                    "Catalogue accessory": "inventory:demo-accessory-mouse"}
        if text in selected:
            return IntakeResult(intent="catalogue", catalogue_ids=[selected[text]])
        return IntakeResult(description=text, model_id="demo-laptop-01")


def cleanup_database(client, name):
    if not re.fullmatch(r"fixora_wa_verify_[a-f0-9]{16}", name):
        raise RuntimeError("Refusing to clean a database not owned by this verifier.")
    database = client[name]
    for collection in database.list_collection_names():
        try:
            database.drop_collection(collection)
        except OperationFailure:
            # Some managed MongoDB services permit document deletion but not DDL.
            database[collection].delete_many({})


def main():
    os.chdir(ROOT)
    original = Settings.load()
    if not original.mongodb_uri:
        raise SystemExit("Configure MongoDB before running this local integration check.")
    database_name = "fixora_wa_verify_" + uuid4().hex[:16]
    # Replace a previous success immediately and record the owned temporary name,
    # so an interrupted run can be identified and cleaned up without guessing.
    Path(".jac").mkdir(exist_ok=True)
    Path(".jac/whatsapp-verification.json").write_text(json.dumps({
        "passed": False, "status": "running", "temporary_database": database_name,
        "meta_transport": "synthetic", "voice_transcription": "synthetic"}, indent=2) + "\n")
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    settings = replace(original, database=database_name, jac_url=f"http://127.0.0.1:{port}",
        access_token="synthetic-whatsapp-check-token", owner_password="synthetic-local-owner-password",
        app_secret="synthetic-signing-secret", verify_token="synthetic-verify", phone_number_id="12345",
        whatsapp_token="", model="", model_key="")
    environment = {**os.environ, "FIXORA_MONGODB_URI": settings.mongodb_uri, "MONGODB_DB": database_name,
        "FIXORA_ACCESS_TOKEN": settings.access_token, "FIXORA_DEMO_MODE": "true"}
    environment.pop("MONGODB_URI", None)
    Path(".jac").mkdir(exist_ok=True)
    store = Store(settings)
    store.db.command("ping")
    log = open(".jac/whatsapp-integration.log", "w")
    process = None
    summary = None

    def start():
        proc = subprocess.Popen(["bash", "scripts/jac.sh", "start", "main.jac", "--no-client", "--no-dev", "-p", str(port)],
            env=environment, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
        for _ in range(90):
            if proc.poll() is not None:
                raise RuntimeError("Jac startup failed; see .jac/whatsapp-integration.log.")
            try:
                response = httpx.get(f"{settings.jac_url}/openapi.json", timeout=2, trust_env=False)
                if response.status_code == 200:
                    return proc
            except httpx.HTTPError:
                pass
            time.sleep(1)
        stop(proc)
        raise RuntimeError("Jac startup timed out; see .jac/whatsapp-integration.log.")

    def stop(proc):
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)

    try:
        seeded = subprocess.run(["bash", "scripts/jac.sh", "run", "data/seed.jac"], env=environment,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=90)
        if seeded.returncode:
            raise RuntimeError("Catalogue seed failed; see .jac/whatsapp-integration.log.")
        process = start()
        transport = FixtureTransport()
        service = Service(store, JacClient(settings), transport, FixtureIntake(), FixtureTranscriber())
        worker = Worker(service)
        public, owner = create_apps(settings, store, service)
        outcomes = []
        saved_id = ""
        with TestClient(public) as webhooks, TestClient(owner, base_url="http://localhost:8011") as dashboard:
            headers = {"Origin": "http://localhost:8000"}
            assert dashboard.post("/owner/login", json={"password": settings.owner_password}, headers=headers).status_code == 200
            scenarios = json.loads(Path("fixtures/scenarios.json").read_text())
            for index, scenario in enumerate(scenarios):
                sender = "9477000000" + str(index)

                def incoming(key, text="", media=None, audio=False):
                    msg = {"id": key, "from": sender, "timestamp": str(int(time.time())), "type": "audio" if audio else "image" if media else "text"}
                    msg[msg["type"]] = {"id": "999", "mime_type": "audio/ogg"} if audio else {"id": media, "caption": text, "mime_type": "image/png"} if media else {"body": text}
                    payload = {"object": "whatsapp_business_account", "entry": [{"changes": [{"field": "messages", "value": {
                        "metadata": {"phone_number_id": settings.phone_number_id}, "messages": [msg]}}]}]}
                    body = json.dumps(payload).encode()
                    signature = "sha256=" + hmac.new(settings.app_secret.encode(), body, hashlib.sha256).hexdigest()
                    assert webhooks.post("/webhooks/whatsapp", content=body, headers={"X-Hub-Signature-256": signature}).status_code == 200
                    assert worker.work("wa_inbox")

                incoming(scenario["id"] + "-issue", scenario["description"])
                for ordinal, kind in enumerate(("invoice", "product")):
                    mid = str(index * 10 + ordinal + 1)
                    transport.images[mid] = ROOT / "fixtures" / scenario[kind]
                    incoming(scenario["id"] + "-" + kind, "INVOICE" if kind == "invoice" else "DEVICE", mid)
                incoming(scenario["id"] + "-ready", "READY")
                assert worker.work("wa_jobs")
                case = store.case(store.conversation(sender)["active_case_id"])
                assert case["status"] == scenario["expected_status"], "Unexpected case state: " + case["status"]
                view = dashboard.get("/owner/cases/" + case["_id"]).json()["case"]
                assert len(view["evidence"]) == 2
                image = dashboard.get(f"/owner/cases/{case['_id']}/evidence/{view['evidence'][0]['id']}")
                assert image.status_code == 200 and image.headers["content-type"] == "image/png"
                if case["status"] == "completed":
                    saved_id = case["_id"]
                    assert view["status"] == "awaiting_approval"
                    assert view["coverage"] == scenario["expected_coverage"]
                    assert "26500.00" in view["findings"]["next_action"]
                    note = dashboard.post(f"/owner/cases/{saved_id}/note", json={"expected_revision": case["revision"],
                        "request_id": uuid4().hex, "text": "Private verification note"}, headers=headers)
                    assert note.status_code == 200
                    decision = dashboard.post(f"/owner/cases/{saved_id}/review", json={"expected_revision": case["revision"],
                        "request_id": uuid4().hex, "action": "rejected", "reason": "Saved policy shows the warranty period has expired; paid repair remains available."}, headers=headers)
                    assert decision.status_code == 200 and decision.json()["case"]["status"] == "rejected"
                    stale = dashboard.post(f"/owner/cases/{saved_id}/review", json={"expected_revision": case["revision"],
                        "request_id": uuid4().hex, "action": "approved", "reason": "Stale review"}, headers=headers)
                    assert stale.status_code == 409
                outcomes.append({"scenario": scenario["id"], "status": case["status"]})
                print(scenario["id"] + ": " + case["status"], flush=True)
            sender = "94770000099"
            incoming("shopping-product", "Catalogue product")
            incoming("shopping-part", "Catalogue part")
            incoming("shopping-voice", audio=True)
            shopping_conversation = store.conversation(sender)
            assert shopping_conversation["active_case_id"] is None
            assert store.db.wa_inbox.find_one({"message_id": "shopping-voice"})["transcript"] == "Catalogue accessory"
            chats = dashboard.get("/owner/conversations").json()["conversations"]
            shop_chat = next(c for c in chats if c["sender_id"] == sender)
            assert any(m["input_kind"] == "audio" for m in shop_chat["messages"])
            assert any("189,900.00" in m["text"] for m in shop_chat["messages"])
            assert any("9,500.00" in m["text"] for m in shop_chat["messages"])
            assert any("USB Mouse" in m["text"] for m in shop_chat["messages"])
            assert len(dashboard.get("/owner/catalogue").json()["items"]) == 13
            print("Shopping products, parts and voice accessories: saved without a repair case", flush=True)
            store.publish()
            while worker.deliver():
                pass
            assert transport.sent and not any("Private verification note" in text for text in transport.sent)
            assert len(dashboard.get("/owner/cases").json()["cases"]) == 3
        stop(process)
        process = start()
        restored = service.jac.call("get_case", case_id=saved_id)["case"]
        assert restored["review_status"] == "rejected" and len(restored["decisions"]) == 1
        summary = {"passed": True, "scenarios": outcomes, "restart_persistence": True,
                   "owner_review": True, "private_notes": True, "shopping_enquiries": True,
                   "voice_transcription": "synthetic", "meta_transport": "synthetic", "model": "recorded fixtures"}
    finally:
        stop(process)
        log.close()
        # This randomly named database is owned exclusively by this verification run.
        try:
            cleanup_database(store.client, database_name)
        finally:
            store.client.close()
    if summary:
        summary["temporary_records_removed"] = True
        Path(".jac/whatsapp-verification.json").write_text(json.dumps(summary, indent=2) + "\n")
        print("Owner review, evidence access, private notes, outbound queue and restart persistence passed; temporary records removed.", flush=True)


if __name__ == "__main__":
    main()
