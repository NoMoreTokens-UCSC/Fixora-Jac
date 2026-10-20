"""Run with python -m whatsapp.worker. No in-memory background tasks are authoritative."""
import logging
import time

from .config import Settings
from .service import Service
from .store import Store, stamp
from .transport import ChannelError, IntakeModel, JacClient, MetaClient

log = logging.getLogger("fixora.worker")


class Worker:
    def __init__(self, service):
        self.service = service
        self.store, self.db = service.store, service.store.db

    def work(self, name):
        collection = self.db[name]
        candidates = collection.find({"$or": [{"status": "queued"},
            {"status": "processing", "lease_until": {"$lte": time.time()}}]}).sort(
                "received_at" if name == "wa_inbox" else "created_at", 1).limit(30)
        for candidate in candidates:
            if candidate.get("kind") == "status":
                claimed = self.store.claim(collection, candidate["_id"])
                if claimed:
                    self.delivery_status(claimed)
                    collection.update_one({"_id": claimed["_id"]}, {"$set": {"status": "done"}})
                    return True
                continue
            try:
                with self.store.lock(candidate["conversation_id"]) as conversation:
                    claimed = self.store.claim(collection, candidate["_id"])
                    if not claimed:
                        continue
                    try:
                        if name == "wa_inbox":
                            self.service.process_message(claimed, conversation)
                        else:
                            self.service.assess(claimed, conversation)
                        collection.update_one({"_id": claimed["_id"]}, {"$set": {"status": "done", "finished_at": stamp()}})
                    except Exception as error:
                        safe = error if isinstance(error, ChannelError) else ChannelError("PROCESSING_FAILED", "Processing was interrupted. Your information is saved. Reply RETRY or contact the shop.")
                        collection.update_one({"_id": claimed["_id"]}, {"$set": {
                            "status": "failed", "error": safe.code, "finished_at": stamp()}})
                        if name == "wa_inbox" and safe.code not in ("NOT_FOUND", "VALIDATION_ERROR", "INVALID_MEDIA"):
                            self.db.wa_conversations.update_one({"_id": conversation["_id"]},
                                                               {"$set": {"failed_event_id": claimed["_id"]}})
                        current = self.db.wa_conversations.find_one({"_id": conversation["_id"]})
                        if current.get("active_case_id"):
                            self.store.message(current["active_case_id"], "failure:" + claimed["_id"], "assistant", str(safe))
                        else:
                            self.store.chat_message(current, "failure:" + claimed["_id"], "assistant", str(safe))
                        log.warning("%s failed: %s", name, safe.code)
                    return True
            except ChannelError as error:
                if error.code != "CONVERSATION_BUSY":
                    raise
        return False

    def delivery_status(self, event):
        status = event["payload"]
        name = status.get("status")
        rank = {"sent": 1, "delivered": 2, "read": 3, "failed": 1}.get(name)
        if rank is None:
            return
        row = self.db.wa_outbox.find_one({"provider_id": status.get("id")})
        if row and rank >= row.get("delivery_rank", 0):
            self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {
                "delivery_rank": rank, "status": name, "delivery_updated_at": stamp()}})
        elif not row:
            # A template acknowledgement must not mark the withheld case update delivered.
            self.db.wa_outbox.update_one({"template_provider_id": status.get("id")},
                                        {"$set": {"template_delivery": name}})

    def deliver(self):
        # A process may have died after Meta accepted the POST but before saving its ID.
        self.db.wa_outbox.update_many({"status": "sending", "lease_until": {"$lte": time.time()}},
                                     {"$set": {"status": "uncertain", "error": "DELIVERY_UNCERTAIN"}})
        for candidate in self.db.wa_outbox.find({"status": "queued"}).sort([("created_at", 1), ("position", 1)]).limit(30):
            try:
                with self.store.lock(candidate["conversation_id"]) as conversation:
                    first = self.db.wa_outbox.find_one({"conversation_id": candidate["conversation_id"],
                        "status": {"$in": ["queued", "sending"]}}, sort=[("created_at", 1), ("position", 1)])
                    if first and first["_id"] != candidate["_id"]:
                        continue
                    return self.send_locked(candidate, conversation)
            except ChannelError as error:
                if error.code != "CONVERSATION_BUSY":
                    raise
        return False

    def send_locked(self, candidate, conversation):
        row = self.db.wa_outbox.find_one_and_update({"_id": candidate["_id"], "status": "queued"},
            {"$set": {"status": "sending", "lease_until": time.time() + 90}, "$inc": {"attempts": 1}},
            return_document=True)
        if not row:
            return False
        if not conversation or (conversation.get("opted_out") and not row.get("opt_out_ack")):
            self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {"status": "cancelled"}})
            return True
        in_window = time.time() - conversation.get("last_inbound_at", 0) < 86400
        template = not in_window and bool(self.store.settings.template_name) and conversation.get("notifications_opt_in", False)
        # One generic re-engagement template per customer service window, regardless
        # of how many pending owner updates there are. Never send the withheld text.
        if not in_window and (not template or conversation.get("template_window") == conversation.get("last_inbound_at")):
            self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {"status": "pending_window"}})
            return True
        try:
            if template:
                reserved = self.db.wa_conversations.update_one({"_id": conversation["_id"],
                    "template_window": {"$ne": conversation.get("last_inbound_at")}},
                    {"$set": {"template_window": conversation.get("last_inbound_at")}})
                if reserved.modified_count != 1:
                    self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {"status": "pending_window"}})
                    return True
            provider_id = self.service.meta.send(row["sender_id"], row["text"], template=bool(template))
            updates = {"status": "awaiting_reply", "template_provider_id": provider_id} if template else {
                "status": "sent", "provider_id": provider_id, "delivery_rank": 1}
            self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {**updates, "sent_at": stamp()}})
        except Exception as error:
            code = error.code if isinstance(error, ChannelError) else "DELIVERY_UNCERTAIN"
            status = "failed" if code == "DELIVERY_REJECTED" else "uncertain"
            self.db.wa_outbox.update_one({"_id": row["_id"]}, {"$set": {"status": status, "error": code}})
        return True

    def tick(self):
        worked = self.work("wa_inbox")
        self.store.publish()
        sent = self.deliver()
        assessed = self.work("wa_jobs")
        self.store.publish()
        return self.deliver() or worked or sent or assessed


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    settings = Settings.load()
    settings.require("worker")
    store = Store(settings)
    worker = Worker(Service(store, JacClient(settings), MetaClient(settings), IntakeModel(settings)))
    try:
        while True:
            try:
                if not worker.tick():
                    time.sleep(1)
            except KeyboardInterrupt:
                break
            except Exception:
                # Avoid credentials, provider bodies and customer evidence in logs.
                log.error("Worker dependency unavailable; retrying in five seconds.")
                time.sleep(5)
    finally:
        if store.client:
            store.client.close()


if __name__ == "__main__":
    main()
