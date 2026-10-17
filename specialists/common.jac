import from shared.contracts { StageResult, FixoraError }

def _mode(context: dict[str, any]) -> str {
    return "demo_fixture" if context.get("demo_mode", False) else "live_model";
}

def _refs(context: dict[str, any], kind: str = "") -> list[str] {
    return [row["id"] for row in context["evidence"] if not kind or row["kind"] == kind] as list[str];
}

def _prior(context: dict[str, any], stage: str) -> dict[str, any] {
    result = context["prior_results"].get(stage);
    if result is None or result.get("status") != "completed" {
        raise FixoraError("MISSING_STAGE_RESULT", "A completed " + stage + " result is required.");
    }
    return result["findings"] as dict[str, any];
}

def _blocked(stage: str, message: str, refs: list[str], fields: list[str] = [],
    conflicts: list[str] = [], findings: dict[str, any] = {}, action: str = "needs_information") -> StageResult {
    return StageResult(stage=stage, status="blocked", findings={**findings, "summary": message},
        evidence_refs=refs, missing_fields=fields, conflicts=conflicts, next_action=action);
}
