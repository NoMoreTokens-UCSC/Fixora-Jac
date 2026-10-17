# Verification plan — shared ownership

No test code is implemented in this scaffold. Add focused checks alongside the behavior each member creates.

| Owner | Checks to add during implementation |
| --- | --- |
| A | MongoDB restart persistence; GridFS round trip; revision/stage lease checks; repeated requests; stale-result rejection; database/provider failure handling |
| B | Missing invoice fields; future/expiry/month-end dates; identity conflicts; uncertain causes; exact compatibility; out-of-stock handling; integer-money totals |
| C | Intake validation and retained inputs; actual stage status; saved-case reload; evidence links; clarification and inspection recommendations |

Integrate and run the three scenarios in `fixtures/README.md` together before polishing the demo. Confirm the testing conventions supported by the shared Jac 0.34.6 runtime before choosing test filenames or commands. Human approval and review workflow tests are deferred with those features.
