# Owner: Member A. Case + active assessment updates are atomic in ONE document.
# The assessments collection holds immutable historical snapshots. Archive the
# active snapshot before replacing it; active results remain authoritative in cases.
import copy;
import from datetime { datetime, timezone, timedelta }
import from pymongo { ReturnDocument }
import from pymongo.errors { DuplicateKeyError }
import from data.connection { _get_database }
import from shared.config { _get_settings }
import from shared.contracts { FixoraError }
import from shared.statuses { STAGES }
import from shared.validation { _now, _new_id, _identifier, _request_id, _text, _fingerprint }

def _get_case_record(case_id: str) -> dict[str, any] {
    _identifier(case_id, "Case ID");
    item = _get_database().cases.find_one({"_id": case_id, "shop_id": _get_settings().shop_id});
    if item is None { raise FixoraError("NOT_FOUND", "Case not found."); }
    return item as dict[str, any];
}

def _case_view(item: dict[str, any]) -> dict[str, any] {
    assessment = copy.deepcopy(item["assessment"]);
    if assessment is not None {
        assessment["id"] = assessment.pop("_id");
        assessment.pop("completed_requests", None);
        assessment.pop("request_id", None);
    }
    return {"id": item["_id"], "description": item["description"],
        "claimed_model_id": item["claimed_model_id"], "status": item["status"],
        "revision": item["revision"], "created_at": item["created_at"],
        "updated_at": item["updated_at"], "evidence_ids": item["evidence_ids"],
        "active_assessment_id": item["active_assessment_id"],
        "assessment": assessment, "review_status": item.get("review_status", "unreviewed"),
        "review_assessment_id": item.get("review_assessment_id"),
        "owner_inspection": item.get("owner_inspection"),
        "messages": item.get("messages", []), "decisions": item.get("decisions", [])};
}

def _assert_revision(item: dict[str, any], expected_revision: int) {
    if expected_revision != item["revision"] {
        raise FixoraError("STALE_REVISION", "Reload the case and retry with its current revision.");
    }
}

def _assert_not_busy(item: dict[str, any]) {
    lease = item.get("stage_lease");
    if lease and lease["expires_at"] > _now() {
        raise FixoraError("STAGE_BUSY", "A specialist is running. Retry after it finishes or its lease expires.");
    }
}

def _archive_assessment(item: dict[str, any]) {
    snapshot = item.get("assessment");
    if snapshot {
        _get_database().assessments.update_one({"_id": snapshot["_id"]},
            {"$setOnInsert": copy.deepcopy(snapshot)}, upsert=True);
    }
}

def _create_case_record(description: str, claimed_model_id: str, submission_id: str) -> dict[str, any] {
    description = _text(description, "Description", 4000);
    claimed_model_id = _text(claimed_model_id, "Model ID", 120, required=False);
    _request_id(submission_id);
    signature = _fingerprint({"description": description, "claimed_model_id": claimed_model_id});
    timestamp = _now();
    item: dict[str, any] = {"_id": _new_id(), "shop_id": _get_settings().shop_id,
        "submission_id": submission_id, "submission_signature": signature,
        "description": description, "claimed_model_id": claimed_model_id,
        "status": "draft", "revision": 0, "assessment_number": 0,
        "assessment": None, "active_assessment_id": None, "stage_lease": None,
        "evidence_ids": [], "created_at": timestamp, "updated_at": timestamp};
    database = _get_database();
    try { database.cases.insert_one(item); }
    except DuplicateKeyError {
        existing = database.cases.find_one({"shop_id": item["shop_id"], "submission_id": submission_id});
        if existing is None or existing["submission_signature"] != signature {
            raise FixoraError("IDEMPOTENCY_CONFLICT", "This submission ID was already used with different input.");
        }
        return existing as dict[str, any];
    }
    return item;
}

def _list_case_records(limit: int, cursor: str) -> dict[str, any] {
    if type(limit) is not int or limit < 1 or limit > 50 { raise FixoraError("VALIDATION_ERROR", "Limit must be an integer between 1 and 50."); }
    query: dict[str, any] = {"shop_id": _get_settings().shop_id};
    if cursor {
        previous = _get_case_record(cursor);
        query["$or"] = [{"created_at": {"$lt": previous["created_at"]}},
            {"created_at": previous["created_at"], "_id": {"$lt": cursor}}];
    }
    records = list(_get_database().cases.find(query).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1)) as list[dict[str, any]];
    visible = records[:limit];
    summaries: list[dict[str, any]] = [];
    for item in visible {
        summaries.append({"id": item["_id"], "description": item["description"],
            "status": item["status"], "revision": item["revision"],
            "claimed_model_id": item["claimed_model_id"], "updated_at": item["updated_at"]});
    }
    return {"cases": summaries, "next_cursor": visible[-1]["_id"] if len(records) > limit else None};
}

