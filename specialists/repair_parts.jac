import from shared.contracts { StageResult, FixoraError }
import from specialists.common { _mode, _refs, _prior, _blocked }
import from rules.compatibility { _choose_part }
import from rules.pricing { _estimate }

def run_stage(context: dict[str, any]) -> StageResult {
    invoice = _prior(context, "document")["invoice"];
    observations = _prior(context, "vision")["observations"];
    _prior(context, "coverage");
    model_id = invoice["model_id"] as str;
    categories = set(row["category"] for row in observations);
    catalogue = context["catalogue"];
    options: list[dict[str, any]] = [];
    unsupported: list[str] = [];
    for repair in catalogue["repairs"] {
        if model_id not in repair.get("compatible_model_ids", []) or repair.get("diagnosis_code") not in categories { continue; }
        parts: list[dict[str, any]] = [];
        absent: list[str] = [];
        for part_type in repair["required_part_types"] {
            part = _choose_part(model_id, part_type as str, catalogue["inventory"], repair.get("currency", "") as str);
            if part is None { absent.append(part_type as str); continue; }
            parts.append({"sku": part["sku"], "model_id": model_id, "part_type": part["part_type"],
                "quantity_available": part["quantity_available"], "unit_price_minor": part["unit_price_minor"],
                "currency": part["currency"], "inventory_id": part["_id"]});
        }
        if absent { unsupported.extend(absent); continue; }
        estimate = _estimate(repair, parts);
        refs = list(dict.fromkeys(ref for row in observations if row["category"] == repair["diagnosis_code"] for ref in row["evidence_refs"]));
        options.append({"repair_id": repair["_id"], "title": repair["title"], "model_id": model_id,
            "observation_category": repair["diagnosis_code"], "explanation": "Possible repair for the visible observation; confirm by physical inspection.",
            "parts": parts, "estimate": estimate, "evidence_refs": refs, "provisional": True,
            "availability": "in_stock" if all(part["quantity_available"] > 0 for part in parts) else "out_of_stock",
            "turnaround_estimate": None});
    }
    findings: dict[str, any] = {"options": options, "analysis_mode": _mode(context),
        "unmatched_part_types": sorted(set(unsupported)), "inventory_reserved": False,
        "limitations": ["Stock and prices are a read-only snapshot and may change.", "No internal fault, final repair, or payment is authorized by this estimate."]};
    if not options {
        return _blocked("repair_parts", "No complete compatible repair option is available in the catalogue. Inspection is required.",
            _refs(context), findings=findings, action="needs_inspection");
    }
    return StageResult(stage="repair_parts", status="completed", findings=findings, evidence_refs=_refs(context));
}
