# Fixora UI specification: customer chat and shop dashboard

Status: interactive browser-local UI prototype implemented. See DEVELOPMENT.md for execution, tests, and the remaining live backend integration. The requirements below also describe the eventual production access and persistence boundaries.

## Updated scope

Keep the existing intake, evidence extraction, warranty rules, conditional routing, repairs, parts, saved cases, and durable evidence features. Present them through exactly two primary views:

1. Customer chat: submit and follow a complaint.
2. Shop dashboard: manage complaints, inspect all supporting details, and record decisions.

Case details, evidence viewers, assessment results, and review controls are panels or dialogs within those views. Do not add separate intake, report, inventory-management, or approval pages. Access prompts can be embedded in either view.

This supersedes the earlier single staff workspace and the deferral of human review. Approval/rejection, requests for information, and technician inspection entry are now in scope. It does not add the architecture's deferred PDF intake, turnaround estimates, supplier integrations, stock mutations, or additional product categories.

## Customer chat

| Component | Required behavior |
| --- | --- |
| Conversation shell | Start a complaint, reopen the customer's own saved conversations, and show the case reference and current status without leaving the chat view. |
| Message timeline | Display customer messages, assistant questions, attachments, findings, and published shop decisions in order. Preserve the conversation after reload. |
| Composer and attachments | Send a complaint or follow-up, upload one JPEG/PNG invoice and up to three product images, preview files, show upload progress/errors, and retain unsent text after a failure. Initial file cap: 5 MB each, subject to hosting validation. |
| Guided intake cards | Collect or confirm the claimed model and required facts within the conversation. Never infer an exact model solely from product appearance. |
| Clarification cards | Identify missing/unreadable information or conflicting invoice/product identities, link to the evidence, and accept corrected information or additional evidence. |
| Assessment activity | Show the real saved document, vision, coverage, repair/parts, and resolution stages. Offer explicit resume after interrupted processing and appropriate retry after technical failures. |
| Result cards | Show a customer-readable warranty assessment, supporting evidence, repair options, availability, costs, uncertainties, and next step. Mark provisional suggestions clearly. |
| Shop response cards | Show published approval/rejection reasons, requests for more information, and inspection requests. Keep internal shop notes private. |

The chat is a presentation layer over structured case operations. It must not depend on an unrestricted conversational agent to decide access, calculate money, invent policy terms, approve cases, or change inventory. Do not add autonomous background completion or external notifications unless implemented separately.

## Shop dashboard

| Component | Required behavior |
| --- | --- |
| Complaint queue | List saved complaints; filter by processing, information needed, inspection needed, awaiting review, approved, rejected, and technical failure. Search by case reference or available product/customer labels. |
| Case detail panel | Open the selected complaint inside the dashboard. Show the complaint, conversation, current revision/assessment, stage activity, and decision history. |
| Evidence viewer | Preview and open the invoice and product images. Findings link to the exact uploaded source, retained invoice text, or policy clause. |
| Invoice and photo findings | Show extracted invoice fields, visible observations, missing values, identity conflicts, image limitations, and corrections with their original sources. |
| Warranty panel | Separate purchase/expiry eligibility from coverage. Show the policy version, applicable clauses, blockers, and evidence supporting exclusions. |
| Repair and parts panel | Show supported/provisional diagnoses, curated repair options, exact compatible SKUs, quantity/availability, snapshot prices, and labour/part totals. Keep shop cost separate from customer payable while coverage is unresolved. No inventory edits or stock reservation. |
| Inspection and correction panel | Record a supported diagnosis, corrections, and notes. Save a new revision and explicitly reassess; a correction invalidates the previous current approval. |
| Decision controls | Approve, reject, request information, or request physical inspection. Require a recorded reason for rejection and an explanation for an override. Publish only the appropriate customer-facing response. |
| Decision history | Show outcome, scope, automatic versus owner origin, reason, policy/assessment version, actor, and timestamp. Retain prior outcomes as history. |

Queue counts are derived from saved cases. No separate analytics, inventory, customer-administration, or settings dashboard is required for this scope.

## Decisions and routing

Treat processing status, warranty coverage, and the shop's final decision as separate values. An in-period purchase is not automatically covered. Declining warranty coverage does not automatically reject a paid repair request.

| Condition | Behavior |
| --- | --- |
| All explicit automatic-approval rules pass with sufficient evidence | Record and publish approval for the defined scope, with policy/assessment references. |
| An explicit automatic-rejection rule is established by evidence | Record and publish the rejection and reason for that scope. Do not infer a policy exclusion from a model's speculation. |
| Required information is missing, unreadable, invalid, or contradictory | Ask the customer for clarification in chat. Do not reject the complaint automatically. |
| Diagnosis or damage cause is uncertain | Request owner review or physical inspection. Repair hypotheses remain provisional. |
| A model request or database operation fails | Show technical failure/retry. Do not convert the failure into a warranty decision. |
| Owner records inspection/corrections | Create a new assessment revision, retain previous findings as history, and require a current decision. |
| Owner overrides an automatic outcome | Record an explicit, authorized revision and override reason; preserve the original decision. |

