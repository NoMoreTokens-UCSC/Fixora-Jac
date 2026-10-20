# Owner browser gateway. All service tokens, model keys and Meta credentials
# remain in the local Python/Jac services, never in this client bundle.
cl {
import from .models { CaseRecord, Evidence, Assessment }

def:pub uid() -> str { browser_window: any = window; return browser_window.crypto.randomUUID() as str; }
def:pub stamp() -> str { return new(Date).toISOString(); }
def:pub error_message(error: any) -> str { return error.message as str if error and error.message else str(error); }
def:pub owner_base() -> str {
    browser_window: any = window;
    return str(browser_window.location.protocol) + "//" + str(browser_window.location.hostname) + ":8011";
}
async def:pub owner_request(path: str, method: str = "GET", body: any = None) -> any {
    options: any = {"method": method, "credentials": "include", "cache": "no-store"};
    if body is not None { options.headers = {"Content-Type": "application/json"}; options.body = JSON.stringify(body); }
    response = await fetch(owner_base() + path, options);
    data: any = await response.json();
    if response.status == 401 and path != "/owner/login" {
        browser_window: any = window;
        browser_window.dispatchEvent(new(Event, "fixora-session-expired"));
    }
    if not response.ok { raise Exception(data.error or data.detail or "The owner service is unavailable."); }
    return data;
}
async def:pub owner_session() -> bool {
    response = await fetch(owner_base() + "/owner/session", {"credentials": "include", "cache": "no-store"});
    return response.ok;
}
async def:pub owner_login(password: str) -> None { await owner_request("/owner/login", "POST", {"password": password}); }
async def:pub owner_logout() -> None { await owner_request("/owner/logout", "POST", {}); }
async def:pub load_models() -> list[str] {
    data = await owner_request("/owner/models");
    return [m.name as str for m in data.models];
}
def:pub hydrate(c: CaseRecord) -> CaseRecord {
    for e in c.evidence { e.preview = owner_base() + "/owner/cases/" + c.id + "/evidence/" + e.id; }
    return c;
}
async def:pub load_cases() -> list[CaseRecord] {
    data = await owner_request("/owner/cases");
    return [hydrate(c as CaseRecord) for c in data.cases];
}
async def:pub refresh_cases() -> list[CaseRecord] { return await load_cases(); }
async def:pub get_case(case_id: str) -> CaseRecord {
    data = await owner_request("/owner/cases/" + case_id);
    return hydrate(data.case as CaseRecord);
}
async def:pub search_cases(query: str, persona: str, owner: bool) -> list[CaseRecord] {
    rows = await load_cases(); needle = query.strip().lower();
    return [c for c in rows if not needle or needle in (c.reference + " " + c.title + " " + c.model + " " + c.customer + " " + " ".join([m.text for m in c.messages])).lower()];
}
async def command(case_id: str, expected: int, action: str, payload: any) -> CaseRecord {
    payload.expected_revision = expected; payload.request_id = uid();
    data = await owner_request("/owner/cases/" + case_id + "/" + action, "POST", payload);
    return hydrate(data.case as CaseRecord);
}
async def:pub send_shop_message(case_id: str, expected: int, text: str) -> CaseRecord {
    if not text.strip() { raise Exception("Write a message before sending."); }
    return await command(case_id, expected, "message", {"text": text});
}
async def:pub save_internal_note(case_id: str, expected: int, text: str) -> CaseRecord {
    return await command(case_id, expected, "note", {"text": text});
}
async def:pub correct_case(case_id: str, expected: int, model: str, correction: str, actor: str = "shop") -> CaseRecord {
    return await command(case_id, expected, "correct", {"model": model, "description": correction});
}
async def:pub inspect_case(case_id: str, expected: int, diagnosis: str, notes: str) -> CaseRecord {
    return await command(case_id, expected, "inspection", {"diagnosis": diagnosis, "notes": notes});
}
async def:pub review_case(case_id: str, expected: int, action: str, reason: str) -> CaseRecord {
    return await command(case_id, expected, "review", {"action": action, "reason": reason});
}
async def:pub advance_case(case_id: str, expected: int) -> CaseRecord {
    return await command(case_id, expected, "assess", {});
}
async def:pub retry_delivery(case_id: str, expected: int, message_id: str) -> CaseRecord {
    return await command(case_id, expected, "retry_delivery", {"message_id": message_id});
}
async def:pub check_parts(case_id: str, expected: int, retry: bool = False) -> CaseRecord {
    # Availability is the saved Jac repair/parts snapshot. A fresh assessment
    # refreshes it, including policy and compatibility checks.
    return await get_case(case_id);
}
def:pub assessment(c: CaseRecord) -> Assessment { return c.findings; }
cl def:pub model_image(model: str) -> str { return "device-silver"; }
cl def:pub status_label(status: str) -> str {
    names: dict = {"draft": "Draft", "processing": "Assessing", "needs_information": "Needs information", "needs_inspection": "Needs inspection", "awaiting_approval": "Awaiting review", "approved": "Approved", "rejected": "Warranty declined", "failed": "Needs retry"};
    return (names[status] as str) if names[status] else status;
}
# Kept as explicit errors for the retired customer web view. Customer intake is
# available exclusively through WhatsApp; these operations cannot mutate data.
async def:pub create_case(customer_id: str, model: str, scenario: str) -> CaseRecord { raise Exception("Start a case in WhatsApp."); }
async def:pub send_message(case_id: str, expected: int, text: str) -> CaseRecord { raise Exception("Send customer messages through WhatsApp."); }
async def:pub attach_evidence(case_id: str, expected: int, evidence: Evidence) -> CaseRecord { raise Exception("Send evidence through WhatsApp."); }
async def:pub remove_evidence(case_id: str, expected: int, evidence_id: str) -> CaseRecord { raise Exception("Use REMOVE <image ID> in WhatsApp."); }
async def:pub read_image(file: any, kind: str, onProgress: Callable[[int], None]) -> Evidence { raise Exception("Send evidence through WhatsApp."); }
}
