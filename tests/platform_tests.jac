# Member A: deterministic platform checks; no real database or provider calls.
import os;
import io;
import base64;
import json;
import tempfile;
import mongomock;
import from mongomock.gridfs { enable_gridfs_integration }
import from PIL { Image }
import from types { SimpleNamespace }
import from pathlib { Path }
import from data.connection { _use_test_database, _get_database }
import from data.repositories { _get_case_record, _claim_stage, _commit_stage }
import from data.seed { _seed_catalogue }
import from shared.contracts { StageResult, FixoraError }
import from shared.validation { _new_id }
import from workflow.coordinator { _set_test_handlers }
import from server.cases { create_case, get_case, list_cases, update_case, start_assessment, advance_case }
import from server.evidence { upload_evidence, get_evidence, remove_evidence }

glob TOKEN: str = "fixora-unit-test-token-not-a-real-secret";

def _reset() {
    os.environ.pop("MONGODB_URI", None);
    os.environ["FIXORA_MONGODB_URI"] = "mongodb://localhost:27017";
    os.environ["MONGODB_DB"] = "fixora_unit_tests";
    os.environ["FIXORA_ACCESS_TOKEN"] = TOKEN;
    os.environ["FIXORA_SHOP_TIMEZONE"] = "Asia/Colombo";
    enable_gridfs_integration();
    # mongomock 4.3 predates PyMongo's client-side operation-timeout option.
    # Model that option on the TEST client; production GridFS remains unpatched.
    mongo_client = mongomock.MongoClient();
    mongo_client.options = SimpleNamespace(timeout=None);
    _use_test_database(mongo_client["fixora_unit_tests"]);
    _set_test_handlers({});
}

def _png() -> str {
    buffer = io.BytesIO();
    image = Image.new("RGB", (4, 4), "white");
    image.save(buffer, format="PNG");
    image.close();
    return base64.b64encode(buffer.getvalue()).decode("ascii");
}

def _case() -> dict[str, any] {
    result = create_case(description="Laptop will not power on", submission_id=_new_id(), access_token=TOKEN);
    assert result.ok, str(result.error);
    return result.data["case"] as dict[str, any];
}

def _ready_case() -> dict[str, any] {
    item = _case();
    for kind in ["invoice", "product"] {
        result = upload_evidence(case_id=item["id"] as str, expected_revision=item["revision"] as int,
            kind=kind, filename=kind + ".png", content_base64=_png(), request_id=_new_id(), access_token=TOKEN);
        assert result.ok, str(result.error);
        item = result.data["case"] as dict[str, any];
    }
    return item;
}

def _started_case() -> dict[str, any] {
    item = _ready_case();
    result = start_assessment(case_id=item["id"] as str, expected_revision=item["revision"] as int,
        request_id=_new_id(), access_token=TOKEN);
    assert result.ok, str(result.error);
    return result.data["case"] as dict[str, any];
}

def _good(context: dict[str, any]) -> StageResult {
    stage = context["stage"] as str;
    assert "access_token" not in context and "mongodb_uri" not in context;
    if stage in ["document", "vision"] { assert len(context["attachments"]) == 1; }
    return StageResult(stage=stage, status="completed", findings={"summary": "Test-only result"},
        evidence_refs=[record["id"] for record in context["evidence"]] as list[str],
        next_action="complete" if stage == "resolution" else "continue");
}

def _advance(item: dict[str, any], request_id: str = "") -> dict[str, any] {
    result = advance_case(case_id=item["id"] as str, assessment_id=item["active_assessment_id"] as str,
        expected_revision=item["revision"] as int, request_id=request_id or _new_id(), access_token=TOKEN);
    assert result.ok, str(result.error);
    return result.data["case"] as dict[str, any];
}

test "access is checked before reading case data" {
    _reset();
    result = get_case(case_id="bad-id", access_token="wrong");
    assert not result.ok and result.error is not None and result.error.code == "UNAUTHORIZED";
}

test "missing access configuration fails closed" {
    _reset();
    os.environ["FIXORA_ACCESS_TOKEN"] = "short";
    result = list_cases(access_token=TOKEN);
    assert not result.ok and result.error is not None and result.error.code == "ACCESS_NOT_CONFIGURED";
}

test "create submission is idempotent and rejects changed input" {
    _reset();
    request_id = _new_id();
    first = create_case("Power problem", request_id, access_token=TOKEN);
    second = create_case("Power problem", request_id, access_token=TOKEN);
    assert first.ok and second.ok and first.data["case"]["id"] == second.data["case"]["id"];
    conflict = create_case("Different problem", request_id, access_token=TOKEN);
    assert not conflict.ok and conflict.error is not None and conflict.error.code == "IDEMPOTENCY_CONFLICT";
}

test "invalid case IDs and empty descriptions are rejected" {
    _reset();
    invalid = get_case("not-a-case", access_token=TOKEN);
    assert not invalid.ok and invalid.error is not None and invalid.error.code == "VALIDATION_ERROR";
    empty = create_case("  ", _new_id(), access_token=TOKEN);
    assert not empty.ok and _get_database().cases.count_documents({}) == 0;
}

