# Fixora AI

Warranty assessment and repair recommendations for a single electronics shop, built with Jac and MongoDB.

**Status: Member A backend and Member B specialists implemented on Jac 0.34.6.** Invoice/photo extraction uses typed byLLM calls; warranty, compatibility, pricing and the final report use fixed rules. Live Gemini invoice/photo analysis and the complete five-stage API path are verified using synthetic evidence. Member C's interface and JacHammer deployment remain pending. See [MEMBER_B_HANDOFF.md](MEMBER_B_HANDOFF.md) for provider setup, finding schemas and demo inputs, and [MEMBER_A_HANDOFF.md](MEMBER_A_HANDOFF.md) for platform contracts.

Verification: 38 offline tests pass, and the three fixture scenarios pass over the full HTTP API with real MongoDB. Saved findings survive a server restart. The development database contains the fictional catalogue (1 policy, 3 products, 3 repairs, 9 stock records); temporary verification collections are removed after each live check. Restart the development server after pulling these changes; use the current demo token in your local `.env`. Run `jac run scripts/verify_live_agents.jac` for an opt-in check using the configured model and synthetic uploads; it makes real provider requests.

For every endpoint's parameters, response shapes, errors, and curl/Python/browser examples, see [API_README.md](API_README.md).

See [AGENT_VERIFICATION.md](AGENT_VERIFICATION.md) for the live Gemini results, fixes and rerun instructions.
**Status: runnable UI prototype.** Customer chat and the shop dashboard work with labelled demo scenarios, generated photography, dark mode, browser-local persistence, and owner review. Real AI inference, MongoDB/GridFS, production authentication, and deployment remain unimplemented. See [DEVELOPMENT.md](DEVELOPMENT.md) for run commands and verification.

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
- The production persistence target is MongoDB records and GridFS files. The current UI prototype uses browser IndexedDB.
- Jac coordinates bounded stages: document, vision, coverage, repair/parts, resolution.
- Exactly two primary interfaces: customer chat and shop dashboard. Intake, evidence, findings, saved cases, and review controls live within those views.
- Customer conversations, follow-up clarification, owner inspection/corrections, approval/rejection, and persisted decision history are implemented in the browser-local demo.
- Automatic decisions require explicit versioned shop rules and sufficient evidence; unresolved cases go to owner review. Unknown diagnoses remain provisional.
- Customers access only their own cases; owner-only details and actions require server-enforced access. Full account-management dashboards are not required.
- Turnaround estimates, PDF intake, trained ML models, supplier integrations, stock mutations, authentication dashboards, and extra product categories are deferred.

The latest user direction restores owner review and adds customer chat. [UI_SPECIFICATION.md](UI_SPECIFICATION.md) records the current two-view scope and supersedes earlier UI/review exclusions. See [ARCHITECTURE_STRATEGY.md](ARCHITECTURE_STRATEGY.md) for the broader architecture and original schedule. The UI is implemented with a typed demo gateway. Backend source placeholders remain for the later live integration.

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
fixtures/                      B  Empty catalogue placeholders and scenario guidance
ui/                            C  Customer chat, shop dashboard, embedded case details and review
assets/                        C  Guidance for small, shareable visual assets
tests/                       A/B/C Platform and specialist tests; UI checks to follow
```

File ownership and responsibilities are recorded in each source file. Member A's shared contracts and operation signatures are now available; agree changes before adding cross-module imports.

## Local backend setup

1. All members confirm the reported Linux runtime: `jac --version` should report `jac 0.34.6 (Linux x86_64)`. This is the shared development baseline; do not upgrade independently.
2. Run `jac install --dev` to install the pinned platform dependencies and test driver into the project's Jac environment.
3. Copy `.env.example` to your own `.env` and configure MongoDB plus a `FIXORA_ACCESS_TOKEN` of at least 16 characters. The server reads `.env` without exporting its contents; process environment takes precedence. A local access token has already been generated in the current developer's ignored `.env`. For hosted secrets, prefer `FIXORA_MONGODB_URI` to keep Jac's separate graph backend independent.
4. Run `jac run data/seed.jac` to load the fictional shop policy, three models, repairs and inventory. Seeding is explicit and repeatable; it replaces records with the same fixture IDs.
5. Configure a vision model and its key, or set `FIXORA_DEMO_MODE=true` to accept only the bundled synthetic evidence with clearly labelled recorded extractions. There is no automatic fallback from live mode.
6. Run `jac start main.jac --no-client` to start the API backend. Stop stage advancement on clarification, inspection, completion, or technical failure.

MongoDB is the authoritative business store. Reconstruct temporary Jac graphs from repository records; do not create a second persistent copy of case data in the Jac root graph.

## Hosting handoff

Target JacHammer after the first complete local path. Member A must verify runtime compatibility, deployment entitlement, request/upload limits, server-side secrets, and outbound database/model access. Use a MongoDB endpoint reachable from the hosted app; a developer's local `localhost` connection will not work remotely. Keep uploaded evidence out of the deployment bundle.

The active assessment lives atomically inside its case record; superseded snapshots are archived in `assessments`. Hosting is still pending. See the handoff for this refinement of the initial architecture and the remaining integration work.
