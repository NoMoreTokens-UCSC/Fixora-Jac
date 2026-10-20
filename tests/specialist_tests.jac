import os;
import json;
import base64;
import mongomock;
import from pathlib { Path }
import from types { SimpleNamespace }
import from mongomock.gridfs { enable_gridfs_integration }
import from jaclang.byllm.lib { Model, MTRuntime }
import from data.connection { _use_test_database, _get_database }
import from data.seed { _seed_catalogue }
import from shared.contracts { FixoraError }
import from shared.validation { _new_id }
import from workflow.coordinator { _set_test_handlers }
import from server.cases { create_case, start_assessment, advance_case }
import from server.evidence { upload_evidence }
import from specialists.inference { _set_model_for_tests, _extract }
import from specialists.schemas { InvoiceExtraction, PhotoExtraction }
import from specialists.document { run_stage as document_stage }
import from specialists.vision { run_stage as vision_stage }
import from specialists.coverage { run_stage as coverage_stage }
import from specialists.repair_parts { run_stage as repair_stage }
import from rules.warranty { _coverage, _iso_date }
import from rules.compatibility { _choose_part, _resolve_model }
import from rules.pricing { _estimate }

glob TOKEN: str = "fixora-specialist-test-token";
glob _provider_schemas: list[dict[str, any]] = [];
glob _provider_image_counts: list[int] = [];

# MockLLM skips provider schema construction. Exercise that boundary explicitly
# so cross-module schema regressions are caught before making a paid API call.
obj _SchemaCheckingModel(Model) {
    def invoke(mt_run: MTRuntime) -> object {
        shape = mt_run.get_output_schema();
        assert shape is not None;
        _provider_schemas.append(shape as dict[str, any]);
        params = self.make_model_params(mt_run);
        image_count = 0;
        for message in (params["messages"] as list[dict[str, any]]) {
            if isinstance(message.get("content"), list) {
                for part in (message["content"] as list[dict[str, any]]) {
                    if part.get("type") == "image_url" { image_count += 1; }
                }
            }
        }
        _provider_image_counts.append(image_count);
        delegate = self._mock_delegate;
        assert delegate is not None;
        return delegate.invoke(mt_run);
    }
}

def _fixtures(name: str) -> any {
    return json.loads((Path.cwd() / "fixtures" / (name + ".json")).read_text(encoding="utf-8"));
}

def _context(stage: str = "document") -> dict[str, any] {
    _set_model_for_tests(None);
    content = base64.b64encode((Path.cwd() / "fixtures/evidence/invoice-expired.png").read_bytes()).decode("ascii");
    return {"case_id": "test-case", "description": "Cracked display", "claimed_model_id": "demo-laptop-01",
        "stage": stage, "model": "", "demo_mode": True, "evaluation_date": "2026-10-17", "shop_timezone": "Asia/Colombo",
        "evidence": [{"id": "invoice-1", "kind": "invoice"}, {"id": "photo-1", "kind": "product"}],
        "attachments": [{"evidence_id": "invoice-1", "content_base64": content}], "prior_results": {},
        "catalogue": {"policy": _fixtures("policies")[0], "products": _fixtures("products"), "repairs": _fixtures("repairs"), "inventory": _fixtures("inventory")}};
}

def _photo_context(file: str) -> dict[str, any] {
    context = _context();
    result = document_stage(context);
    context["prior_results"] = {"document": {"status": result.status, "findings": result.findings}};
    context["stage"] = "vision";
    context["attachments"] = [{"evidence_id": "photo-1", "content_base64": base64.b64encode((Path.cwd() / "fixtures/evidence" / file).read_bytes()).decode("ascii")}];
    return context;
}

