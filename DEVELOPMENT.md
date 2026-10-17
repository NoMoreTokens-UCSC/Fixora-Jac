# Fixora integrated development setup

The combined application uses **Jac 0.34.6** (`.jac-version`, `jac.toml`), Member C's React UI, the Member A HTTP APIs and MongoDB/GridFS persistence, and Member B's configured model and deterministic specialists. The UI gateway now calls the same-origin `/function/...` endpoints; it does not seed browser cases or generate assessment fixtures.

## Start

From the project folder in PowerShell:

```powershell
.\jac.ps1 --version
.\jac.ps1 install --dev
.\jac.ps1 start main.jac --dev
```

In Linux/WSL:

```bash
bash scripts/jac.sh install --dev
bash scripts/jac.sh start main.jac --dev
```

Open **http://localhost:8000/**, or the port shown at startup. Restart a server started before these changes, then reload the browser. Normal startup on this Jac release rebuilds the client and can take a few minutes on a Windows-mounted checkout. The Windows launcher uses the default WSL distribution; set `$env:JAC_WSL_DISTRO = 'Ubuntu-22.04'` to select one. `FIXORA_JAC_BINARY` can select a Linux compiler path; the wrapper enforces the pinned version.

The server reads private `.env` settings. Keep MongoDB credentials, `GOOGLE_API_KEY`, `FIXORA_MODEL` and `FIXORA_ACCESS_TOKEN` there or in hosting secrets. Never place these in client source or Vite environment variables. Prefer `FIXORA_MONGODB_URI` for hosted configuration, since bare `MONGODB_URI` also configures Jac's independent graph backend. For real model testing use `FIXORA_DEMO_MODE=false`. Seed the fictional product/policy/inventory catalogue once using `jac run data/seed.jac` if it is missing; repeat seeding replaces matching `demo-*` records.

## Connect through the browser

1. Choose Customer (`customer@fixora.demo`) or Shop owner (`owner@fixora.demo`). Both public demo accounts use `Fixora123!`; **Use demo credentials** fills these fields.
2. Sign in with the demo email and password. The server validates them and automatically issues an eight-hour browser session. There is no access-token field. The shop secret is read only on the server from `.env`; the browser uses its temporary session to call the APIs.
3. Start a conversation, select the printed catalogue model, and describe the problem. The case is saved immediately in MongoDB.
4. Attach one JPEG/PNG invoice and one to three product photos, each at most 5 MiB and 25 million pixels. The frontend validates the image and sends plain base64; the server independently validates and stores it in GridFS.
5. Choose **Assess complaint**. The browser starts an assessment, then advances document, vision, coverage, repair/parts and resolution one request at a time. Every request uses the latest returned revision. Progress appears as stages finish.
6. Read invoice extraction, observations, limitations, coverage, applied policy clauses, compatible parts and real catalogue prices. `completed` is shown as **Assessment ready** and means a provisional report, not approval or a completed repair.
7. Reload or sign in as the other demo role to see the same saved shop cases. Selecting a case fetches its current backend record and downloads its linked evidence. No browser-local demo cases are migrated automatically.

Cases, description revisions, evidence and specialist findings are authoritative on the server. The UI keeps a memory cache of case views and image previews only. Theme/notice preferences use localStorage; role and the temporary session use sessionStorage. Sign-out clears the browser session and memory cache. Closing the tab clears this browser storage. A copied session token remains valid until its eight-hour expiry or rotation of the server signing secret; this prototype has no server-side logout revocation. Neither the private shop token, MongoDB credentials nor model-provider secrets are sent to the browser.

Both roles access the same shop queue. The server checks the two public demo accounts and signs a shop-scoped browser session using the private `FIXORA_ACCESS_TOKEN`. This is demo authentication, **not customer ownership isolation or a production account system**. Real user accounts and server-enforced customer/owner permissions remain future work.

## Current scope and limits

