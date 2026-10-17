# Owner: Member A. Validate external values before building database queries.
import re;
import json;
import hashlib;
import from datetime { datetime, timezone }
import from uuid { uuid4 }
import from shared.contracts { FixoraError }

def _now() -> str {
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds");
}

def _new_id() -> str { return uuid4().hex; }

def _identifier(value: str, label: str = "ID") -> str {
    if not re.fullmatch("[a-f0-9]{32}", value) {
        raise FixoraError("VALIDATION_ERROR", label + " must be a valid Fixora ID.");
    }
    return value;
}

def _request_id(value: str) -> str {
    if not re.fullmatch("[A-Za-z0-9_-]{8,80}", value) {
        raise FixoraError("VALIDATION_ERROR", "Request IDs must contain 8-80 letters, digits, underscores or hyphens.");
    }
    return value;
}

def _text(value: str, label: str, maximum: int, required: bool = True) -> str {
    clean = value.strip();
    if (required and not clean) or len(clean) > maximum or "\x00" in clean {
        raise FixoraError("VALIDATION_ERROR", label + " is missing or exceeds its allowed length.");
    }
    return clean;
}

def _fingerprint(value: dict[str, any]) -> str {
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest();
}
