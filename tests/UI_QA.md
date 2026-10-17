# UI verification — 17 October 2026

Validated as a local demo under Jac 0.34.13. No live inference, MongoDB, authentication, payment, stock reservation, or deployment was exercised.

## Compiler and automated checks

- Eight application modules passed `jac check` with zero errors. Browser interop and generated component warnings remain.
- The client production bundle built successfully.
- Eight isolated IndexedDB gateway tests passed, with 32 assertions. These cover reload persistence, scoped search, upload/message validation, assessment and owner review, corrections and decision history, conflict/inspection rules, retry and unavailable stock, and atomic stale-tab rejection.
- `git diff --check` passed; Git reports only line-ending normalization notices.

## Browser checks

- Completed a new complaint, real local image uploads, the five-stage sample assessment, owner approval and decision history, and the published response in customer chat. Reload retained the case and evidence previews. All findings were visibly labelled as samples.
- Verified explicit dark-mode persistence and storage-notice dismissal after reload.
- Opened search using both the button and Ctrl+K; checked persona-scoped results and a no-matches state. Checked dialog keyboard focus, Escape, and focus restoration. Cancelling the nested decision confirmation retained the response and restored focus to Review decision after its closing transition.
- Copied an assistant response, verified the copied feedback and actual clipboard text.
- Tested blank message/decision input, an oversized image and an unreadable image. Specific errors appeared and entered text remained available.
- Inspected customer chat, dashboard queue and complaint detail with 390, 768 and 1440 pixel viewport presets in light and dark themes. The browser's host scaling produced measured content widths of approximately 362, 712 and 1334 pixels. No material horizontal overflow appeared; the desktop has a one-pixel rounding difference. Restored the normal viewport after checks.
- Checked the phone navigation drawer, queue/detail return controls, sticky composer, wrapping decision buttons, evidence dialog, back-to-top, reading progress and contextual floating controls. At normal desktop size, the dashboard fills the viewport.
- Confirmed the local workbench image and all three generated laptop images render. Device thumbnails have lazy loading and explicit dimensions. Both self-hosted font faces register in the browser.

The shared styles include visible focus treatment and a reduced-motion media rule. These checks are manual browser QA, not a formal accessibility certification or a physical-device/mobile-keyboard test. A real backend needs server-enforced authorization, validated extraction, durable evidence storage, and separate integration/security tests.

The final desktop screenshot is saved locally in the ignored `.jac/qa/dashboard-preview.png` folder.
