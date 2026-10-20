import re

from .store import stamp
from .transport import ChannelError, IntakeResult, Transcriber, request_id
from .catalogue import Catalogue
from .views import customer_summary


HELP = ("Ask about product, spare part or accessory prices and stock by text or an English voice note (up to 16 MB). "
        "Include the model or SKU. Voice is transcribed; replies are text. To request repair, tell me what is wrong with your laptop. Send one invoice image and up to three device photos "
        "(JPEG/PNG, 5 MB each). Label them INVOICE or DEVICE. Reply READY when finished. "
        "Commands: STATUS, CASES, OPEN <case ID>, NEW, REMOVE <image ID>, RETRY, HELP. "
        "Reply UPDATES to allow later case notifications, or STOP to stop automated messages. "
        "You can contact the shop or visit it for human assistance. Messages, voice transcripts and evidence images are saved. Voice audio is sent to a transcription provider and is not stored by Fixora.")


class Service:
    def __init__(self, store, jac, meta, intake, transcriber=None):
        self.store, self.jac, self.meta, self.intake = store, jac, meta, intake
        self.db = store.db
        self.catalogue = Catalogue(store)
        self.transcriber = transcriber or Transcriber(store.settings)

    def current(self, conversation):
        cid = conversation.get("active_case_id")
        return self.store.case(cid, conversation["sender_id"]) if cid else None

    def create(self, conversation, key, description="Awaiting customer's complaint."):
        payload = self.jac.call("create_case", description=description,
                                submission_id=request_id("whatsapp-case:" + key))
        cid = payload["case"]["id"]
        self.db.cases.update_one({"_id": cid, "shop_id": self.store.settings.shop_id,
            "$or": [{"sender_id": {"$exists": False}}, {"sender_id": conversation["sender_id"]}]},
            {"$set": {"channel": "whatsapp", "sender_id": conversation["sender_id"],
                      "customer_name": conversation.get("customer_name", "Customer")}})
        case = self.store.case(cid, conversation["sender_id"])
        self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {"active_case_id": cid, "pending_media": []}})
        conversation["active_case_id"] = cid
        return case

    def respond(self, case, key, text):
        self.store.message(case["_id"], key, "assistant", text)

    def process_message(self, event, conversation):
        payload, key = event["payload"], event["_id"]
        kind = payload.get("type", "")
        text = payload.get("text", {}).get("body", "") if kind == "text" else payload.get(kind, {}).get("caption", "")
        text = str(text).strip()[:4000]
        command = text.upper()
        case = self.current(conversation)
        # Opt-out applies to transcription and inference too, not only delivery.
        if conversation.get("opted_out") and command not in ("START", "UPDATES", "STOP"):
            return
        if command == "RETRY" and conversation.get("failed_event_id"):
            failed = self.db.wa_inbox.find_one({"_id": conversation["failed_event_id"], "conversation_id": conversation["_id"]})
            if failed and failed["_id"] != key and (not failed.get("case_id") or (case and failed["case_id"] == case["_id"])):
                self.process_message(failed, conversation)
                self.db.wa_inbox.update_one({"_id": failed["_id"]}, {"$set": {"status": "done", "error": None}})
                self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$unset": {"failed_event_id": ""}})
                return
        if kind == "audio":
            text = event.get("transcript", "")
            if not text:
                mime, content = self.meta.download_audio(str(payload.get("audio", {}).get("id", "")))
                text = self.transcriber.transcribe(mime, content)
                # Cache before inference/replies: explicit retry and restart reuse the transcript.
                self.db.wa_inbox.update_one({"_id": key}, {"$set": {"transcript": text}})
                event["transcript"] = text
            self.store.chat_message(conversation, key, "customer", text, input_kind="audio")
            self.store.chat_message(conversation, "transcript:" + key, "assistant", 'I heard: "' + text[:3000] + '". Please type any correction, especially the model or SKU.')
            command = text.upper()
            if command in ("STOP", "START", "UPDATES", "NEW", "READY", "ASSESS", "RETRY") or command.startswith(("OPEN ", "REMOVE ")):
                self.store.chat_message(conversation, key, "assistant", "Please type that command to confirm it. Voice recognition can mishear case changes.")
                return
        if kind not in ("text", "audio", "image", "document") or (kind == "document" and payload.get("document", {}).get("mime_type") not in ("image/jpeg", "image/png")):
            self.store.chat_message(conversation, key, "customer", "[" + kind + " attachment]")
            self.store.chat_message(conversation, key, "assistant", "Please send text, an English voice note (up to 16 MB), or a JPEG/PNG image (up to 5 MB). PDFs and videos are not supported.")
            return
        # Classify natural text before opening a warranty case. The model can only
        # select catalogue IDs; shopping replies are rendered from fresh Mongo facts.
        controls = {"STOP", "START", "UPDATES", "NEW", "CASES", "HELP", "STATUS", "RETRY", "READY", "ASSESS", "INVOICE", "DEVICE", "PHOTO", "PRODUCT"}
        if text and command not in controls and not command.startswith(("OPEN ", "REMOVE ")):
            self.store.chat_message(conversation, key, "customer", text, input_kind=kind)
            if event.get("intake"):
                route = IntakeResult.model_validate(event["intake"])
            else:
                history = self.store.chat_history(conversation["_id"], 8)
                history += [m for m in (case or {}).get("messages", [])[-8:] if not m.get("internal")]
                history.sort(key=lambda m: m.get("at", ""))
                route = self.intake.parse(text, case or {}, self.store.products(),
                    [{"role": m["role"], "text": m["text"]} for m in history if not m.get("internal")],
                    catalogue=self.catalogue.entries())
                event["intake"] = route.model_dump()
                self.db.wa_inbox.update_one({"_id": key}, {"$set": {"intake": event["intake"]}})
            if route.intent == "catalogue":
                self.store.chat_message(conversation, key, "customer", text, input_kind=kind)
                self.store.chat_message(conversation, key, "assistant", self.catalogue.answer(route.catalogue_ids))
                return
            if kind == "audio" and route.intent in ("ready", "retry"):
                self.store.chat_message(conversation, key, "assistant", "Please type READY to confirm assessment, or RETRY to retry a failed operation.")
                return
        if not case and command in ("HELP", "START", "UPDATES", "STOP"):
            self.store.chat_message(conversation, key, "customer", text)
            if command in ("START", "UPDATES", "STOP"):
                self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {
                    "opted_out": command == "STOP", "notifications_opt_in": command == "UPDATES"}})
            if command == "STOP":
                self.db.wa_outbox.update_many({"conversation_id": conversation["_id"], "status": {"$in": ["queued", "pending_window", "awaiting_reply"]}}, {"$set": {"status": "cancelled"}})
            mid = self.store.chat_message(conversation, key, "assistant", "Automated messages stopped. Reply START to resume." if command == "STOP" else HELP)
            if command == "STOP":
                self.store.publish()
                self.db.wa_outbox.update_one({"_id": mid}, {"$set": {"opt_out_ack": True}})
            return
        if not case:
            case = self.create(conversation, key + ":new" if command == "NEW" else key)
            self.respond(case, "welcome", HELP)
            if command == "NEW":
                return
        self.db.wa_inbox.update_one({"_id": key}, {"$set": {"case_id": case["_id"]}})
        self.db.wa_chat_messages.update_one({"_id": request_id(f"chat:{conversation['_id']}:{key}:customer")},
            {"$set": {"repair_case_id": case["_id"]}})
        self.store.message(case["_id"], key, "customer", ("[Voice transcript] " if kind == "audio" else "") + (text or "[" + kind + " attachment]"))
        if command == "STOP":
            self.db.wa_conversations.update_one({"_id": conversation["_id"]},
                {"$set": {"opted_out": True, "notifications_opt_in": False}})
            self.db.wa_outbox.update_many({"conversation_id": conversation["_id"], "status": {"$in": ["queued", "pending_window", "awaiting_reply"]}},
                                         {"$set": {"status": "cancelled"}})
            self.db.wa_jobs.update_many({"conversation_id": conversation["_id"], "status": "queued"}, {"$set": {"status": "cancelled"}})
            # The acknowledgement is the only automated message after opt-out.
            mid = self.store.message(case["_id"], key, "assistant", "Automated messages stopped. Reply START to resume, or contact the shop directly.")
            self.store.publish()
            self.db.wa_outbox.update_one({"_id": mid}, {"$set": {"opt_out_ack": True}})
            return
        if command in ("START", "UPDATES"):
            self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {
                "opted_out": False, "notifications_opt_in": command == "UPDATES"}})
            self.respond(case, key, "Case notifications enabled." if command == "UPDATES" else HELP)
            return
        if conversation.get("opted_out"):
            return
        if command == "NEW":
            if self.db.wa_jobs.find_one({"case_id": case["_id"], "status": {"$in": ["queued", "processing"]}}):
                raise ChannelError("ASSESSMENT_QUEUED", "Please wait for the current assessment before starting a new case.")
            # Use the event's original case on replay; creation is idempotent.
            case = self.create(conversation, key + ":new")
            self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$unset": {"failed_event_id": ""}})
            self.respond(case, key, "New case " + case["_id"] + ". " + HELP)
            return
        if command.startswith("OPEN "):
            cid = text[5:].strip().lower()
            if not re.fullmatch(r"[a-f0-9]{32}", cid):
                raise ChannelError("NOT_FOUND", "Use OPEN followed by one of your case IDs from CASES.")
            target = self.store.case(cid, conversation["sender_id"])
            self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$set": {"active_case_id": cid, "pending_media": []}})
            self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$unset": {"failed_event_id": ""}})
            self.respond(target, key, customer_summary(target))
            return
        if command == "CASES":
            cases = list(self.db.cases.find({"shop_id": self.store.settings.shop_id, "sender_id": conversation["sender_id"],
                                            "channel": "whatsapp"}).sort("created_at", -1).limit(10))
            self.respond(case, key, "Your latest cases:\n" + "\n".join(c["_id"] + " — " + c["status"] for c in cases) + "\nUse OPEN <case ID> to switch.")
            return
        if command == "HELP":
            self.respond(case, key, HELP)
            return
        if command.startswith("REMOVE "):
            evidence_id = text[7:].strip()
            self.jac.call("remove_evidence", case_id=case["_id"], evidence_id=evidence_id, expected_revision=case["revision"])
            self.respond(case, key, "Image removed from the current inputs. Send its replacement and reply READY. Previous approval is no longer current.")
            return
        if command == "STATUS":
            self.respond(case, key, self.status_text(case))
            return
        if command == "RETRY":
            failed = conversation.get("failed_event_id")
            if failed:
                old = self.db.wa_inbox.find_one({"_id": failed, "conversation_id": conversation["_id"]})
                if old and old.get("case_id") == case["_id"]:
                    self.process_message(old, conversation)
                    self.db.wa_inbox.update_one({"_id": failed}, {"$set": {"status": "done", "error": None}})
                    self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$unset": {"failed_event_id": ""}})
                    return
            self.ready(case, conversation, key, retry=True)
            return

        if kind in ("image", "document"):
            media = payload[kind]
            if self.db.evidence.find_one({"case_id": case["_id"], "request_id": request_id("media:" + key)}):
                self.respond(case, key, self.evidence_prompt(case))
                return
            pending = {"event_id": key, "media_id": media.get("id", ""), "filename": media.get("filename", "")}
            self.db.wa_conversations.update_one({"_id": conversation["_id"], "pending_media.event_id": {"$ne": key}},
                {"$push": {"pending_media": pending}})

        known = {"READY": "ready", "ASSESS": "ready", "INVOICE": "details", "DEVICE": "details", "PHOTO": "details", "PRODUCT": "details"}
        if command in known:
            result = IntakeResult(intent=known[command], evidence_kind="invoice" if command == "INVOICE" else "product" if command in ("DEVICE", "PHOTO", "PRODUCT") else "")
        elif not text:
            result = IntakeResult()
        elif event.get("intake"):
            result = IntakeResult.model_validate(event["intake"])
        else:
            history = [{"role": m["role"], "text": m["text"]} for m in case.get("messages", []) if not m.get("internal")]
            result = self.intake.parse(text, case, self.store.products(), history, catalogue=self.catalogue.entries())
            self.db.wa_inbox.update_one({"_id": key}, {"$set": {"intake": result.model_dump()}})

        if result.intent == "status":
            self.respond(case, key, self.status_text(case))
            return
        if result.intent == "help":
            self.respond(case, key, HELP)
            return
        description = result.description.strip() or case["description"]
        model_id = result.model_id or case.get("claimed_model_id", "")
        if description != case["description"] or model_id != case.get("claimed_model_id", ""):
            self.jac.call("update_case", case_id=case["_id"], expected_revision=case["revision"],
                          description=description, claimed_model_id=model_id)
            case = self.store.case(case["_id"])
            self.db.wa_conversations.update_one({"_id": conversation["_id"]}, {"$unset": {"failed_event_id": ""}})
        current = self.db.wa_conversations.find_one({"_id": conversation["_id"]})
        if current.get("pending_media"):
            if not result.evidence_kind:
                self.respond(case, key, "Is the first unlabelled image your invoice or a device photo? Reply INVOICE or DEVICE. I will ask about any remaining images next.")
                return
            self.upload_pending(case, current, result.evidence_kind)
            case = self.store.case(case["_id"])
            remaining = self.db.wa_conversations.find_one({"_id": conversation["_id"]}).get("pending_media", [])
            if remaining:
                self.respond(case, key, "Image saved. Is the next image an INVOICE or DEVICE photo?")
                return
        if result.intent in ("ready", "retry"):
            self.ready(case, conversation, key, retry=result.intent == "retry")
        else:
            self.respond(case, key, self.evidence_prompt(case))

    def upload_pending(self, case, conversation, evidence_kind):
        media = conversation["pending_media"][0]
        rid = request_id("media:" + media["event_id"])
        if not self.db.evidence.find_one({"case_id": case["_id"], "request_id": rid}):
            mime, content = self.meta.download(media["media_id"])
            filename = media["filename"] or ("invoice" if evidence_kind == "invoice" else "device") + (".png" if mime == "image/png" else ".jpg")
            self.jac.call("upload_evidence", case_id=case["_id"], expected_revision=case["revision"],
                          kind=evidence_kind, filename=filename, content_base64=content, request_id=rid)
        self.db.wa_conversations.update_one({"_id": conversation["_id"]},
            {"$pull": {"pending_media": {"event_id": media["event_id"]}}})

    def evidence_prompt(self, case):
        case = self.store.case(case["_id"])
        evidence = list(self.db.evidence.find({"_id": {"$in": case["evidence_ids"]}}))
        kinds = [e["kind"] for e in evidence]
        lines = ["Saved for case " + case["_id"] + "."]
        if case["description"] == "Awaiting customer's complaint.":
            lines.append("Please describe the laptop issue.")
        if "invoice" not in kinds:
            lines.append("Please send your invoice as a JPEG/PNG image, then label it INVOICE.")
        if "product" not in kinds:
            lines.append("Please send a device photo, including its printed model label if possible, then label it DEVICE.")
        if "invoice" in kinds and "product" in kinds:
            lines.append("Reply READY when all your evidence is uploaded, or send more details first.")
        return "\n".join(lines)

    def status_text(self, case):
        evidence = list(self.db.evidence.find({"_id": {"$in": case["evidence_ids"]}}))
        return (customer_summary(case) + "\nCurrent images (REMOVE <ID> to replace):\n" +
                "\n".join(e["kind"] + ": " + e["_id"] for e in evidence))[:4000]

    def ready(self, case, conversation, key, retry=False):
        current = self.db.wa_conversations.find_one({"_id": conversation["_id"]})
        if current.get("pending_media"):
            self.respond(case, key, "Please label the pending image INVOICE or DEVICE before assessment.")
            return
        if case["description"] == "Awaiting customer's complaint.":
            self.respond(case, key, "Please describe the issue before requesting assessment.")
            return
        if case["status"] in ("completed", "needs_information", "needs_inspection"):
            self.respond(case, key, customer_summary(case))
            return
        kinds = [e["kind"] for e in self.db.evidence.find({"_id": {"$in": case["evidence_ids"]}})]
        if "invoice" not in kinds or "product" not in kinds:
            self.respond(case, key, self.evidence_prompt(case))
            return
        if self.db.wa_jobs.find_one({"case_id": case["_id"], "status": {"$in": ["queued", "processing"]}}):
            self.respond(case, key, "Your assessment is already queued or running. Reply STATUS for an update.")
            return
        self.store.enqueue_assessment(case, key, retry)
        self.respond(case, key, "Your assessment is queued. I will send the findings here. The shop must approve any repair proposal.")

    def assess(self, job, conversation):
        case = self.store.case(job["case_id"], job["sender_id"])
        start_id = request_id("start:" + job["_id"])
        assessment = case.get("assessment") or {}
        same_assessment = bool(job.get("assessment_id")) and assessment.get("_id") == job["assessment_id"]
        if (assessment.get("request_id") != start_id and not same_assessment
                and case["revision"] != job["input_revision"]):
            raise ChannelError("STALE_REVISION", "Case inputs changed before assessment. Reply READY to assess the latest evidence.")
        if case["status"] == "draft" or not assessment:
            self.jac.call("start_assessment", case_id=case["_id"], expected_revision=case["revision"], request_id=start_id)
        case = self.store.case(case["_id"])
        self.db.wa_jobs.update_one({"_id": job["_id"]}, {"$set": {"assessment_id": case["active_assessment_id"]}})
        for _ in range(6):
            self.store.renew(conversation["_id"], conversation["lease_token"])
            case = self.store.case(case["_id"])
            if case["status"] not in ("processing", "failed"):
                break
            active = case["assessment"]
            lease = case.get("stage_lease")
            if lease and lease["expires_at"] > stamp():
                raise ChannelError("STAGE_BUSY", "The assessment is still recovering from an interruption. Please retry after two minutes.")
            self.jac.call("advance_case", case_id=case["_id"], assessment_id=case["active_assessment_id"],
                          expected_revision=case["revision"], request_id=request_id(f"stage:{job['_id']}:{active['next_stage']}"))
            updated = self.store.case(case["_id"])
            if updated["status"] == "failed":
                break
        case = self.store.case(case["_id"])
        self.respond(case, "result:" + job["_id"], customer_summary(case))

    def owner_command(self, case_id, expected, action, payload, key):
        case = self.store.case(case_id)
        with self.store.lock(self.store.conversation_id(case["sender_id"])):
            case = self.store.case(case_id)
            self.store.check_revision(case, expected)
            common = {"case_id": case_id, "expected_revision": expected}
            if action in ("message", "note"):
                self.jac.call("owner_message", **common, text=payload.get("text", ""), request_id=key, internal=action == "note")
            elif action == "review":
                self.jac.call("owner_review", **common, action=payload.get("action", ""), reason=payload.get("reason", ""), request_id=key)
            elif action == "inspection":
                self.jac.call("owner_inspection", **common, diagnosis_code=payload.get("diagnosis", "unknown"),
                              notes=payload.get("notes", ""), request_id=key)
            elif action == "correct":
                product = next((p for p in self.store.products() if payload.get("model") in (p["id"], p["name"], p["code"])), None)
                if product is None:
                    raise ChannelError("VALIDATION_ERROR", "Choose a supported catalogue model.")
                description = payload.get("description", "").strip()
                if not description:
                    raise ChannelError("VALIDATION_ERROR", "Enter the corrected issue description.")
                self.jac.call("update_case", **common, description=description, claimed_model_id=product["id"])
            elif action == "assess":
                self.ready(case, self.store.conversation(case["sender_id"]), key, retry=case["status"] == "failed")
            else:
                raise ChannelError("VALIDATION_ERROR", "Unsupported owner operation.")
        self.store.publish()
