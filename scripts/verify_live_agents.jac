# Opt-in integration check: real provider requests using synthetic evidence.
# Run from the repository root. Never prints keys, tokens, URIs or raw errors.
import os;
import sys;
import json;
import time;
import socket;
import shutil;
import subprocess;
import base64;
import from pathlib { Path }
import from datetime { datetime }
import from zoneinfo { ZoneInfo }
import from urllib.request { Request, urlopen }
import from urllib.error { URLError, HTTPError }
import from pymongo { MongoClient }
import from shared.config { _get_settings }
import from shared.validation { _new_id }

glob _port: int = 0;
glob _process: any = None;
glob _output: any = None;

def _start_server(environment: dict[str, str]) {
    listener = socket.socket();
    listener.bind(("127.0.0.1", 0));
    _port = listener.getsockname()[1] as int;
    listener.close();
    _output = open(".jac/live-agent-check.log", "a");
    _process = subprocess.Popen([shutil.which("jac") or "jac", "start", "main.jac", "--no-client", "-p", str(_port)],
        env=environment, stdin=subprocess.DEVNULL, stdout=_output, stderr=subprocess.STDOUT);
    for attempt in range(60) {
        if _process.poll() is not None { raise RuntimeError("SERVER_START_FAILED"); }
        try {
            response = urlopen("http://127.0.0.1:" + str(_port) + "/openapi.json", timeout=2);
            response.close();
            return;
        } except (URLError, TimeoutError) { time.sleep(1); }
    }
    raise RuntimeError("SERVER_START_TIMEOUT");
}

def _stop_server() {
    if _process is not None {
        _process.terminate();
        try { _process.wait(timeout=10); }
        except subprocess.TimeoutExpired { _process.kill(); _process.wait(timeout=5); }
        _process = None;
    }
    if _output is not None { _output.close(); _output = None; }
}

def _call(operation: str, payload: dict[str, any], token: str) -> dict[str, any] {
    payload["access_token"] = token;
    request = Request("http://127.0.0.1:" + str(_port) + "/function/" + operation,
        data=json.dumps(payload).encode("utf-8"), headers={"Content-Type": "application/json"}, method="POST");
    try { response = urlopen(request, timeout=60); }
    except HTTPError as error { raise RuntimeError("HTTP_" + str(error.code) + "_" + operation); }
    try { envelope = json.loads(response.read()); }
    finally { response.close(); }
    if not envelope.get("ok") { raise RuntimeError("TRANSPORT_ERROR_" + operation); }
    result = envelope["data"]["result"];
    if not result["ok"] {
        code = str(result.get("error", {}).get("code", "APPLICATION_ERROR"));
        raise RuntimeError(code + "_" + operation);
    }
    return result["data"] as dict[str, any];
}

