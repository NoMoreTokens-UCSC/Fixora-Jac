# Owner: Member A. Explicitly import public operations in main.jac for registration.
import from shared.contracts { ApiResult }
import from shared.statuses { STAGES }
import from data.connection { _get_database }
import from data.repositories { _create_case_record, _get_case_record, _case_view,
    _evidence_records, _evidence_view, _list_case_records, _update_case_record,
    _start_assessment_record }
import from workflow.coordinator { _advance_case_record, _load_handler }
import from server.responses { _api_call }

def _case_payload(case_id: str) -> dict[str, any] {
    item = _get_case_record(case_id);
    view = _case_view(item);
    view["evidence"] = [_evidence_view(record) for record in _evidence_records(item)];
    return {"case": view};
}

def:pub create_case(description: str, submission_id: str, claimed_model_id: str = "", access_token: str = "") -> ApiResult {
    return _api_call(access_token, _create_payload, [description, claimed_model_id, submission_id]);
}

def _create_payload(description: str, claimed_model_id: str, submission_id: str) -> dict[str, any] {
    item = _create_case_record(description, claimed_model_id, submission_id);
    return _case_payload(item["_id"] as str);
}

def:pub get_case(case_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _case_payload, [case_id]);
}

def:pub list_cases(limit: int = 20, cursor: str = "", access_token: str = "") -> ApiResult {
    return _api_call(access_token, _list_case_records, [limit, cursor]);
}

def:pub update_case(case_id: str, expected_revision: int, description: str, claimed_model_id: str = "", access_token: str = "") -> ApiResult {
    return _api_call(access_token, _update_payload, [case_id, expected_revision, description, claimed_model_id]);
}

def _update_payload(case_id: str, expected_revision: int, description: str, claimed_model_id: str) -> dict[str, any] {
    _update_case_record(case_id, expected_revision, description, claimed_model_id);
    return _case_payload(case_id);
}

def:pub start_assessment(case_id: str, expected_revision: int, request_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _start_payload, [case_id, expected_revision, request_id]);
}

def _start_payload(case_id: str, expected_revision: int, request_id: str) -> dict[str, any] {
    _start_assessment_record(case_id, expected_revision, request_id);
    return _case_payload(case_id);
}

def:pub advance_case(case_id: str, assessment_id: str, expected_revision: int, request_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _advance_payload, [case_id, assessment_id, expected_revision, request_id]);
}

def _advance_payload(case_id: str, assessment_id: str, expected_revision: int, request_id: str) -> dict[str, any] {
    _advance_case_record(case_id, assessment_id, expected_revision, request_id);
    return _case_payload(case_id);
}

def _platform_payload() -> dict[str, any] {
    _get_database().command("ping");
    specialists: dict[str, str] = {};
    for stage in STAGES {
        try { _load_handler(stage); specialists[stage] = "ready"; }
        except Exception { specialists[stage] = "unavailable"; }
    }
    return {"database": "connected", "jac_baseline": "0.34.13", "specialists": specialists,
        "workflow": "worker-advanced bounded stages", "human_review": "owner_gateway"};
}

def:pub platform_status(access_token: str = "") -> ApiResult {
    return _api_call(access_token, _platform_payload);
}