def _reset_database() {
    os.environ.pop("MONGODB_URI", None);
    os.environ["FIXORA_MONGODB_URI"] = "mongodb://localhost:27017";
    os.environ["MONGODB_DB"] = "fixora_specialist_tests";
    os.environ["FIXORA_ACCESS_TOKEN"] = TOKEN;
    os.environ["FIXORA_DEMO_MODE"] = "true";
    os.environ["FIXORA_SHOP_TIMEZONE"] = "Asia/Colombo";
    enable_gridfs_integration();
    client = mongomock.MongoClient();
    client.options = SimpleNamespace(timeout=None);
    _use_test_database(client["fixora_specialist_tests"]);
    _set_test_handlers({});
    _set_model_for_tests(None);
    _seed_catalogue();
}

def _run_scenario(scenario: dict[str, any]) -> dict[str, any] {
    result = create_case(scenario["description"] as str, _new_id(), scenario["claimed_model_id"] as str, TOKEN);
    assert result.ok, str(result.error);
    item = result.data["case"] as dict[str, any];
    for kind in ["invoice", "product"] {
        path = Path.cwd() / "fixtures" / (scenario[kind] as str);
        result = upload_evidence(item["id"] as str, item["revision"] as int, kind, path.name,
            base64.b64encode(path.read_bytes()).decode("ascii"), _new_id(), TOKEN);
        assert result.ok, str(result.error);
        item = result.data["case"] as dict[str, any];
    }
    result = start_assessment(item["id"] as str, item["revision"] as int, _new_id(), TOKEN);
    assert result.ok, str(result.error);
    item = result.data["case"] as dict[str, any];
    for ordinal in range(5) {
        if item["status"] != "processing" { break; }
        result = advance_case(item["id"] as str, item["active_assessment_id"] as str, item["revision"] as int, _new_id(), TOKEN);
        assert result.ok, str(result.error);
        item = result.data["case"] as dict[str, any];
    }
    return item;
}

test "expiry includes final day and clamps leap year" {
    policy = _fixtures("policies")[0] as dict[str, any];
    invoice: dict[str, any] = {"purchase_date": "2024-02-29"};
    result = _coverage(invoice, policy, [], "2025-02-28");
    assert result["date_eligible"] and result["expiry_date"] == "2025-02-28";
    assert _coverage(invoice, policy, [], "2025-03-01")["outcome"] == "outside_period";
}

test "missing ambiguous and future purchase dates need information" {
    for value in [None, "10/11/26", "2026-02-30", "2027-01-01"] {
        assert _coverage({"purchase_date": value}, _fixtures("policies")[0], [], "2026-10-17")["outcome"] == "needs_information";
    }
}

test "coverage separates date from visible damage and unknown policy" {
    policy = _fixtures("policies")[0] as dict[str, any];
    invoice: dict[str, any] = {"purchase_date": "2026-08-10"};
    covered = _coverage(invoice, policy, [{"category": "cosmetic_damage"}], "2026-10-17");
    assert covered["date_eligible"] and covered["outcome"] == "potentially_covered";
    excluded = _coverage(invoice, policy, [{"category": "screen_crack"}], "2026-10-17");
    assert excluded["date_eligible"] and excluded["outcome"] == "visible_damage_excluded";
    assert "DEMO-PHYSICAL" in (excluded["clause_ids"] as list[str]);
    assert _coverage(invoice, None, [], "2026-10-17")["outcome"] == "needs_inspection";
}

test "model matching uses exact codes and rejects ambiguous catalogue" {
    products = _fixtures("products") as list[dict[str, any]];
    assert _resolve_model("fixora demo", " fd-100 ", products) == "demo-laptop-01";
    assert _resolve_model("Fixora Demo", "looks like FD", products) is None;
    assert _resolve_model("Another maker", "FD-100", products) is None;
    assert _resolve_model(None, "FD-100", products + [products[0]]) is None;
}