Automatic decisions are limited to configured, versioned shop rules enforced by ordinary server code. The exact approval/rejection predicates must be agreed with the policy catalogue before enabling automation; an LLM interpretation is not itself an authorization rule. Missing rule configuration routes the case to owner review.

## Shared interaction and persistence requirements

- Customers can access only their own cases, messages, and files. Shop-only review, inspection, internal notes, and decisions require server-enforced owner access. A browser toggle is not sufficient. Select a version-supported access mechanism during implementation; full account-management screens are not required.
- Save messages, uploads, structured findings, revisions, and decisions through the existing MongoDB repository boundary. Use GridFS for files, not browser storage or ephemeral application disk.
- Reopening either view restores the same saved case and decision. While open, the customer view can refresh the persisted state to receive an owner's response; do not imply notification delivery after the browser closes.
- Keep bounded stage advancement and request/revision checks. Reject stale review attempts, preserve entered notes, and offer to load the current assessment. Repeated submissions must not create duplicate cases, messages, assessments, or approvals.
- Adding evidence or correcting inputs starts an explicit reassessment. Do not present an old approval as current while revised evidence is being processed.
- Show loading, empty, uploading, processing, paused, blocked, failed, and saved states. Use readable limitations rather than unsupported confidence percentages.
- Clearly label fixture mode, synthetic evidence, fictional policies, seeded stock, and saved fallback results. Never silently replace failed live inference with fixture output.

## Suggested component boundaries

Current implementation boundaries are listed below. Legacy comment-only `ui/intake.jac`, `ui/case_list.jac`, and `ui/workspace.jac` placeholders are not imported by the runnable UI.

| Location | Responsibility |
| --- | --- |
| `ui/app.jac` | Dummy account session, role-specific two-view shell, saved conversation navigation, sign-out, search, theme/storage preferences, evidence/review dialogs, and confirmations. |
| `ui/login.jac` | Customer/shop-owner login UI with visible dummy credentials, validation, password visibility, and role selection. No real authentication. |
| `ui/login.css` | Reference-inspired split login layout; strictly monochrome tokens scoped to login. |
| `ui/brand.jac` | User-provided light/dark brand mark, selected with the existing theme. |
| `ui/motion.jac` | Framer Motion title entrance with reduced-motion support. |
| `ui/login-feature.css` | Centered, inverse-theme login feature panel and scoped laptop glass card. |
| `ui/readability.css` | Shared larger typography tokens, responsive layouts, and flatter summary/assessment sections. |
| `ui/inventory.jac` | Fictional six-item catalogue and typed asynchronous part match/stock result. |
| `ui/parts.jac` | Customer/owner availability details, separate stock retry, and customer enquiry action. |
| `ui/chat.jac` | Customer timeline, composer, uploads, clarification, stage activity, and published result/decision cards. |
| `ui/dashboard.jac` | Owner queue, filters/counts, embedded conversation/evidence/assessment/history tabs, customer-facing reply composer, and review controls. |
| `ui/findings.jac` | Shared warranty, invoice, observation, repair/parts, cost and next-action displays. |
| `ui/pieces.jac` | Status labels, copy feedback, stage activity, evidence previews, and empty states. |
| `ui/models.jac` | Typed client records for cases, messages, evidence, assessments, and decisions. |
| `ui/gateway.jac` | Asynchronous IndexedDB demo adapter, fixture results, revisions, and atomic stale-write protection. |
| `ui/imagery.jac` | Generated illustrative device-photo asset URLs. |

Reuse shared buttons, fields, status badges, alerts, upload cards, image dialogs, evidence references, and loading indicators across both views.

## Backend work required

The current server and shared contracts are also placeholders. Before claiming functional integration, define and implement:

- Customer- versus owner-scoped create/list/get-case and evidence operations.
- Persisted message send/read operations, attachment associations, and customer-safe versus internal visibility.
- Structured intake corrections, missing-information responses, and explicit reassessment.
- Existing start/advance-assessment operations for the five bounded stages.
- Record-inspection and review-case operations, including approve/reject/request-information/request-inspection actions.
- Versioned automatic decision rules, audited decisions, conditional revision updates, and customer-visible outcome projection.

The exact contracts and generated Jac routes must be checked against the project's agreed installed runtime. This UI scope change does not silently change the team's compiler baseline.

## Acceptance checks

1. A customer submits a complaint and valid evidence entirely through chat, then reopens the saved conversation.
2. Owner dashboard shows that same case, files, stage progress, findings, and evidence trail.
3. A mismatch or unreadable invoice produces a specific clarification request in chat; the customer responds and explicitly reassesses.
4. Uncertain damage produces an inspection/review route, not a fabricated diagnosis or automatic rejection.
5. Owner records findings, reassesses, and approves/rejects the current proposal; the customer sees the published outcome and reason.
6. Configured automatic outcomes identify their rule, scope, evidence, and origin; absent/uncertain rules route to review.
7. Provider failures, out-of-stock parts, stale reviews, repeated submissions, and revised evidence display the correct distinct states.
8. Reload/restart retains conversations, evidence, assessments, and decisions. Another customer's files and shop-only actions are inaccessible.
9. All of this is reachable inside the two primary views, with no separate intake, report, inventory, or approval page.
