# Verification plan — shared ownership

`platform_tests.jac` contains 21 passing Member A tests. Run from the repository root inside Linux/WSL:

```bash
PYTEST_XDIST_AUTO_NUM_WORKERS=1 jac test tests/platform_tests.jac -v
```

The tests use synthetic images and an isolated in-memory MongoDB substitute. They do not write to the real database or invoke an LLM. One worker avoids starting a compiler/runtime for every CPU core on shared hackathon laptops.

| Owner | Verification ownership |
| --- | --- |
| A | Implemented: access/validation checks, GridFS round trips, repeated requests, pagination, conditional routing, stage leases, stale-result rejection, archival, seed validation/upserts. Also verified real HTTP/MongoDB persistence across server restart using a temporary database. |
| B | Missing invoice fields; future/expiry/month-end dates; identity conflicts; uncertain causes; exact compatibility; out-of-stock handling; integer-money totals |
| C | Intake validation and retained inputs; actual stage status; saved-case reload; evidence links; clarification and inspection recommendations |

Integrate and run the three scenarios in `fixtures/README.md` together before polishing the demo. Follow the Jac 0.34.6 conventions demonstrated by the existing test file; avoid the `test_*.jac` naming pattern. Human approval and review workflow tests are deferred with those features.