test "compatible stock is preferred and incompatible SKU cannot be selected" {
    inventory = _fixtures("inventory") as list[dict[str, any]];
    before = json.dumps(inventory, sort_keys=True);
    selected = _choose_part("demo-laptop-01", "display_panel", inventory, "LKR");
    assert selected is not None and selected["sku"] == "DEMO-1-DISPLAY_PANEL";
    assert _choose_part("unknown", "display_panel", inventory, "LKR") is None;
    assert _choose_part("demo-laptop-01", "display_panel", inventory, "USD") is None;
    inventory.append({**inventory[0], "sku": "CHEAPER-OUT", "unit_price_minor": 1, "quantity_available": 0});
    assert _choose_part("demo-laptop-01", "display_panel", inventory, "LKR")["sku"] == "DEMO-1-DISPLAY_PANEL";
    inventory.pop();
    assert json.dumps(inventory, sort_keys=True) == before;
}

test "money uses integer minor units and never declares an amount payable" {
    repair = _fixtures("repairs")[0] as dict[str, any];
    part = _fixtures("inventory")[0] as dict[str, any];
    result = _estimate(repair, [part]);
    assert result["total_cost_minor"] == 2650000 and result["customer_payable_minor"] is None;
    try { _estimate(repair, [{**part, "currency": "USD"}]); assert False; }
    except FixoraError as error { assert error.code == "INVALID_CATALOGUE"; }
}

test "fixture extraction is labelled and tied to actual image bytes" {
    context = _context();
    result = document_stage(context);
    assert result.status == "completed" and result.findings["analysis_mode"] == "demo_fixture";
    assert result.findings["invoice"]["evidence_refs"] == ["invoice-1"];
    context["attachments"][0]["content_base64"] = base64.b64encode(b"unrecognized-image").decode("ascii");
    try { document_stage(context); assert False; }
    except FixoraError as error { assert error.code == "DEMO_EVIDENCE_NOT_FOUND"; }
}

test "invoice product mismatch routes to clarification" {
    result = vision_stage(_photo_context("product-mismatch.png"));
    assert result.status == "blocked" and result.next_action == "needs_information" and result.conflicts;
}

test "visible scratch never diagnoses no power fault" {
    context = _photo_context("product-scratch.png");
    context["description"] = "Laptop will not power on";
    result = vision_stage(context);
    assert result.next_action == "needs_inspection";
    assert result.findings["observations"][0]["category"] == "cosmetic_damage";
}

test "out of stock remains provisional and missing compatible parts stops the proposal" {
    context = _photo_context("product-cracked.png");
    vision = vision_stage(context);
    context["prior_results"]["vision"] = {"status": vision.status, "findings": vision.findings};
    coverage = coverage_stage(context);
    context["prior_results"]["coverage"] = {"status": coverage.status, "findings": coverage.findings};
    for row in context["catalogue"]["inventory"] { row["quantity_available"] = 0; }
    proposed = repair_stage(context);
    assert proposed.status == "completed" and proposed.findings["options"][0]["availability"] == "out_of_stock";
    assert proposed.findings["options"][0]["turnaround_estimate"] is None;
    context["catalogue"]["inventory"] = [];
    unsupported = repair_stage(context);
    assert unsupported.next_action == "needs_inspection" and unsupported.findings["options"] == [];
}

test "invalid vision categories and duplicated image indexes are rejected" {
    context = _photo_context("product-cracked.png");
    context["demo_mode"] = False;
    for output in [PhotoExtraction(image_index=0, category="invented_diagnosis"), PhotoExtraction(image_index=2, category="screen_crack")] {
        _set_model_for_tests(Model(model_name="mockllm", config={"outputs": [[output]]}));
        try { vision_stage(context); assert False; }
        except FixoraError as error { assert error.code == "MODEL_INVALID_OUTPUT"; }
        finally { _set_model_for_tests(None); }
    }
}

test "real byLLM invocation accepts typed mock output for both image stages" {
    context = _context();
    context["demo_mode"] = False;
    _set_model_for_tests(Model(model_name="mockllm", config={"outputs": [InvoiceExtraction(purchase_date="2024-06-15", manufacturer="Fixora Demo", model_code="FD-100"),
        [PhotoExtraction(image_index=0, category="screen_crack", description="A crack is visible.", severity="moderate")]]}));
    try {
        document = document_stage(context);
        assert document.status == "completed" and document.findings["analysis_mode"] == "live_model";
        context["prior_results"] = {"document": {"status": document.status, "findings": document.findings}};
        context["attachments"][0]["evidence_id"] = "photo-1";
        vision = vision_stage(context);
        assert vision.status == "completed";
    } finally { _set_model_for_tests(None); }
}

