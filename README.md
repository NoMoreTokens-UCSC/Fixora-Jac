# Fixora AI

Warranty assessment and repair recommendations for a single electronics shop, built with Jac and MongoDB.

**The frontend now connects to the Jac 0.34.6 backend APIs.** Create MongoDB cases, upload invoice/product images to GridFS, run configured model extraction, and view saved warranty, repair and inventory findings through the browser. Sign in with the demo email and password; the server automatically creates a short-lived browser session. The private shop token, model keys and database credentials stay on the server. See [DEVELOPMENT.md](DEVELOPMENT.md) for setup and the first manual test, [MEMBER_B_HANDOFF.md](MEMBER_B_HANDOFF.md) for model configuration, and [MEMBER_A_HANDOFF.md](MEMBER_A_HANDOFF.md) for API contracts.

Verification: **43 backend and 16 frontend contract tests pass**, and the complete live scenario passed through the compiled frontend gateway, HTTP, MongoDB/GridFS and Gemini. Additional live checks encountered `MODEL_RATE_LIMIT`; the UI preserves evidence and shows an explicit retry state. Earlier API-only checks verified all three fixture scenarios and persistence across server restart. The fictional catalogue contains 1 policy, 3 products, 3 repairs and 9 stock records. Temporary verification records are cleaned up. Restart the development server after pulling these changes to register the new server-side demo login endpoint. See [tests/FRONTEND_API_QA.md](tests/FRONTEND_API_QA.md) for the connected-browser checks.

For every endpoint's parameters, response shapes, errors, and curl/Python/browser examples, see [API_README.md](API_README.md).

See [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md) for the live Gemini results, fixes and rerun instructions.

## Team starting points

| Member | Focus | Start here | First handoff |
| --- | --- | --- | --- |
| A | Platform, coordinator, MongoDB, deployment | `shared/`, `data/`, `server/`, `workflow/`, `main.jac`, `jac.toml` | Publish shared types and operation signatures; persist and reload a case and evidence file. |
| B | Invoice/photo extraction, warranty rules, repair recommendations | `specialists/`, `rules/`, `fixtures/` | Supply validated specialist results and the three agreed scenario fixtures. |
| C | Customer chat, shop dashboard, case details, findings and review | `ui/`, `assets/` | Render the shared fixtures in the two views, then connect Member A's server operations. |

Member A owns changes to shared contracts and configuration. Agree interfaces together before implementing consumers. Member B owns fixture content; Member A owns the seed entry point that eventually loads it. Keep the first integration checkpoint at hour two.

## MVP boundary

- One shop, laptops, three supported models, English.
- Invoice/product-image intake, evidence extraction, policy evaluation, conditional routing, repair and compatible-part recommendations, saved case results.
- Business records use MongoDB and evidence uses GridFS. The UI reads these through the same-origin HTTP APIs; it no longer seeds browser-local cases.
- Jac coordinates bounded stages: document, vision, coverage, repair/parts, resolution.
- Exactly two primary interfaces: customer chat and shop dashboard. Intake, evidence, findings, saved cases, and review controls live within those views.
- Customer updates revise the saved problem description and require reassessment. Corrections and evidence changes are persisted. The existing backend has no independent chat, owner inspection or approval endpoints; unsupported controls are unavailable.
- Automatic decisions require explicit versioned shop rules and sufficient evidence; unresolved cases go to owner review. Unknown diagnoses remain provisional.
- Production customer isolation and owner actions require additional server-enforced access. The server validates the public demo credentials and issues signed sessions; both roles still access the same shop queue.
- Turnaround estimates, PDF intake, trained ML models, supplier integrations, stock mutations, authentication dashboards, and extra product categories are deferred.

[UI_SPECIFICATION.md](UI_SPECIFICATION.md) describes the broader two-view UI and review target. [ARCHITECTURE_STRATEGY.md](ARCHITECTURE_STRATEGY.md) describes the architecture. The HTTP gateway is connected; backend conversations/review, production authentication and JacHammer deployment remain future work.

## Project map

```text
main.jac                       A  Application composition
jac.toml                       A  Runtime baseline and pinned platform dependencies
.env.example                      Environment variable names, without credentials
shared/                        A  Contracts, status names, configuration
server/                        A  Case operations and evidence upload/download
workflow/                      A  Coordinator, transient case graph, transitions
data/                          A  MongoDB connection, repositories, GridFS, seeding
specialists/                   B  Document, vision, coverage, repair/parts, resolution
rules/                         B  Policy/date, compatibility, money calculations
fixtures/                      B  Synthetic catalogue, five evidence images, three scenarios
ui/                            C  App shell, intake, saved cases, workspace and findings
assets/                        C  Guidance for small, shareable visual assets
tests/                       A/B/C Platform and specialist tests; UI checks to follow
```

File ownership and responsibilities are recorded in each source file. Member A's shared contracts and operation signatures are now available; agree changes before adding cross-module imports.

## Local setup

1. Use Jac **0.34.6 (Linux x86_64)** as pinned in `.jac-version` and `jac.toml`. Member C's original UI checks used 0.34.13; the integration branch retains the team's agreed baseline.
2. Run `bash scripts/jac.sh install --dev` in Linux/WSL. The merged manifest includes Python, byLLM, npm and UI test dependencies.
3. Create your local `.env` from `.env.example` if needed. Keep your existing MongoDB URI, model key and access token private. The backend already reads `.env` without exporting it. Prefer `FIXORA_MONGODB_URI` for hosted application persistence.
4. Run `bash scripts/jac.sh run data/seed.jac` only when you want to load/replace the fictional catalogue records.
5. Run `bash scripts/jac.sh start main.jac` to serve the UI at `/` and the ten APIs at `/function/<name>`. Use `--dev` for UI development, or `--no-client` for an API-only process. Windows users can use the `jac.ps1` wrapper described in [DEVELOPMENT.md](DEVELOPMENT.md).
6. Sign in using a documented demo email and password. No token entry is required. Create a case, upload evidence and choose **Assess complaint** to test MongoDB and the configured model through the frontend. Use `FIXORA_DEMO_MODE=false` for live model calls. See [DEVELOPMENT.md](DEVELOPMENT.md) for exact test images and expected findings.

MongoDB is the authoritative business store. Reconstruct temporary Jac graphs from repository records; do not create a second persistent copy of case data in the Jac root graph.

## Hosting handoff

Target JacHammer after the first complete local path. Member A must verify runtime compatibility, deployment entitlement, request/upload limits, server-side secrets, and outbound database/model access. Use a MongoDB endpoint reachable from the hosted app; a developer's local `localhost` connection will not work remotely. Keep uploaded evidence out of the deployment bundle.

Combined installation, compiler checks, client builds, and demo-adapter tests are described in [DEVELOPMENT.md](DEVELOPMENT.md). The backend seed, live inference and MongoDB checks are documented in [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md); production authentication and deployment remain unverified.
The active assessment lives atomically inside its case record; superseded snapshots are archived in `assessments`. Hosting is still pending. See the handoff for this refinement of the initial architecture and the remaining integration work.
