# Owner: Member A. JSON/base64 transport; one validated image per request.
import from shared.contracts { ApiResult }
import from data.files { _upload_image, _read_image, _remove_image }
import from data.repositories { _evidence_view }
import from server.cases { _case_payload }
import from server.responses { _api_call }

def:pub upload_evidence(case_id: str, expected_revision: int, kind: str, filename: str,
    content_base64: str, request_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _upload_payload, [case_id, expected_revision, kind, filename, content_base64, request_id]);
}

def _upload_payload(case_id: str, expected_revision: int, kind: str, filename: str,
    content_base64: str, request_id: str) -> dict[str, any] {
    metadata = _upload_image(case_id, expected_revision, kind, filename, content_base64, request_id);
    payload = _case_payload(case_id);
    payload["uploaded_evidence"] = _evidence_view(metadata);
    return payload;
}

def:pub get_evidence(case_id: str, evidence_id: str, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _read_image, [case_id, evidence_id]);
}

def:pub remove_evidence(case_id: str, evidence_id: str, expected_revision: int, access_token: str = "") -> ApiResult {
    return _api_call(access_token, _remove_payload, [case_id, evidence_id, expected_revision]);
}

def _remove_payload(case_id: str, evidence_id: str, expected_revision: int) -> dict[str, any] {
    _remove_image(case_id, evidence_id, expected_revision);
    return _case_payload(case_id);
}
