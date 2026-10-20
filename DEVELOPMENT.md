# Fixora development

Customers interact through WhatsApp; the shop owner uses the web dashboard. MongoDB persists cases and GridFS stores evidence. IndexedDB and dummy customer/owner credentials are no longer used. Earlier browser demo data is not migrated.

Follow [WHATSAPP.md](WHATSAPP.md) for configuration, startup, Meta setup and the demonstration sequence. Backend and client use Jac 0.34.13 in WSL; the Python channel service has its own environment.

## Verification

```bash
bash scripts/whatsapp.sh setup
bash scripts/whatsapp.sh test
```

This runs Python transport/worker tests, Jac platform/specialist/owner tests, and the client production build with emitted gateway tests. These checks make no model or Meta requests and do not touch customer records.

```bash
bash scripts/whatsapp.sh verify
```

The integration check needs configured MongoDB. It seeds its own temporary database, starts Jac HTTP, passes signed synthetic messages through the receiver and worker, checks owner operations, verifies persistence after restart and removes its temporary collections/records. Meta delivery and intake parsing are explicit test doubles; document/vision use labelled recorded fixtures. It does not validate live model inference or an actual recipient's WhatsApp connection.

Targeted checks:

```bash
bash scripts/jac.sh check main.jac shared server data workflow specialists ui -n
bash scripts/test-ui.sh
```

## Runtime boundaries

- Public FastAPI app: `/webhooks/whatsapp` on loopback port 8010. Tunnel this port only.
- Owner FastAPI app: port 8011, with a password session and browser-origin checks. The session cookie is HttpOnly.
- Jac UI/API: port 8000. Only the gateway/worker sends the service token.
- MongoDB leases coordinate work. Browser polling only refreshes views; it does not advance agents.
- Evidence/corrections reset review state while preserving decision history and archived assessments.
- `.env`, environments, uploads and `.jac/` logs/build output remain ignored.

The local runtime adaptations cover Jac 0.34.6 and 0.34.13: endpoint defaults retain their types, runtime logs omit function arguments, and guest-root recovery is guarded. Server contract classes and client gateway functions explicitly pin their codespaces to avoid incorrect native/RPC placement.
