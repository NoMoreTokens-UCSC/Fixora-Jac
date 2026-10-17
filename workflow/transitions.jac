# Owner: Member A. Fail closed on unsupported specialist output.
import json;
import from shared.contracts { StageResult, FixoraError }
import from shared.statuses { STAGES, NEXT_ACTIONS }

def _validate_result(result: StageResult, stage: str, evidence_ids: list[str]) -> dict[str, any] {
    if not isinstance(result, StageResult) or result.stage != stage {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist returned the wrong result type or stage.");
    }
    if result.status not in ["completed", "blocked", "failed"] or result.next_action not in NEXT_ACTIONS {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist returned an unsupported status or next action.");
    }
    if not isinstance(result.findings, dict) {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist findings must be an object.");
    }
    for values in [result.evidence_refs, result.missing_fields, result.conflicts] {
        if not isinstance(values, list) or not all(isinstance(value, str) for value in values) {
            raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist references and limitations must be string lists.");
        }
    }
    if `any(ref not in evidence_ids for ref in result.evidence_refs) {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist referenced evidence outside this case.");
    }
    if result.next_action == "complete" and stage != STAGES[-1] {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Only the resolution stage can finish the assessment.");
    }
    status = result.status;
    action = result.next_action;
    if result.conflicts or result.missing_fields { status = "blocked"; action = "needs_information"; }
    if action in ["needs_information", "needs_inspection"] { status = "blocked"; }
    if status == "blocked" and action not in ["needs_information", "needs_inspection"] {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "A blocked result must explain its next action.");
    }
    if status == "failed" and result.error is None {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "A failed specialist must return an error code and safe message.");
    }
    document: dict[str, any] = {"stage": stage, "status": status, "findings": result.findings,
        "evidence_refs": result.evidence_refs, "missing_fields": result.missing_fields,
        "conflicts": result.conflicts, "next_action": action,
        "error": {"code": result.error.code, "message": result.error.message} if result.error is not None else None};
    try { encoded = json.dumps(document, allow_nan=False); }
    except (TypeError, ValueError) {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist output must be JSON serializable.");
    }
    if len(encoded.encode("utf-8")) > 131072 {
        raise FixoraError("INVALID_SPECIALIST_RESULT", "Specialist output exceeds 128 KB; return references instead of raw files.");
    }
    return document;
}

def _next_case_status(result: dict[str, any]) -> str {
    if result["status"] == "failed" { return "failed"; }
    if result["next_action"] in ["needs_information", "needs_inspection"] {
        return result["next_action"] as str;
    }
    if result["stage"] == STAGES[-1] { return "completed"; }
    return "processing";
}
