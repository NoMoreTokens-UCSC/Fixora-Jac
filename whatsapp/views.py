"""Render saved Jac findings, without a second assessment or catalogue."""


def findings(case):
    assessment = case.get("assessment") or {}
    return {name: record.get("findings", {}) for name, record in assessment.get("stages", {}).items()}


def customer_summary(case):
    data = findings(case)
    lines = ["Case " + case["_id"], "Assessment: " + case["status"].replace("_", " ") + "."]
    for stage in (case.get("assessment") or {}).get("stages", {}).values():
        if stage.get("status") == "blocked":
            lines.extend(stage.get("conflicts", []))
            lines.extend("Please clarify: " + field.replace("_", " ") for field in stage.get("missing_fields", []))
            explanation = stage.get("findings", {}).get("summary") or stage.get("findings", {}).get("explanation")
            if explanation:
                lines.append(explanation)
    coverage = data.get("coverage", {}).get("coverage", {})
    if coverage:
        lines.append("Warranty: " + str(coverage.get("outcome", "needs review")).replace("_", " ") + ". " + coverage.get("explanation", ""))
    for option in data.get("repair_parts", {}).get("options", []):
        estimate = option.get("estimate", {})
        total = estimate.get("total_cost_minor")
        price = f"; estimate {estimate.get('currency', '')} {total / 100:.2f}" if type(total) is int else ""
        lines.append(option["title"] + " (provisional); " + option["availability"].replace("_", " ") + price + ".")
    if case["status"] == "failed":
        lines.append("Processing failed. Your evidence is saved. Reply RETRY, or ask the shop for help.")
    elif case["status"] == "needs_inspection":
        lines.append("The shop needs to inspect the device to establish the fault. Please arrange an in-store inspection.")
    elif case["status"] == "needs_information":
        lines.append("Please provide the requested correction or replace the unclear evidence, then reply READY.")
    elif case["status"] == "completed":
        lines.append("The shop must review this proposal before a repair is approved. Stock is not reserved and final payment is not determined.")
    else:
        lines.append("Send your complaint, invoice image and device photos. Reply READY when your uploads are complete.")
    review = case.get("review_status", "unreviewed")
    if review != "unreviewed":
        lines.append("Shop review: " + review.replace("_", " ") + ".")
    return "\n".join(lines)[:4000]


def case_view(store, case, products=None):
    data = findings(case)
    invoice = data.get("document", {}).get("invoice", {})
    coverage = data.get("coverage", {}).get("coverage", {})
    vision = data.get("vision", {})
    options = data.get("repair_parts", {}).get("options", [])
    assessment = case.get("assessment") or {}
    products = {p["id"]: p["name"] for p in (store.products() if products is None else products)}
    status = case["status"]
    review = case.get("review_status", "unreviewed")
    if review in ("needs_information", "needs_inspection"):
        status = review
    elif status == "completed":
        status = review if review in ("approved", "rejected") and case.get("review_assessment_id") == case.get("active_assessment_id") else "awaiting_approval"
    evidence = []
    for record in store.db.evidence.find({"_id": {"$in": case["evidence_ids"]}, "case_id": case["_id"]}):
        evidence.append({"id": record["_id"], "name": record["filename"], "kind": record["kind"],
                         "mime": record["mime_type"], "size": record["size_bytes"],
                         "preview": ""})
    messages = []
    delivery = {row["_id"]: row["status"] for row in store.db.wa_outbox.find({"case_id": case["_id"]})}
    for message in case.get("messages", []):
        messages.append({**{k: message.get(k, "") for k in ("id", "role", "text", "at")},
                         "internal": message.get("internal", False), "kind": "", "revision": 0,
                         "delivery": delivery.get(message["id"], "queued" if message.get("publication_pending") else "")})
    observations = vision.get("observations", [])
    limitations = []
    for stage in data.values():
        limitations.extend(stage.get("limitations", []))
    result = {
        "purchase_date": invoice.get("purchase_date") or "Unknown", "expiry_date": coverage.get("expiry_date") or "Unknown",
        "invoice": invoice.get("invoice_number") or "Unknown", "serial": invoice.get("serial_number") or "Unknown",
        "seller": invoice.get("seller") or "Unknown", "policy": str(coverage.get("policy_id", "Not evaluated")),
        "eligibility": "Within the date period" if coverage.get("date_eligible") is True else "See policy assessment",
        "coverage": str(coverage.get("outcome", "Not evaluated")).replace("_", " "),
        "rationale": coverage.get("explanation") or "No policy assessment is available for the current inputs.",
        "observation": " ".join(row.get("description", "") for row in observations) or "No saved visual observations.",
        "limitation": " ".join(dict.fromkeys(limitations)) or "No confirmed diagnosis is available.",
        "repair": "; ".join(row["title"] for row in options) or "No supported repair option yet",
        "part": "", "stock": 0, "part_minor": 0, "labour_minor": 0,
        "next_action": customer_summary(case), "invoice_total": "Unknown", "currency": invoice.get("currency") or "",
    }
    if type(invoice.get("amount_minor")) is int:
        result["invoice_total"] = f"{invoice.get('currency') or ''} {invoice['amount_minor'] / 100:.2f}"
    modes = {row.get("analysis_mode") for row in data.values()}
    mode = "Recorded fixture extraction" if "demo_fixture" in modes else "Live model extraction and fixed rules"
    availability = {"revision": case["revision"], "status": "unchecked", "compatibility": "unknown", "provisional": True,
                    "requirement": result["repair"], "stock": 0, "unit_minor": 0, "labour_minor": 0,
                    "part_name": "", "sku": "", "currency": "", "checked_at": case["updated_at"], "explanation": "No compatible repair option has been saved."}
    if options:
        option = options[0]
        parts = option.get("parts", [])
        estimate = option.get("estimate", {})
        availability.update(status=option["availability"], compatibility="confirmed", part_name=option["title"],
            sku=", ".join(part["sku"] for part in parts), stock=min((part["quantity_available"] for part in parts), default=0),
            unit_minor=sum(part["unit_price_minor"] for part in parts), labour_minor=estimate.get("labour_cost_minor", 0),
            explanation=option["explanation"], currency=estimate.get("currency", ""))
    inspection = case.get("owner_inspection") or {}
    return {"id": case["_id"], "reference": case["_id"], "title": case["description"][:90],
            "description": case["description"], "model": products.get(case.get("claimed_model_id"), invoice.get("model_code") or "Unconfirmed"),
            "customer": case.get("customer_name") or case["sender_id"], "customer_id": case["sender_id"],
            "scenario": "live", "status": status, "assessment_status": case["status"], "review_status": review,
            "revision": case["revision"], "version": case["revision"], "stage": assessment.get("next_stage", 0),
            "assessed_revision": case["revision"] if case["status"] == "completed" else -1,
            "coverage": coverage.get("outcome", "needs_review"), "updated_at": case["updated_at"],
            "inspection": inspection.get("notes", ""), "diagnosis": inspection.get("diagnosis_code", ""),
            "correction": "", "evidence": evidence, "messages": messages, "decisions": case.get("decisions", []),
            "availability": availability, "findings": result, "analysis_mode": mode}
