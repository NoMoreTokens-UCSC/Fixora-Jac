# Connected frontend verification — 17 October 2026

## Login update: no manual token entry

The current login accepts only the demo email and password. `POST /function/demo_login` validates the selected demo account on the server and issues a signed eight-hour browser session. The private shop secret stays in server configuration; it is never returned or compiled into the frontend. Legacy browser-stored shop tokens are removed automatically.

Current automated checks: **28 platform tests, 15 specialist tests and 16 frontend tests pass** (59 total; 107 frontend assertions). Session tests cover wrong credentials/role, expiry, forged payloads, wrong shop, malformed tokens, signing-secret rotation and missing configuration. Frontend tests cover automatic session exchange and failed-login cleanup. No additional Gemini calls are needed for these login checks.

Browser verification of the new flow used a fresh temporary database: the token field was absent; a wrong password returned `INVALID_CREDENTIALS` from the server; the valid email/password opened the workspace; creating a case returned **Saved to MongoDB**. The server's test log contained neither issued session tokens nor the submitted test password/private shop secret. The rebuilt client secret scan found no configured secret values in 72 generated files.

Reload retained the browser session and reloaded that case from MongoDB. Sign-out returned to the email/password screen with empty fields. The isolated server and its temporary records were cleaned up after the check; no extra model calls were made.

The sections below record the earlier API-integration checks, before the token field was removed; they are historical where they refer to entering a shop token.

Runtime: Jac 0.34.6 in Linux/WSL. Browser checks used a separately started local server, a fresh temporary MongoDB database and an ephemeral test-only shop token. Development records, `.env` and the user's existing server were not modified.

## Automated checks

| Check | Result |
| --- | --- |
| Frontend production build | Passed |
| Frontend HTTP-contract tests | 15 passed, 95 assertions |
| Platform regressions | 23 passed |
| Specialist regressions | 15 passed |
| Generated client secret scan | No configured secret values found in 72 generated files |
| Live complete scenario through compiled frontend gateway | Passed: upload/retrieve PNGs, document and vision extraction, all five stages, list/reload and fresh client preview retrieval |
| Live report | `live_model`, `completed`, `outside_period`, LKR 2,650,000 minor units (26,500.00), customer payable unresolved |
| Additional live scenarios | Gemini returned `MODEL_RATE_LIMIT` during the next scenario's document stage; remaining live scenarios were not completed |

The live verifier cleaned its temporary collections. Its current multi-scenario summary correctly reports an incomplete check; the successful complete scenario is retained in `.jac/live-agent-check.json`. This run did not reach the verifier's server-restart step. Earlier API-only restart checks are documented separately in [AGENT_VERIFICATION.md](../AGENT_VERIFICATION.md).

## Earlier browser checks (token-entry version)

- Invalid shop token showed `UNAUTHORIZED` without entering the workspace.
- Customer sign-in with the isolated server's valid shop token loaded an empty shop queue, without seeded browser cases.
- Creating a case saved the entered description and selected FD-100 model in MongoDB.
- Actual file-picker uploads accepted `invoice-expired.png` and `product-cracked.png`; previews and server-save confirmation appeared.
- **Assess complaint** invoked the real assessment API. Gemini returned `MODEL_RATE_LIMIT`; the case stopped, displayed the saved error and offered **Retry assessment**. No repair prices, extracted invoice fields or successful model findings were fabricated.
- Browser reload retrieved the case, both evidence images and failed stage from MongoDB/GridFS with a fresh client memory cache.
- Sign-out returned to the login screen and cleared the entered token; signing in again requires the shop token.
- A fresh owner sign-in on a second server loaded the same saved case immediately, without a browser reload. An initial React state sequencing issue was found during this check and fixed by using the locally returned case list before setting the active case.
- The owner queue and case detail showed the saved error/revision; approval was explicitly unavailable rather than a local-only action.
- **Correct details** saved the complete edited description as revision 6, returned the case to draft and cleared the failed current assessment. The owner Evidence tab still showed both stored images afterward.

The complete live path was verified through the emitted HTTP adapter. Browser interaction verified uploads, persistence and the provider-failure path; it did not demonstrate a successful fresh Gemini run because of the provider limit.

## Remaining product limits

Both public demo roles share the shop queue. They are not customer isolation. Follow-ups revise the saved description rather than create independent chat messages. Shop replies, owner inspection records and approval/decision-history APIs remain unavailable. No payment, stock reservation, trained turnaround model or hosting deployment was added.

Follow [DEVELOPMENT.md](../DEVELOPMENT.md) for manual browser testing and opt-in live check commands. Historical fixture-only browser checks in [UI_QA.md](UI_QA.md) describe the previous gateway.
