# Fixora integrated development setup

This branch combines the Jac backend, live byLLM agents and MongoDB/GridFS persistence with Member C's React/shadcn/Tailwind UI. The shared compiler baseline is **Jac 0.34.6**, pinned in `.jac-version` and `jac.toml`. Member C's historical UI checks used 0.34.13. The combined entrypoint registers all ten backend APIs and serves the UI at `/`.

The UI's current gateway still uses browser-local demo cases and dummy accounts. Its buttons do not yet call the live agents. The backend independently reads private `.env` settings and exposes the APIs described in [API_README.md](API_README.md). See [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md) for real Gemini/MongoDB checks.

## Run on this Windows machine

From the project folder:

```powershell
.\jac.ps1 --version
.\jac.ps1 install --dev
.\jac.ps1 start --dev
```

Open **http://localhost:8000/**, using the actual port shown at startup. Keep using the same hostname: browser storage for `localhost` and `127.0.0.1` is separate. The launcher uses your default WSL distribution and the `jac` on its PATH. Set `$env:JAC_WSL_DISTRO = 'Ubuntu-22.04'` (or your installed distribution) to select another one. Inside WSL, `FIXORA_JAC_BINARY` can select a compiler path; the launcher checks that its version matches `.jac-version`. No adjacent project checkout or machine-specific compiler path is required.

In Linux/WSL, use `bash scripts/jac.sh install --dev` followed by `bash scripts/jac.sh start main.jac --dev`. Optional local dependency-directory links are machine-specific and are not required by the project. Tailwind scanning is explicitly limited to UI/component directories. Existing `.env` files are not replaced during installation.

The full server rebuilds its client during normal startup on this Jac release. On a Windows-mounted checkout, initial compilation can take a few minutes. Dependency installation can also be much faster with the ignored `node_modules` directory linked to a Linux cache. Use the startup output's actual port after the build finishes.

## Use the demo

- The opening login UI provides two dummy accounts. Select Customer with `customer@fixora.demo`, or Shop owner with `owner@fixora.demo`. Both use password `Fixora123!`; Use demo credentials fills the form. These are public UI fixtures, not real authentication.
- The customer account opens Alex's conversations only. The owner account opens the shop dashboard with the full local queue and a Customer chats shortcut. There is no in-workspace role/persona switcher; use Sign out to change accounts. The demo role survives reload in that browser tab through sessionStorage; passwords are not saved.
- The owner's Conversation tab includes a customer-facing reply composer. Replies appear in the customer's chat after switching accounts and are saved locally without changing assessment/approval state. Sign out confirms before discarding unsent text.
- Start a new conversation and select one of seven sample scenarios. Describe the issue, then attach one JPEG/PNG invoice and one to three product images (5 MB maximum each). The scenario supplies fixture findings; uploaded images are not analysed by AI.
- Assessment advances five bounded, locally saved stages. Conflicts request clarification, uncertain faults request inspection, and a sample timeout offers retry.
- In the shop dashboard, open a case to inspect its conversation/evidence/assessment/history, record an inspection, or approve/decline/request details. The published response appears in customer chat. Internal inspection notes are hidden from that chat's rendering.
- Corrections and evidence changes create a new revision and invalidate the current approval. Earlier decisions remain in history. Atomic IndexedDB updates reject stale tabs and preserve the submitted text for retry after loading the latest case.
- A paid repair is distinct from warranty coverage. Prices and stock are explicitly seeded snapshots; no payment or stock reservation occurs.

UI demo cases, messages, image previews, revisions, and decisions are stored in IndexedDB. Theme and storage-notice preferences use localStorage; the dummy account selection uses sessionStorage. Clearing site storage clears that demo. Backend cases and evidence separately use real MongoDB/GridFS and live AI. Connecting those stores to the UI, authenticated ownership checks, conversation/review APIs, and deployment remain integration work.

## Verify

```powershell
.\jac.ps1 check main.jac ui/app.jac ui/chat.jac ui/dashboard.jac ui/findings.jac ui/gateway.jac ui/models.jac ui/imagery.jac
.\jac.ps1 build --client web
```

Inside WSL, run:

```bash
bash scripts/test-ui.sh
```

The test runner builds the client, then runs the emitted gateway against isolated in-memory IndexedDB. It never touches the browser's saved cases. Browser interop and generated primitives can produce compiler warnings; errors must be resolved. The checks do not validate real inference, MongoDB, production authentication, or deployment.

## Assets and dependencies

Generated photographs and their exact prompts are in `assets/imagery/`. Customer evidence and synthetic evidence fixtures are separate. Outfit and Inter variable fonts are bundled locally via fontsource; there is no runtime font CDN. Generated shadcn primitives stay under `components/ui/` and are maintained by `jac install --shadcn`, with visual customization in shared CSS.

The user-supplied light/dark logos are in `assets/brand/`, shared by login, navigation and assistant avatars. The login follows the supplied two-column reference in black, white and neutral greys. Workspace light-theme tokens are retained; dark-theme surfaces and accents use neutral greys. Native-select wrappers have no separate border or padding, so each select draws only one field border and one focus treatment. Login styles are scoped in `ui/login.css`.

Framer Motion 14.3.0 powers a short title entrance through `ui/motion.jac`. It runs when a title mounts (or the role/case title changes), without loops. `useReducedMotion` skips the entrance when the visitor requests reduced motion. Only opacity and a seven-pixel vertical translation are animated.

Member C's historical dependency baseline was Jac 0.34.13, React 18.3.1, Vite 6.4.4, Tailwind 4.3.3, Radix UI 1.8.1, idb-keyval 6.3.0, fontsource Inter/Outfit 5.3.0, and fake-indexeddb 6.2.6. The integration compiler is pinned to 0.34.6; install the shared manifest to resolve its Python and client dependencies. The asynchronous typed functions in `ui/gateway.jac` remain the replacement boundary for authenticated server integration; UI components do not query MongoDB directly.

## Integration branch checks — 17 October 2026

- The combined manifest parses without duplicate tables, includes both Python and npm dependencies, and matches `.jac-version` at 0.34.6. Both the Linux launcher and Windows/WSL launcher report that version.
- The entrypoint and 29 UI/component modules pass compiler checks. The production client bundle builds successfully. Redundant backend contract-type imports were removed from the mixed entrypoint to avoid erroneous browser wasm bindings on 0.34.6; contract types remain in the backend modules that use them.
- All 38 backend regression tests and all 9 UI gateway tests pass (39 UI assertions).
- A temporary combined server served the UI at `/` and the original branding image. Its OpenAPI schema retained all ten backend endpoints and the backend `create_case` signature. Read-only HTTP checks verified MongoDB connectivity, five specialist imports, omitted case-list defaults and rejection of an invalid demo token.
- Generated client output was scanned for configured secret values; none were found. The HTTP smoke check made no model requests or business-record writes, and its server was stopped afterward.

The UI continues to use its original IndexedDB gateway. Mapping its model names, case records and statuses to backend contracts, adding authenticated customer/owner identity, and persisting chat/review actions on the server are the next integration tasks. The passing UI tests exercise the local demo; the backend's earlier live model checks remain documented separately in [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md).
