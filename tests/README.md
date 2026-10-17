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
| C | Intake validation and retained inputs; actual stage status; saved-case reload; evidence links; clarification and inspection recommendations |

Integrate and run the three scenarios in `fixtures/README.md` together before polishing the demo. Follow the Jac 0.34.6 conventions demonstrated by the existing test file; avoid the `test_*.jac` naming pattern. Human approval and review workflow tests are deferred with those features.
