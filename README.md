# Fixora AI

Warranty assessment and repair recommendations for a single electronics shop, built with Jac and MongoDB.

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
jac.toml                       A  Project metadata; dependency configuration pending
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
tests/                       A/B/C Planned verification; no tests implemented
```

File ownership and intended responsibilities are recorded inside every source placeholder. Filenames describe intended boundaries; shared contracts must be settled before adding cross-module imports.

## Before implementation

1. All members confirm the reported Linux runtime: `jac --version` should report `jac 0.34.13 (Linux x86_64)`. This is the shared development baseline; do not upgrade independently.
2. Member A validates full-stack configuration, server/client calls, and upload handling with that installed version. `jac.toml` is metadata only; dependencies and model configuration still need to be added. Record exact working dependency versions after validation and share the same configuration across all three members; rolling documentation may describe newer APIs.
3. Copy `.env.example` to a local `.env` and populate the appropriate values. Environment-file loading is not implemented; the application must explicitly load these values or receive them from its process environment.
4. Member A verifies MongoDB connectivity; Member B selects the actual model provider and its API-key variable. `FIXORA_*` names are application settings the team must implement.
5. Agree shared contracts and scenario outputs. Then work in the ownership areas above and integrate at hour two.

MongoDB is the authoritative business store. Reconstruct temporary Jac graphs from repository records; do not create a second persistent copy of case data in the Jac root graph.

## Hosting handoff

Target JacHammer after the first complete local path. Member A must verify runtime compatibility, deployment entitlement, request/upload limits, server-side secrets, and outbound database/model access. Use a MongoDB endpoint reachable from the hosted app; a developer's local `localhost` connection will not work remotely. Keep uploaded evidence out of the deployment bundle.

Local UI installation, compiler checks, client builds, and demo-adapter tests are described in DEVELOPMENT.md. Live seed, inference, MongoDB, access-control, and deployment commands remain unvalidated.
