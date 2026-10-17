# Verification plan — shared ownership

The interactive UI gateway has fifteen regression tests in `gateway.test.mjs`, using isolated in-memory IndexedDB. Run `bash scripts/test-ui.sh` from WSL with the preview server stopped; the runner builds emitted client code before testing. These checks cover local persistence, scoped search, uploads, customer messages and shop replies, clarification/inspection, corrections, decisions, retry, stock, and stale writes. Parts tests cover automatic offers, exact fictional model mapping, unavailable stock, uncertain compatibility, inventory retry, duplicate prevention, revision-tagged history, and older stored records. They do not exercise real AI, a live inventory service, or MongoDB.

| Owner | Checks to add during implementation |
| --- | --- |
| A | MongoDB restart persistence; GridFS round trip; revision/stage lease checks; repeated requests; stale-result rejection; database/provider failure handling |
| B | Missing invoice fields; future/expiry/month-end dates; identity conflicts; uncertain causes; exact compatibility; out-of-stock handling; integer-money totals |
| C | Customer chat/attachment validation and retained inputs; actual stage status; conversation/case reload; evidence links; clarification; owner dashboard inspection/review controls; published versus internal messages |

The current compiler baseline is Jac 0.34.13. The checks above validate the UI demo boundary. MongoDB restart durability, server-enforced customer isolation, authenticated owner actions, real extraction, and live deployment still require implementation and dedicated integration tests. See `DEVELOPMENT.md` for current run commands and limitations.
