# Fixora WhatsApp demo

Customers use WhatsApp; the shop owner uses the existing web dashboard. Jac still runs document, vision, coverage, repair/parts and resolution. MongoDB is the shared source of truth; GridFS stores evidence. There is no browser-local case database or customer web sign-in.

## Local setup (WSL / Linux)

Use Jac **0.34.13**, the shared client/backend baseline. The project launcher finds the existing WSL installation or respects `FIXORA_JAC_BINARY`. Python **3.12+** is required for the channel service.

```bash
bash scripts/jac.sh install --dev
bash scripts/whatsapp.sh setup
```

The setup script uses `uv` if available, otherwise `python3 -m venv` and pip. Ubuntu installations without venv support need `python3-venv`. The isolated Python environment defaults to `~/.cache/fixora-whatsapp/python`; override its interpreter with `FIXORA_WHATSAPP_PYTHON`.

Copy missing settings from `.env.example` into your ignored `.env`; preserve any existing MongoDB configuration and service token. Configure:

- `FIXORA_MONGODB_URI` (or local `MONGODB_URI`), `MONGODB_DB`, and `FIXORA_ACCESS_TOKEN` (16+ characters).
- `FIXORA_MODEL` and its provider key (`GOOGLE_API_KEY`, `OPENAI_API_KEY`, etc., or `FIXORA_MODEL_API_KEY`). Use a vision-capable model for evidence. `FIXORA_INTAKE_MODEL` optionally selects a separate text model.
- `FIXORA_DEMO_MODE=false` for live evidence extraction. There is no silent fallback to fixtures. The natural-language intake model always requires its own valid model configuration, including when recorded evidence extraction is selected.
- `FIXORA_OWNER_PASSWORD`: choose a separate password of at least 16 characters. There is no default password or customer login.
- `FIXORA_TRANSCRIPTION_API_KEY` (or `OPENAI_API_KEY`) for English voice notes. `FIXORA_TRANSCRIPTION_MODEL` defaults to `gpt-4o-mini-transcribe`. This is separate from a Gemini or other intake/vision key; all voice replies are text.
- `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, and `WHATSAPP_GRAPH_VERSION` from your Meta setup. The verification token is a separate value you choose, not the access token or app secret.

Seed the fictional catalogue once in the intended demo database:

```bash
bash scripts/jac.sh run data/seed.jac
```

Seeding replaces catalogue records with the same IDs. It does not clear cases. Existing browser-local demo cases are not migrated. The seeded models are **FD-100, FD-200, FD-300**; the earlier UI-only Studio/Pro/Air catalogue is not used.

## Run the four processes

In separate WSL terminals, from the project root:

```bash
# Jac API and owner web interface
bash scripts/jac.sh start main.jac --no-dev -p 8000

# Public webhook receiver only
bash scripts/whatsapp.sh public

# Private owner API and password session
bash scripts/whatsapp.sh owner

# Durable inbox, assessment jobs and outgoing messages
bash scripts/whatsapp.sh worker
```

Open **http://localhost:8000** and sign in with the owner password. The browser talks to **localhost:8011** using an HttpOnly, SameSite=Strict cookie, with an eight-hour expiry. Keep the same hostname for both services. The owner API accepts browser writes only from configured `FIXORA_OWNER_ORIGINS` and rate-limits password attempts. Service, model and Meta credentials stay server-side. Restart these processes after changing `.env`.

The owner gateway and public receiver are separate FastAPI applications. Tunnel **only port 8010**. Do not expose ports 8000 or 8011. This is a local demonstration setup, not a production authentication or hosting configuration.

## Connect Meta's test number

1. In Meta's developer dashboard, create/select the business app and add WhatsApp. Use its test business number and add the permitted recipient numbers shown in API Setup.
2. Fill the WhatsApp configuration values above. Select the Graph API version supported by your Meta application; the adapter intentionally requires an explicit version.
3. Start an HTTPS tunnel to `http://127.0.0.1:8010`, for example `cloudflared tunnel --url http://127.0.0.1:8010` or `ngrok http 8010` if installed.
4. Set the callback URL to `https://<tunnel-host>/webhooks/whatsapp`. Enter the configured `WHATSAPP_VERIFY_TOKEN` and verify the challenge.
5. Subscribe the app/account to **messages** webhooks so customer messages and delivery receipts reach the receiver. Verify that the webhook's `metadata.phone_number_id` matches your configured test number ID.
6. Send a message from an approved test recipient to that number. Temporary Meta tokens can expire; replace them and restart the worker when necessary.

The receiver checks the `X-Hub-Signature-256` HMAC against the raw body and app secret. It returns 200 only after inbox records are saved. Database failures return 503 for redelivery. Unknown phone number IDs are ignored. The public app exposes no owner routes or API docs.

