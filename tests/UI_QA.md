# UI verification — 17 October 2026

Validated as a local demo under Jac 0.34.13. No live inference, MongoDB, authentication, payment, stock reservation, or deployment was exercised.

## Compiler and automated checks

- Eight application modules passed `jac check` with zero errors. Browser interop and generated component warnings remain.
- The client production bundle built successfully.
- Nine isolated IndexedDB gateway tests passed, with 39 assertions. These cover reload persistence, scoped search, upload/message validation, customer-facing shop replies without decision changes, assessment and owner review, corrections and decision history, conflict/inspection rules, retry and unavailable stock, and atomic stale-tab rejection.
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

## Dummy login and role-specific UI update

The four changed modules (app, login, dashboard and gateway) passed compiler checks, and the production client built successfully. Browser testing confirmed required-field and wrong-role credential errors, both dummy account paths, customer-only navigation, removal of the persona switcher, role retention after reload, sign-out and cancelled draft-discard confirmation. The owner's Customer chats shortcut opens the Conversation tab. An empty reply showed validation; a valid shop reply appeared in the customer's conversation after switching accounts. No production authentication is claimed.

The login was checked in light/dark themes and a narrow viewport. A missing space at hidden desktop line breaks was corrected and verified in the rebuilt preview. At a measured 392-pixel viewport, the login and owner reply composer had no horizontal overflow; the reply composer and decision controls remained separate. The viewport was reset afterward. Account credentials are shown on the login screen and documented in DEVELOPMENT.md. The final login screenshot is saved in `.jac/qa/login-preview.png`.

## Monochrome login, branding and field refinement

- The login now follows the supplied form-left / feature-panel-right reference, using only monochrome UI colours. At measured widths of 392, 771 and approximately 1097 pixels, it had no horizontal overflow. The feature panel is hidden on narrow screens; account selection, credentials and form controls remain available. Both light and dark appearances were inspected, then the viewport override was reset.
- Verified both dummy account entry paths, required-field feedback, password visibility, account-dependent feature copy and expandable login help after the redesign.
- User-supplied logo PNGs loaded locally. Light mode displays the black mark on white; dark mode displays the white mark on black. The sidebar, login and assistant use the shared mark, and the favicon follows the theme.
- Measured native-select wrappers at zero border and zero padding, with a single approximately one-pixel inner select border and a 42-pixel field height. Scenario selection still works. Inspected both themes and saved `.jac/qa/dropdowns-fixed.png` as visual evidence.
- Dark sidebar and card surfaces measured RGB 24/24/24; active navigation measured RGB 41/41/41 with RGB 222/222/222 text. The light workspace palette is retained. Removed the nested input background from dashboard search and added consistent container focus treatment to search/composer controls.
- Framer Motion 14.3.0 is installed and bundled. Main title elements settle at opacity 1 and transform none; the shared helper uses `useReducedMotion` to disable its entrance. An OS-level reduced-motion preference was not changed during this browser pass.
- The six affected Jac modules passed compiler checks (five in the initial check, app after its browser-head typing adjustment). Production build and all nine gateway tests passed with 39 assertions. Subsequent changes were CSS refinements and demo-help wording only.
- The final preview rebuilt successfully after those refinements. Dashboard search measured a transparent, borderless inner input with a single outer border; filtering by FX-1048 returned the expected case. Final login screenshot: `.jac/qa/login-refined.png`.

## Readability, waves and parts-availability update

- Ten changed/new Jac UI modules passed compiler checks with zero errors. The Jac 0.34.13 production client built successfully. All 15 isolated gateway tests passed with 78 assertions, including six new tests covering exact-model stock matches, absent stock, uncertain compatibility, lookup failure/retry, offer deduplication, revision invalidation, and legacy-record normalization without data loss.
- In the browser, created a clearly labelled missing-charger demo complaint, uploaded the local invoice fixture and an illustrative laptop photo, and completed assessment. The sample FX-AC14 charger result showed five units and USD 60.00. A customer availability message was published automatically. Asking about the part filled the composer, and sending that enquiry made it visible in the owner's Conversation tab. Refreshing stock retained one offer for that revision; reload retained evidence, messages, and availability.
- Corrected the case in the owner view. The earlier offer remained visibly marked as belonging to the previous revision. Reassessment generated the new revision's result while preserving conversation history. Warranty coverage and the owner's review state remained separate from stock availability.
- Measured 18 px chat/body text and part explanations, 16 px form inputs, and responsive page titles of 32, 38 and 44 px at approximately 392, 771 and 1446 px viewport widths. Both self-hosted families remain in use. Inspected light and grayscale dark surfaces; no horizontal overflow was observed in the checked login, customer, queue, detail and dialog layouts.
- Inspected mobile chat, attachment controls, multiline composer, floating controls and new-case dialog. The composer measured 18 px; floating buttons cleared it. The new-case dialog fit within the viewport. Shift+Tab wrapped from its first field to Close, Escape dismissed it, and focus returned to the opening button. Mobile owner actions are in document flow to avoid covering the larger content. Refined the smaller-screen banner so its copy and photograph occupy separate regions.
- Waves use neutral strokes and reserve their own space outside interactive content. Verified moving/static states, pause persistence after reload and across accounts, and offscreen pausing. Reduced-motion support is implemented using Framer Motion's preference hook; an OS-level preference change and physical mobile keyboard were not exercised in this pass.
- The preview remains explicitly local and sample-driven. Real image analysis, live inventory, authentication, purchase and reservation were not connected. Existing saved cases were preserved; browser QA added one labelled demo enquiry.

Final rebuilt preview verified the corrected login spacing, 14 px table/breadcrumb metadata, 44 px desktop title and responsive banner. Saved `.jac/qa/dashboard-readable.png` and restored the browser's normal viewport. The local preview is running at http://localhost:8000/.

## Wave removal and inverse-theme login glass card

Removed the decorative waves, pause controls and reserved wave spacing from login, customer chat and owner dashboard. Centered the login's laptop showcase and supporting copy. The feature panel now uses RGB 241/241/241 in dark mode and RGB 16/16/16 in light mode; the laptop card uses a scoped translucent surface, 24 px backdrop blur, fine reflective border and solid fallback. Other workspace surfaces retain their existing themes.

Five affected Jac modules passed compiler checks; the production client built successfully under Jac 0.34.13. Browser checks at measured widths of approximately 391, 769 and 1440 px found no horizontal overflow. Verified theme inversion and persistence, centered content (within one pixel), glass styling, both dummy-account entry paths, and zero wave elements/controls in chat and dashboard. Their introduction padding is zero after wave removal. The mobile login retains its existing form-only layout. Saved `.jac/qa/login-inverse-glass.png` and `.jac/qa/login-black-glass.png`, then restored the normal browser viewport. No case data or workflow logic was changed in this update.
