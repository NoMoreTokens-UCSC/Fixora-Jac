import from shared.contracts { StageResult }
import from specialists.common { _mode, _refs, _prior, _blocked }
import from rules.warranty { _coverage }

def run_stage(context: dict[str, any]) -> StageResult {
    invoice = _prior(context, "document")["invoice"];
    observations = _prior(context, "vision")["observations"];
    policy = context["catalogue"].get("policy");
    result = _coverage(invoice, policy, observations, context["evaluation_date"] as str);
    clauses: list[dict[str, any]] = [];
    if policy is not None {
        clause_ids = result.get("clause_ids", []) as list[str];
        clauses = [row for row in policy.get("clauses", []) if row.get("id") in clause_ids] as list[dict[str, any]];
    }
    findings: dict[str, any] = {"coverage": result, "policy_clauses": clauses, "analysis_mode": _mode(context), "decision_method": "deterministic_policy"};
    if result["outcome"] in ["needs_information", "needs_inspection"] {
        return _blocked("coverage", result["explanation"] as str, _refs(context),
            fields=["valid_purchase_date"] if result["outcome"] == "needs_information" else [],
            findings=findings, action=result["outcome"] as str);
    }
    return StageResult(stage="coverage", status="completed", findings=findings, evidence_refs=_refs(context));
}