References: [Meta Cloud API collection](https://www.postman.com/meta/whatsapp-business-platform/collection/wlk6lh4/whatsapp-cloud-api), [WhatsApp messaging policy](https://whatsappbusiness.com/policy/), [FastAPI credentialed CORS](https://fastapi.tiangolo.com/tutorial/cors/), [LiteLLM structured output](https://docs.litellm.ai/docs/completion/json_mode).

## Demonstrate the customer and owner journey

1. Customer: describe the laptop issue naturally and identify the printed model if known. The bot saves the complaint and requests missing evidence.
2. Send the invoice as a JPEG/PNG photo, with caption `INVOICE`, and one to three device photos with caption `DEVICE`. Without a clear caption, Fixora asks you to label the first pending image; subsequent images are handled in order. Each file must be at most 5 MB and meet the existing decoded-image validation.
3. Reply `READY` when the evidence is complete. The worker runs the existing bounded stages independently of the browser. It stops for missing information, identity conflict, inspection or failure. Do not expect a power/charging fault to be established from a picture; the seeded repair catalogue supports display, hinge and keyboard work.
4. Owner: open the case, inspect evidence and saved findings, and reply from the Conversation tab. Public replies enter the outgoing queue. **Add internal note** and inspection notes stay private.
5. Use **Correct details** to replace the issue description/model, or **Inspection** to record a supported diagnosis (or `unknown`). Both create a revision, invalidate the previous assessment/approval, and retain decision history. Queue a new assessment after resolving the inputs. Inspection cannot bypass invoice identity conflicts or establish an unsupported internal fault.
6. Approve or decline a completed current proposal with a customer-facing reason. Assessment status remains separate from owner review. Stale revisions and unresolved information/inspection requests block final review. Approval does not reserve parts, charge money or establish final payment.
7. The customer receives the shop response in WhatsApp. The dashboard refreshes every four seconds while idle; it pauses refreshes during editing so a review stays tied to the displayed revision. Use **Load latest** after a conflict.

Customer commands:

| Command | Behavior |
| --- | --- |
| `READY` / `ASSESS` | Confirm uploads and queue assessment |
| `STATUS` | Saved findings and image IDs |
| `CASES` | List the customer's ten most recent cases |
| `OPEN <case ID>` | Switch to an existing case owned by that sender |
| `NEW` | Start a fresh active case |
| `REMOVE <image ID>` | Unlink a current image before replacing it; invalidate assessment |
| `RETRY` | Retry a failed intake/media operation or failed assessment |
| `HELP` | Intake guidance and a route to shop assistance |
| `UPDATES` | Opt in to later case notifications |
| `STOP` / `START` | Stop / resume automated responses |

Text, English voice notes and JPEG/PNG images are supported. PDFs and videos receive an explanatory response. Media bytes are downloaded using the Meta access token only from approved Meta HTTPS hosts. Images pass through the existing Jac image validator into GridFS.

## Voice notes and shopping enquiries

Customers can ask, for example, “Is the FD-100 available, and how much?”, “Do you have an FD-100 keyboard?” or “How much is a USB mouse?” by text or voice. These enquiries do not open a warranty case or change an existing repair assessment. The configured intake model selects catalogue IDs; server code reloads their saved stock and prices and formats the reply. Unknown items, missing prices/quantities and ambiguous variants receive clarification instead of invented facts. Multiple matches include their model/SKU so the customer can specify one. Stock is not reserved and fitting/labour is separate.

Audio download and transcription happen in the durable worker. Accept OGG/Opus WhatsApp voice notes, MP3, M4A, WAV and WebM, with a 16 MB download limit enforced on both metadata and actual bytes. AAC and AMR are not converted in this release; send an ordinary WhatsApp voice note or type the question instead. The transcription request uses an extension-bearing multipart file and English language hint. See the [OpenAI transcription API](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create).

The transcript is persisted before inference and reused on restart or explicit `RETRY`. Customers see what was heard and can type corrections, especially model codes. Raw audio is held only in worker memory and sent to the transcription provider; Fixora stores the transcript and Meta media ID, not the audio bytes. Transcripts can contain recognition errors. Case-control commands, including `READY`, must be typed. Voice symptoms can update repair intake. Transcription/provider failures are saved and surfaced; there is no fixture fallback. Missing transcription credentials leave typed chat usable.

In the owner dashboard, **Customer conversations** includes shopping enquiries, voice transcripts, repair messages and delivery state. Select a sender to reply or save a private note; **Refresh** loads new messages while the conversation is open. **Products and stock** shows the catalogue snapshot.

Catalogue source of truth:

| Collection | Fields |
| --- | --- |
| `products` | Existing model identity plus optional `quantity_available`, `unit_price_minor`, `currency`, `aliases` |
| `inventory` | Existing repair-part stock/price/compatibility; `display_name`, `aliases`, and `category: "part"` or `"accessory"` |
| Either | `retail_enabled: false` excludes an item from shopping; `synthetic: true` explicitly labels demo facts |

Prices use integer minor units (100 minor units per LKR/USD unit). Missing or invalid values remain unconfirmed. Maintain these records in the configured MongoDB database; this release includes a read-only dashboard catalogue, not an inventory-management screen. Keep real records scoped to the shop with `shop_id`, use the existing supported product IDs for part compatibility, and remove `synthetic` only for verified real data. The seed now includes three fictional laptop sale prices/quantities, existing repair parts and one fictional USB mouse. Do not rerun the seed over edited records with the same IDs: seeding replaces them.

## Delivery and restart behavior

Inbox message IDs, case submission IDs, media upload IDs and job IDs are stable across retries. MongoDB conversation leases serialize customer processing, owner operations and outgoing delivery. Expired work leases are reclaimable after a restart; active specialist leases remain respected. The default conversation lease is ten minutes and is renewed between stages.

Public messages are saved in their case or wa_chat_messages first and published into an idempotent outbox. A restart between those steps cannot lose the message. Internal notes are never published. Delivery receipts update the corresponding outgoing message, without regressing a read receipt to sent.

Free-form replies are sent only within 24 hours of the latest customer message. After that, updates remain `pending_window`. If `WHATSAPP_UPDATE_TEMPLATE` names an approved **no-parameter utility template**, a customer who replied `UPDATES` can receive one generic re-engagement template per expired window. The full case update remains withheld until the customer replies. `WHATSAPP_TEMPLATE_LANGUAGE` defaults to `en_US`. An example template to submit for approval is: “There is an update on your repair case. Please reply to view it.” Actual approval and availability are controlled by Meta.

The conversation shows `queued`, `sent`, `delivered`, `read`, `pending_window`, `awaiting_reply`, `failed`, `uncertain`, or `cancelled`. A known rejected/failed delivery has a **Retry delivery** control after its cause is resolved. A timeout or interrupted send may already have been accepted by Meta; it is marked **uncertain** and is not automatically resent. Check the actual WhatsApp chat before any manual re-send. Exactly-once external delivery cannot be guaranteed by the Cloud API.

`STOP` cancels queued automatic work/messages, sends one acknowledgement and suppresses further automated replies until `START` or `UPDATES`. The bot includes a shop/in-store escalation path. Configure the business support contact and publish the required privacy notice before onboarding real customers.

## Verification

```bash
# Offline adapter/worker tests, Jac backend tests and owner client build/tests
bash scripts/whatsapp.sh test

# Real MongoDB + Jac HTTP + owner API, using recorded synthetic evidence
bash scripts/whatsapp.sh verify
```

The integration verifier creates its own randomly named temporary database, exercises complete/conflicting/inspection cases, owner decisions, private notes, GridFS evidence, product/part/accessory enquiries, a saved voice transcript and restart persistence, then removes only its temporary collections/records. Its signed webhook calls run through the real receiver; Meta delivery, intake parsing and transcription are explicit test doubles. It never sends messages or makes model requests. Summary and server log: `.jac/whatsapp-verification.json` and `.jac/whatsapp-integration.log`.

A live WhatsApp demonstration additionally requires configured Meta assets, an approved recipient, a working HTTPS callback, a model/key, and all four running processes. Verify that invoice/vision findings show `live_model` and confirm the message on the recipient's phone. Local fixture verification is not evidence of live Meta/model connectivity.

## Owner API additions

The private API exposes `POST /owner/login`, `GET /owner/session`, `POST /owner/logout`, `GET /owner/models`, `GET /owner/policy`, `GET /owner/cases`, `GET /owner/cases/{id}`, and session-protected evidence bytes at `GET /owner/cases/{id}/evidence/{evidence_id}`.

Mutations use `POST /owner/cases/{id}/{action}` with `expected_revision` and an 8–80 character `request_id`. Actions are `message`/`note` (`text`), `correct` (`model`, `description`), `inspection` (`diagnosis`, `notes`), `review` (`action`, `reason`), `assess`, and `retry_delivery` (`message_id`). The browser generates request IDs and never supplies a service token.

Jac adds service-token-protected `owner_message`, `owner_review`, and `owner_inspection` operations. Cases gain optional channel/sender metadata, embedded messages/decisions, `review_status`, `review_assessment_id` and `owner_inspection`; existing cases need no destructive migration. Communication state lives in `wa_chat_messages`, `wa_conversations`, `wa_inbox`, `wa_jobs`, `wa_outbox`, `wa_sessions` and `wa_login_attempts` in the same configured database.

Shopping/voice owner endpoints also require the same session: `GET /owner/catalogue`, `GET /owner/conversations`, and `POST /owner/conversations/{id}/messages` with `request_id`, `text` and optional `internal`. Public replies use the same persisted outbox and service-window rules.