test "provider schemas build for invoice objects and photo lists" {
    context = _context();
    context["demo_mode"] = False;
    _provider_schemas.clear();
    _provider_image_counts.clear();
    _set_model_for_tests(_SchemaCheckingModel(model_name="mockllm", config={"outputs": [
        InvoiceExtraction(purchase_date="2024-06-15", manufacturer="Fixora Demo", model_code="FD-100"),
        [PhotoExtraction(image_index=index, category="screen_crack", description="A visible crack.", severity="moderate") for index in range(3)]]}));
    try {
        document = document_stage(context);
        context["prior_results"] = {"document": {"status": document.status, "findings": document.findings}};
        content = context["attachments"][0]["content_base64"];
        context["attachments"] = [{"evidence_id": "photo-" + str(index + 1), "content_base64": content} for index in range(3)];
        vision_stage(context);
        assert len(_provider_schemas) == 2, "Expected two provider schemas, got " + str(len(_provider_schemas));
        invoice_schema = _provider_schemas[0]["json_schema"]["schema"];
        assert "purchase_date" in (invoice_schema["properties"] as dict[str, any]), "Missing invoice purchase_date schema";
        assert "category" in json.dumps(_provider_schemas[1]), "Missing photo category schema";
        assert _provider_image_counts == [1, 3], "All invoice and product images must be included as multimodal content";
    } finally { _set_model_for_tests(None); }
}

test "unreadable invoice fields stay missing and missing model never falls back" {
    context = _context();
    context["demo_mode"] = False;
    _set_model_for_tests(Model(model_name="mockllm", config={"outputs": [InvoiceExtraction()]}));
    try {
        result = document_stage(context);
        assert result.next_action == "needs_information" and len(result.missing_fields) == 2;
    } finally { _set_model_for_tests(None); }
    try { _extract(context, "document"); assert False; }
    except FixoraError as error { assert error.code == "MODEL_NOT_CONFIGURED"; }
}

test "three scenarios traverse real specialists and preserve inventory" {
    for scenario in _fixtures("scenarios") {
        _reset_database();
        database = _get_database();
        before = list(database.inventory.find({}));
        item = _run_scenario(scenario as dict[str, any]);
        assert item["status"] == scenario["expected_status"], str(item["assessment"]["stages"]);
        assert list(database.inventory.find({})) == before;
        if scenario["id"] == "complete" {
            final_report = item["assessment"]["stages"]["resolution"]["findings"]["report"];
            assert final_report["is_demo"] and final_report["coverage"]["outcome"] == "outside_period";
            assert final_report["repair_options"][0]["estimate"]["total_cost_minor"] == 2650000;
            assert final_report["customer_payable_minor"] is None;
        }
    }
    os.environ["FIXORA_DEMO_MODE"] = "false";
}

test "owner inspection can support catalogue repairs but cannot bypass identity or hidden faults" {
    context = _photo_context("product-scratch.png");
    context["description"] = "The display needs repair after physical inspection.";
    context["owner_inspection"] = {"diagnosis_code": "screen_crack", "notes": "Confirmed damaged display during shop inspection."};
    result = vision_stage(context);
    assert result.status == "completed";
    observations = result.findings["observations"];
    assert observations[-1]["source"] == "owner_inspection" and not observations[-1]["provisional"];
    context["description"] = "Laptop will not power on.";
    assert vision_stage(context).next_action == "needs_inspection";
    context = _photo_context("product-mismatch.png");
    context["owner_inspection"] = {"diagnosis_code": "screen_crack", "notes": "Inspected display"};
    assert vision_stage(context).next_action == "needs_information";
}