test "GridFS round trip and upload retry preserve one file" {
    _reset();
    item = _case();
    request_id = _new_id();
    first = upload_evidence(item["id"] as str, 0, "invoice", "../invoice.png", _png(), request_id, TOKEN);
    assert first.ok, str(first.error);
    second = upload_evidence(item["id"] as str, 0, "invoice", "../invoice.png", _png(), request_id, TOKEN);
    assert second.ok;
    evidence_id = first.data["uploaded_evidence"]["id"] as str;
    downloaded = get_evidence(item["id"] as str, evidence_id, TOKEN);
    assert downloaded.ok and downloaded.data["content_base64"] == _png();
    assert downloaded.data["filename"] == "invoice.png";
    assert _get_database()["uploads.files"].count_documents({}) == 1;
}

test "evidence cannot be read through a different case" {
    _reset();
    item = _ready_case();
    other = _case();
    result = get_evidence(other["id"] as str, item["evidence_ids"][0] as str, TOKEN);
    assert not result.ok and result.error is not None and result.error.code == "NOT_FOUND";
}

test "invalid images and excessive invoices are rejected" {
    _reset();
    item = _case();
    invalid = upload_evidence(item["id"] as str, 0, "invoice", "fake.png", "bm90LWFuLWltYWdl", _new_id(), TOKEN);
    assert not invalid.ok and _get_database()["uploads.files"].count_documents({}) == 0;
    first = upload_evidence(item["id"] as str, 0, "invoice", "first.png", _png(), _new_id(), TOKEN);
    assert first.ok;
    extra = upload_evidence(item["id"] as str, 1, "invoice", "second.png", _png(), _new_id(), TOKEN);
    assert not extra.ok and extra.error is not None and extra.error.code == "VALIDATION_ERROR";
}

test "removing evidence unlinks it without erasing historical bytes" {
    _reset();
    item = _ready_case();
    evidence_id = item["evidence_ids"][0] as str;
    result = remove_evidence(item["id"] as str, evidence_id, item["revision"] as int, TOKEN);
    assert result.ok and len(result.data["case"]["evidence_ids"]) == 1;
    assert _get_database()["uploads.files"].count_documents({}) == 2;
    denied = get_evidence(item["id"] as str, evidence_id, TOKEN);
    assert not denied.ok;
}

test "start requires invoice and product evidence" {
    _reset();
    item = _case();
    result = start_assessment(item["id"] as str, 0, _new_id(), TOKEN);
    assert not result.ok and result.error is not None and result.error.code == "MISSING_EVIDENCE";
}

test "missing specialist fails honestly and same stage can be retried" {
    _reset();
    item = _started_case();
    item = _advance(item);
    assert item["status"] == "failed";
    assert item["assessment"]["stages"]["document"]["error"]["code"] == "SPECIALIST_UNAVAILABLE";
    _set_test_handlers({"document": _good});
    retried = _advance(item);
    assert retried["status"] == "processing" and retried["assessment"]["next_stage"] == 1;
}

test "coordinator completes five bounded stages without approval" {
    _reset();
    _set_test_handlers({"document": _good, "vision": _good, "coverage": _good,
        "repair_parts": _good, "resolution": _good});
    item = _started_case();
    for ordinal in range(5) {
        item = _advance(item);
        assert item["assessment"]["next_stage"] == ordinal + 1;
    }
    assert item["status"] == "completed" and len(item["assessment"]["stages"]) == 5;
}

test "duplicate advance request does not run another stage" {
    _reset();
    _set_test_handlers({"document": _good});
    item = _started_case();
    request_id = _new_id();
    first = _advance(item, request_id);
    duplicate = _advance(item, request_id);
    assert first["revision"] == duplicate["revision"] and duplicate["assessment"]["next_stage"] == 1;
}

def _conflicting(context: dict[str, any]) -> StageResult {
    return StageResult(stage=context["stage"] as str, status="completed", conflicts=["Invoice model differs from product label"]);
}

test "conflicts route to information even when specialist says completed" {
    _reset();
    _set_test_handlers({"document": _conflicting});
    item = _advance(_started_case());
    assert item["status"] == "needs_information" and item["assessment"]["next_stage"] == 0;
    result = advance_case(item["id"] as str, item["active_assessment_id"] as str,
        item["revision"] as int, _new_id(), TOKEN);
    assert not result.ok and result.error is not None and result.error.code == "INVALID_STATE";
}

def _inspection(context: dict[str, any]) -> StageResult {
    return StageResult(stage=context["stage"] as str, status="blocked", next_action="needs_inspection");
}

test "uncertain evidence ends in an inspection recommendation" {
    _reset();
    _set_test_handlers({"document": _inspection});
    item = _advance(_started_case());
    assert item["status"] == "needs_inspection";
}

