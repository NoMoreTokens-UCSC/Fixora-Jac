# Server-only provider adapter. No keys or Model objects enter specialist findings.
import os;
import base64;
import json;
import hashlib;
import from pathlib { Path }
import from threading { Lock }
import from dotenv { dotenv_values }
import from jaclang.byllm.lib { Model, Image, AuthenticationError, RateLimitError, ModelNotFoundError, OutputConversionError }
import from litellm.exceptions { ServiceUnavailableError, InternalServerError, APIConnectionError, Timeout as ProviderTimeout }
import from shared.contracts { FixoraError }
import from specialists.schemas { InvoiceExtraction, PhotoExtraction, _invoice, _photos, _use_model }

glob _test_model: Model | None = None;
glob _model_lock: Lock = Lock();

# 0.34.6 replaces constructor call_params at each `by` invocation and removes
# api_base before the LiteLLM call. Apply transport options at that boundary.
obj _ProviderModel(Model) {
    def model_call_no_stream(params: dict) -> dict {
        params["timeout"] = 30;
        params["num_retries"] = 0;
        # Simple extraction should not spend its output budget on deep reasoning.
        if self.model_name.startswith("gemini/gemini-3") { params["reasoning_effort"] = "low"; }
        if self.config.get("base_url") { params["api_base"] = self.config["base_url"]; }
        return Model.model_call_no_stream(self, params);
    }
}

def _set_model_for_tests(model: Model | None) { _test_model = model; }

def _configure(context: dict[str, any]) {
    if _test_model is not None { _use_model(_test_model); return; }
    model = str(context.get("model", "")).strip();
    if not model { raise FixoraError("MODEL_NOT_CONFIGURED", "Set FIXORA_MODEL and the provider API key, or explicitly enable fixture demo mode."); }
    values = dotenv_values(str(Path.cwd() / ".env"), interpolate=False);
    key_name = "GOOGLE_API_KEY" if model.startswith("gemini/") else "OPENAI_API_KEY";
    if model.startswith("anthropic/") or model.startswith("claude-") { key_name = "ANTHROPIC_API_KEY"; }
    if model.startswith("openrouter/") { key_name = "OPENROUTER_API_KEY"; }
    key = str(os.getenv("FIXORA_MODEL_API_KEY") or values.get("FIXORA_MODEL_API_KEY")
        or os.getenv(key_name) or values.get(key_name) or "");
    if model.startswith("gemini/") and not key {
        key = str(os.getenv("GEMINI_API_KEY") or values.get("GEMINI_API_KEY") or "");
    }
    provider_config: dict = {};
    if model.startswith("ollama/") or model.startswith("ollama_chat/") {
        provider_config["base_url"] = str(os.getenv("FIXORA_MODEL_BASE_URL") or values.get("FIXORA_MODEL_BASE_URL") or "http://localhost:11434");
    } elif not key { raise FixoraError("MODEL_NOT_CONFIGURED", "The selected model provider needs a server-side API key."); }
    _use_model(_ProviderModel(model_name=model, api_key=key, config=provider_config));
}

def _demo_outputs(context: dict[str, any], stage: str) -> list[dict[str, any]] {
    records = json.loads((Path(str(__file__)).resolve().parent.parent / "fixtures" / "demo_evidence.json").read_text(encoding="utf-8"));
    outputs: list[dict[str, any]] = [];
    for attachment in context["attachments"] {
        digest = hashlib.sha256(base64.b64decode(attachment["content_base64"], validate=True)).hexdigest();
        record = records.get(digest);
        if record is None or record["stage"] != stage {
            raise FixoraError("DEMO_EVIDENCE_NOT_FOUND", "Fixture mode accepts only the bundled synthetic evidence. Disable FIXORA_DEMO_MODE for real analysis.");
        }
        outputs.append(record["output"] as dict[str, any]);
    }
    return outputs;
}

def _extract(context: dict[str, any], stage: str) -> any {
    if context.get("demo_mode", False) {
        outputs = _demo_outputs(context, stage);
        if stage == "document" { return InvoiceExtraction(**outputs[0]); }
        return [PhotoExtraction(image_index=index, **value) for (index, value) in enumerate(outputs)];
    }
    if not _model_lock.acquire(timeout=0.1) { raise FixoraError("MODEL_BUSY", "Another image analysis is running. Retry shortly."); }
    try {
        _configure(context);
        images = [_image(base64.b64decode(row["content_base64"], validate=True)) for row in context["attachments"]];
        if stage == "document" { return _invoice(images[0]); }
        return _photos(images);
    } except AuthenticationError { raise FixoraError("MODEL_AUTH_ERROR", "Model credentials were rejected. Check the server configuration."); }
    except RateLimitError { raise FixoraError("MODEL_RATE_LIMIT", "The model provider quota was reached. Retry later."); }
    except ModelNotFoundError { raise FixoraError("MODEL_NOT_FOUND", "The provider could not find the configured model."); }
    except OutputConversionError { raise FixoraError("MODEL_INVALID_OUTPUT", "The model did not return valid structured evidence. Retry with clearer images."); }
    except ProviderTimeout { raise FixoraError("MODEL_TIMEOUT", "The model provider exceeded the request timeout. Retry this stage later."); }
    except (ServiceUnavailableError, InternalServerError) { raise FixoraError("MODEL_UNAVAILABLE", "The model provider is temporarily unavailable or busy. Retry this stage later."); }
    except APIConnectionError { raise FixoraError("MODEL_CONNECTION_ERROR", "Could not connect to the model provider. Check connectivity and retry."); }
    finally { _model_lock.release(); }
}

# The bundled Image constructor has a stringified union annotation in 0.34.6.
# Isolate that external typing boundary; Image itself validates input bytes.
def _image(value: any) -> Image { return Image(value); }
