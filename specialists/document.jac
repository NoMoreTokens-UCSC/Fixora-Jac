import from dataclasses { asdict }
import from shared.contracts { StageResult, FixoraError }
import from specialists.schemas { InvoiceExtraction }
import from specialists.inference { _extract }
import from specialists.common { _mode, _refs, _blocked }
import from rules.compatibility { _resolve_model }
import from rules.warranty { _iso_date }

def run_stage(context: dict[str, any]) -> StageResult {
    refs = _refs(context, "invoice");
    if len(context["attachments"]) != 1 { return _blocked("document", "Upload one invoice image.", refs, ["invoice"]); }
    extracted = _extract(context, "document");
    if not isinstance(extracted, InvoiceExtraction) { raise FixoraError("MODEL_INVALID_OUTPUT", "Invoice extraction has an invalid structure."); }
    invoice = asdict(extracted) as dict[str, any];
    for name in ["invoice_number", "purchase_date", "manufacturer", "model_code", "serial_number", "seller", "currency"] {
        if invoice[name] is not None and (not isinstance(invoice[name], str) or len(invoice[name]) > 200) {
            raise FixoraError("MODEL_INVALID_OUTPUT", "Invoice extraction contains an invalid text field.");
        }
    }
    if not isinstance(invoice["source_text"], str) or len(invoice["source_text"]) > 2000
        or (invoice["amount_minor"] is not None and (type(invoice["amount_minor"]) is not int or invoice["amount_minor"] < 0)) {
        raise FixoraError("MODEL_INVALID_OUTPUT", "Invoice transcription or amount is invalid.");
    }
    model_id = _resolve_model(invoice["manufacturer"], invoice["model_code"], context["catalogue"]["products"]);
    invoice["model_id"] = model_id;
    invoice["evidence_refs"] = refs;
    fields: list[str] = [];
    conflicts: list[str] = [];
    purchased = _iso_date(invoice["purchase_date"]);
    today = _iso_date(context["evaluation_date"]);
    if purchased is None or today is None or purchased > today { fields.append("valid_purchase_date"); }
    if model_id is None { fields.append("supported_printed_model_code"); }
    claimed = context.get("claimed_model_id", "");
    if claimed and model_id and claimed != model_id { conflicts.append("The selected product differs from the model printed on the invoice."); }
    findings: dict[str, any] = {"invoice": invoice, "analysis_mode": _mode(context),
        "limitations": ["Extracted invoice text is not proof that an invoice is authentic."]};
    if fields or conflicts { return _blocked("document", "Clarify invoice details before assessment.", refs, fields, conflicts, findings); }
    return StageResult(stage="document", status="completed", findings=findings, evidence_refs=refs);
}
