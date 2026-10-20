# Private service operations: the local owner gateway authenticates its session
# and supplies the server-only service token. Never expose Jac through the tunnel.
import hashlib;
import from pymongo { ReturnDocument }
import from shared.contracts { ApiResult, FixoraError }
import from shared.validation { _now, _request_id, _text }
import from data.connection { _get_database }
import from data.repositories { _get_case_record, _assert_revision, _assert_not_busy, _archive_assessment }
import from server.responses { _api_call }
import from server.cases { _case_payload }

def _message(key: str, role: str, text: str, internal: bool = False) -> dict[str, any] {
    return {"id": hashlib.sha256(key.encode()).hexdigest(), "role": role, "text": text,
        "at": _now(), "internal": internal, "publication_pending": not internal};
}

def:pub owner_message(case_id: str, expected_revision: int, text: str, request_id: str,
    internal: bool = False, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _message_payload, [case_id, expected_revision, text, request_id, internal]);
}

def _message_payload(case_id: str, expected_revision: int, text: str, request_id: str, internal: bool) -> dict[str, any] {
    _request_id(request_id); text = _text(text, "Message", 4000);
    item = _get_case_record(case_id);
    msg = _message(case_id + request_id, "shop", text, internal);
    if `any(row["id"] == msg["id"] for row in item.get("messages", [])) { return _case_payload(case_id); }
    _assert_revision(item, expected_revision); _assert_not_busy(item);
    updated = _get_database().cases.find_one_and_update({"_id": case_id, "revision": expected_revision,
        "messages.id": {"$ne": msg["id"]}}, {"$push": {"messages": msg}, "$set": {"updated_at": _now()}},
        return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Reload the latest case."); }
    return _case_payload(case_id);
}

def:pub owner_review(case_id: str, expected_revision: int, action: str, reason: str,
    request_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _review_payload, [case_id, expected_revision, action, reason, request_id]);
}

def _review_payload(case_id: str, expected_revision: int, action: str, reason: str, request_id: str) -> dict[str, any] {
    _request_id(request_id); reason = _text(reason, "Reason", 3500);
    if action not in ["approved", "rejected", "needs_information", "needs_inspection"] {
        raise FixoraError("VALIDATION_ERROR", "Unsupported review action.");
    }
    item = _get_case_record(case_id);
    if `any(row.get("request_id") == request_id for row in item.get("decisions", [])) { return _case_payload(case_id); }
    _assert_revision(item, expected_revision); _assert_not_busy(item);
    if action in ["approved", "rejected"] and (item["status"] != "completed" or not item.get("assessment")) {
        raise FixoraError("INVALID_STATE", "Complete the current assessment before making a final decision.");
    }
    if action in ["approved", "rejected"] and item.get("review_status") in ["needs_information", "needs_inspection"] {
        raise FixoraError("INVALID_STATE", "Resolve the requested details or inspection and reassess first.");
    }
    decision = {"id": hashlib.sha256((case_id + request_id).encode()).hexdigest(), "action": action,
        "reason": reason, "origin": "owner", "revision": expected_revision + 1,
        "assessment_id": item.get("active_assessment_id"), "at": _now(), "request_id": request_id,
        "scope": "Warranty repair proposal"};
    msg = _message(case_id + request_id + "review", "shop", "Shop decision (" + action.replace("_", " ") + "): " + reason);
    updated = _get_database().cases.find_one_and_update({"_id": case_id, "revision": expected_revision},
        {"$set": {"review_status": action, "review_assessment_id": item.get("active_assessment_id"), "updated_at": _now()},
            "$inc": {"revision": 1}, "$push": {"decisions": decision, "messages": msg}}, return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Reload the latest case before reviewing."); }
    return _case_payload(case_id);
}

def:pub owner_inspection(case_id: str, expected_revision: int, diagnosis_code: str, notes: str,
    request_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _inspection_payload, [case_id, expected_revision, diagnosis_code, notes, request_id]);
}

def _inspection_payload(case_id: str, expected_revision: int, diagnosis_code: str, notes: str, request_id: str) -> dict[str, any] {
    _request_id(request_id); notes = _text(notes, "Inspection notes", 3000);
    if diagnosis_code not in ["screen_crack", "hinge_damage", "keyboard_damage", "unknown"] {
        raise FixoraError("VALIDATION_ERROR", "Choose a supported confirmed observation, or unknown.");
    }
    item = _get_case_record(case_id);
    previous = item.get("owner_inspection");
    if previous and previous.get("request_id") == request_id { return _case_payload(case_id); }
    _assert_revision(item, expected_revision); _assert_not_busy(item); _archive_assessment(item);
    inspection = {"diagnosis_code": diagnosis_code, "notes": notes, "at": _now(),
        "actor": "owner", "request_id": request_id, "evidence_ids": item["evidence_ids"]};
    msg = _message(case_id + request_id + "inspection", "shop", "Inspection: " + diagnosis_code + ". " + notes, True);
    updated = _get_database().cases.find_one_and_update({"_id": case_id, "revision": expected_revision},
        {"$set": {"owner_inspection": inspection, "assessment": None, "active_assessment_id": None,
            "stage_lease": None, "status": "draft", "review_status": "unreviewed", "review_assessment_id": None,
            "updated_at": _now()}, "$inc": {"revision": 1}, "$push": {"messages": msg}}, return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Reload the latest case before recording an inspection."); }
    return _case_payload(case_id);
}