- All ten protected case, image, assessment and status endpoints are connected, plus the public `demo_login` endpoint; see [API_README.md](API_README.md).
- Document and vision extraction use the configured model. Coverage, compatibility and price calculations use server catalogue rules. The result card labels `live_model` versus explicitly enabled `demo_fixture` replay; provider failures never silently fall back to invented findings.
- Customer follow-ups update the problem description and invalidate the previous assessment. They are not independent chat records. **Edit details** changes the complete description/model. Evidence changes also require reassessment; previous assessments are archived by the backend.
- The existing backend does not have shop-reply, inspection-record, approval or decision-history endpoints. Those controls are unavailable instead of saving local-only decisions. Shared shop access and normal case updates remain usable from both views.
- Unknown/contradictory invoice models request information. A power failure that cannot be diagnosed from photos requests inspection. The seeded supported products are fictional **Fixora Demo FD-100, FD-200 and FD-300**, not arbitrary real-world laptop models.
- Technical failures show the saved specialist error and offer explicit retry. Failed or uncertain stages stop advancement. A network failure may occur after a successful write: load the latest case before resubmitting. No provider retry loop, stock reservation, payment, final warranty approval or turnaround prediction is added.

## First manual test

Create a case with **Fixora Demo FD-100** and description:

> The display is visibly cracked. Please estimate a display replacement.

Upload `fixtures/evidence/invoice-expired.png` and `fixtures/evidence/product-cracked.png`. Assess it. With the seeded catalogue, expect an expired warranty period, a provisional display replacement estimate of **LKR 26,500 before tax**, and unresolved customer payable. The extraction mode must say live model when fixture mode is disabled. These files are synthetic labelled evidence; this checks integration, not real-photo accuracy.

Then try the other scenarios in [fixtures/scenarios.json](fixtures/scenarios.json): a mismatching product label should request information; a recent invoice and scratched product with a power-on complaint should request inspection.

Verify an edit or image removal returns the case to draft and clears current findings. Verify an incorrect password or wrong-role email fails at sign-in and a stale tab gets a reload instruction rather than overwriting a newer revision.

During verification the complete live scenario passed, then Gemini returned `MODEL_RATE_LIMIT` on additional requests. If you see this, the case and evidence remain saved. Retry after the provider allows requests again; this is not a MongoDB connection failure or a warranty rejection. No automatic retry or fixture fallback occurs. Current check details are in [tests/FRONTEND_API_QA.md](tests/FRONTEND_API_QA.md).

## Verify changes

```bash
# Build the emitted frontend and run isolated HTTP-contract tests; no real DB/model.
bash scripts/test-ui.sh

# Existing backend regressions; no real DB/model.
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/specialist_tests.jac -v

# Opt-in: compiled frontend adapter → HTTP → real MongoDB/GridFS → real model.
# Build first. Uses synthetic evidence and a fresh temporary database, then cleans it.
FIXORA_CHECK_FRONTEND=true jac run scripts/verify_live_agents.jac

# Also include clarification and inspection scenarios.
FIXORA_CHECK_FRONTEND=true FIXORA_CHECK_ALL=true jac run scripts/verify_live_agents.jac
```

Live checks consume provider quota and verify persistence across server restart. They leave `.env` and normal development records unchanged. Summary: `.jac/live-agent-check.json`. A gateway failure writes local diagnostics to `.jac/frontend-live-test.log`; no credential values are printed by the verifier. API-only checks remain available without `FIXORA_CHECK_FRONTEND`.

## Assets and dependencies

UI assets, local fonts, brand logos and generated illustrative product/shop photographs remain under `assets/`. Customer evidence is separate. UI components do not import database settings or call MongoDB directly. `ui/gateway.jac` is the HTTP/contract adapter; `ui/models.jac` contains client view records; `ui/findings.jac` renders saved specialist outputs. React/shadcn/Tailwind and Framer Motion are configured through the combined manifest. Historical fixture-only browser checks in [tests/UI_QA.md](tests/UI_QA.md) describe the earlier UI and are not evidence for the connected backend.
