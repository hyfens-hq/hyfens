# Task 228: Exact-record drawer and border reduction

Status: [x] Completed

## Goal

Show exact records in a right-side drawer on desktop and reduce unnecessary visual chrome by removing the `.surface-panel` border and input-field box shadows.

## Scope and Non-goals

Scope:

- Convert the existing exact-record overlay from a bottom sheet to a right-side drawer on desktop.
- Preserve an accessible overlay, focus management, Escape/backdrop dismissal, and a mobile-friendly fallback.
- Remove the `.surface-panel` border.
- Remove `box-shadow` declarations from input and select field rules, including normal, hover, and focus states.
- Keep the exact-record drawer surface at 90% background opacity in both color themes.
- Update focused source-contract tests and the stylesheet asset version.

Non-goals:

- No data-model, API, authentication, or routing changes.
- No broad component redesign or removal of semantic dividers unrelated to the requested controls.
- No dependency, deployment, or Docker changes.

## Owner

Coordinator (Codex)

## Dependencies

- Existing exact-record overlay markup and focus-trap behavior in `dashboard/index.html` and `dashboard/app.js`.
- Existing dashboard stylesheet and `dashboard/test_serve.py` source-contract tests.

## Assumptions

- The existing `record-sheet` IDs/classes can remain as the stable accessibility and JavaScript contract while the component is visually implemented as a drawer.
- Desktop should use a right-side drawer; narrow screens should retain a bottom-sheet fallback so the record remains usable without an overly narrow panel.
- Drawer depth may retain its own shadow because the request targets input fields/classes and `.surface-panel` borders, not the drawer boundary.

## Work Items

- [x] Add regression coverage for right-drawer placement and removal of panel/input visual chrome.
- [x] Update exact-record overlay layout and responsive motion styles.
- [x] Remove `.surface-panel` border and input/select box-shadow declarations.
- [x] Keep the exact-record drawer background at 90% opacity for dark and light themes.
- [x] Review the combined task diff and run targeted validation.
- [x] Update this task with outcome and validation evidence.

## Validation

- `python3 -m unittest dashboard.test_serve`
- `node --check dashboard/app.js`
- Static review of all `box-shadow` declarations adjacent to input/select rules and the exact-record responsive rules.

## Next Action

Complete; no further action remains within this task.

## Blockers

None.

## Outcome

Exact records now open in a desktop right-side drawer with a mobile bottom-sheet fallback, preserving keyboard focus management, Escape/backdrop dismissal, and reduced-motion behavior. `.surface-panel` is borderless, input/select box shadows are removed, and the drawer uses a 90% opaque theme-aware surface so page content does not show through the drawer background. The local dashboard stack was rebuilt and verified healthy.

## References

- User request: exact records should open in a right-side drawer; remove `.surface-panel` border and input-field box shadows.
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/app.js`
- `dashboard/test_serve.py`
- Apple-style drawer guidance used for spatially consistent enter/exit motion and reduced-motion behavior.

## History

- 2026-09-01: Reserved task 228 and began implementation.
- 2026-09-01: Implemented the responsive exact-record drawer, removed the requested panel/input visual chrome, and added focused source-contract coverage.
- 2026-09-01: Corrected the drawer surface to 90% opacity for dark and light themes, rebuilt the local dashboard, and verified live drawer geometry, focus restoration, dismissal, and computed background color.