def _update_case_record(case_id: str, expected_revision: int, description: str, claimed_model_id: str) -> dict[str, any] {
    item = _get_case_record(case_id);
    _assert_revision(item, expected_revision);
    _assert_not_busy(item);
    description = _text(description, "Description", 4000);
    claimed_model_id = _text(claimed_model_id, "Model ID", 120, required=False);
    _archive_assessment(item);
    updated = _get_database().cases.find_one_and_update(
        {"_id": case_id, "revision": expected_revision},
        {"$set": {"description": description, "claimed_model_id": claimed_model_id,
            "status": "draft", "assessment": None, "active_assessment_id": None,
            "stage_lease": None, "review_status": "unreviewed", "review_assessment_id": None,
            "owner_inspection": None, "updated_at": _now()}, "$inc": {"revision": 1}},
        return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Case changed during the update. Reload and retry."); }
    return updated as dict[str, any];
}

def _evidence_records(item: dict[str, any]) -> list[dict[str, any]] {
    return list(_get_database().evidence.find({"case_id": item["_id"], "_id": {"$in": item["evidence_ids"]}})) as list[dict[str, any]];
}

def _evidence_view(item: dict[str, any]) -> dict[str, any] {
    return {"id": item["_id"], "kind": item["kind"], "filename": item["filename"],
        "mime_type": item["mime_type"], "size_bytes": item["size_bytes"],
        "sha256": item["sha256"], "uploaded_at": item["uploaded_at"]};
}

def _start_assessment_record(case_id: str, expected_revision: int, request_id: str) -> dict[str, any] {
    _request_id(request_id);
    item = _get_case_record(case_id);
    active = item.get("assessment");
    if active and active["request_id"] == request_id { return item; }
    if _get_database().assessments.find_one({"case_id": case_id, "request_id": request_id}) is not None {
        raise FixoraError("IDEMPOTENCY_CONFLICT", "This assessment request belongs to an earlier case revision. Use a new request ID.");
    }
    _assert_revision(item, expected_revision);
    _assert_not_busy(item);
    evidence = _evidence_records(item);
    kinds = [record["kind"] for record in evidence];
    if "invoice" not in kinds or "product" not in kinds {
        raise FixoraError("MISSING_EVIDENCE", "Upload an invoice and at least one product photo before starting.");
    }
    _archive_assessment(item);
    timestamp = _now();
    assessment_id = _new_id();
    assessment: dict[str, any] = {"_id": assessment_id, "case_id": case_id,
        "version": item["assessment_number"] + 1, "input_revision": expected_revision,
        "request_id": request_id, "created_at": timestamp, "updated_at": timestamp,
        "next_stage": 0, "stages": {}, "completed_requests": [], "next_action": "continue"};
    updated = _get_database().cases.find_one_and_update(
        {"_id": case_id, "revision": expected_revision},
        {"$set": {"assessment": assessment, "active_assessment_id": assessment_id,
            "stage_lease": None, "status": "processing", "review_status": "unreviewed",
            "review_assessment_id": None, "updated_at": timestamp},
            "$inc": {"revision": 1, "assessment_number": 1}},
        return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Case changed while starting. Reload and retry."); }
    return updated as dict[str, any];
}

def _claim_stage(case_id: str, assessment_id: str, expected_revision: int, request_id: str) -> dict[str, any] | None {
    _identifier(assessment_id, "Assessment ID");
    _request_id(request_id);
    item = _get_case_record(case_id);
    if item["active_assessment_id"] != assessment_id {
        raise FixoraError("STALE_REVISION", "This assessment is no longer current.");
    }
    assessment = item["assessment"];
    if request_id in assessment["completed_requests"] { return None; }
    _assert_revision(item, expected_revision);
    if item["status"] not in ["processing", "failed"] {
        raise FixoraError("INVALID_STATE", "This case is stopped. Correct its inputs and start a new assessment if needed.");
    }
    _assert_not_busy(item);
    stage_index = assessment["next_stage"] as int;
    if stage_index >= len(STAGES) { raise FixoraError("INVALID_STATE", "Assessment is already complete."); }
    expires_at = (datetime.now(timezone.utc) + timedelta(seconds=_get_settings().stage_lease_seconds)).isoformat(timespec="milliseconds");
    lease = {"token": _new_id(), "request_id": request_id, "stage": STAGES[stage_index],
        "started_at": _now(), "expires_at": expires_at};
    updated = _get_database().cases.find_one_and_update(
        {"_id": case_id, "revision": expected_revision, "active_assessment_id": assessment_id},
        {"$set": {"stage_lease": lease, "status": "processing", "updated_at": _now()}, "$inc": {"revision": 1}},
        return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Another request advanced this case. Reload and retry."); }
    return updated as dict[str, any];
}

def _commit_stage(claimed: dict[str, any], result: dict[str, any], case_status: str) -> dict[str, any] {
    assessment = copy.deepcopy(claimed["assessment"]) as dict[str, any];
    lease = claimed["stage_lease"];
    result["started_at"] = lease["started_at"];
    result["finished_at"] = _now();
    assessment["stages"][lease["stage"]] = result;
    assessment["updated_at"] = _now();
    assessment["next_action"] = result["next_action"];
    if result["status"] == "completed" {
        assessment["next_stage"] += 1;
    }
    # Failed attempts remain retryable, including the same request after timeout.
    if result["status"] != "failed" {
        assessment["completed_requests"].append(lease["request_id"]);
    }
    updated = _get_database().cases.find_one_and_update(
        {"_id": claimed["_id"], "revision": claimed["revision"],
            "active_assessment_id": claimed["active_assessment_id"], "stage_lease.token": lease["token"]},
        {"$set": {"assessment": assessment, "status": case_status,
            "stage_lease": None, "updated_at": _now()}, "$inc": {"revision": 1}},
        return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "This specialist result was superseded and was not saved."); }
    return updated as dict[str, any];
}

def _catalogue_snapshot() -> dict[str, any] {
    database = _get_database();
    shop_id = _get_settings().shop_id;
    policy = database.policies.find_one({"shop_id": shop_id}, sort=[("version", -1)]);
    return {"policy": policy, "products": list(database.products.find({})),
        "repairs": list(database.repair_catalog.find({})), "inventory": list(database.inventory.find({}))};
}
