# Same-origin HTTP adapter. No database/provider secrets or fixture results in the client.
import from .models { CaseRecord, Message, Evidence, Assessment }

glob _cases: list[CaseRecord] = [];
glob _previews: dict = {};

def:pub stamp() -> str { return new(Date).toISOString(); }
def:pub uid() -> str { browser_window: any = window; return browser_window.crypto.randomUUID() as str; }
def:pub error_message(error: any) -> str { return error.message as str if error and error.message else str(error); }
def:pub status_label(status: str) -> str {
    names: dict = {"draft": "Draft", "processing": "Assessing", "needs_information": "Needs information", "needs_inspection": "Needs inspection", "completed": "Assessment ready", "failed": "Needs retry", "outside_period": "Outside warranty period", "potentially_covered": "Potentially covered", "needs_review": "Needs review"};
    return (names[status] as str) if names[status] else status;
}
cl def:pub model_image(model: str) -> str {
    if model == "Fixora Demo FD-200" { return "device-graphite"; }
    if model == "Fixora Demo FD-300" { return "device-compact"; }
    return "device-silver";
}
def model_id(model: str) -> str {
    ids: dict = {"Fixora Demo FD-100": "demo-laptop-01", "Fixora Demo FD-200": "demo-laptop-02", "Fixora Demo FD-300": "demo-laptop-03"};
    return (ids[model] as str) if ids[model] else ("" if model == "Unspecified model" else model);
}
def model_name(id: str) -> str {
    names: dict = {"demo-laptop-01": "Fixora Demo FD-100", "demo-laptop-02": "Fixora Demo FD-200", "demo-laptop-03": "Fixora Demo FD-300"};
    return (names[id] as str) if names[id] else (id or "Unspecified model");
}
def:pub disconnect() {
    sessionStorage.removeItem("fixora-api-token");
    sessionStorage.removeItem("fixora-session-token"); _cases = []; _previews = {};
}
async def:pub api_call(endpoint: str, body: any) -> any {
    if endpoint != "demo_login" {
        token = sessionStorage.getItem("fixora-session-token");
        if not token { raise Exception("Please sign in to connect to the server."); }
        body.access_token = token;
    }
    response: any = None;
    try {
        response = await fetch("/function/" + endpoint, {"method": "POST", "headers": {"Content-Type": "application/json"}, "body": JSON.stringify(body)});
    } except Exception { raise Exception("The server could not be reached. Your request may have been saved; reload the latest case before retrying."); }
    if not response.ok { raise Exception("The server rejected the request (HTTP " + str(response.status) + "). Reload the case before retrying."); }
    envelope: any = await response.json();
    result: any = envelope.data.result if envelope and envelope.ok and envelope.data else None;
    if not result { raise Exception("The server returned an unexpected response. Check that the Fixora backend is running."); }
    if not result.ok {
        detail: any = result.error;
        raise Exception((str(detail.code) + ": " + str(detail.message)) if detail else "The operation could not be completed.");
    }
    return result.data;
}
async def:pub connect(role: str, email: str, password: str) -> None {
    disconnect();
    try {
        session: any = await api_call("demo_login", {"email": email, "password": password, "role": role});
        if not session.session_token or session.role != role { raise Exception("The server returned an invalid sign-in session."); }
        sessionStorage.setItem("fixora-session-token", session.session_token);
        await api_call("platform_status", {});
    }
    except Exception as error { disconnect(); raise error; }
}
def remember(c: CaseRecord) -> CaseRecord {
    _cases = [c] + [old for old in _cases if old.id != c.id];
    return c;
}
def:pub adapt_case(raw: any) -> CaseRecord {
    c = CaseRecord(id=raw.id, reference="FX-" + (raw.id as str)[:8].upper(), description=raw.description or "", title=(raw.description or "Repair request")[:54], model=model_name(raw.claimed_model_id or ""), status=raw.status, revision=raw.revision, updated_at=raw.updated_at, backend=raw);
    c.customer = "Hackathon customer";
    c.messages = [Message(id=c.id + "-description", role="customer", text=c.description, at=raw.created_at or raw.updated_at)];
    current: any = raw.assessment;
    if current {
        c.stage = current.next_stage;
        c.assessed_revision = c.revision if c.status == "completed" else 0;
        stages: any = current.stages;
        for name in ["document", "vision", "coverage", "repair_parts", "resolution"] {
            stage: any = stages[name];
            if not stage { continue; }
            if stage.error { c.failure = str(stage.error.code) + ": " + str(stage.error.message); }
            detail: any = stage.findings;
            text: str = str(detail.summary or ("Stage completed." if stage.status == "completed" else "Further information is required."));
            if stage.conflicts and len(stage.conflicts) > 0 { text = text + " " + " ".join(stage.conflicts); }
            if stage.missing_fields and len(stage.missing_fields) > 0 { text = text + " Missing: " + ", ".join(stage.missing_fields); }
            c.messages = c.messages + [Message(id=str(current.id) + "-" + name, text=name + ": " + (str(c.failure) if stage.error else str(text)), at=stage.finished_at or raw.updated_at)];
        }
        coverage: any = stages.coverage;
        if coverage and coverage.findings.coverage { c.coverage = coverage.findings.coverage.outcome; }
    }
    if raw.evidence {
        c.evidence = [Evidence(id=e.id, name=e.filename, kind="photo" if e.kind == "product" else "invoice", mime=e.mime_type, size=e.size_bytes, preview=(_previews[e.id] as str) if _previews[e.id] else "") for e in raw.evidence];
    }
    return c;
}
async def hydrate(raw: any) -> CaseRecord {
    # Only the selected case downloads images. Previews are memory-only.
    if raw.evidence {
        for e in raw.evidence {
            if not _previews[e.id] {
                image: any = await api_call("get_evidence", {"case_id": raw.id, "evidence_id": e.id});
                _previews[e.id] = "data:" + image.mime_type + ";base64," + image.content_base64;
            }
        }
    }
    return remember(adapt_case(raw));
}
async def:pub load_cases() -> list[CaseRecord] { return _cases; }
async def:pub refresh_cases() -> list[CaseRecord] {
    if not sessionStorage.getItem("fixora-session-token") { _cases = []; return []; }
    rows: list[CaseRecord] = []; cursor: str = "";
    while True {
        page: any = await api_call("list_cases", {"limit": 50, "cursor": cursor});
        for raw in page.cases {
            cached = [old for old in _cases if old.id == raw.id and old.revision == raw.revision and old.backend and old.backend.evidence];
            rows = rows + [cached[0] if len(cached) > 0 else adapt_case(raw)];
        }
        if not page.next_cursor { break; }
        cursor = page.next_cursor;
    }
    _cases = rows; return rows;
}
async def:pub get_case(case_id: str) -> CaseRecord {
    data: any = await api_call("get_case", {"case_id": case_id});
    return await hydrate(data.case);
}
async def:pub search_cases(query: str, persona: str, owner: bool) -> list[CaseRecord] {
    await refresh_cases(); needle = query.strip().lower();
    return [c for c in _cases if not needle or needle in (c.reference + " " + c.title + " " + c.model + " " + c.description).lower()];
}
async def:pub create_case(customer_id: str, model: str, description: str) -> CaseRecord {
    if not description.strip() { raise Exception("Describe the problem before creating the case."); }
    data: any = await api_call("create_case", {"description": description.strip(), "claimed_model_id": model_id(model), "submission_id": uid()});
    return remember(adapt_case(data.case));
}
async def:pub correct_case(case_id: str, expected: int, model: str, description: str, actor: str = "customer") -> CaseRecord {
    if not description.strip() { raise Exception("Enter the corrected problem description."); }
    data: any = await api_call("update_case", {"case_id": case_id, "expected_revision": expected, "description": description.strip(), "claimed_model_id": model_id(model)});
    return await hydrate(data.case);
}
async def:pub send_message(case_id: str, expected: int, text: str) -> CaseRecord {
    if not text.strip() { raise Exception("Write an update before sending."); }
    c = await get_case(case_id);
    updated = c.description + "\n\nCustomer update: " + text.strip();
    if len(updated) > 4000 { raise Exception("The combined problem description must be 4,000 characters or fewer. Use Edit details to shorten it."); }
    return await correct_case(case_id, expected, c.model, updated);
}
async def:pub attach_evidence(case_id: str, expected: int, evidence: Evidence) -> CaseRecord {
    data: any = await api_call("upload_evidence", {"case_id": case_id, "expected_revision": expected, "kind": "product" if evidence.kind == "photo" else "invoice", "filename": evidence.name, "content_base64": evidence.preview.split(",")[1], "request_id": uid()});
    _previews[data.uploaded_evidence.id] = evidence.preview;
    return await hydrate(data.case);
}
async def:pub remove_evidence(case_id: str, expected: int, evidence_id: str) -> CaseRecord {
    data: any = await api_call("remove_evidence", {"case_id": case_id, "expected_revision": expected, "evidence_id": evidence_id});
    return await hydrate(data.case);
}
async def:pub advance_case(case_id: str, expected: int) -> CaseRecord {
    c = await get_case(case_id);
    if c.revision != expected { raise Exception("STALE_REVISION: This case changed. Reload the latest case before assessing."); }
    if c.status == "draft" {
        started: any = await api_call("start_assessment", {"case_id": case_id, "expected_revision": expected, "request_id": uid()});
        return await hydrate(started.case);
    }
    data: any = await api_call("advance_case", {"case_id": case_id, "assessment_id": c.backend.active_assessment_id, "expected_revision": expected, "request_id": uid()});
    return await hydrate(data.case);
}
def:pub assessment(c: CaseRecord) -> Assessment {
    a = Assessment();
    if not c.backend or not c.backend.assessment { return a; }
    stages: any = c.backend.assessment.stages;
    limitations: list[str] = [];
    for name in ["document", "vision", "coverage", "repair_parts", "resolution"] {
        s: any = stages[name];
        if not s { continue; }
        f: any = s.findings;
        if f.analysis_mode { a.mode = f.analysis_mode; }
        if f.limitations { limitations = limitations + f.limitations; }
        if f.summary { a.next_action = f.summary; }
        if name == "document" and f.invoice {
            inv: any = f.invoice;
            a.invoice = inv.invoice_number or "Not extracted"; a.serial = inv.serial_number or "Not extracted";
            a.purchase_date = inv.purchase_date or "Not extracted"; a.seller = inv.seller or "Not extracted";
            if inv.amount_minor != None and inv.currency { a.invoice_total = money(inv.amount_minor, inv.currency); }
        }
        if name == "vision" and f.observations { a.observation = " ".join([row.description for row in f.observations]); }
        if name == "coverage" and f.coverage {
            cov: any = f.coverage;
            a.coverage = status_label(cov.outcome); a.rationale = cov.explanation;
            a.expiry_date = cov.expiry_date or "Not evaluated";
            a.eligibility = "Within the policy period; coverage is a separate decision." if cov.date_eligible == True else ("Outside the policy period." if cov.date_eligible == False else "Date eligibility is unresolved.");
            a.policy = (cov.policy_id or "Unknown policy") + " · version " + str(cov.policy_version);
            a.clauses = f.policy_clauses or [];
        }
        if name == "repair_parts" { a.options = f.options or []; }
        if name == "resolution" and f.report {
            a.next_action = f.report.recommendation;
            limitations = limitations + (f.report.limitations or []);
        }
    }
    if len(limitations) > 0 { a.limitation = " ".join(limitations); }
    if c.failure { a.next_action = c.failure + " Your inputs are saved; retry or correct the configuration."; }
    return a;
}
def:pub money(amount: int, currency: str) -> str { return f"{currency} {amount / 100:.2f}"; }

