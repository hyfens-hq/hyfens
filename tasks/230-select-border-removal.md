# Task 230: Select border removal

Status: [x] Completed

## Goal

Remove visual borders from every dashboard select control while preserving dropdown arrows, sizing, surfaces, hover feedback, and accessible keyboard focus indication.

## Scope and Non-goals

Scope:

- Remove visible border values and border-color declarations from all select-specific dashboard rules, using explicit zero-width resets where needed to override native styling.
- Preserve a non-border focus outline for keyboard users.
- Add focused source-contract coverage and bump the stylesheet asset version.

Non-goals:

- No changes to text inputs, buttons, wrappers, dropdown option menus, or unrelated panels.
- No changes to select layout, padding, arrow positioning, or background states.
- No dependency, API, authentication, routing, or Docker changes.

## Owner

Coordinator (Codex)

## Dependencies

- Existing select rules in `dashboard/styles.css`.
- Existing dashboard source-contract tests in `dashboard/test_serve.py`.

## Assumptions

- “All select classes” means every dashboard select control and state rule, including organization, context, and collection filters.
- Focus outlines remain as accessibility affordances because they are not component borders.

## Work Items

- [x] Add focused source-contract coverage for borderless select rules and preserved focus outlines.
- [x] Remove select border and border-color declarations across normal, hover, and focus states.
- [x] Review the task diff, run targeted validation, and rebuild the local dashboard.
- [x] Update this task with outcome and validation evidence.

## Validation

- `python3 -m unittest dashboard.test_serve`
- Static review of all CSS rules containing `select` to confirm no select border declarations remain.
- `sh scripts/local-dashboard.sh status`
- Verify `http://127.0.0.1:18083/` serves the updated stylesheet version.

## Next Action

Complete; no further action remains within this task.

## Blockers

None.

## Outcome

All dashboard select controls now render without visible borders across normal, hover, and focus states. The existing keyboard focus outline remains available, and select sizing, backgrounds, arrows, and dropdown behavior are unchanged. Focused tests passed, the stylesheet was bumped to version 232, and the local Docker dashboard was rebuilt and verified healthy.

## References

- User request: remove borders from all select classes.
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/index.html`

## History

- 2026-09-01: Reserved task 230 and began implementation.
- 2026-09-01: Removed select border and border-color states, added borderless/focus-outline coverage, passed the dashboard test suite, and rebuilt the local dashboard with stylesheet version 232.
