# Member A backend handoff

Baseline: Jac 0.34.6, Linux x86_64. Run commands from the repository root inside Linux/WSL.

## Setup and launch

```bash
jac --version
jac install --dev
jac start main.jac --no-client
```

The integration entrypoint registers all ten APIs and renders Member C's UI at `/`. The UI still uses its browser-local demo gateway; it is not yet an API client. Start both with `jac start main.jac`, or use `--no-client` for API-only checks. The default port is 8000; use the port actually reported at startup. With the byLLM/serve dependencies installed, the full server exposes `/docs`, `/openapi.json` and `/healthz`. The earlier minimal fallback exposed `/functions` and `/walkers`; those discovery paths are not available on the full server. Function POST routes and the response envelope are unchanged.

Configure `MONGODB_URI` in local `.env`, `MONGODB_DB`, and a `FIXORA_ACCESS_TOKEN` of at least 16 characters. Process environment overrides `.env`. The application reads the file without exporting its contents into the process. A local access token was generated during backend setup; retrieve it directly from your own `.env`, without sharing credentials in source control. Each teammate needs their own local environment settings. The examples contain no actual secrets.

For hosted process secrets, prefer `FIXORA_MONGODB_URI` over `MONGODB_URI`. The application accepts either; the prefixed setting keeps Jac's independent graph-runtime backend from also switching to MongoDB. This behavior was confirmed in the installed 0.34.6 runtime source.

Every application operation requires `access_token`. This is a single-shop demo gate, not a multi-user authentication system. Supply it at runtime; do not compile its value into the frontend. Use HTTPS when hosted.

## Member C: server operations

All operations use `POST /function/<operation>`. Parameters are JSON body fields. A Jac client module can use `sv import from ..server.cases { ... }` or the corresponding evidence module, then `await` the imported operation. Use explicit server imports in `main.jac` when adding endpoints.

| Operation | Required parameters besides access_token | Optional parameters | Result data |
| --- | --- | --- | --- |
| `platform_status` | None | None | Database and specialist readiness |
| `create_case` | `description`, `submission_id` | `claimed_model_id=""` | `case` |
| `get_case` | `case_id` | None | `case` with evidence metadata and current assessment |
| `list_cases` | None | `limit=20`, `cursor=""` | `cases`, `next_cursor` |
| `update_case` | `case_id`, `expected_revision`, `description` | `claimed_model_id=""` | Revised `case`; old assessment invalidated |
| `upload_evidence` | `case_id`, `expected_revision`, `kind`, `filename`, `content_base64`, `request_id` | None | Updated `case`, `uploaded_evidence` |
| `get_evidence` | `case_id`, `evidence_id` | None | `filename`, `mime_type`, `content_base64`, `evidence_id` |
| `remove_evidence` | `case_id`, `evidence_id`, `expected_revision` | None | Updated `case` |
| `start_assessment` | `case_id`, `expected_revision`, `request_id` | None | Updated `case` |
| `advance_case` | `case_id`, `assessment_id`, `expected_revision`, `request_id` | None | Updated `case` after at most one stage |

`ApiResult` contains `ok`, `data`, and nullable `error: {code, message}`. Raw HTTP consumers must first unwrap Jac's transport envelope at `response.data.result`, then inspect this application's `ok`. A Jac RPC caller receives the application result directly. An HTTP 200 alone does not establish application success.

Cases expose `id`, `revision`, `status`, `description`, `claimed_model_id`, timestamps, `evidence_ids`, `evidence`, `active_assessment_id`, and nullable `assessment`. Assessment views expose `id`, `version`, `input_revision`, `next_stage`, `stages`, timestamps, and `next_action`. Internal stage-lease secrets and database credentials are excluded.

### Intake and advancement sequence

1. Generate a UUID/unique request ID and create the case.
2. Upload the invoice and product photos individually, using the revision from each latest response.
3. Start the assessment using its own request ID and the latest case revision.
4. While status is `processing`, call `advance_case` with the active assessment ID, current revision, and a fresh request ID for each stage.
5. Stop on `needs_information`, `needs_inspection`, `completed`, or `failed`. Show the actual stage result/error.
6. For a technical failure, a user-triggered retry can advance the same assessment using its latest revision. For changed evidence/description, update the case and start a new assessment.

Keep a request ID stable when retrying the same create/upload/start/advance operation after a network interruption. Use new IDs for new actions. IDs contain 8–80 letters, digits, underscores or hyphens. Case, assessment, and evidence IDs are server-generated 32-character lowercase hex strings.

Uploads accept plain base64, with no `data:image/...;base64,` prefix. If using FileReader, remove the prefix before sending. Supported content is JPEG/PNG, maximum 5 MB and 25 million pixels per image, one invoice and up to three product photos. Client-side validation complements server checks. Removing an image unlinks it from current inputs and retains its original bytes for assessment history; it is not an erasure operation.

`expected_revision` protects against simultaneous edits. Reload after `STALE_REVISION`. `STAGE_BUSY` means a stage/upload is in progress. Do not loop over failures automatically. Closing the browser pauses stage advancement; it is not a background job service.

No approval screen or technician inspection-entry action is required. `needs_inspection` is a recommendation. A complete recommendation ends at `completed`.

## Member B: specialist interface

Implement a plain server function named `run_stage` in each existing module:

