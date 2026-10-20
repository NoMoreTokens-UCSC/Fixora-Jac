# Owner: Member A. Adapters call Member B's run_stage(context) implementations.
import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from concurrent.futures { ThreadPoolExecutor, TimeoutError }
import from data.repositories { _claim_stage, _commit_stage, _get_case_record, _evidence_records, _evidence_view, _catalogue_snapshot }
import from data.files { _read_image }
import from shared.config { _get_settings }
import from shared.contracts { StageResult, FixoraError }
import from workflow.graph { _select_next_stage }
import from workflow.transitions { _validate_result, _next_case_status }
import from specialists.document { run_stage as _document_stage }
import from specialists.vision { run_stage as _vision_stage }
import from specialists.coverage { run_stage as _coverage_stage }
import from specialists.repair_parts { run_stage as _repair_stage }
import from specialists.resolution { run_stage as _resolution_stage }

glob _test_handlers: dict[str, Callable[[dict[str, any]], StageResult]] = {};

def _set_test_handlers(handlers: dict[str, Callable[[dict[str, any]], StageResult]]) {
    # Internal test dependency seam. Not exported as an HTTP operation.
    _test_handlers = handlers;
}

def _load_handler(stage: str) -> Callable[[dict[str, any]], StageResult] {
    if stage in _test_handlers { return _test_handlers[stage]; }
    # Use Jac imports consistently: mixing importlib and Jac aliases can load
    # distinct StageResult classes when the test/runtime module cache is reused.
    handlers: dict[str, Callable[[dict[str, any]], StageResult]] = {
        "document": _document_stage, "vision": _vision_stage, "coverage": _coverage_stage,
        "repair_parts": _repair_stage, "resolution": _resolution_stage};
    if stage not in handlers { raise FixoraError("SPECIALIST_UNAVAILABLE", "Unsupported specialist stage."); }
    return handlers[stage];
}

def _stage_context(item: dict[str, any], stage: str) -> dict[str, any] {
    records = _evidence_records(item);
    attachments: list[dict[str, any]] = [];
    if stage in ["document", "vision"] {
        wanted = "invoice" if stage == "document" else "product";
        for record in records {
            if record["kind"] == wanted {
                attachments.append(_read_image(item["_id"] as str, record["_id"] as str));
            }
        }
    }
    settings = _get_settings();
    return {"case_id": item["_id"], "description": item["description"],
        "claimed_model_id": item["claimed_model_id"], "stage": stage,
        "owner_inspection": item.get("owner_inspection"),
        "assessment_id": item["active_assessment_id"],
        "evidence": [_evidence_view(record) for record in records], "attachments": attachments,
        "prior_results": item["assessment"]["stages"], "catalogue": _catalogue_snapshot(),
        "evaluation_date": datetime.now(ZoneInfo(settings.timezone)).date().isoformat(),
        "shop_timezone": settings.timezone, "model": settings.model, "demo_mode": settings.demo_mode};
}

def _advance_case_record(case_id: str, assessment_id: str, expected_revision: int, request_id: str) -> dict[str, any] {
    claimed = _claim_stage(case_id, assessment_id, expected_revision, request_id);
    if claimed is None { return _get_case_record(case_id); }
    stage = claimed["stage_lease"]["stage"] as str;
    try {
        if _select_next_stage(claimed) != stage {
            raise FixoraError("INVALID_STATE", "The workflow graph and persisted stage are inconsistent.");
        }
        handler = _load_handler(stage);
        context = _stage_context(claimed, stage);
        executor = ThreadPoolExecutor(max_workers=1);
        try {
            future = executor.submit(handler, context);
            result = future.result(timeout=45) as StageResult;
        } finally {
            # A timed-out handler cannot commit results; specialist tools must be
            # read-only. Python cannot forcibly stop a running provider thread.
            executor.shutdown(wait=False, cancel_futures=True);
        }
        document = _validate_result(result, stage, claimed["evidence_ids"] as list[str]);
    } except FixoraError as error {
        document = _failed_stage(stage, error.code, error.message);
    } except TimeoutError {
        document = _failed_stage(stage, "MODEL_TIMEOUT", "Specialist exceeded 45 seconds. Retry this stage with the latest case revision.");
    } except NotImplementedError {
        document = _failed_stage(stage, "SPECIALIST_UNAVAILABLE", "This specialist has not been implemented yet.");
    } except Exception {
        document = _failed_stage(stage, "SPECIALIST_FAILED", "Specialist failed. Details are withheld to protect uploaded content and secrets.");
    }
    return _commit_stage(claimed, document, _next_case_status(document));
}

def _failed_stage(stage: str, code: str, message: str) -> dict[str, any] {
    return {"stage": stage, "status": "failed", "findings": {}, "evidence_refs": [],
        "missing_fields": [], "conflicts": [], "next_action": "continue",
        "error": {"code": code, "message": message}};
}
