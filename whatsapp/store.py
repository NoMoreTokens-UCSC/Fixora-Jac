"""MongoDB communication records. Cases and evidence use the existing Jac store."""
from contextlib import contextmanager
from datetime import datetime, timezone
import time
from uuid import uuid4

from pymongo import MongoClient, ReturnDocument

from .transport import ChannelError, request_id


def stamp():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class Store:
    def __init__(self, settings, database=None):
        self.settings = settings
        self.client = None
        if database is None:
            self.client = MongoClient(settings.mongodb_uri, serverSelectionTimeoutMS=10000,
                                      connectTimeoutMS=10000, socketTimeoutMS=15000, appname="fixora-whatsapp")
            database = self.client[settings.database]
        self.db = database
        self.db.wa_inbox.create_index([("status", 1), ("received_at", 1)])
        self.db.wa_inbox.create_index([("conversation_id", 1), ("received_at", 1)])
        self.db.wa_jobs.create_index([("status", 1), ("created_at", 1)])
        self.db.wa_outbox.create_index([("status", 1), ("created_at", 1)])
        self.db.wa_outbox.create_index("provider_id", sparse=True)
        self.db.wa_outbox.create_index("case_id")
        self.db.cases.create_index([("shop_id", 1), ("sender_id", 1)])
        self.db.wa_chat_messages.create_index([("conversation_id", 1), ("at", 1)])
        self.db.wa_chat_messages.create_index("publication_pending")

    def conversation_id(self, sender):
        return f"{self.settings.shop_id}:{self.settings.phone_number_id}:{sender}"

    def conversation(self, sender):
        key = self.conversation_id(sender)
        self.db.wa_conversations.update_one({"_id": key}, {"$setOnInsert": {
            "sender_id": sender, "shop_id": self.settings.shop_id, "active_case_id": None,
            "pending_media": [], "last_inbound_at": 0, "notifications_opt_in": False,
            "opted_out": False, "created_at": stamp(), "lease_until": 0,
        }}, upsert=True)
        return self.db.wa_conversations.find_one({"_id": key})

    @contextmanager
    def lock(self, conversation_id):
        token = uuid4().hex
        locked = self.db.wa_conversations.find_one_and_update(
            {"_id": conversation_id, "lease_until": {"$lte": time.time()}},
            {"$set": {"lease_token": token, "lease_until": time.time() + self.settings.lease_seconds}},
            return_document=ReturnDocument.AFTER,
        )
        if locked is None:
            raise ChannelError("CONVERSATION_BUSY", "This conversation is being processed. Please wait and refresh.")
        try:
            yield locked
        finally:
            self.db.wa_conversations.update_one({"_id": conversation_id, "lease_token": token},
                                                  {"$set": {"lease_until": 0}, "$unset": {"lease_token": ""}})

    def renew(self, conversation_id, token):
        result = self.db.wa_conversations.update_one({"_id": conversation_id, "lease_token": token},
                         {"$set": {"lease_until": time.time() + self.settings.lease_seconds}})
        if result.matched_count != 1:
            raise ChannelError("LEASE_LOST", "Processing was interrupted. Please retry.")

    def case(self, case_id, sender=None):
        query = {"_id": case_id, "shop_id": self.settings.shop_id, "channel": "whatsapp"}
        if sender is not None:
            query["sender_id"] = sender
        item = self.db.cases.find_one(query)
        if item is None:
            raise ChannelError("NOT_FOUND", "That case could not be found for this customer.")
        return item

    def check_revision(self, case, expected):
        if case["revision"] != expected:
            raise ChannelError("STALE_REVISION", "This case changed. Refresh it before saving.")
        if case.get("stage_lease") and case["stage_lease"]["expires_at"] > stamp():
            raise ChannelError("STAGE_BUSY", "A specialist is running. Please wait and refresh.")

    def message(self, case_id, key, role, text, internal=False):
        message_id = request_id(f"{case_id}:{key}:{role}")
        self.db.cases.update_one({"_id": case_id, "shop_id": self.settings.shop_id,
                                  "messages.id": {"$ne": message_id}}, {"$push": {"messages": {
            "id": message_id, "role": role, "text": text[:4000], "internal": internal,
            "at": stamp(), "publication_pending": role != "customer" and not internal,
        }}, "$set": {"updated_at": stamp()}})
        return message_id

    def publish(self):
        # Publication is recoverable without a cross-document transaction: the embedded
        # message is authoritative and the outbox uses its stable unique ID.
        for case in self.db.cases.find({"shop_id": self.settings.shop_id, "channel": "whatsapp",
                                       "messages.publication_pending": True}):
            for position, message in enumerate(case.get("messages", [])):
                if not message.get("publication_pending"):
                    continue
                if not message.get("internal") and message["role"] != "customer":
                    self.db.wa_outbox.update_one({"_id": message["id"]}, {"$setOnInsert": {
                        "case_id": case["_id"], "conversation_id": self.conversation_id(case["sender_id"]),
                        "sender_id": case["sender_id"], "text": message["text"], "status": "queued",
                        "created_at": message["at"], "position": position, "attempts": 0,
                    }}, upsert=True)
                self.db.cases.update_one({"_id": case["_id"], "messages.id": message["id"]},
                    {"$set": {"messages.$.publication_pending": False}})
        for message in self.db.wa_chat_messages.find({"shop_id": self.settings.shop_id, "publication_pending": True}):
            if not message.get("internal") and message["role"] != "customer":
                self.db.wa_outbox.update_one({"_id": message["_id"]}, {"$setOnInsert": {
                    "conversation_id": message["conversation_id"], "sender_id": message["sender_id"],
                    "text": message["text"], "status": "queued", "created_at": message["at"],
                    "position": 0, "attempts": 0,
                }}, upsert=True)
            self.db.wa_chat_messages.update_one({"_id": message["_id"]}, {"$set": {"publication_pending": False}})

    def chat_message(self, conversation, key, role, text, input_kind="text", internal=False):
        mid = request_id(f"chat:{conversation['_id']}:{key}:{role}")
        current = self.db.wa_conversations.find_one_and_update({"_id": conversation["_id"]},
            {"$inc": {"chat_sequence": 1}}, return_document=ReturnDocument.AFTER)
        self.db.wa_chat_messages.update_one({"_id": mid}, {"$setOnInsert": {
            "shop_id": self.settings.shop_id, "conversation_id": conversation["_id"],
            "sender_id": conversation["sender_id"], "role": role, "text": text[:4000],
            "input_kind": input_kind, "internal": internal, "at": stamp(),
            "sequence": current["chat_sequence"],
            "publication_pending": role != "customer" and not internal,
        }}, upsert=True)
        return mid

    def chat_history(self, conversation_id, limit=30):
        rows = list(self.db.wa_chat_messages.find({"conversation_id": conversation_id,
            "shop_id": self.settings.shop_id}).sort([("at", -1), ("sequence", -1)]).limit(limit))
        return list(reversed(rows))

    def ingest(self, payload):
        if payload.get("object") != "whatsapp_business_account":
            raise ChannelError("INVALID_WEBHOOK", "Expected a WhatsApp Business webhook.")
        for entry in payload.get("entry", []):
            for change in entry.get("changes", []):
                if change.get("field") != "messages":
                    continue
                value = change.get("value", {})
                if str(value.get("metadata", {}).get("phone_number_id", "")) != self.settings.phone_number_id:
                    continue
                names = {contact["wa_id"]: contact.get("profile", {}).get("name", "Customer")
                         for contact in value.get("contacts", []) if "wa_id" in contact}
                for message in value.get("messages", []):
                    sender, mid = message.get("from"), message.get("id")
                    if not isinstance(sender, str) or not isinstance(mid, str) or not sender or not mid:
                        raise ChannelError("INVALID_WEBHOOK", "Message sender and ID are required.")
                    conversation = self.conversation(sender)
                    try:
                        inbound_at = min(time.time(), float(message.get("timestamp", time.time())))
                    except (ValueError, TypeError):
                        raise ChannelError("INVALID_WEBHOOK", "Invalid message timestamp.") from None
                    self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {
                        "$max": {"last_inbound_at": inbound_at}, "$set": {"customer_name": names.get(sender, "Customer")}})
                    self.db.wa_inbox.update_one({"_id": request_id(self.settings.phone_number_id + ":" + mid)}, {
                        "$setOnInsert": {"message_id": mid, "sender_id": sender,
                            "conversation_id": conversation["_id"], "payload": message,
                            "kind": "message", "status": "queued", "received_at": stamp(), "lease_until": 0}}, upsert=True)
                    self.db.wa_outbox.update_many({"conversation_id": conversation["_id"],
                        "status": {"$in": ["pending_window", "awaiting_reply"]}}, {"$set": {"status": "queued"}})
                for status in value.get("statuses", []):
                    identity = ":".join(str(status.get(k, "")) for k in ("id", "status", "timestamp"))
                    self.db.wa_inbox.update_one({"_id": request_id("status:" + identity)}, {"$setOnInsert": {
                        "kind": "status", "payload": status, "status": "queued", "received_at": stamp(), "lease_until": 0}}, upsert=True)

    def enqueue_assessment(self, case, key, retry=False):
        job_id = request_id(f"assessment:{case['_id']}:{key}")
        self.db.wa_jobs.update_one({"_id": job_id}, {"$setOnInsert": {
            "case_id": case["_id"], "sender_id": case["sender_id"],
            "conversation_id": self.conversation_id(case["sender_id"]), "input_revision": case["revision"],
            "retry": retry, "status": "queued", "created_at": stamp(), "lease_until": 0,
        }}, upsert=True)
        return job_id

    def claim(self, collection, key):
        return collection.find_one_and_update({"_id": key, "$or": [
            {"status": "queued"}, {"status": "processing", "lease_until": {"$lte": time.time()}}]},
            {"$set": {"status": "processing", "lease_until": time.time() + self.settings.lease_seconds}},
            return_document=ReturnDocument.AFTER)

    def products(self):
        return [{"id": p["_id"], "name": p["display_name"], "code": p["model_code"]}
                for p in self.db.products.find({})]
