# Live agent/API verification

Checked on **17 October 2026, 15:01 Asia/Colombo**, with Jac **0.34.6** and **gemini/gemini-3.8-flash**. Fixture replay was disabled. Invoice and product-image extraction used real Gemini requests; warranty, compatibility, prices and the final report used the application rules.

## Results

| Scenario | Actual case status | Result |
| --- | --- | --- |
| Cracked display, expired invoice | `completed` | All five stages passed. Warranty outcome `outside_period`; compatible display in stock; provisional **LKR 26,500.00** before tax. Customer payable remains unknown. |
| Invoice/product model and serial mismatch | `needs_information` | Live photo extraction identified the conflicting device; the workflow stopped before proposing repairs. |
| No-power complaint with exterior scratch | `needs_inspection` | The workflow stopped without treating visible damage as the cause of an internal fault. |

The complete path's measured API stage times were 6.41s for document extraction, 11.27s for photo analysis, 2.02s for coverage, 2.33s for repair/parts, and 2.92s for resolution. These are observations from one run, not performance guarantees.

Verified over HTTP: platform status, case creation, invoice/product upload, exact evidence-byte retrieval, assessment start, stage advancement, case listing with omitted optional parameters, and saved-case retrieval after a server restart. Real MongoDB/GridFS stored the temporary cases and files. The verifier confirmed cleanup of all its temporary collections; it left the normal development database and `.env` unchanged.

**38 offline regression tests pass** (23 platform, 15 specialist). Type checking passed for all 27 backend modules, both test files and the live verifier.

## Fixes made during verification

- Kept byLLM function declarations with their return schemas: imported archetype metadata otherwise failed provider-schema generation on Jac 0.34.6.
- Passed product images as separate top-level `Image` arguments in one model call. This release serialized a list of images as text, leaving the provider without the intended pictures.
- Preserved real HTTP parameter defaults. The full server otherwise sent the default case-list limit as a string; explicit null limits now return a validation error.
- Applied provider timeout/retry settings at the actual transport boundary and used low reasoning effort for Gemini 3 extraction. Provider timeout, connectivity and temporary-unavailability errors produce safe saved-stage codes.
- Made synthetic manufacturer/model labels explicit and included a visible laptop illustration. Matching rules were kept exact.
- Added regressions for provider-schema construction, all three product-image attachments, and HTTP defaults.

Earlier requests encountered a transient Gemini high-demand response and a timeout. The final three-scenario run passed. Provider availability and quotas can still affect later runs; the application does not silently substitute fixture output.

## Repeat the check

From the repository root in Linux/WSL, using the model/key in your local `.env`:

```bash
# One complete path; makes real provider requests.
jac run scripts/verify_live_agents.jac

# Complete path plus mismatch and inspection routes.
FIXORA_CHECK_ALL=true jac run scripts/verify_live_agents.jac
```

Machine-readable results are written to `.jac/live-agent-check.json`. The verifier starts and stops its own server and uses a fresh temporary database. Restart an already-running development server to load the fixes before testing it manually:

```bash
jac start main.jac --no-client
```

This check used synthetic invoices and illustrations. It verifies basic integration and routing, not accuracy on representative customer photographs or invoice authenticity. Member C's interface, Ollama connectivity and JacHammer deployment were not verified by this run.