def _run_scenario(scenario: dict[str, any], token: str) -> dict[str, any] {
    if os.getenv("FIXORA_CHECK_FRONTEND", "false").lower() == "true" {
        return _run_frontend_scenario(scenario, token);
    }
    item = _call("create_case", {"description": scenario["description"], "claimed_model_id": scenario["claimed_model_id"], "submission_id": _new_id()}, token)["case"];
    for kind in ["invoice", "product"] {
        path = Path.cwd() / "fixtures" / (scenario[kind] as str);
        content = base64.b64encode(path.read_bytes()).decode("ascii");
        uploaded = _call("upload_evidence", {"case_id": item["id"], "expected_revision": item["revision"], "kind": kind,
            "filename": path.name, "content_base64": content, "request_id": _new_id()}, token);
        item = uploaded["case"];
        downloaded = _call("get_evidence", {"case_id": item["id"], "evidence_id": uploaded["uploaded_evidence"]["id"]}, token);
        assert downloaded["content_base64"] == content, "Evidence bytes changed in storage";
    }
    item = _call("start_assessment", {"case_id": item["id"], "expected_revision": item["revision"], "request_id": _new_id()}, token)["case"];
    measurements: list[dict[str, any]] = [];
    for ordinal in range(5) {
        if item["status"] != "processing" { break; }
        started = time.monotonic();
        item = _call("advance_case", {"case_id": item["id"], "assessment_id": item["active_assessment_id"],
            "expected_revision": item["revision"], "request_id": _new_id()}, token)["case"];
        stage_name = ["document", "vision", "coverage", "repair_parts", "resolution"][ordinal];
        result = item["assessment"]["stages"][stage_name];
        code = result["error"]["code"] if result.get("error") else None;
        measurements.append({"stage": stage_name, "status": result["status"], "analysis_mode": result["findings"].get("analysis_mode"),
            "error_code": code, "elapsed_seconds": round(time.monotonic() - started, 2)});
        print(scenario["id"], stage_name, result["status"], code or "", flush=True);
    }
    outcome: dict[str, any] = {"scenario": scenario["id"], "expected_status": scenario["expected_status"], "actual_status": item["status"],
        "passed": item["status"] == scenario["expected_status"], "stages": measurements};
    if item["status"] == "completed" {
        final_report = item["assessment"]["stages"]["resolution"]["findings"]["report"];
        outcome["coverage"] = final_report["coverage"]["outcome"];
        outcome["total_cost_minor"] = final_report["repair_options"][0]["estimate"]["total_cost_minor"];
        outcome["currency"] = final_report["repair_options"][0]["estimate"]["currency"];
        assert not final_report["is_demo"] and final_report["analysis_mode"] == "live_model";
        assert final_report["customer_payable_minor"] is None;
        if scenario.get("expected_total_cost_minor") is not None {
            assert outcome["total_cost_minor"] == scenario["expected_total_cost_minor"], "Wrong repair total";
        }
        if scenario.get("expected_coverage") is not None {
            assert outcome["coverage"] == scenario["expected_coverage"], "Wrong coverage outcome";
        }
    }
    # Retain only synthetic case output locally, never credentials or context.
    (Path.cwd() / ".jac/live-agent-last-case.json").write_text(json.dumps(item, indent=2), encoding="utf-8");
    return {"outcome": outcome, "case_id": item["id"], "status": item["status"]};
}

def _run_frontend_scenario(scenario: dict[str, any], token: str) -> dict[str, any] {
    # Run the compiled browser adapter against the same temporary API/database.
    # Secrets travel only in child environment variables, never command arguments.
    runtime = shutil.which("bun");
    if not runtime {
        candidates = list((Path.home() / ".cache/jac/rt").glob("**/runtimelib/client/_bun/bun"));
        if not candidates { raise RuntimeError("BUNDLED_BUN_NOT_FOUND"); }
        runtime = str(candidates[0]);
    }
    if not (Path.cwd() / ".jac/client/compiled/ui/gateway.js").exists() {
        raise RuntimeError("BUILD_FRONTEND_FIRST");
    }
    shutil.copyfile("tests/frontend-live.mjs", ".jac/client/frontend-live.test.mjs");
    environment = dict(os.environ);
    environment["FIXORA_TEST_BASE_URL"] = "http://127.0.0.1:" + str(_port);
    environment["FIXORA_TEST_SCENARIO"] = json.dumps(scenario);
    completed = subprocess.run([runtime, "test", "frontend-live.test.mjs"], cwd=".jac/client", env=environment,
        capture_output=True, timeout=240);
    if completed.returncode != 0 {
        # The child handles synthetic fixtures only; keep diagnostic output local.
        (Path.cwd() / ".jac/frontend-live-test.log").write_text(completed.stdout.decode(errors="replace") + completed.stderr.decode(errors="replace"));
        raise RuntimeError("FRONTEND_GATEWAY_CHECK_FAILED");
    }
    verified = json.loads((Path.cwd() / ".jac/frontend-live-result.json").read_text());
    print(scenario["id"], "compiled frontend gateway:", verified["status"], flush=True);
    return verified as dict[str, any];
}

