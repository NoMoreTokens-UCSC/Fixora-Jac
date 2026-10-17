# Verification plan — shared ownership

`platform_tests.jac` contains 28 tests. `specialist_tests.jac` contains 15 tests covering dates, identity, compatibility, price arithmetic, structured byLLM calls with MockLLM, explicit fixture mode and all three coordinator scenarios. Regression checks construct real provider schemas, count actual image attachments, and verify typed HTTP defaults. Run from the repository root inside Linux/WSL:

```bash
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/specialist_tests.jac -v
```

Platform checks include login validation, expiry, tampering, wrong-shop sessions and secret rotation. The tests use synthetic images and an isolated in-memory MongoDB substitute. They do not write to the real database or invoke an LLM. One worker avoids starting a compiler/runtime for every CPU core on shared hackathon laptops.

For an opt-in check of real Gemini/model calls through HTTP and real MongoDB:

```bash
jac run scripts/verify_live_agents.jac
FIXORA_CHECK_ALL=true jac run scripts/verify_live_agents.jac
```

This verifier consumes provider quota, uses a fresh temporary database, and cleans up its test collections. It leaves `.env` and the normal development database unchanged. Results are written to `.jac/live-agent-check.json`. The first command checks the complete path; the second includes clarification and inspection routes.

| Owner | Verification ownership |
| --- | --- |
| A | Implemented: access/validation checks, GridFS round trips, repeated requests, pagination, conditional routing, stage leases, stale-result rejection, archival, seed validation/upserts. Also verified real HTTP/MongoDB persistence across server restart using a temporary database. |
| B | Missing invoice fields; future/expiry/month-end dates; identity conflicts; uncertain causes; exact compatibility; out-of-stock handling; integer-money totals |
| C | Customer chat/attachment validation and retained inputs; actual stage status; conversation/case reload; evidence links; clarification; owner dashboard inspection/review controls; published versus internal messages |

## Frontend API checks

The integration compiler baseline is Jac **0.34.6**, matching `.jac-version` and `jac.toml`. Build the combined client and run its isolated HTTP-contract gateway suite with:

```bash
bash scripts/test-ui.sh
```

The 16 gateway tests cover server-validated sign-in, automatic browser sessions, legacy-token cleanup, nested HTTP/application errors, network ambiguity, pagination, real contract mapping, selected-case evidence retrieval, model IDs, base64 uploads, returned revisions/assessment IDs, stale changes, partial/failed results, catalogue currencies, corrections and description updates. HTTP is stubbed; no real MongoDB or model calls are made.

For the emitted frontend gateway against actual HTTP, MongoDB/GridFS and model extraction, build first, then run:

```bash
FIXORA_CHECK_FRONTEND=true jac run scripts/verify_live_agents.jac
FIXORA_CHECK_FRONTEND=true FIXORA_CHECK_ALL=true jac run scripts/verify_live_agents.jac
```

`tests/frontend-live.mjs` runs only through this opt-in verifier. It uploads synthetic images using the compiled gateway, advances the live agents, checks real saved findings, and reloads evidence with fresh client module memory. The verifier uses a temporary database, checks persistence after server restart and cleans up its temporary collections. Live calls consume provider quota. Summary: `.jac/live-agent-check.json`.

Historical fixture-only browser checks are in [UI_QA.md](UI_QA.md). The frontend is connected; server-enforced customer ownership, independent conversations, owner review/inspection APIs and deployment remain out of scope. See [DEVELOPMENT.md](../DEVELOPMENT.md) for current browser instructions and limitations.
