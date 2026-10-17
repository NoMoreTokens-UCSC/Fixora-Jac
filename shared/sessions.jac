# Short-lived browser sessions. The shop secret never leaves the server.
import base64;
import hashlib;
import hmac;
import json;
import secrets;
import time;

def _signature(secret: str, payload: str) -> str {
    return hmac.new(secret.encode("utf-8"), ("fixora-browser-session-v1:" + payload).encode("ascii"), hashlib.sha256).hexdigest();
}

def _issue_session(secret: str, shop_id: str, role: str, lifetime: int = 28800) -> dict[str, any] {
    expires_at = int(time.time()) + lifetime;
    claims = {"shop_id": shop_id, "role": role, "expires_at": expires_at, "nonce": secrets.token_urlsafe(16)};
    payload = base64.urlsafe_b64encode(json.dumps(claims, separators=(",", ":")).encode("utf-8")).decode("ascii").rstrip("=");
    return {"session_token": "fixora-session." + payload + "." + _signature(secret, payload), "role": role, "expires_at": expires_at};
}

def _valid_session(secret: str, shop_id: str, token: str) -> bool {
    if len(token) > 2048 or not token.startswith("fixora-session.") { return False; }
    try {
        pieces = token.split(".");
        if len(pieces) != 3 { return False; }
        payload = pieces[1];
        if not hmac.compare_digest(_signature(secret, payload).encode("ascii"), pieces[2].encode("utf-8")) { return False; }
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)));
        return isinstance(claims, dict) and claims.get("shop_id") == shop_id
            and claims.get("role") in ["customer", "owner"]
            and type(claims.get("expires_at")) is int and claims["expires_at"] > int(time.time());
    } except Exception { return False; }
}
