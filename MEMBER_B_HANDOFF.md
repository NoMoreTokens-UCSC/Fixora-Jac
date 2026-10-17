# Member B handoff

Member B implements all five `run_stage(context) -> StageResult` adapters on Jac **0.34.6**. The public APIs and shared contracts are unchanged. Member C can now render saved results using the fields below. No approval, inspection-entry, stock mutation or turnaround-prediction workflow is included.

## Setup

Run from the repository root in Linux/WSL:

```bash
jac install --dev
jac run data/seed.jac
jac start main.jac --no-client
```

The seed command upserts one fictional policy, three fictional laptop models, three repair definitions and nine stock records. Their IDs begin with `demo-`; prices are illustrative LKR amounts, with 100 minor units per major unit. Seeding replaces records with matching IDs and never runs automatically at startup.

### Hosted model recommendation: Gemini API

Create a key in [Google AI Studio](https://aistudio.google.com/apikey) and add these values to your local `.env` or the hosting service's server-side secrets:

```dotenv
FIXORA_MODEL=gemini/gemini-3.8-flash
GOOGLE_API_KEY=your-key-here
FIXORA_DEMO_MODE=false
```

Google currently lists free-tier input/output access for Gemini 3.8 Flash, subject to project quotas and model availability. Check your project's available models and limits in AI Studio. Free-tier data may be used to improve Google products; use synthetic invoices for the hackathon. [Pricing](https://ai.google.dev/gemini-api/docs/pricing), [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).

The adapter uses the byLLM/LiteLLM integration installed with this Jac release. Live Gemini 3.8 Flash invoice/photo calls and the complete five-stage API path have been verified using synthetic evidence, in addition to offline checks. If your project cannot use the example model, set `FIXORA_MODEL=gemini/<available-image-capable-model>` and rerun the live check. A Gemini chatbot subscription does not configure API access.

### Local alternative: Ollama

Install and start an image-capable model supported by your Ollama version, then configure, for example:

```dotenv
FIXORA_MODEL=ollama_chat/gemma3:4b
FIXORA_MODEL_BASE_URL=http://localhost:11434
FIXORA_DEMO_MODE=false
```

This example needs a separately installed model and sufficient hardware; its speed and extraction quality have not been measured here. Text-only models cannot read the submitted images. WSL must be able to reach the Ollama service; use the host address if it runs on Windows and localhost forwarding is unavailable.

After hosting, `localhost` belongs to the hosted server. Reaching a developer laptop requires a reachable, access-controlled endpoint and the laptop staying online. This extra networking work makes Gemini API the simpler hackathon deployment choice. Running Ollama inside JacHammer is not assumed or verified. [Ollama networking](https://docs.ollama.com/faq).

Other model settings: `FIXORA_MODEL_API_KEY` can override the provider-specific key; `GEMINI_API_KEY` is accepted as a Gemini fallback. OpenAI, Anthropic and OpenRouter use their corresponding server-side key variables. Keys and model objects are never included in specialist findings. Provider calls request a 30-second timeout with automatic retries disabled; the coordinator's existing 45-second limit still applies.

### Explicit fixture demo

Set `FIXORA_DEMO_MODE=true` and use the exact bundled inputs listed in `fixtures/scenarios.json`. The document/vision stages match the actual image bytes against `fixtures/demo_evidence.json`; changing a filename cannot select a different result. Arbitrary uploads fail with `DEMO_EVIDENCE_NOT_FOUND`. There is **no automatic fallback** when a live model is unavailable.

All demo stage findings carry `analysis_mode: "demo_fixture"`. The final report additionally includes `is_demo: true` and `demo_notice`. Display that notice prominently. These small illustrations and invoices are synthetic; they are not live computer-vision results or real customer evidence.

| Scenario | Inputs in `fixtures/evidence/` | Description | Expected outcome |
| --- | --- | --- | --- |
| Complete | `invoice-expired.png`, `product-cracked.png` | The display is visibly cracked. Please estimate a display replacement. | `completed`; outside warranty period; provisional LKR 26,500.00 before tax; compatible display in stock |
| Identity conflict | `invoice-expired.png`, `product-mismatch.png` | The display is visibly cracked. | `needs_information`; no repair proposal |
| Uncertain fault | `invoice-recent.png`, `product-scratch.png` | Laptop will not power on. There is a small exterior scratch. | `needs_inspection`; no causal diagnosis or repair quote |

Use claimed model `demo-laptop-01` for these inputs. The recent invoice is dated 2026-08-10; expectations about its warranty period depend on the shop evaluation date. The expiry demonstration uses an already expired 2024 invoice. Fixture tests pin rule evaluation to 2026-10-17 where date boundaries matter.

## Stage behavior

| Stage | Implementation and stopping conditions |
| --- | --- |
| `document` | One typed byLLM invoice extraction; keeps unknown fields null. Resolves only exact printed model codes against the catalogue. Missing/invalid/future date, unknown model or selected-model conflict requests information. Does not authenticate invoices. |
| `vision` | One typed byLLM call for all product images. Maps observation indexes to server-owned evidence IDs. Printed model/manufacturer/serial conflicts request information. Unknown/cosmetic-only evidence or a recognized hidden-fault complaint requests inspection. Images do not establish internal faults or causation. |
| `coverage` | Deterministic calendar-month arithmetic; inclusive expiry, clamped end-of-month. Separates date eligibility from conditional coverage and component-specific physical-damage exclusions. Returns versioned policy and clause snapshots. |
| `repair_parts` | Matches visible categories to supported repairs and exact model/part compatibility. Prefers in-stock compatible parts, then lower price and stable SKU. Returns provisional price/availability snapshots. Missing complete compatible options requests inspection. |
| `resolution` | Deterministic report assembling evidence, policy clauses and provisional options. Ends the assessment with `next_action: "complete"`. Completion means a recommendation is ready. |

The vision stage uses a small English phrase list to conservatively route common power/charging/heat/liquid complaints. This is a hackathon triage heuristic, not a general fault classifier. Supported visible categories are `screen_crack`, `hinge_damage`, `keyboard_damage`, `cosmetic_damage`, `no_visible_damage`, and `unknown`. No diagnosis can authorize repair or payment.

## Findings for Member C

Read `case.assessment.stages[stage].findings`. Stage `missing_fields`, `conflicts`, `evidence_refs` and `next_action` remain siblings of `findings`. Blocked stages include `findings.summary` and retain their usable observations. Every stage includes `analysis_mode`; deterministic stages also preserve the selected analysis mode for the whole assessment.

| Stage | Finding fields |
| --- | --- |
| `document` | `invoice`: invoice_number, purchase_date, manufacturer, model_code, model_id, serial_number, seller, amount_minor, currency, source_text, evidence_refs. `limitations`: string array. |
| `vision` | `observations`: array of image_index, manufacturer, model_code, serial_number, category, description, severity, limitations, evidence_refs, provisional. `identity_verified`: at least one readable model label agrees; this is not proof of authenticity. `limitations`: string array. |
| `coverage` | `coverage`: outcome, date_eligible, purchase_date, evaluation_date, expiry_date, policy_id, policy_version, clause_ids, explanation, and excluded_visible_categories when evaluated within period. `policy_clauses`: matched clause snapshots. `decision_method`: deterministic_policy. Missing-policy/date routes can omit fields that cannot be established. |
| `repair_parts` | `options`: array described below. `unmatched_part_types`, `inventory_reserved: false`, `limitations`. |
| `resolution` | `report`: headline, case_id, evaluation_date, shop_timezone, invoice, observations, identity_verified, coverage, policy_clauses, repair_options, recommendation, limitations, evidence_refs, analysis_mode, is_demo, nullable customer_payable_minor and turnaround_estimate, inventory_reserved. `demo_notice` is present in fixture mode. |

Coverage outcomes are `outside_period`, `potentially_covered`, `visible_damage_excluded`, `needs_information`, or `needs_inspection`. A valid date alone does not establish coverage. A visible exclusion applies only to the listed damage category and affected component.

Each repair option contains:

```json
{
  "repair_id": "demo-repair-display",
  "title": "Display replacement",
  "model_id": "demo-laptop-01",
  "observation_category": "screen_crack",
  "explanation": "Possible repair for the visible observation; confirm by physical inspection.",
  "parts": [{
    "sku": "DEMO-1-DISPLAY_PANEL",
    "model_id": "demo-laptop-01",
    "part_type": "display_panel",
    "quantity_available": 3,
    "unit_price_minor": 2400000,
    "currency": "LKR",
    "inventory_id": "demo-stock-1-display_panel"
  }],
  "estimate": {
    "currency": "LKR",
    "parts_cost_minor": 2400000,
    "labour_cost_minor": 250000,
    "total_cost_minor": 2650000,
    "provisional": true,
    "customer_payable_minor": null,
    "tax_included": false,
    "explanation": "Illustrative repair estimate before tax; final diagnosis, coverage and charges are not established."
  },
  "evidence_refs": ["case-specific-evidence-id"],
  "provisional": true,
  "availability": "in_stock",
  "turnaround_estimate": null
}
```

`availability` can also be `out_of_stock`; display a supply-confirmation recommendation and do not imply a delivery date. No stock is reserved or deducted. Always render minor units using the stated currency. Unknown customer payment must stay unknown; it is not zero.

## Errors and verification

Saved specialist errors include `MODEL_NOT_CONFIGURED`, `MODEL_AUTH_ERROR`, `MODEL_RATE_LIMIT`, `MODEL_NOT_FOUND`, `MODEL_INVALID_OUTPUT`, `MODEL_BUSY`, `DEMO_EVIDENCE_NOT_FOUND`, `INVALID_CATALOGUE`, and `MISSING_STAGE_RESULT`, alongside the coordinator's generic safe failure/timeout errors. A saved error can arrive inside an HTTP-successful call; inspect case and stage status.

```bash
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/specialist_tests.jac -v
jac check main.jac shared server workflow data specialists rules -n
```

Verified: 23 platform tests and 15 specialist tests pass. All three fixture scenarios pass through the full HTTP API with real MongoDB, and saved findings survive a server restart. The configured development database contains 1 policy, 3 products, 3 repairs and 9 stock records.

The specialist suite uses in-memory MongoDB and MockLLM; it also constructs the real provider schemas and verifies that one invoice and all three product images become image attachments. No provider request or production data is needed for this offline suite. Accuracy on real customer photographs and JacHammer deployment remain pending.

For a live check with the configured provider (may consume quota), run from the repository root:

```bash
jac run scripts/verify_live_agents.jac
# Also check identity-conflict and uncertain-fault scenarios:
FIXORA_CHECK_ALL=true jac run scripts/verify_live_agents.jac
```

The verifier starts its own HTTP server, seeds a fresh temporary MongoDB database, disables fixture replay only for that child process, uploads synthetic evidence, advances the actual agents, checks saved results after a server restart, and removes its temporary collections. It leaves the normal development database and `.env` unchanged. The machine-readable summary is `.jac/live-agent-check.json`; a single temporary case output is `.jac/live-agent-last-case.json`. A provider timeout or high-demand response is a failed check, not a fabricated successful analysis; retry explicitly later.

## Jac 0.34.6 server compatibility

Installing the byLLM/serve dependency set activates the full Jac server. Its API schema is at `/openapi.json` and Swagger is at `/docs`; `/functions` was a discovery route of the earlier minimal fallback. The ten application POST routes and their envelopes remain the same.

`main.jac` installs an application-local, version-gated adapter from `server/runtime_compat.jac`. It suppresses the full server's unconditional function-parameter print, which would otherwise log access tokens and uploaded data. It also repairs guest-root recovery through Scale's own identity store: the bundled implementation inherits a reset method that accesses an uninitialized `_lock` and the wrong users table. Only guest recovery is changed; application access checks still run on every operation. No installed package or existing graph data is modified/deleted by this adapter. Revalidate and remove it when changing Jac versions; hosting compatibility remains to be tested.

The adapter also preserves typed function defaults when creating HTTP request schemas. Jac 0.34.6 otherwise stringifies an omitted numeric default (e.g. `limit=20`), causing `list_cases` to fail. ByLLM declarations stay in the same module as their return schemas because imported schema references fail provider-schema construction on this release. Product photos are passed as separate top-level `Image` arguments in a single call because lists of images are serialized as text by this release. These fixes are covered by offline regressions and the live verifier. Transport timeouts/retry limits are applied at the provider-call boundary; Gemini 3 requests use low reasoning effort for extraction. The synthetic evidence now has explicit manufacturer/model labels and a visible laptop illustration.

The completed live run passed all three scenarios, case-list defaults, evidence retrieval and persistence after restart. See [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md) for measured results and test scope.

The local demo access token was replaced after the logging behavior was discovered; read its current value from your own `.env`. MongoDB credentials and model settings were left unchanged. Restart the development server to load the new entrypoint and compatibility adapter.
