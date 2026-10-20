# Fixora verification

From the project root in WSL, use the shared Jac 0.34.13 runtime:

```bash
bash scripts/whatsapp.sh setup
bash scripts/whatsapp.sh test
```

This runs:

- Python adapter/worker tests: signed and durable webhooks, deduplication, owner sessions/origin checks, natural intake schemas, evidence classification, customer isolation, background assessment, restarts, revision changes, opt-out, service windows and uncertain delivery.
- Voice/enquiry tests: bounded Meta audio download, multipart transcription, cached transcripts on retry/restart, product/part/accessory facts, missing/ambiguous matches, no repair case for shopping, and private owner notes. These use simulated provider boundaries, not live audio inference.
- Jac platform/specialist tests: access control, GridFS validation, stage leases, stale results, fixed rules, typed byLLM output/schema construction, recorded fixtures, identity conflicts and inspection boundaries.
- Jac owner tests: protected operations, current-assessment review, approval invalidation, private notes, inspection revisions and history.
- Client build and emitted gateway/render tests: cookie requests, saved evidence/findings/currency, revision conflicts, session expiry, private/public operations, owner-only sign-in and empty inbox rendering.

Offline tests use synthetic inputs and isolated in-memory storage. They do not send WhatsApp messages, call a model, or alter saved customer records. One Jac test worker avoids redundant compiler processes.

## Real storage and HTTP

```bash
bash scripts/whatsapp.sh verify
```

This starts Jac against an isolated, randomly named temporary database and exercises the signed receiver, worker, real case/evidence HTTP API, owner API, private notes, review and persistence across server restart. Its Meta transport/intake parsing are explicit test doubles; evidence analysis uses the labelled recorded fixtures. Temporary collections/records are removed. See `.jac/whatsapp-verification.json` and `.jac/whatsapp-integration.log`.

## Live verification

Follow [WHATSAPP.md](../WHATSAPP.md) to configure the Meta test number, permitted recipient, callback and live model. Confirm the reply on the real phone and check that extraction findings say `live_model`.

The earlier optional `scripts/verify_live_agents.jac` checks direct live model/backend calls, consumes provider quota, and does not exercise WhatsApp. The new integration verifier and all offline checks make no paid model requests.