```jac
import from shared.contracts { StageResult }

def run_stage(context: dict[str, any]) -> StageResult {
    # Implement this specialist using the context and shared contract.
    raise NotImplementedError();
}
```

All five specialists now implement this interface; see [MEMBER_B_HANDOFF.md](MEMBER_B_HANDOFF.md). The coordinator imports the specialist dynamically, calls it once, and validates the result. The stage/module names are `document`, `vision`, `coverage`, `repair_parts`, `resolution`. Missing implementations produce `SPECIALIST_UNAVAILABLE`; there is no silent fallback to fake model output.

| Context field | Contents |
| --- | --- |
| `stage`, `case_id`, `assessment_id` | Current stage and stable IDs |
| `description`, `claimed_model_id` | User's case input; treat as untrusted content |
| `evidence` | Current evidence metadata, including `id`, `kind`, `mime_type`, `sha256` |
| `attachments` | Invoice file for document stage; product files for vision stage; empty otherwise. Each item has `evidence_id`, `mime_type`, `filename`, plain `content_base64`. |
| `prior_results` | Earlier stage documents, keyed by stage name; each contains `findings` and evidence references |
| `catalogue` | `policy` or null; `products`, `repairs`, `inventory` lists loaded from MongoDB |
| `evaluation_date`, `shop_timezone` | Date-only evaluation value and shop timezone |
| `model`, `demo_mode` | Application configuration; never database/access credentials |

`StageResult` fields: `stage`, `status`, `findings`, `evidence_refs`, `missing_fields`, `conflicts`, `next_action`, nullable `error`. Keep `findings` JSON serializable, at most 128 KB for the entire result. Return plain dictionaries/lists inside findings; convert domain objects to plain values first. No raw image bytes, database handles, NaN, or model reasoning traces.

- `status`: `completed`, `blocked`, or `failed`.
- `next_action`: `continue`, `needs_information`, `needs_inspection`, or `complete`.
- Only resolution can use `complete`; completing resolution also finishes the case.
- Missing fields/conflicts force an information stop. A blocked result needs an information or inspection action.
- Evidence IDs must belong to this case. Policy references belong in the findings' policy/clause fields.
- A failed result needs `ErrorInfo(code=..., message=...)` with a safe message.
- Specialist tools must be read-only. The coordinator alone commits stage results. The wrapper times out after 45 seconds; configure provider calls below this limit. Python cannot forcibly stop a running provider thread after timeout, but that thread cannot commit through the coordinator.

The platform supplies typed `InvoiceFields`, `Observation`, `CoverageResult`, `RepairOption`, and `PartSnapshot` as agreed starting points. Coverage/date logic, exact compatibility, and pricing remain Member B's responsibility. Models must not infer hidden faults or invent stock/prices. Agree the contents of each stage's `findings` with Member C before rendering them.

### Catalogue seeding

Member B has populated `fixtures/policies.json`, `products.json`, `repairs.json`, and `inventory.json` with explicitly fictional data. Every record has a stable string `_id`. Repair and inventory `compatible_model_ids` reference product `_id` values. Other required fields follow validation in `data/seed.jac`.

Then explicitly run:

```bash
jac run data/seed.jac
```

The loader validates all files before writing and upserts by stable ID. Repeated runs replace catalogue records with those IDs; they never overwrite cases. Empty placeholders are rejected with `EMPTY_FIXTURES`. Seeding is never triggered by server startup.

## Persistence and concurrency

The active assessment is embedded in its case record. Case state, revision, lease, and active stage result change together through MongoDB conditional single-document updates. This intentionally refines the initial architecture's separate active-assessment layout to avoid cross-document consistency assumptions.

Before an assessment is replaced by a correction or a new run, its snapshot is archived idempotently in `assessments`. Active results survive restart in `cases` immediately, even if they have not yet become historical snapshots. GridFS bytes and evidence metadata are separate records. Known rejected uploads are cleaned up; ambiguous network failures may leave unlinked files/metadata for later housekeeping. There is no claim of a multi-document transaction or exactly-once file storage.

Stage leases last 120 seconds. Expired leases can be reclaimed; result commits require the exact assessment, case revision, and lease token. Superseded results are rejected. No inventory quantities are mutated. Jac graphs are temporary and disconnected from persistent root.

## Verification and hosting

```bash
jac check main.jac shared server data workflow tests/platform_tests.jac -n
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
```

All 21 tests pass under the installed Jac 0.34.6 runtime. The suite uses an in-memory MongoDB substitute and synthetic image bytes, covering access checks, validation, duplicate requests, case pagination, GridFS round trips, conditional routing, stage leases, stale results, archival, and repeatable/validated seeding. Unit test handlers are internal injection points, never API endpoints or an environment-selected production mode.

A live HTTP smoke check also passed against the configured MongoDB service using a fresh temporary database: API connectivity, real GridFS uploads/downloads, honest missing-specialist errors, and saved case/assessment/file recovery after restarting the server. The temporary test collections were removed and the test servers stopped. No fixture catalogue or synthetic case was added to the application's configured database.

Before JacHammer hosting, set server-side secrets, confirm runtime/dependency support, verify MongoDB outbound access, and test the upload/request limits. The coordinator's 45-second timeout is a local application choice and still needs validation against hosted limits. No deployment has been performed.
