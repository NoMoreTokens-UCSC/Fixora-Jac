# Fixora AI

WhatsApp customer intake and a private shop-owner dashboard for warranty assessment and repair recommendations. Jac runs the five bounded assessment stages; MongoDB and GridFS persist cases and evidence. A small FastAPI adapter receives WhatsApp webhooks, and a durable worker advances assessments and sends replies.

**Start with [WHATSAPP.md](WHATSAPP.md)** for configuration, Meta's test-number setup, startup commands, customer commands, delivery behavior and verification.

## Development

Use the shared **Jac 0.34.13** Linux/WSL runtime and Python 3.12+.

```bash
bash scripts/jac.sh install --dev
bash scripts/whatsapp.sh setup
# Configure your ignored .env using .env.example.
bash scripts/jac.sh run data/seed.jac
```

Run each process in its own terminal:

```bash
bash scripts/jac.sh start main.jac --no-dev -p 8000
bash scripts/whatsapp.sh public   # 127.0.0.1:8010: webhook only
bash scripts/whatsapp.sh owner    # 127.0.0.1:8011: private owner API
bash scripts/whatsapp.sh worker
```

Open **http://localhost:8000** and use your configured owner password. Customers use WhatsApp; there is no customer web login. Expose **only port 8010** through the HTTPS tunnel. This is a local demonstration, without production hosting or business-number onboarding.

```bash
bash scripts/whatsapp.sh test     # Offline backend/worker checks and owner client build/tests
bash scripts/whatsapp.sh verify   # Real MongoDB/Jac HTTP; explicit synthetic transport/model fixtures
```

Live WhatsApp/model verification requires Meta credentials, a permitted test recipient, a callback URL and model configuration. The integration verifier never contacts Meta or a model; see `.jac/whatsapp-verification.json` after a successful run.

## Behavior and boundaries

- One shop, English, and the seeded FD-100/FD-200/FD-300 laptop catalogue.
- Typed questions and English voice notes can ask about products, spare parts and accessories. Answers use saved catalogue stock/prices; unclear variants require clarification. The shop can read transcripts and reply from Customer conversations.
- Customers explain the fault naturally, submit one invoice image and up to three device photos, then confirm `READY`. JPEG/PNG only, 5 MB per image.
- Document/vision extraction uses the configured model; coverage, compatibility, prices and the report use fixed rules. Technical failures do not silently fall back to fixtures.
- Clarification and uncertain faults stop processing for more evidence or physical inspection. Final repair proposals require an owner decision.
- The owner dashboard reads shared cases, evidence, findings, messages and history. Replies enter the WhatsApp outbox; internal notes stay private.
- Input changes invalidate assessment and approval. Old decisions and assessment snapshots remain historical.
- No payments, stock reservations, PDFs/videos, voice replies, supplier integration or automatic warranty approval.
- Earlier browser-local demo cases are not migrated. Older handoffs describe earlier project stages; the current workflow is documented in `WHATSAPP.md`.

## Project map

| Area | Responsibility |
| --- | --- |
| `whatsapp/` | Signed webhook, owner sessions/API, intake model, queues and worker |
| `server/`, `data/` | Jac case/evidence/owner operations, MongoDB and GridFS |
| `workflow/` | Stage coordination, leases and revision checks |
| `specialists/`, `rules/` | Structured extraction, policy, compatibility, pricing and resolution |
| `ui/` | Private owner dashboard and cookie-authenticated gateway |
| `fixtures/` | Fictional catalogue and labelled synthetic evidence |
| `tests/` | Domain, transport/worker and client gateway tests |

See [API_README.md](API_README.md) for the existing case/evidence API and [DEVELOPMENT.md](DEVELOPMENT.md) for checks.
