import from dataclasses { asdict }
import from shared.contracts { StageResult, FixoraError }
import from specialists.schemas { PhotoExtraction }
import from specialists.inference { _extract }
import from specialists.common { _mode, _refs, _prior, _blocked }
import from rules.compatibility { _normalize }

def run_stage(context: dict[str, any]) -> StageResult {
    refs = _refs(context, "product");
    if not context["attachments"] { return _blocked("vision", "Upload at least one product image.", refs, ["product_photo"]); }
    invoice = _prior(context, "document")["invoice"];
    outputs = _extract(context, "vision") as list[PhotoExtraction];
    if not isinstance(outputs, list) or len(outputs) != len(context["attachments"]) {
        raise FixoraError("MODEL_INVALID_OUTPUT", "Expected one observation per product image.");
    }
    observations: list[dict[str, any]] = [];
    conflicts: list[str] = [];
    for (index, output) in enumerate(outputs) {
        if not isinstance(output, PhotoExtraction) or type(output.image_index) is not int or output.image_index != index
            or output.category not in ["screen_crack", "hinge_damage", "keyboard_damage", "cosmetic_damage", "no_visible_damage", "unknown"]
            or output.severity not in ["cosmetic", "moderate", "severe", "unknown"] {
            raise FixoraError("MODEL_INVALID_OUTPUT", "Product observation has invalid index, category or severity.");
        }
        if not isinstance(output.description, str) or len(output.description) > 600 or not isinstance(output.limitations, list)
            or len(output.limitations) > 5 or not all(isinstance(item, str) and len(item) <= 300 for item in output.limitations) {
            raise FixoraError("MODEL_INVALID_OUTPUT", "Product observation text is invalid.");
        }
        for label in [output.manufacturer, output.model_code, output.serial_number] {
            if label is not None and (not isinstance(label, str) or len(label) > 200) {
                raise FixoraError("MODEL_INVALID_OUTPUT", "Product label text is invalid.");
            }
        }
        if output.model_code and _normalize(output.model_code) != _normalize(invoice.get("model_code")) {
            conflicts.append("Printed product model differs from the invoice model in image " + str(index + 1) + ".");
        }
        if output.manufacturer and invoice.get("manufacturer") and _normalize(output.manufacturer) != _normalize(invoice["manufacturer"]) {
            conflicts.append("Printed manufacturer differs from the invoice.");
        }
        if output.serial_number and invoice.get("serial_number") and _normalize(output.serial_number) != _normalize(invoice["serial_number"]) {
            conflicts.append("Printed device serial number differs from the invoice.");
        }
        record = asdict(output) as dict[str, any];
        record["evidence_refs"] = [context["attachments"][index]["evidence_id"]];
        record["provisional"] = True;
        observations.append(record);
    }
    findings: dict[str, any] = {"observations": observations, "analysis_mode": _mode(context),
        "limitations": ["Images cannot establish internal faults or prove the cause of damage.",
            "An unreadable product label leaves product identity unverified."],
        "identity_verified": `any(bool(output.model_code) for output in outputs)};
    if conflicts { return _blocked("vision", "Product identity conflicts with the invoice.", refs, conflicts=conflicts, findings=findings); }
    # Only authenticated owner operations can populate this field. A customer
    # message or an image instruction can never establish a confirmed diagnosis.
    inspection = context.get("owner_inspection");
    if inspection and inspection.get("diagnosis_code") in ["screen_crack", "hinge_damage", "keyboard_damage"] {
        observations.append({"category": inspection["diagnosis_code"], "description": inspection["notes"],
            "severity": "unknown", "evidence_refs": refs, "provisional": False, "source": "owner_inspection"});
        findings["owner_inspection"] = inspection;
    }
    description = _normalize(context["description"]);
    hidden_fault = `any(phrase in description for phrase in ["no power", "no_power", "not power", "won't turn on", "will not turn on", "not turning on", "overheat", "charging", "battery", "liquid", "water", "burn", "smoke"]);
    actionable = `any(row["category"] in ["screen_crack", "hinge_damage", "keyboard_damage"] for row in observations);
    if hidden_fault or not actionable {
        return _blocked("vision", "Physical inspection is needed to establish the reported fault. Visible damage does not prove its cause.", refs,
            findings=findings, action="needs_inspection");
    }
    return StageResult(stage="vision", status="completed", findings=findings, evidence_refs=refs);
}
