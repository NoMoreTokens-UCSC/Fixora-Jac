import from shared.contracts { StageResult }
import from specialists.common { _mode, _refs, _prior }

def run_stage(context: dict[str, any]) -> StageResult {
    document = _prior(context, "document");
    vision = _prior(context, "vision");
    coverage = _prior(context, "coverage");
    repairs = _prior(context, "repair_parts");
    options = repairs["options"];
    in_stock = `any(option["availability"] == "in_stock" for option in options);
    limitations: list[str] = [];
    for stage_findings in [document, vision, repairs] {
        limitations.extend(stage_findings.get("limitations", []) as list[str]);
    }
    limitations = list(dict.fromkeys(limitations));
    final_report: dict[str, any] = {"headline": "Provisional repair assessment ready", "case_id": context["case_id"],
        "analysis_mode": _mode(context), "is_demo": bool(context.get("demo_mode", False)),
        "evaluation_date": context["evaluation_date"], "shop_timezone": context["shop_timezone"],
        "invoice": document["invoice"], "observations": vision["observations"],
        "identity_verified": vision["identity_verified"], "coverage": coverage["coverage"],
        "policy_clauses": coverage["policy_clauses"], "repair_options": options,
        "recommendation": "Arrange physical inspection to confirm the proposed repair." if in_stock else "Confirm spare-part supply and arrange physical inspection.",
        "limitations": limitations, "customer_payable_minor": None, "turnaround_estimate": None,
        "evidence_refs": _refs(context), "inventory_reserved": False};
    if final_report["is_demo"] { final_report["demo_notice"] = "Synthetic evidence and recorded extractions; no live model call was made."; }
    return StageResult(stage="resolution", status="completed", findings={"report": final_report, "analysis_mode": _mode(context)},
        evidence_refs=_refs(context), next_action="complete");
}