with entry:__main__ {
    settings = _get_settings();
    if not settings.model { print("Configure FIXORA_MODEL before a live check."); sys.exit(1); }
    temporary_database = "fixora_check_" + _new_id()[:16];
    environment = dict(os.environ) as dict[str, str];
    environment.pop("MONGODB_URI", None);
    environment["FIXORA_MONGODB_URI"] = settings.mongodb_uri;
    environment["MONGODB_DB"] = temporary_database;
    environment["FIXORA_ACCESS_TOKEN"] = settings.access_token;
    environment["FIXORA_DEMO_MODE"] = "false";
    environment["JAC_DATA_PATH"] = str(Path.cwd() / ".jac" / temporary_database);
    client = MongoClient(settings.mongodb_uri, serverSelectionTimeoutMS=10000, socketTimeoutMS=15000);
    summary: dict[str, any] = {"checked_at": datetime.now(ZoneInfo(settings.timezone)).isoformat(), "model": settings.model,
        "demo_mode": False, "scenarios": [], "restart_persistence": False, "cleanup_confirmed": False};
    summary["frontend_gateway"] = os.getenv("FIXORA_CHECK_FRONTEND", "false").lower() == "true";
    exit_code = 0;
    try {
        seed = subprocess.run([shutil.which("jac") or "jac", "run", "data/seed.jac"], env=environment, capture_output=True, timeout=60);
        if seed.returncode != 0 { raise RuntimeError("TEMPORARY_SEED_FAILED"); }
        _start_server(environment);
        status = _call("platform_status", {}, settings.access_token);
        assert status["database"] == "connected";
        assert all(value == "ready" for value in status["specialists"].values());
        assert _call("list_cases", {}, settings.access_token)["cases"] == [];
        summary["case_list_defaults"] = True;
        print("API, MongoDB and all five specialists ready. Live model:", settings.model, flush=True);
        scenarios = json.loads((Path.cwd() / "fixtures/scenarios.json").read_text(encoding="utf-8"));
        if os.getenv("FIXORA_CHECK_ALL", "false").lower() != "true" { scenarios = scenarios[:1]; }
        last: dict[str, any] = {};
        for scenario in scenarios {
            last = _run_scenario(scenario as dict[str, any], settings.access_token);
            summary["scenarios"].append(last["outcome"]);
            if not last["outcome"]["passed"] { exit_code = 1; break; }
        }
        listed = _call("list_cases", {}, settings.access_token);
        _stop_server();
        _start_server(environment);
        restored = _call("get_case", {"case_id": last["case_id"]}, settings.access_token)["case"];
        assert restored["status"] == last["status"] and len(restored["evidence_ids"]) == 2;
        summary["restart_persistence"] = True;
        print("Saved case and agent findings survive server restart.", flush=True);
    } except Exception as error {
        # RuntimeError messages above are fixed codes. Other exception text may
        # contain credentials, so only record its class name.
        summary["check_error"] = str(error) if type(error) is RuntimeError else type(error).__name__;
        print("LIVE_CHECK_FAILED:", summary["check_error"], flush=True);
        exit_code = 1;
    } finally {
        _stop_server();
        if temporary_database.startswith("fixora_check_") and len(temporary_database) == 29 {
            try {
                for collection_name in client[temporary_database].list_collection_names() { client[temporary_database].drop_collection(collection_name); }
                summary["cleanup_confirmed"] = True;
            } except Exception { exit_code = 1; }
        }
        client.close();
        (Path.cwd() / ".jac/live-agent-check.json").write_text(json.dumps(summary, indent=2), encoding="utf-8");
        print("Verification summary: .jac/live-agent-check.json; temporary collection cleanup:", summary["cleanup_confirmed"], flush=True);
    }
    sys.exit(exit_code);
}
