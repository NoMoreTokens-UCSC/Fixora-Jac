"""Two apps: public_app on 8010 (webhook only), owner_app on loopback 8011."""
import base64
from contextlib import asynccontextmanager
import hashlib
import hmac
import json
import secrets
import time

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, ConfigDict, Field
from pymongo import ReturnDocument
from starlette.concurrency import run_in_threadpool

from .config import Settings
from .service import Service
from .store import Store
from .transport import ChannelError, IntakeModel, JacClient, MetaClient, request_id
from .views import case_view


class Login(BaseModel):
    password: str = Field(min_length=1, max_length=500)


class Command(BaseModel):
    model_config = ConfigDict(extra="forbid")
    expected_revision: int = Field(ge=0, strict=True)
    request_id: str = Field(pattern=r"^[A-Za-z0-9_-]{8,80}$")
    text: str = Field(default="", max_length=4000)
    reason: str = Field(default="", max_length=3500)
    action: str = ""
    diagnosis: str = "unknown"
    notes: str = Field(default="", max_length=3000)
    model: str = Field(default="", max_length=200)
    description: str = Field(default="", max_length=4000)
    message_id: str = ""


class ChatCommand(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request_id: str = Field(pattern=r"^[A-Za-z0-9_-]{8,80}$")
    text: str = Field(min_length=1, max_length=4000)
    internal: bool = False


def create_apps(settings=None, store=None, service=None):
    settings = settings or Settings.load()

    @asynccontextmanager
    async def lifespan(app):
        role = "public" if app is public else "owner"
        settings.require(role)
        current = store or Store(settings)
        app.state.store = current
        app.state.service = service or Service(current, JacClient(settings), MetaClient(settings), IntakeModel(settings))
        yield
        if store is None and current.client:
            current.client.close()

    public = FastAPI(title="Fixora WhatsApp webhook", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    owner = FastAPI(title="Fixora local owner API", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    owner.add_middleware(CORSMiddleware, allow_origins=list(settings.owner_origins), allow_credentials=True,
                         allow_methods=["GET", "POST"], allow_headers=["Content-Type"])

    async def safe_error(request, error):
        status = 404 if error.code == "NOT_FOUND" else 409 if error.code in ("STALE_REVISION", "CONVERSATION_BUSY", "STAGE_BUSY", "INVALID_STATE") else 400
        return JSONResponse({"error": str(error), "code": error.code}, status_code=status)

    public.add_exception_handler(ChannelError, safe_error)
    owner.add_exception_handler(ChannelError, safe_error)

    @owner.middleware("http")
    async def owner_boundary(request, call_next):
        if request.method not in ("GET", "HEAD", "OPTIONS") and request.headers.get("origin") not in settings.owner_origins:
            return JSONResponse({"error": "Use the local Fixora dashboard."}, status_code=403)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    @public.get("/webhooks/whatsapp")
    def verify(request: Request):
        query = request.query_params
        if query.get("hub.mode") != "subscribe" or not settings.verify_token or not hmac.compare_digest(
                query.get("hub.verify_token", "").encode(), settings.verify_token.encode()):
            raise HTTPException(403, "Webhook verification failed.")
        return PlainTextResponse(query.get("hub.challenge", ""))

    @public.post("/webhooks/whatsapp")
    async def receive(request: Request):
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > 2097152:
                raise HTTPException(413, "Webhook is too large.")
            chunks.append(chunk)
        body = b"".join(chunks)
        expected = "sha256=" + hmac.new(settings.app_secret.encode(), body, hashlib.sha256).hexdigest()
        if not settings.app_secret or not hmac.compare_digest(request.headers.get("x-hub-signature-256", ""), expected):
            raise HTTPException(403, "Invalid webhook signature.")
        try:
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ValueError()
            # MongoDB persistence completes before returning 200. A storage error returns
            # 503, allowing Meta to redeliver the same idempotent event.
            await run_in_threadpool(request.app.state.store.ingest, payload)
        except (ValueError, TypeError, KeyError):
            raise HTTPException(400, "Invalid webhook payload.") from None
        except ChannelError:
            raise
        except Exception:
            raise HTTPException(503, "Webhook storage unavailable.") from None
        return {"received": True}

    def authenticated(request: Request):
        token = request.cookies.get("fixora_owner", "")
        if not token or not request.app.state.store.db.wa_sessions.find_one({
            "_id": request_id(token), "expires_at": {"$gt": time.time()}}):
            raise HTTPException(401, "Sign in to the owner workspace.")
        return True

    @owner.post("/owner/login")
    def login(body: Login, request: Request, response: Response):
        db = request.app.state.store.db
        key = request.client.host if request.client else "local"
        bucket = str(int(time.time() // 60)) + ":" + key
        attempts = db.wa_login_attempts.find_one_and_update({"_id": bucket}, {"$inc": {"attempts": 1}}, upsert=True, return_document=ReturnDocument.AFTER)
        if attempts["attempts"] > 10:
            raise HTTPException(429, "Too many attempts. Wait one minute.")
        if not settings.owner_password or not hmac.compare_digest(body.password.encode(), settings.owner_password.encode()):
            raise HTTPException(401, "Incorrect owner password.")
        token = secrets.token_urlsafe(32)
        db.wa_sessions.insert_one({"_id": request_id(token), "expires_at": time.time() + 28800})
        response.set_cookie("fixora_owner", token, httponly=True, samesite="strict", max_age=28800, path="/")
        return {"owner": True}

    @owner.get("/owner/session", dependencies=[Depends(authenticated)])
    def session():
        return {"owner": True}

    @owner.post("/owner/logout", dependencies=[Depends(authenticated)])
    def logout(request: Request, response: Response):
        request.app.state.store.db.wa_sessions.delete_one({"_id": request_id(request.cookies.get("fixora_owner", ""))})
        response.delete_cookie("fixora_owner", path="/")
        return {"owner": False}

    @owner.get("/owner/models", dependencies=[Depends(authenticated)])
    def models(request: Request):
        return {"models": request.app.state.store.products()}

    @owner.get("/owner/catalogue", dependencies=[Depends(authenticated)])
    def catalogue(request: Request):
        return {"items": request.app.state.service.catalogue.entries()}

    def conversation_view(current, row):
        messages = [m for m in current.chat_history(row["_id"], 100) if not m.get("repair_case_id")]
        for case in current.db.cases.find({"shop_id": settings.shop_id, "channel": "whatsapp", "sender_id": row["sender_id"]}):
            messages.extend({**m, "_id": m["id"], "case_id": case["_id"]} for m in case.get("messages", []))
        # A repair intake is also logged before inference. Hide its duplicate in
        # the combined view while keeping the case's authoritative message.
        messages.sort(key=lambda m: m.get("at", ""))
        public_fields = ("role", "text", "at", "internal", "input_kind", "case_id")
        messages = messages[-100:]
        deliveries = {m["_id"]: m.get("status", "") for m in current.db.wa_outbox.find(
            {"_id": {"$in": [m["_id"] for m in messages]}}, {"status": 1})}
        result = []
        for m in messages:
            result.append({"id": m["_id"], **{k: m.get(k, "") for k in public_fields}, "delivery": deliveries.get(m["_id"], "")})
        return {"id": row["_id"], "sender_id": row["sender_id"], "customer": row.get("customer_name", "Customer"),
                "active_case_id": row.get("active_case_id"), "messages": result}

    @owner.get("/owner/conversations", dependencies=[Depends(authenticated)])
    def conversations(request: Request):
        current = request.app.state.store
        return {"conversations": [conversation_view(current, row) for row in current.db.wa_conversations.find({
            "shop_id": settings.shop_id}).sort("last_inbound_at", -1).limit(100)]}

    @owner.post("/owner/conversations/{conversation_id}/messages", dependencies=[Depends(authenticated)])
    def chat_message(conversation_id: str, body: ChatCommand, request: Request):
        current = request.app.state.store
        if not current.db.wa_conversations.find_one({"_id": conversation_id, "shop_id": settings.shop_id}):
            raise ChannelError("NOT_FOUND", "Conversation not found.")
        with current.lock(conversation_id) as row:
            if row.get("shop_id") != settings.shop_id:
                raise ChannelError("NOT_FOUND", "Conversation not found.")
            if not body.text.strip():
                raise ChannelError("VALIDATION_ERROR", "Write a message first.")
            current.chat_message(row, "owner:" + body.request_id, "shop", body.text.strip(), internal=body.internal)
            current.publish()
        return {"saved": True}

    @owner.get("/owner/cases", dependencies=[Depends(authenticated)])
    def cases(request: Request):
        current = request.app.state.store
        products = current.products()
        return {"cases": [case_view(current, c, products) for c in current.db.cases.find({
            "shop_id": settings.shop_id, "channel": "whatsapp"}).sort("updated_at", -1)]}

    @owner.get("/owner/policy", dependencies=[Depends(authenticated)])
    def policy(request: Request):
        return {"policy": request.app.state.store.db.policies.find_one({"shop_id": settings.shop_id}, sort=[("version", -1)])}

    @owner.get("/owner/cases/{case_id}", dependencies=[Depends(authenticated)])
    def get_case(case_id: str, request: Request):
        current = request.app.state.store
        return {"case": case_view(current, current.case(case_id))}

    @owner.get("/owner/cases/{case_id}/evidence/{evidence_id}", dependencies=[Depends(authenticated)])
    def evidence(case_id: str, evidence_id: str, request: Request):
        current = request.app.state.store
        current.case(case_id)
        image = request.app.state.service.jac.call("get_evidence", case_id=case_id, evidence_id=evidence_id)
        return Response(base64.b64decode(image["content_base64"]), media_type=image["mime_type"],
                        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})

    @owner.post("/owner/cases/{case_id}/{action}", dependencies=[Depends(authenticated)])
    def command(case_id: str, action: str, body: Command, request: Request):
        current = request.app.state.store
        if action == "retry_delivery":
            current.check_revision(current.case(case_id), body.expected_revision)
            result = current.db.wa_outbox.update_one({"_id": body.message_id, "case_id": case_id, "status": "failed"},
                                                    {"$set": {"status": "queued"}})
            if result.modified_count != 1:
                raise ChannelError("INVALID_STATE", "Only a confirmed failed delivery can be retried. Check WhatsApp manually for uncertain delivery.")
        else:
            request.app.state.service.owner_command(case_id, body.expected_revision, action, body.model_dump(), body.request_id)
        return {"case": case_view(current, current.case(case_id))}

    return public, owner


public_app, owner_app = create_apps()
