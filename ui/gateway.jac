import from "idb-keyval" { get, update }
import from .models { CaseRecord, Message, Evidence, Decision, Assessment, PartAvailability }
import from .inventory { lookup_parts, requirement_for }

glob _cases: list[CaseRecord] = [];
glob _loaded: bool = False;
glob _writing: bool = False;
glob _key: str = "fixora-demo-v1";

def:pub stamp() -> str { return new(Date).toISOString(); }
def:pub uid() -> str { browser_window: any = window; return browser_window.crypto.randomUUID() as str; }
def:pub clone_case(c: CaseRecord) -> CaseRecord {
    copy = JSON.parse(JSON.stringify(c)) as CaseRecord;
    if not copy.availability { copy.availability = PartAvailability(); }
    for m in copy.messages {
        if not m.kind { m.kind = ""; }
        if not m.revision { m.revision = 0; }
    }
    return copy;
}
def:pub message(role: str, text: str, internal: bool = False) -> Message {
    return Message(id=uid(), role=role, text=text, at=stamp(), internal=internal);
}
def:pub status_label(status: str) -> str {
    names: dict = {"draft": "Draft", "processing": "Assessing", "needs_information": "Needs information", "needs_inspection": "Needs inspection", "awaiting_approval": "Awaiting review", "approved": "Approved", "rejected": "Warranty declined", "failed": "Needs retry"};
    return (names[status] as str) if names[status] else status;
}
cl def:pub model_image(model: str) -> str {
    if model == "Pro 15" { return "device-graphite"; }
    if model == "Air 13" { return "device-compact"; }
    return "device-silver";
}
cl def:pub error_message(error: any) -> str {
    return error.message as str if error and error.message else str(error);
}
def:pub assessment(c: CaseRecord) -> Assessment {
    a = Assessment();
    a.part = "FX-CH14 · " + c.model + " charging connector";
    if c.model == "Pro 15" { a.part = "FX-CH15 · Pro 15 charging connector"; }
    if c.model == "Air 13" { a.part = "FX-CH13 · Air 13 charging connector"; }
    if c.scenario == "conflict" and not c.clarified {
        a.coverage = "Needs review";
        a.rationale = "Invoice model Studio 14 conflicts with the sample product label Pro 15. Confirm the correct product before evaluating coverage.";
        a.next_action = "Confirm the laptop model and provide the matching invoice in chat.";
    }
    if c.scenario == "inspection" and c.diagnosis != "Charging connector failure confirmed" {
        a.coverage = "Needs review";
        a.observation = "The sample label identifies the device, but the complaint's power failure cannot be diagnosed from this identity evidence.";
        a.rationale = "A visible scratch does not establish the cause of a power failure. No exclusion is applied without supporting evidence.";
        a.next_action = "Bring the laptop to the shop for a physical inspection.";
    }
    if c.scenario == "rejected" {
        a.purchase_date = "2024-03-12";
        a.expiry_date = "2025-03-12";
        a.eligibility = "Outside the sample warranty period";
        a.coverage = "Outside period";
        a.rationale = "Sample rule W-01: the fictional 12-month warranty has expired. Paid repair remains available.";
        a.next_action = "The shop can discuss a paid repair; this is not a rejection of repair service.";
    }
    if c.scenario == "no_stock" {
        a.stock = 0;
        a.next_action = "The compatible part is out of stock. Arrival and completion dates are unknown.";
    }
    if c.scenario in ["missing_charger", "uncertain_compatibility"] {
        a.coverage = "Accessory request · shop review";
        a.rationale = "A reported missing charger is not proof of a warranty-covered defect. Accessory cost and any coverage must be confirmed by the shop.";
        a.repair = "Confirm a compatible replacement charger";
        a.next_action = "Check the sample part availability below, then ask the shop about collection. No purchase or reservation occurs here.";
    }
    if c.inspection { a.observation = "Owner inspection: " + c.inspection; }
    if c.correction { a.rationale = a.rationale + " Recorded correction: " + c.correction; }
    if c.scenario == "auto" {
        a.rationale = "Sample rule A-01: the fixture includes a previously verified charging-connector diagnosis and all sample approval conditions.";
    }
    if c.status == "approved" { a.next_action = "The recorded proposal is approved. Read the shop response for its conditions and the next step."; }
    if c.status == "rejected" { a.next_action = "The warranty request was declined. A paid repair remains available; read the recorded reason."; }
    return a;
}

