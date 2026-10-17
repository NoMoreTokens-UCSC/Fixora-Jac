# Fixora interactive UI

The application is a local UI prototype built with Jac 0.34.13, React output, Jac's generated shadcn primitives, and Tailwind. It has exactly two primary views: customer chat and shop dashboard. It uses no application inference credentials or live business database.

## Run on this Windows machine

From the project folder:

```powershell
.\jac.ps1 --version
.\jac.ps1 install
.\jac.ps1 start --dev
```

Open **http://localhost:8000/**. Keep using the same hostname: browser storage for `localhost` and `127.0.0.1` is separate. The launcher uses Ubuntu-24.04 in WSL and the verified compiler from the adjacent Jac technology knowledge project. For another installation, set `FIXORA_JAC_BINARY` inside WSL to the installed compiler's Linux path, or put `jac` on WSL's PATH.

The local ignored npm dependency directory can be linked to WSL's Linux filesystem to avoid Windows filesystem overhead. The current machine uses `/root/.cache/fixora-ui-node/node_modules`; tracked source remains in the Fixora folder. Tailwind scanning is explicitly limited to UI/component directories.

## Use the demo

- The opening login UI provides two dummy accounts. Select Customer with `customer@fixora.demo`, or Shop owner with `owner@fixora.demo`. Both use password `Fixora123!`; Use demo credentials fills the form. These are public UI fixtures, not real authentication.
- The customer account opens Alex's conversations only. The owner account opens the shop dashboard with the full local queue and a Customer chats shortcut. There is no in-workspace role/persona switcher; use Sign out to change accounts. The demo role survives reload in that browser tab through sessionStorage; passwords are not saved.
- The owner's Conversation tab includes a customer-facing reply composer. Replies appear in the customer's chat after switching accounts and are saved locally without changing assessment/approval state. Sign out confirms before discarding unsent text.
- Start a new conversation and select one of eleven sample scenarios. Describe the issue, then attach one JPEG/PNG invoice and one to three product images (5 MB maximum each). The scenario supplies fixture findings; uploaded images are not analysed by AI. Additional scenarios cover a missing charger, replacement component, uncertain part compatibility, and an inventory timeout.
- Assessment advances five bounded, locally saved stages. Conflicts request clarification, uncertain faults request inspection, and a sample timeout offers retry.
- In the shop dashboard, open a case to inspect its conversation/evidence/assessment/history, record an inspection, or approve/decline/request details. The published response appears in customer chat. Internal inspection notes are hidden from that chat's rendering.
- Corrections and evidence changes create a new revision and invalidate the current approval. Earlier decisions remain in history. Atomic IndexedDB updates reject stale tabs and preserve the submitted text for retry after loading the latest case.
- A paid repair is distinct from warranty coverage. Prices and stock are explicitly seeded snapshots; no payment or stock reservation occurs.
- The Repair & parts stage now checks a six-item fictional catalogue. A compatible in-stock part automatically creates one revision-tagged availability message in customer chat; the part action fills a customer enquiry for the user to send. Uncertain compatibility makes no offer, unavailable stock has no arrival promise, and an inventory timeout offers a separate retry without changing warranty/decision state.
- Legacy saved cases receive empty availability/message-tag defaults in memory, without clearing or reseeding their evidence and history. Existing completed cases can use Check sample stock. Corrections retain earlier offers as history and require a fresh assessment for the current revision.

Cases, messages, image previews, revisions, and decisions are stored in IndexedDB. Theme and storage-notice preferences use localStorage; the dummy account selection uses sessionStorage. Clearing site storage clears the local demo. Real MongoDB/GridFS, live AI, authenticated ownership checks, and deployment remain integration work; the original backend directories still contain placeholders.

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

Framer Motion 14.3.0 powers short, reduced-motion-aware title entrances. Decorative waves and their pause controls have been removed. The sign-in feature panel contrasts with the selected theme: light in dark mode, black in light mode. Its centered laptop showcase uses a scoped translucent glass treatment with a solid fallback; other application surfaces retain their existing styling. Overrides live in ui/login-feature.css.

Shared typography tokens live in `ui/readability.css`: 18 px body, 16 px controls/labels, 14 px metadata, and 12 px secondary legal/illustration captions. Page titles scale from 44 px desktop through 38 px tablet to 32 px mobile. The dashboard summary uses one divided strip; assessment details use sections inside a shared surface. The catalogue and typed availability result are in `ui/inventory.jac` and `ui/models.jac`; `check_parts` in the asynchronous gateway is the later live-inventory integration boundary.

Verified dependency baseline: Jac 0.34.13, React 18.3.1, Vite 6.4.4, Tailwind 4.3.3, Radix UI 1.8.1, idb-keyval 6.3.0, fontsource Inter/Outfit 5.3.0, and fake-indexeddb 6.2.6 for tests. The asynchronous typed functions in `ui/gateway.jac` are the replacement boundary for later authenticated server integration; UI components do not query a database directly.