# Decode locally for validation, then upload plain base64 to the API.
async def:pub read_image(file: any, kind: str, onProgress: Callable[[int], None]) -> Evidence {
    if file.type not in ["image/jpeg", "image/png"] { raise Exception("Choose a JPEG or PNG image."); }
    if file.size > 5242880 { raise Exception("Each image must be 5 MB or smaller."); }
    browser_window: any = window;
    error_type: any = browser_window.Error;
    data: str = await new(Promise, lambda (resolve: any, reject: any) {
        reader: any = new(FileReader as any);
        reader.onprogress = lambda (event: any) { if event.lengthComputable { onProgress(min(90, int((event.loaded as float) / (event.total as float) * 90.0))); } };
        reader.onload = lambda { resolve.call(None, reader.result); };
        reader.onerror = lambda { reject.call(None, new(error_type, "The image could not be read.")); };
        reader.readAsDataURL(file);
    });
    await new(Promise, lambda (resolve: any, reject: any) {
        image: any = new(Image as any);
        image.onload = lambda {
            if image.naturalWidth * image.naturalHeight > 25000000 { reject.call(None, new(error_type, "Choose an image with at most 25 million pixels.")); }
            else { resolve.call(None, True); }
        };
        image.onerror = lambda { reject.call(None, new(error_type, "This file is not a readable image.")); };
        image.src = data;
    });
    onProgress(95);
    return Evidence(id=uid(), name=file.name as str, kind=kind, mime=file.type as str, size=file.size as int, preview=data);
}