def fixture_evidence(model: str, kind: str, prefix: str, purchase: str = "2026-03-12") -> Evidence {
    title = "SYNTHETIC INVOICE" if kind == "invoice" else "SYNTHETIC PRODUCT LABEL";
    detail = "INV-DEMO-1048 | Purchase " + purchase + " | USD 899.00" if kind == "invoice" else "Serial FX-DEMO-0142 | Device identity reference";
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="600" viewBox="0 0 900 600"><rect width="900" height="600" fill="#f5f5f7"/><rect x="60" y="50" width="780" height="500" rx="16" fill="white" stroke="#ddd"/><text x="100" y="120" font-size="20" fill="#6853a6" font-family="Arial">FIXORA / FICTIONAL DEMO EVIDENCE</text><text x="100" y="210" font-size="32" fill="#222" font-family="Arial">' + title + '</text><text x="100" y="280" font-size="25" fill="#333" font-family="Arial">Model: ' + model + '</text><text x="100" y="340" font-size="20" fill="#444" font-family="Arial">' + detail + '</text><text x="100" y="460" font-size="18" fill="#777" font-family="Arial">Illustrative fixture. Not a real invoice or customer photograph.</text></svg>';
    return Evidence(id=prefix + "-" + kind, name="sample-" + kind + ".svg", kind=kind, mime="image/svg+xml", size=len(svg), preview="data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg));
}

def seed() -> list[CaseRecord] {
    result: list[CaseRecord] = [];
    scenarios = ["complete", "conflict", "inspection", "auto", "rejected", "no_stock", "failure"];
    titles = ["My laptop is not charging", "Invoice and device don't match", "Laptop will not power on", "Charging port repair", "Warranty period enquiry", "Replacement charging connector", "Assessment was interrupted"];
    for (i, scenario) in enumerate(scenarios) {
        c = CaseRecord(id="sample-" + scenario, reference="FX-" + str(1048 + i), title=titles[i], scenario=scenario, stage=5, assessed_revision=1, status="awaiting_approval", coverage="potentially_covered", updated_at=stamp());
        c.description = "My laptop only charges when I hold the cable at an angle. Can you help me check the warranty?";
        c.model = "Pro 15" if i % 3 == 1 else ("Air 13" if i % 3 == 2 else "Studio 14");
        c.customer = "Alex Morgan" if i < 4 else "Jamie Chen";
        c.customer_id = "alex" if i < 4 else "jamie";
        invoice_model = "Studio 14" if scenario == "conflict" else c.model;
        purchase = "2024-03-12" if scenario == "rejected" else "2026-03-12";
        c.evidence = [fixture_evidence(invoice_model, "invoice", c.id, purchase), fixture_evidence(c.model, "photo", c.id)];
        c.messages = [message("assistant", "Hi " + c.customer.split(" ")[0] + ". Tell me what is happening with your laptop. You can attach your invoice and up to three photos."), message("customer", c.description), message("assistant", "I have prepared a sample assessment for " + c.model + ". This demonstration uses fixture findings; no uploaded image has been analysed.")];
        if scenario == "conflict" {
            c.status = "needs_information";
            c.coverage = "needs_review";
            c.messages = c.messages + [message("assistant", "The sample invoice says Studio 14, while the sample product label says Pro 15. Which model do you have? Please add the matching invoice and confirm the model below.")];
        }
        if scenario == "inspection" {
            c.status = "needs_inspection";
            c.coverage = "needs_review";
            c.messages = c.messages + [message("shop", "We need to inspect the laptop to establish the cause of the power fault. Please bring the device and charger to the shop.")];
        }
        if scenario == "auto" or scenario == "rejected" {
            c.status = "approved" if scenario == "auto" else "rejected";
            c.coverage = "potentially_covered" if scenario == "auto" else "outside_period";
            reason = "Sample rule A-01 passed: the fixture includes a verified diagnosis and matching evidence." if scenario == "auto" else "Sample rule W-01: warranty expired on 12 March 2025. Paid repair remains available.";
            c.decisions = [Decision(id=uid(), action=c.status, reason=reason, origin="automatic", revision=1, at=stamp())];
            c.messages = c.messages + [message("shop", reason)];
        }
        if scenario == "failure" { c.status = "failed"; c.stage = 1; c.assessed_revision = 0; }
        result = result + [c];
    }
    return result;
}

async def:pub load_cases() -> list[CaseRecord] {
    if not _loaded {
        await update(_key, lambda (stored: any) { return stored if stored else JSON.parse(JSON.stringify(seed())); });
        _cases = await get(_key) as list[CaseRecord];
        _loaded = True;
    }
    return [clone_case(c) for c in _cases];
}
async def:pub get_case(case_id: str) -> CaseRecord {
    await load_cases();
    for c in _cases { if c.id == case_id { return clone_case(c); } }
    raise Exception("This case could not be found. Refresh the saved-case list.");
}

async def:pub refresh_cases() -> list[CaseRecord] {
    _loaded = False;
    return await load_cases();
}
async def:pub search_cases(query: str, persona: str, owner: bool) -> list[CaseRecord] {
    rows: list[CaseRecord] = await load_cases();
    needle = query.strip().lower();
    return [c for c in rows if (owner or c.customer_id == persona) and (not needle or needle in (c.reference + " " + c.title + " " + c.model + " " + c.customer + " " + " ".join([m.text for m in c.messages if owner or not m.internal])).lower())];
}

def publish_availability(c: CaseRecord) {
    a = c.availability;
    if a.revision != c.revision or a.status in ["unchecked", "error"] { return; }
    key = str(c.revision) + ":" + a.sku + ":" + a.status;
    previous = [m for m in c.messages if m.kind == "availability:" + key and m.revision == c.revision];
    if previous { a.message_id = previous[0].id; a.publication_key = key; return; }
    text = "Sample stock check: compatibility is uncertain. Please confirm your model and the matching part specification with the shop; no availability offer has been made.";
    if a.status == "in_stock" and a.compatibility == "confirmed" {
        text = "Sample stock check: " + a.part_name + " (" + a.sku + ") is available from our shop for " + c.model + ". " + str(a.stock) + " in sample stock. Ask us here about collection or installation. No stock is reserved and no purchase has been made.";
        if a.provisional { text = text + " This is a candidate replacement; the shop must confirm the fault and final fit before any repair."; }
    } elif a.status == "out_of_stock" {
        text = "Sample stock check: " + a.part_name + " matches " + c.model + ", but it is out of stock. Arrival is unknown; ask the shop about alternatives. No availability offer has been made.";
    }
    m = message("assistant", text); m.kind = "availability:" + key; m.revision = c.revision;
    c.messages = c.messages + [m]; a.message_id = m.id; a.publication_key = key;
}

async def:pub check_parts(case_id: str, expected: int, retry: bool = False) -> CaseRecord {
    c = await get_case(case_id);
    if c.stage < 4 or c.status in ["needs_information", "needs_inspection", "draft", "failed"] {
        raise Exception("Resolve the case details and assess the current revision before checking parts.");
    }
    c.availability = await lookup_parts(c, retry);
    if c.stage == 5 { publish_availability(c); }
    return await persist(c, expected);
}
async def persist(c: CaseRecord, expected: int) -> CaseRecord {
    if _writing { raise Exception("Another change is being saved. Please try again."); }
    _writing = True;
    try {
        c.updated_at = stamp();
        previous_version = c.version;
        c.version = c.version + 1;
        def apply_change(previous: any) -> any {
            records: list[CaseRecord] = (previous as list[CaseRecord]) if previous else [];
            for old in records {
                if old.id == c.id and (old.revision != expected or old.version != previous_version) {
                    raise Exception("This case changed in another view. Reload the latest case before saving; your text has been kept.");
                }
            }
            updated = [c if old.id == c.id else old for old in records];
            if not [old for old in records if old.id == c.id] { updated = [c] + records; }
            return JSON.parse(JSON.stringify(updated));
        }
        await update(_key, apply_change);
        _cases = await get(_key) as list[CaseRecord];
    } finally { _writing = False; }
    return clone_case(c);
}
async def:pub create_case(customer_id: str, model: str, scenario: str) -> CaseRecord {
    await load_cases();
    c = CaseRecord(id=uid(), reference="FX-" + str(1100 + len(_cases)), customer_id=customer_id, model=model, scenario=scenario, updated_at=stamp());
    c.customer = "Jamie Chen" if customer_id == "jamie" else "Alex Morgan";
    c.messages = [message("assistant", "Hi " + c.customer.split(" ")[0] + ". Let's take a look at your laptop. Tell me what is happening, and attach your invoice and product photos when you're ready.")];
    return await persist(c, 1);
}
async def:pub send_message(case_id: str, expected: int, text: str) -> CaseRecord {
    if not text.strip() { raise Exception("Write a message before sending."); }
    if len(text) > 4000 { raise Exception("Keep your message to 4,000 characters or fewer."); }
    c = await get_case(case_id);
    c.messages = c.messages + [message("customer", text.strip())];
    if not c.description {
        c.description = text.strip();
        c.title = text.strip()[:54];
        c.revision = c.revision + 1;
        c.messages = c.messages + [message("assistant", "Thanks for explaining. Please add one invoice and one to three product photos, then choose Assess complaint. Results in this preview come from the selected demo scenario.")];
    } else {
        c.messages = c.messages + [message("assistant", "Your follow-up is saved with this case for the shop to review. If the evidence or model needs correcting, use Confirm details below before reassessing.")];
    }
    return await persist(c, expected);
}
async def:pub send_shop_message(case_id: str, expected: int, text: str) -> CaseRecord {
    if not text.strip() { raise Exception("Write a reply before sending."); }
    if len(text) > 4000 { raise Exception("Keep your reply to 4,000 characters or fewer."); }
    c = await get_case(case_id);
    c.messages = c.messages + [message("shop", text.strip())];
    return await persist(c, expected);
}
async def:pub attach_evidence(case_id: str, expected: int, evidence: Evidence) -> CaseRecord {
    c = await get_case(case_id);
    limit = 1 if evidence.kind == "invoice" else 3;
    if len([e for e in c.evidence if e.kind == evidence.kind]) >= limit {
        raise Exception("This case already has its maximum " + evidence.kind + " attachments.");
    }
    c.evidence = c.evidence + [evidence];
    c.revision = c.revision + 1;
    c.status = "draft";
    c.stage = 0;
    c.coverage = "needs_review";
    c.messages = c.messages + [message("assistant", "Saved " + evidence.name + ". Updated evidence needs a fresh assessment; earlier decisions are retained as history.")];
    return await persist(c, expected);
}
async def:pub correct_case(case_id: str, expected: int, model: str, correction: str, actor: str = "customer") -> CaseRecord {
    if not correction.strip() { raise Exception("Explain the correction so its source is recorded."); }
    c = await get_case(case_id);
    c.model = model;
    c.correction = correction.strip();
    c.clarified = True;
    c.revision = c.revision + 1;
    c.stage = 0;
    c.status = "draft";
    c.coverage = "needs_review";
    c.messages = c.messages + [message(actor, "Confirmed model: " + model + ". " + correction.strip())];
    return await persist(c, expected);
}

async def:pub remove_evidence(case_id: str, expected: int, evidence_id: str) -> CaseRecord {
    c = await get_case(case_id);
    c.evidence = [e for e in c.evidence if e.id != evidence_id];
    c.revision = c.revision + 1;
    c.status = "draft";
    c.stage = 0;
    c.coverage = "needs_review";
    return await persist(c, expected);
}
async def:pub inspect_case(case_id: str, expected: int, diagnosis: str, notes: str) -> CaseRecord {
    if not diagnosis or not notes.strip() { raise Exception("Select a supported finding and enter inspection notes."); }
    c = await get_case(case_id);
    c.inspection = diagnosis + ". " + notes.strip();
    c.diagnosis = diagnosis;
    c.revision = c.revision + 1;
    c.status = "draft";
    c.stage = 0;
    c.coverage = "needs_review";
    c.messages = c.messages + [message("internal", "Inspection recorded: " + c.inspection, True)];
    return await persist(c, expected);
}
async def:pub advance_case(case_id: str, expected: int) -> CaseRecord {
    c = await get_case(case_id);
    if not c.description { raise Exception("Describe the problem before starting an assessment."); }
    if c.id[:7] != "sample-" {
        if not [e for e in c.evidence if e.kind == "invoice"] or not [e for e in c.evidence if e.kind == "photo"] {
            raise Exception("Attach one invoice and at least one product photo before assessing.");
        }
    }
    if c.status == "approved" or c.status == "rejected" {
        raise Exception("Correct the inputs or record an inspection to create a revised assessment.");
    }
    if c.status == "failed" { c.retried = True; }
    c.status = "processing";
    c.stage = min(c.stage + 1, 5);
    if c.stage == 4 { c.availability = await lookup_parts(c); }
    if c.scenario == "failure" and c.stage == 2 and not c.retried {
        c.status = "failed";
        c.messages = c.messages + [message("assistant", "The sample vision stage timed out. Your evidence is saved. Choose Retry assessment to resume; this is not a warranty rejection.")];
    } elif c.scenario == "conflict" and not c.clarified and c.stage >= 2 {
        c.status = "needs_information";
        c.messages = c.messages + [message("assistant", assessment(c).next_action)];
    } elif c.scenario == "inspection" and c.diagnosis != "Charging connector failure confirmed" and c.stage >= 3 {
        c.status = "needs_inspection";
        c.messages = c.messages + [message("assistant", assessment(c).next_action)];
    } elif c.stage == 5 {
        c.status = "awaiting_approval";
        c.coverage = "potentially_covered";
        c.assessed_revision = c.revision;
        if c.scenario in ["missing_charger", "uncertain_compatibility"] { c.coverage = "needs_review"; }
        c.messages = c.messages + [message("assistant", "Your sample assessment is ready. " + assessment(c).next_action + " See the evidence-backed summary below.")];
        if c.scenario == "auto" or c.scenario == "rejected" {
            c.status = "approved" if c.scenario == "auto" else "rejected";
            c.coverage = "potentially_covered" if c.scenario == "auto" else "outside_period";
            reason = assessment(c).rationale;
            c.decisions = c.decisions + [Decision(id=uid(), action=c.status, reason=reason, origin="automatic", revision=c.revision, at=stamp())];
            c.messages = c.messages + [message("shop", reason)];
        }
        publish_availability(c);
    }
    return await persist(c, expected);
}
async def:pub review_case(case_id: str, expected: int, action: str, reason: str) -> CaseRecord {
    if not reason.strip() { raise Exception("Enter a reason or customer-facing message before saving."); }
    c = await get_case(case_id);
    if (action == "approved" or action == "rejected") and (c.stage != 5 or c.assessed_revision != c.revision) {
        raise Exception("Assess the latest case revision before approving or rejecting.");
    }
    if action == "approved" and c.status in ["needs_information", "needs_inspection"] {
        raise Exception("Resolve the missing information or inspection finding and reassess before approving.");
    }
    if action not in ["approved", "rejected", "needs_information", "needs_inspection"] { raise Exception("Unsupported review action."); }
    c.status = action;
    c.decisions = c.decisions + [Decision(id=uid(), action=action, reason=reason.strip(), revision=c.revision, at=stamp())];
    c.messages = c.messages + [message("shop", status_label(action) + ": " + reason.strip())];
    return await persist(c, expected);
}

# FileReader is a browser boundary; only decoded JPEG/PNG previews are persisted.
async def:pub read_image(file: any, kind: str, onProgress: Callable[[int], None]) -> Evidence {
    if file.type not in ["image/jpeg", "image/png"] { raise Exception("Choose a JPEG or PNG image."); }
    if file.size > 5242880 { raise Exception("Each image must be 5 MB or smaller."); }
    browser_window: any = window;
    error_type: any = browser_window.Error;
    data: str = await new(Promise, lambda (resolve: any, reject: any) {
        reader: any = new(FileReader as any);
        reader.onprogress = lambda (event: any) {
            loaded_bytes: float = event.loaded as float;
            total_bytes: float = event.total as float;
            if event.lengthComputable and total_bytes > 0 { onProgress(min(90, int(loaded_bytes / total_bytes * 90.0))); }
        };
        reader.onload = lambda { resolve.call(None, reader.result); };
        reader.onerror = lambda { reject.call(None, new(error_type, "The file could not be read. Please choose it again.")); };
        reader.readAsDataURL(file);
    });
    await new(Promise, lambda (resolve: any, reject: any) {
        image: any = new(Image as any);
        image.onload = lambda {
            if image.naturalWidth > 12000 or image.naturalHeight > 12000 {
                reject.call(None, new(error_type, "Choose an image smaller than 12,000 pixels on each side."));
            } else { resolve.call(None, True); }
        };
        image.onerror = lambda { reject.call(None, new(error_type, "This file is not a readable image.")); };
        image.src = data;
    });
    onProgress(95);
    return Evidence(id=uid(), name=file.name as str, kind=kind, mime=file.type as str, size=file.size as int, preview=data);
}