def _invalid(context: dict[str, any]) -> StageResult {
    return StageResult(stage=context["stage"] as str, status="completed", evidence_refs=[_new_id()]);
}

test "invented evidence references cannot be committed as findings" {
    _reset();
    _set_test_handlers({"document": _invalid});
    item = _advance(_started_case());
    assert item["status"] == "failed";
    assert item["assessment"]["stages"]["document"]["error"]["code"] == "INVALID_SPECIALIST_RESULT";
}

test "stage lease prevents concurrent claims" {
    _reset();
    item = _started_case();
    claimed = _claim_stage(item["id"] as str, item["active_assessment_id"] as str, item["revision"] as int, _new_id());
    assert claimed is not None;
    try {
        _claim_stage(item["id"] as str, item["active_assessment_id"] as str, claimed["revision"] as int, _new_id());
        assert False, "Second claim should fail";
    } except FixoraError as error { assert error.code == "STAGE_BUSY"; }
}

test "late result from expired lease cannot overwrite new claim" {
    _reset();
    item = _started_case();
    first = _claim_stage(item["id"] as str, item["active_assessment_id"] as str, item["revision"] as int, _new_id());
    assert first is not None;
    _get_database().cases.update_one({"_id": item["id"]}, {"$set": {"stage_lease.expires_at": "2000-01-01T00:00:00+00:00"}});
    second = _claim_stage(item["id"] as str, item["active_assessment_id"] as str, first["revision"] as int, _new_id());
    assert second is not None;
    result: dict[str, any] = {"stage": "document", "status": "completed", "next_action": "continue"};
    try {
        _commit_stage(first, result, "processing");
        assert False, "Expired result should be rejected";
    } except FixoraError as error { assert error.code == "STALE_REVISION"; }
}

test "input correction archives old results and rejects stale revisions" {
    _reset();
    _set_test_handlers({"document": _good});
    item = _advance(_started_case());
    updated = update_case(item["id"] as str, item["revision"] as int, "Corrected product information", access_token=TOKEN);
    assert updated.ok and updated.data["case"]["assessment"] is None;
    assert _get_database().assessments.count_documents({"case_id": item["id"]}) == 1;
    stale = update_case(item["id"] as str, item["revision"] as int, "Stale update", access_token=TOKEN);
    assert not stale.ok and stale.error is not None and stale.error.code == "STALE_REVISION";
}

test "case pagination returns each case once" {
    _reset();
    for _index in range(5) { _case(); }
    cursor = "";
    found: set[str] = set();
    for _page in range(3) {
        result = list_cases(limit=2, cursor=cursor, access_token=TOKEN);
        assert result.ok;
        for item in result.data["cases"] {
            assert item["id"] not in found;
            found.add(item["id"]);
        }
        cursor = result.data["next_cursor"] or "";
    }
    assert len(found) == 5;
}

def _seed_input() -> dict[str, list[dict[str, any]]] {
    return {"products": [{"_id": "model-1", "manufacturer": "Demo", "model_code": "M1", "display_name": "Demo laptop"}],
        "policies": [{"_id": "policy-1", "version": 1, "duration_months": 12,
            "clauses": [{"id": "clause-1", "text": "Fictional test policy"}], "expiry_rule": "inclusive"}],
        "repairs": [{"_id": "repair-1", "diagnosis_code": "display", "compatible_model_ids": ["model-1"],
            "required_part_types": ["display"], "labour_cost_minor": 1000}],
        "inventory": [{"_id": "part-1", "sku": "DISPLAY-1", "part_type": "display",
            "compatible_model_ids": ["model-1"], "quantity_available": 3, "unit_price_minor": 2500, "currency": "LKR"}]};
}

def _write_seed_input(folder: str, payload: dict[str, list[dict[str, any]]]) {
    for name in payload {
        (Path(folder) / (name + ".json")).write_text(json.dumps(payload[name]), encoding="utf-8");
    }
}

test "seeding is repeatable and does not modify cases" {
    _reset();
    item = _case();
    with tempfile.TemporaryDirectory() as folder {
        _write_seed_input(folder, _seed_input());
        _seed_catalogue(folder);
        _seed_catalogue(folder);
    }
    assert _get_database().inventory.count_documents({}) == 1;
    assert _get_database().inventory.find_one({"sku": "DISPLAY-1"})["quantity_available"] == 3;
    assert _get_case_record(item["id"] as str)["revision"] == 0;
}

test "invalid seed compatibility prevents all catalogue writes" {
    _reset();
    payload = _seed_input();
    payload["inventory"][0]["compatible_model_ids"] = ["unknown-model"];
    with tempfile.TemporaryDirectory() as folder {
        _write_seed_input(folder, payload);
        try {
            _seed_catalogue(folder);
            assert False, "Invalid catalogue should not be written";
        } except FixoraError as error { assert error.code == "VALIDATION_ERROR"; }
    }
    assert _get_database().products.count_documents({}) == 0;
    assert _get_database().policies.count_documents({}) == 0;
}
