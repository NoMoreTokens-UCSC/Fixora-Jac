# Verification plan — shared ownership

`platform_tests.jac` contains 23 tests. `specialist_tests.jac` contains 15 tests covering dates, identity, compatibility, price arithmetic, structured byLLM calls with MockLLM, explicit fixture mode and all three coordinator scenarios. Regression checks construct real provider schemas, count actual image attachments, and verify typed HTTP defaults. Run from the repository root inside Linux/WSL:

```bash
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/specialist_tests.jac -v
```

The tests use synthetic images and an isolated in-memory MongoDB substitute. They do not write to the real database or invoke an LLM. One worker avoids starting a compiler/runtime for every CPU core on shared hackathon laptops.

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

## UI demo checks

The integration compiler baseline is Jac **0.34.6**, matching `.jac-version` and `jac.toml`. Member C originally checked the UI with 0.34.13. Build the combined client and run its isolated IndexedDB gateway suite with:

```bash
bash scripts/test-ui.sh
```

The UI gateway suite covers its browser-local sample cases, messages, evidence, review/correction flows and stale-tab handling. These tests do not connect the UI to MongoDB or Gemini. Historical manual browser checks are in [UI_QA.md](UI_QA.md); backend live extraction and restart checks are in [AGENT_VERIFICATION.md](../AGENT_VERIFICATION.md).

The backend's MongoDB/GridFS persistence and real extraction are implemented. Connecting the UI gateway to those APIs, server-enforced customer/owner identity, conversation/review persistence, and deployment remain integration work. See [DEVELOPMENT.md](../DEVELOPMENT.md) for current commands and limitations.
