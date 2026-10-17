# Fixora AI API reference

This document describes the implemented Member A backend on **Jac 0.34.6 (Linux x86_64)**. Source of truth: `main.jac`, `server/`, `shared/`, `data/`, and `workflow/`.

The case/evidence APIs, coordinator and all five specialist modules are implemented. Seed the catalogue and configure a vision model/API key, or explicitly enable fixture demo mode. Without model configuration, a live assessment saves a `MODEL_NOT_CONFIGURED` error. See [MEMBER_B_HANDOFF.md](MEMBER_B_HANDOFF.md) for setup and detailed findings.

## Contents

- [Start and authenticate](#start-and-authenticate)
- [Response format](#response-format)
- [Endpoint summary](#endpoint-summary)
- [Copyable command setup](#copyable-command-setup)
- [Endpoint details and examples](#endpoint-details-and-examples)
- [Case, evidence, and assessment schemas](#case-evidence-and-assessment-schemas)
- [States, revisions, and retries](#states-revisions-and-retries)
- [Error reference](#error-reference)
- [Complete Python walkthrough](#complete-python-walkthrough)
- [Browser and Jac client examples](#browser-and-jac-client-examples)

## Start and authenticate

Run from the repository root inside Linux/WSL:

```bash
jac --version
jac install
jac start main.jac --no-client
```

Default base URL: `http://localhost:8000`. Use the actual port shown at startup. Hosting replaces this with your JacHammer application URL.

The server needs MongoDB settings and `FIXORA_ACCESS_TOKEN` in its environment or local `.env`. The token must contain at least 16 characters. Each application request supplies that token in the **JSON body** as `access_token`.

```json
{
  "access_token": "REPLACE_WITH_YOUR_LOCAL_DEMO_TOKEN"
}
```

This token is the shop's demo access secret, not a Jac user JWT. Sending an `Authorization: Bearer ...` header alone does not satisfy this application's access check. Do not hardcode the secret in a shared client bundle; supply it at runtime.

The server reads `.env` without exporting its contents into the process. For hosted environment secrets, prefer `FIXORA_MONGODB_URI`; the application also accepts local `MONGODB_URI`. The prefixed name avoids also configuring Jac's independent graph-persistence backend. Database URIs are never client API parameters.

## Response format

There are two response layers. Essential fields are shown below; Jac may include additional transport and `_jac_*` serialization metadata.

### Successful operation

```json
{
  "ok": true,
  "data": {
    "result": {
      "ok": true,
      "data": {
        "case": {
          "id": "11111111111111111111111111111111",
          "status": "draft",
          "revision": 0
        }
      },
      "error": null
    }
  }
}
```

The example case above is abbreviated. For raw HTTP clients, the Fixora application result is **`response.data.result`**. It contains:

| Field | Type | Meaning |
| --- | --- | --- |
| `ok` | boolean | Whether the requested platform operation succeeded |
| `data` | object | Operation-specific payload |
| `error` | object or null | Application error with `code` and `message` |

### Application error

The server normally returns application errors inside a successful Jac transport response, often with **HTTP 200**:

```json
{
  "ok": true,
  "data": {
    "result": {
      "ok": false,
      "data": {},
      "error": {
        "code": "STALE_REVISION",
        "message": "Reload the case and retry with its current revision."
      }
    }
  }
}
```

Check HTTP status, the outer transport result, **and the inner `ok`**. Jac routing, malformed JSON, missing parameters, or type-validation errors may fail at the transport layer and have a framework-specific error body.

### Saved specialist failure

An `advance_case` call can have inner `ok: true` while the returned case has `status: "failed"`: the operation successfully recorded a failed specialist attempt. Inspect `data.case.status` and `data.case.assessment.stages[stage].error` as well. This is distinct from a rejected API request.

All endpoint response examples below show **only the inner application's `data` payload**, unless labelled otherwise. IDs, dates, and findings are illustrative; replace IDs with values returned by your server.

## Endpoint summary

All ten application endpoints use **POST** and `Content-Type: application/json`, including read operations.

| Endpoint | Purpose | Main response payload |
| --- | --- | --- |
| `/function/platform_status` | Check database access and specialist availability | Database and specialist status |
| `/function/create_case` | Save a new intake case | `case` |
| `/function/get_case` | Fetch a saved case and current results | `case` |
| `/function/list_cases` | Fetch a page of case summaries | `cases`, `next_cursor` |
| `/function/update_case` | Correct description/model and invalidate current results | `case` |
| `/function/upload_evidence` | Upload one invoice/product image | `case`, `uploaded_evidence` |
| `/function/get_evidence` | Retrieve a currently linked image as base64 | Image content and metadata |
| `/function/remove_evidence` | Unlink an image from current case inputs | `case` |
| `/function/start_assessment` | Create an assessment without executing a specialist | `case` |
| `/function/advance_case` | Execute at most one specialist stage | `case` |

With all project dependencies installed, the full Jac server exposes:

```bash
curl -sS http://localhost:8000/healthz
curl -sS http://localhost:8000/openapi.json
# Open http://localhost:8000/docs for interactive API documentation.
```

These are framework operations, not case-data APIs. The earlier minimal fallback used `/functions` and `/walkers` for discovery; those routes are absent from the full server. Jac's built-in `/user/...` routes are outside this application's API contract. The entrypoint includes a Jac 0.34.6 compatibility adapter for guest initialization and request-parameter log redaction; restart the server after updating.

## Copyable command setup

The endpoint examples use **Bash, curl, and jq**. Run this setup once in the same terminal. Enter the token from your own `.env` at the prompt; it is not echoed.

```bash
set -o pipefail
export BASE_URL="http://localhost:8000"
read -rsp "Fixora access token: " FIXORA_ACCESS_TOKEN
printf '\n'
export FIXORA_ACCESS_TOKEN

# Read a JSON object from stdin, add the token, and POST it to an operation.
api() {
  jq '. + {access_token: env.FIXORA_ACCESS_TOKEN}' |
    curl --silent --show-error \
      "$BASE_URL/function/$1" \
      --header 'Content-Type: application/json' \
      --data-binary @-
}

# Replace these illustrative values as you receive real responses.
export CASE_ID="11111111111111111111111111111111"
export EVIDENCE_ID="22222222222222222222222222222222"
export ASSESSMENT_ID="33333333333333333333333333333333"
export REVISION="0"
```

`api` prints the raw Jac response, not just its inner data. Inspect both `ok` fields before using the payload. The Python walkthrough later handles this automatically and does not require jq.

For Postman/Insomnia or a one-off request, the equivalent direct call is:

```bash
curl --request POST 'http://localhost:8000/function/platform_status' \
  --header 'Content-Type: application/json' \
  --data '{"access_token":"REPLACE_WITH_YOUR_LOCAL_DEMO_TOKEN"}'
```

## Endpoint details and examples

### 1. Platform status

**POST `/function/platform_status`**

Checks the database and whether each specialist module exports a callable `run_stage` function. `ready` means the function is loadable; it does not certify working model credentials, a populated catalogue, or specialist accuracy. Database access may initialize repository indexes on the first call.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `access_token` | string | Yes | Configured Fixora demo access token |

```bash
printf '{}' | api platform_status
```

Example response data after dependencies are installed:

```json
{
  "database": "connected",
  "jac_baseline": "0.34.6",
  "specialists": {
    "document": "ready",
    "vision": "ready",
    "coverage": "ready",
    "repair_parts": "ready",
    "resolution": "ready"
  },
  "workflow": "client-advanced bounded stages",
  "human_review": "deferred"
}
```

Common errors: `UNAUTHORIZED`, `ACCESS_NOT_CONFIGURED`, `CONFIGURATION_ERROR`, `DATABASE_UNAVAILABLE`.

### 2. Create a case

**POST `/function/create_case`**

Saves the complaint and optional claimed product model. It does not upload files or run analysis.

| Parameter | Type | Required/default | Description |
| --- | --- | --- | --- |
| `description` | string | Required | Nonempty after trimming; at most 4,000 characters |
| `submission_id` | string | Required | Caller-generated ID for retry protection |
| `claimed_model_id` | string | Optional, `""` | At most 120 characters; use the catalogue model ID when known |
| `access_token` | string | Required | Demo access token |

```bash
RESPONSE="$(jq -n '{
  description: "Laptop does not power on. There is a crack near the hinge.",
  submission_id: "create-demo-0001",
  claimed_model_id: "demo-laptop-01"
}' | api create_case)"
printf '%s\n' "$RESPONSE" | jq '.'
```

Use a fresh submission ID for a genuinely new case. Repeating the same ID and trimmed description/model returns the existing case; changing the input with the same ID yields `IDEMPOTENCY_CONFLICT`. This endpoint stores the model claim; it does not establish that the model is supported or verified.

Response data: `{ "case": CaseView }`. A new case has `status: "draft"`, `revision: 0`, empty evidence lists, and null assessment fields. See the complete CaseView example below.

After checking both `ok` fields, capture actual IDs and revision from the saved create response:

```bash
export CASE_ID="$(printf '%s' "$RESPONSE" | jq -r '.data.result.data.case.id')"
export REVISION="$(printf '%s' "$RESPONSE" | jq -r '.data.result.data.case.revision')"
```

Common errors: `VALIDATION_ERROR`, `IDEMPOTENCY_CONFLICT`, plus common access/configuration/database errors.

### 3. Get a case

**POST `/function/get_case`**

Returns current case inputs, linked evidence metadata, and the active assessment. File bytes are fetched separately through `get_evidence`.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Server-returned case ID |
| `access_token` | string | Yes | Demo access token |

```bash
jq -n '{case_id: env.CASE_ID}' | api get_case
```

Response data: `{ "case": CaseView }`.

Use this operation to refresh the revision after a conflict, recover state after reconnecting, or inspect a previously saved stage error. Reading does not advance the workflow.

Common errors: `VALIDATION_ERROR`, `NOT_FOUND`, plus common errors.

### 4. List cases

**POST `/function/list_cases`**

Returns summaries ordered by creation timestamp descending, with case ID descending as a tie-breaker. The list is not sorted by last update.

| Parameter | Type | Required/default | Description |
| --- | --- | --- | --- |
| `limit` | integer | Optional, `20` | Between 1 and 50 |
| `cursor` | string | Optional, `""` | Prior page's `next_cursor` case ID |
| `access_token` | string | Required | Demo access token |

```bash
jq -n '{limit: 10}' | api list_cases
```

Example response data:

```json
{
  "cases": [
    {
      "id": "11111111111111111111111111111111",
      "description": "Laptop does not power on.",
      "status": "draft",
      "revision": 0,
      "claimed_model_id": "demo-laptop-01",
      "updated_at": "2026-10-17T07:00:00.000+00:00"
    }
  ],
  "next_cursor": null
}
```

For a subsequent page, pass the actual non-null cursor:

```bash
export CURSOR="11111111111111111111111111111111"
jq -n '{limit: 10, cursor: env.CURSOR}' | api list_cases
```

`next_cursor: null` means there is no next page. Send an omitted/empty cursor for the first page, not JSON null.

Common errors: `VALIDATION_ERROR`, `NOT_FOUND` for an unknown cursor case, plus common errors.

### 5. Update a case

**POST `/function/update_case`**

Replaces the complaint/model inputs. Archives the previous assessment if present, clears the active assessment, and returns the case to `draft`. Linked evidence is retained. The revision increases by one on a normal successful update.

| Parameter | Type | Required/default | Description |
| --- | --- | --- | --- |
| `case_id` | string | Required | Case to update |
| `expected_revision` | integer | Required | Latest revision returned by the server |
| `description` | string | Required | Replacement description; same limits as create |
| `claimed_model_id` | string | Optional, `""` | Replacement model ID; omitting it clears the current claim |
| `access_token` | string | Required | Demo access token |

```bash
jq -n '{
  case_id: env.CASE_ID,
  expected_revision: (env.REVISION | tonumber),
  description: "Corrected report: laptop starts, but the screen stays black.",
  claimed_model_id: "demo-laptop-01"
}' | api update_case
```

Response data: `{ "case": CaseView }` with `assessment: null`, `active_assessment_id: null`, and `status: "draft"`.

An active unexpired stage lease prevents edits. If inputs change, start a new assessment before advancing again. This operation has no request-ID retry protection: after an uncertain network outcome, fetch the case and inspect its current values/revision before repeating the edit.

Common errors: `STALE_REVISION`, `STAGE_BUSY`, `VALIDATION_ERROR`, `NOT_FOUND`, plus common errors.

### 6. Upload evidence

**POST `/function/upload_evidence`**

Stores one image in MongoDB GridFS and links it to the case. This API uses JSON/base64, not multipart form data.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Case receiving the upload |
| `expected_revision` | integer | Yes | Latest case revision |
| `kind` | string | Yes | Exactly `"invoice"` or `"product"` |
| `filename` | string | Yes | Nonempty filename, at most 120 characters after path stripping |
| `content_base64` | string | Yes | Plain base64 of actual JPEG/PNG bytes |
| `request_id` | string | Yes | Unique upload ID, reused only for the same upload retry |
| `access_token` | string | Yes | Demo access token |

Limits: **5,242,880 decoded bytes (5 MiB)** and **25,000,000 pixels** per image; at most **one invoice and three product images** linked to a case. The server checks image content rather than trusting the extension. Do not include a `data:image/png;base64,` prefix.

Upload a real local invoice file without placing base64 in a shell argument:

```bash
base64 < invoice.png | tr -d '\r\n' |
  jq -Rs '{
    case_id: env.CASE_ID,
    expected_revision: (env.REVISION | tonumber),
    kind: "invoice",
    filename: "invoice.png",
    content_base64: .,
    request_id: "invoice-demo-0001"
  }' | api upload_evidence
```

Read the new case revision from that response before uploading the product photo:

```bash
base64 < product.png | tr -d '\r\n' |
  jq -Rs '{
    case_id: env.CASE_ID,
    expected_revision: (env.REVISION | tonumber),
    kind: "product",
    filename: "product.png",
    content_base64: .,
    request_id: "product-demo-0001"
  }' | api upload_evidence
```

Response data has two fields:

```json
{
  "case": {
    "id": "11111111111111111111111111111111",
    "revision": 1,
    "status": "draft"
  },
  "uploaded_evidence": {
    "id": "22222222222222222222222222222222",
    "kind": "invoice",
    "filename": "invoice.png",
    "mime_type": "image/png",
    "size_bytes": 1024,
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "uploaded_at": "2026-10-17T07:01:00.000+00:00"
  }
}
```

The case is abbreviated here. The evidence hash/size are illustrative, not the expected values for your file.

A successful new upload increases revision by one and invalidates any active assessment. An identical upload retry with the same request ID returns its existing evidence without creating another file. Reusing that ID with changed content, kind, or normalized filename yields `IDEMPOTENCY_CONFLICT`. Concurrent finalization may return `STAGE_BUSY`.

Common errors: `VALIDATION_ERROR`, `STALE_REVISION`, `STAGE_BUSY`, `IDEMPOTENCY_CONFLICT`, `NOT_FOUND`, plus common errors.

### 7. Get evidence

**POST `/function/get_evidence`**

Returns one currently linked evidence file. Both IDs are required; a valid evidence ID cannot be fetched through an unrelated case.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Owning case ID |
| `evidence_id` | string | Yes | Evidence ID currently linked to that case |
| `access_token` | string | Yes | Demo access token |

```bash
jq -n '{case_id: env.CASE_ID, evidence_id: env.EVIDENCE_ID}' | api get_evidence
```

Response data fields: `evidence_id`, `filename`, `mime_type`, and `content_base64`. The content is the original bytes encoded as plain base64; the response is JSON, not a binary download or public file URL.

Save a PNG response locally after checking application success:

```bash
jq -n '{case_id: env.CASE_ID, evidence_id: env.EVIDENCE_ID}' |
  api get_evidence |
  jq -er 'if .ok and .data.result.ok then .data.result.data.content_base64 else error("Evidence request failed") end' |
  base64 --decode > downloaded-evidence.png
```

Use an extension matching the returned MIME type. Browser code can construct a preview URL with `data:${mime_type};base64,${content_base64}`.

Common errors: `NOT_FOUND`, `VALIDATION_ERROR`, `EVIDENCE_UNAVAILABLE`, plus common errors.

### 8. Remove evidence

**POST `/function/remove_evidence`**

Unlinks an image from current case inputs. It **retains the original file and metadata** for historical assessment references. It is not a permanent deletion API. An unlinked image can no longer be fetched through the current `get_evidence` API.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Owning case ID |
| `evidence_id` | string | Yes | Currently linked evidence ID |
| `expected_revision` | integer | Yes | Latest case revision |
| `access_token` | string | Yes | Demo access token |

```bash
jq -n '{
  case_id: env.CASE_ID,
  evidence_id: env.EVIDENCE_ID,
  expected_revision: (env.REVISION | tonumber)
}' | api remove_evidence
```

Response data: `{ "case": CaseView }`. A successful removal increases revision by one, archives/clears the current assessment, and returns the case to `draft`.

To replace an invoice, remove the old image, read the returned revision, then upload its replacement using a **new** upload request ID. After an uncertain removal response, fetch the case and check whether the evidence ID is still linked before retrying.

Common errors: `STALE_REVISION`, `STAGE_BUSY`, `NOT_FOUND`, `VALIDATION_ERROR`, plus common errors.

### 9. Start an assessment

**POST `/function/start_assessment`**

Creates the next assessment version and sets the case to `processing`. Requires a linked invoice and at least one linked product image. **No specialist is executed by this call.**

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Case with required evidence |
| `expected_revision` | integer | Yes | Latest case revision |
| `request_id` | string | Yes | Unique start request ID |
| `access_token` | string | Yes | Demo access token |

```bash
jq -n '{
  case_id: env.CASE_ID,
  expected_revision: (env.REVISION | tonumber),
  request_id: "assessment-demo-0001"
}' | api start_assessment
```

Response data: `{ "case": CaseView }`. Its `active_assessment_id` matches `case.assessment.id`; the initial assessment has `next_stage: 0`, `stages: {}`, and `next_action: "continue"`. The case revision increases by one on a new start.

For example, a case with revision 2 after two uploads becomes revision 3. Its assessment's `input_revision` remains 2, recording the input snapshot.

Retrying the current assessment's start request ID returns the current case without starting another run. A new request ID starts a new assessment version and archives the previous assessment, provided no stage has an unexpired lease. A request ID already belonging to archived assessment history is rejected with `IDEMPOTENCY_CONFLICT`.

Common errors: `MISSING_EVIDENCE`, `STALE_REVISION`, `STAGE_BUSY`, `IDEMPOTENCY_CONFLICT`, `NOT_FOUND`, `VALIDATION_ERROR`, plus common errors.

### 10. Advance a case

**POST `/function/advance_case`**

Claims and executes **at most one** next stage, validates its result, and saves the updated case. Stage order is:

```text
document -> vision -> coverage -> repair_parts -> resolution
```

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `case_id` | string | Yes | Case to advance |
| `assessment_id` | string | Yes | Current `active_assessment_id` |
| `expected_revision` | integer | Yes | Latest case revision |
| `request_id` | string | Yes | Fresh ID for this stage attempt, retained for a retry of that attempt |
| `access_token` | string | Yes | Demo access token |

```bash
jq -n '{
  case_id: env.CASE_ID,
  assessment_id: env.ASSESSMENT_ID,
  expected_revision: (env.REVISION | tonumber),
  request_id: "advance-demo-0001"
}' | api advance_case
```

Response data: `{ "case": CaseView }`. A normal claim and result commit each increase the revision, so a stage ordinarily increases it by **two**. Always use the actual revision returned by the server instead of calculating it yourself.

The stage result is at `case.assessment.stages[stage]`. The following is the inner application result when **live model configuration is missing**; the case is abbreviated:

```json
{
  "ok": true,
  "data": {
    "case": {
      "id": "11111111111111111111111111111111",
      "status": "failed",
      "revision": 5,
      "active_assessment_id": "33333333333333333333333333333333",
      "assessment": {
        "id": "33333333333333333333333333333333",
        "next_stage": 0,
        "stages": {
          "document": {
            "stage": "document",
            "status": "failed",
            "findings": {},
            "evidence_refs": [],
            "missing_fields": [],
            "conflicts": [],
            "next_action": "continue",
            "error": {
              "code": "MODEL_NOT_CONFIGURED",
              "message": "Set FIXORA_MODEL and the provider API key, or explicitly enable fixture demo mode."
            },
            "started_at": "2026-10-17T07:02:00.000+00:00",
            "finished_at": "2026-10-17T07:02:00.100+00:00"
          }
        }
      }
    }
  },
  "error": null
}
```

Only advance automatically while `case.status == "processing"`. Stop on `needs_information`, `needs_inspection`, `completed`, or `failed`. A failed case can be retried explicitly with the same assessment and latest revision after fixing the underlying issue. Missing specialists require implementation; repeated calls alone will not fix them.

The wrapper times out a specialist after 45 seconds; allow a longer HTTP client timeout, such as 60 seconds. A stage lease lasts 120 seconds. After a crashed request, reload the case and wait for an active lease to finish/expire before retrying. Closing the browser pauses future advancement; this is not an autonomous background queue.

Replaying an already completed/blocked stage request ID returns current case state without advancing another stage. Failed attempts remain retryable. Revision and lease checks reject superseded results.

Rejected-call errors: `INVALID_STATE`, `STALE_REVISION`, `STAGE_BUSY`, `NOT_FOUND`, `VALIDATION_ERROR`, plus common errors. Saved-stage errors include `SPECIALIST_UNAVAILABLE`, `MODEL_TIMEOUT`, `INVALID_SPECIALIST_RESULT`, and `SPECIALIST_FAILED`.

## Case, evidence, and assessment schemas

### CaseView

A full newly created case response data example:

```json
{
  "case": {
    "id": "11111111111111111111111111111111",
    "description": "Laptop does not power on.",
    "claimed_model_id": "demo-laptop-01",
    "status": "draft",
    "revision": 0,
    "created_at": "2026-10-17T07:00:00.000+00:00",
    "updated_at": "2026-10-17T07:00:00.000+00:00",
    "evidence_ids": [],
    "evidence": [],
    "active_assessment_id": null,
    "assessment": null
  }
}
```

`get_case` and case mutation responses return this same view shape. The assessment becomes a populated object after starting. `list_cases` returns the smaller summary shape shown earlier.

### Evidence metadata

Entries in `case.evidence` and `uploaded_evidence` contain `id`, `kind`, `filename`, `mime_type`, `size_bytes`, `sha256`, and `uploaded_at`. They omit GridFS IDs, file bytes, and internal upload request identifiers. Use `evidence_ids`/metadata to identify files; do not rely on array position to determine invoice versus product kind.

### Assessment view

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Assessment ID |
| `case_id` | string | Owning case ID |
| `version` | integer | Assessment version for this case, starting at 1 |
| `input_revision` | integer | Case revision used to start this assessment |
| `created_at`, `updated_at` | ISO 8601 strings | UTC event timestamps |
| `next_stage` | integer | Next stage index, 0–4; 5 after a fully completed pipeline |
| `stages` | object | Persisted stage results keyed by stage name |
| `next_action` | string | Most recently saved next-action recommendation |

Each persisted stage result contains `stage`, `status`, `findings`, `evidence_refs`, `missing_fields`, `conflicts`, `next_action`, nullable `error`, `started_at`, and `finished_at`.

Stage status values: `completed`, `blocked`, `failed`. Next-action values: `continue`, `needs_information`, `needs_inspection`, `complete`. Case status governs whether the client should keep advancing; a failed stage may still have `next_action: "continue"` so that it can be retried explicitly.

`findings` is stage-specific JSON: `document.invoice`, `vision.observations`, `coverage.coverage` and `policy_clauses`, `repair_parts.options`, and `resolution.report`. Each stage includes `analysis_mode` (`live_model` or `demo_fixture`); the latter is an explicitly selected recorded extraction. Prices are integer minor units; customer payable and turnaround remain null. [Member B's schema reference](MEMBER_B_HANDOFF.md#findings-for-member-c) includes report and option details.

## States, revisions, and retries

| Case status | Meaning | Client behavior |
| --- | --- | --- |
| `draft` | Inputs are being assembled or were corrected | Add required evidence, then start an assessment |
| `processing` | An assessment has a next stage | Advance one stage at a time using the latest revision |
| `needs_information` | Missing fields or conflicting evidence | Show the issue; correct inputs/evidence and start a new assessment |
| `needs_inspection` | Evidence cannot establish a reliable next decision | Show inspection recommendation; do not invent a confirmed fault |
| `completed` | Resolution stage finished | Display the recommendation |
| `failed` | A technical specialist attempt failed | Show its saved error; offer an explicit retry when appropriate |

Human approval, warranty claim submission, stock reservation, and technician inspection-entry endpoints are not implemented. `completed` means the recommendation is ready; it does not mean a repair was performed or a warranty claim approved.

Case/assessment/evidence IDs are **32 lowercase hexadecimal characters**. Submission/request IDs contain **8–80 letters, digits, underscores or hyphens**. A UUID hex string works for a caller-generated request ID.

| Operation | Retry protection |
| --- | --- |
| `create_case` | Same `submission_id` + same input returns existing case |
| `upload_evidence` | Same case/request ID + same content/kind/filename returns existing evidence |
| `start_assessment` | Repeating the active start request returns current case; archived reuse is rejected |
| `advance_case` | Replaying a completed/blocked request does not execute another stage; failed attempts can be retried |
| `update_case`, `remove_evidence` | Revision protection only; fetch current state after an uncertain network outcome |

Never reuse one request ID for different actions. Refresh `expected_revision` after mutations and after a technical failure. On a lost response, fetch the case before retrying if its revision may have changed. Do not blindly send a newly generated request ID after a lost stage response: that could advance the following stage.

## Error reference

All application endpoints may return access, configuration, database, or internal errors. Error messages are safe descriptions; database credentials and raw provider exceptions are withheld.

| Code | Location | Meaning/action |
| --- | --- | --- |
| `UNAUTHORIZED` | Application error | Wrong/missing demo token |
| `ACCESS_NOT_CONFIGURED` | Application error | Server token missing or shorter than 16 characters |
| `CONFIGURATION_ERROR` | Application error | Invalid server database configuration |
| `VALIDATION_ERROR` | Application error | Invalid ID, empty/oversized text, invalid limit, unsupported/oversized image, or upload-count limit |
| `NOT_FOUND` | Application error | Unknown case/evidence/cursor, or evidence not linked to that case |
| `IDEMPOTENCY_CONFLICT` | Application error | Request identity was reused for different or archived input |
| `STALE_REVISION` | Application error | Case/assessment changed; reload before retrying |
| `STAGE_BUSY` | Application error | Active lease or an upload being finalized; wait/reload |
| `MISSING_EVIDENCE` | Application error | Starting requires an invoice and at least one product image |
| `INVALID_STATE` | Application error or saved stage error | Case cannot advance in its current state, or workflow consistency failed |
| `DATABASE_UNAVAILABLE` | Application error | MongoDB operation failed; check server access/configuration/connectivity |
| `EVIDENCE_UNAVAILABLE` | Application error | Metadata exists but GridFS cannot retrieve the file |
| `INTERNAL_ERROR` | Application error | Unexpected platform failure; inspect server configuration/logs |
| `SPECIALIST_UNAVAILABLE` | Saved stage error | Specialist function or installed dependency could not be loaded |
| `MODEL_NOT_CONFIGURED` | Saved stage error | Set a vision model and provider key, or explicitly use bundled fixture mode |
| `MODEL_AUTH_ERROR`, `MODEL_RATE_LIMIT`, `MODEL_NOT_FOUND` | Saved stage error | Fix provider credentials, quota or model selection before retrying |
| `MODEL_INVALID_OUTPUT` | Saved stage error | Structured extraction or its validated fields are invalid |
| `MODEL_BUSY` | Saved stage error | Another image request is running; retry shortly |
| `MODEL_UNAVAILABLE`, `MODEL_CONNECTION_ERROR` | Saved stage error | Provider is temporarily busy/unavailable or cannot be reached; retry explicitly later |
| `DEMO_EVIDENCE_NOT_FOUND` | Saved stage error | Fixture mode received an image outside the bundled hash allowlist |
| `INVALID_CATALOGUE`, `MISSING_STAGE_RESULT` | Saved stage error | Catalogue or prerequisite result does not support this stage |
| `MODEL_TIMEOUT` | Saved stage error | Specialist exceeded 45 seconds |
| `INVALID_SPECIALIST_RESULT` | Saved stage error | Wrong stage/type/status, invalid references, non-JSON/oversized result, or invalid next action |
| `SPECIALIST_FAILED` | Saved stage error | Unexpected specialist exception; details withheld |

Catalogue-seeding errors such as `EMPTY_FIXTURES` belong to the explicit seed command, not an HTTP endpoint. There are currently no HTTP catalogue-editing or seeding operations.

## Complete Python walkthrough

This example needs only Python's standard library. Start the server first, save the example as a local script, and put synthetic `invoice.png` and `product.png` next to it. It **creates a persistent case and two evidence files** in the server's configured database. It does not delete them afterwards.

It uses `FIXORA_ACCESS_TOKEN` from the terminal environment or prompts for it. The server reading `.env` does not automatically populate the client script's environment.

```python
import base64
import getpass
import json
import os
import uuid
from pathlib import Path
from urllib.request import Request, urlopen

base_url = os.environ.get("BASE_URL", "http://localhost:8000").rstrip("/")
token = os.environ.get("FIXORA_ACCESS_TOKEN") or getpass.getpass("Fixora token: ")

def call_api(operation, **payload):
    request = Request(
        f"{base_url}/function/{operation}",
        data=json.dumps({**payload, "access_token": token}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=60) as response:
        envelope = json.load(response)
    if envelope.get("ok") is not True:
        raise RuntimeError("Jac transport rejected the request")
    result = envelope.get("data", {}).get("result", {})
    if result.get("ok") is not True:
        error = result.get("error") or {}
        raise RuntimeError(f"{error.get('code')}: {error.get('message')}")
    return result["data"]

print("Database:", call_api("platform_status")["database"])
case = call_api(
    "create_case",
    description="Synthetic demo: laptop does not power on.",
    submission_id=uuid.uuid4().hex,
    claimed_model_id="demo-laptop-01",
)["case"]

for kind, filename in [("invoice", "invoice.png"), ("product", "product.png")]:
    case = call_api(
        "upload_evidence",
        case_id=case["id"],
        expected_revision=case["revision"],
        kind=kind,
        filename=filename,
        content_base64=base64.b64encode(Path(filename).read_bytes()).decode("ascii"),
        request_id=uuid.uuid4().hex,
    )["case"]

case = call_api(
    "start_assessment",
    case_id=case["id"],
    expected_revision=case["revision"],
    request_id=uuid.uuid4().hex,
)["case"]

# Five stages maximum; stop on any blocked, failed, or completed case.
for _ in range(5):
    if case["status"] != "processing":
        break
    case = call_api(
        "advance_case",
        case_id=case["id"],
        assessment_id=case["active_assessment_id"],
        expected_revision=case["revision"],
        request_id=uuid.uuid4().hex,
    )["case"]

print("Case:", case["id"], "Status:", case["status"], "Revision:", case["revision"])
for stage_name, stage in case["assessment"]["stages"].items():
    print(stage_name, stage["status"], stage.get("error"))

restored = call_api("get_case", case_id=case["id"])["case"]
print("Reloaded case:", restored["id"], restored["status"])
```

Use the matching invoice/product pair and description from `fixtures/scenarios.json` in fixture mode; arbitrary images are rejected there. With live mode enabled, configure a vision model and API key. This example has no automatic network retry; retain request IDs and reconcile case state as described above.

## Browser and Jac client examples

### Browser fetch

Pass a runtime-entered access token. Same-origin requests work when the interface is served alongside the Jac backend. A separately hosted frontend needs an appropriate development proxy or tested server CORS configuration; this scaffold does not promise cross-origin access.

```javascript
async function callFixora(operation, payload, accessToken, baseUrl = "") {
  const response = await fetch(`${baseUrl}/function/${operation}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...payload, access_token: accessToken }),
  });
  const envelope = await response.json();
  if (!response.ok || envelope.ok !== true) {
    throw new Error("Jac transport request failed");
  }
  const result = envelope.data?.result;
  if (result?.ok !== true) {
    const error = result?.error;
    throw new Error(`${error?.code ?? "API_ERROR"}: ${error?.message ?? "Request failed"}`);
  }
  return result.data;
}

// accessToken comes from your runtime UI, not a bundled secret constant.
async function loadSavedCase(caseId, accessToken) {
  const { case: savedCase } = await callFixora("get_case", { case_id: caseId }, accessToken);
  return savedCase;
}
```

### Jac client RPC

From a client module inside `ui/`, import the operation and its response type through the server boundary. The function below is a client-side helper sketch, not a complete component:

```jac
cl {
    sv import from ..server.cases { get_case, ApiResult }

    async def load_saved_case(case_id: str, access_token: str) -> ApiResult {
        return await get_case(case_id=case_id, access_token=access_token);
    }
}
```

A Jac RPC caller receives `ApiResult` directly, so inspect `result.ok` and `result.data["case"]`; do not unwrap another `data.result` layer. The interface still needs to inspect `case.status` after advancement.

See [MEMBER_A_HANDOFF.md](MEMBER_A_HANDOFF.md) for specialist contracts and [README.md](README.md) for project setup and team ownership.
