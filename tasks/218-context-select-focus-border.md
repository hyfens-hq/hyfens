# Task 218: Context select focus border

Status: [x] Completed

## Goal

Fix the dashboard context select styling so the profile, application, and environment controls use a 0.5px border and do not render a duplicated focus border.

## Scope and Non-goals

Scope:

- Correct the context-select focus cascade in `dashboard/styles.css`.
- Keep one visible, accessible accent focus treatment on the selected control.
- Add a focused dashboard source-contract regression test.
- Rebuild and verify the local dashboard image and rendered control states.

Non-goals:

- No changes to select behavior, context data, navigation, typography, or API contracts.
- No broad restyling of unrelated inputs, buttons, cards, or tables.
- No removal of keyboard focus indication from other controls.

## Owner

Coordinator: Codex. Implementation and review are single-threaded because the defect is isolated to one CSS cascade and its focused dashboard contract test.

## Dependencies

- Existing context controls in `dashboard/index.html`.
- Existing dashboard CSS and `DashboardContractTest` in `dashboard/test_serve.py`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The visible duplicate is caused by the context select’s focus box-shadow combined with the global focus-visible outline; the wrapper itself has no border.
- The requested 0.5px border should remain the source-level border width for normal, hover, and focus states.
- A single accent border is sufficient for the compact context controls while preserving visible keyboard focus.

## Work Items

- [x] Add a regression contract that fails when context selects retain the duplicate focus treatment.
- [x] Override the context-select focus cascade with a single 0.5px accent border and no second ring.
- [x] Rebuild the dashboard image and verify normal, hover, and keyboard-focus computed styles in the local browser.
- [x] Record validation and close the task.

## Validation

Completed:

- The new regression contract failed before the fix and passed after the fix.
- `python3 -m unittest dashboard.test_serve` — 17 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh -n scripts/local-dashboard.sh` — passed.
- Docker Compose config validation — passed.
- Rebuilt and recreated the canonical dashboard service with CSS cache version `218`.
- Served HTML/CSS expose `tokens.css?v=218` and `styles.css?v=218` with the corrected context-select rule.
- Browser verification confirmed normal neutral border, hovered/focused accent border, `box-shadow: none`, and no focus outline on `#environment-context`.

## Next Action

No further action is required within this task.

## Blockers

None currently.

## Outcome

Context selectors now retain a single hairline border in normal and hover states. Focused selectors use one 0.5px accent border, with the duplicate 3px shadow and 2px outline removed for these compact controls only.

## References

- User-provided screenshot showing the focused environment select with two visible orange borders.
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/index.html`

Validation evidence:

- `dashboard/test_serve.py` — 17 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh -n scripts/local-dashboard.sh` and Docker Compose config validation — passed.
- Local Docker/browser verification passed on `127.0.0.1:18083`.

## History

- 2026-09-01: Reserved after a live browser repro showed a 1px border, 3px focus box-shadow, and 2px focus-visible outline on the same context select.
- 2026-09-01: Added the failing regression contract, removed the duplicate context-select focus ring, bumped static CSS cache version to 218, rebuilt Docker, and verified normal/hover/focus states in the live browser.
