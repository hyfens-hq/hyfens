# Task 227: Clarify passive and active context surfaces

Status: [x] Completed

## Goal

Reduce unnecessary chrome in the sidebar by making the organization context and account trigger visually quiet at rest, while retaining a clear accented surface when the account dropdown is open or focused.

## Scope and Non-goals

Scope:

- Remove the border and background from the passive organization context container.
- Remove the border and background from the passive account summary trigger.
- Preserve the account trigger’s accent border and background while its dropdown is open or the trigger is keyboard-focused.
- Keep the organization selector’s own control and all switching behavior unchanged.

Non-goals:

- No organization data, switching behavior, account menu actions, or session changes.
- No changes to the dropdown contents, placement, or responsive sidebar behavior.
- No new visual dependency or broad sidebar redesign.

## Owner

Coordinator.

## Dependencies

- Existing workspace context and account-menu markup in `dashboard/index.html`.
- Existing sidebar surface tokens and open-state handling in `dashboard/styles.css`.
- Existing dashboard contract tests and canonical local Docker stack.

## Assumptions

- The organization selector remains discoverable through its label and native control, so the surrounding container does not need a card treatment at rest.
- The account trigger should use the current accent surface only to communicate an open or focused interactive state.
- Existing border widths and focus accessibility should remain consistent with the dashboard’s hairline control system.

## Work Items

- [x] Inspect the current passive and active organization/account surface rules.
- [x] Remove resting border/background treatments and preserve active account state styling.
- [x] Add/update the source contract and verify the rendered states.
- [x] Run source validation, rebuild Docker, and record the result.

## Validation

Completed:

- Live browser check confirmed the organization wrapper and account trigger compute to a transparent background with no border at rest.
- Source contract confirms the account trigger restores the 0.5px accent border and accent background while open or keyboard-focused; the organization select rules remain unchanged.
- `python3 -m unittest dashboard.test_serve` — 26 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh scripts/local-dashboard.sh up` — rebuilt/recreated the dashboard and completed the local seed step.
- Docker health check — dashboard on `18083`, control plane on `18082`, PostgreSQL, and object store all healthy.

## Next Action

No further action is required for this task.

## Blockers

None.

## Outcome

The organization context and account trigger are visually quiet at rest. The account trigger retains its accent border and tinted background when the dropdown is active or the trigger receives keyboard focus. Organization switching and account actions were not changed.

## References

- User screenshots showing the organization card and account trigger with unwanted resting chrome.
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/test_serve.py`

## History

- 2026-09-01: Reserved task 227 for passive and active sidebar context surface states.
- 2026-09-01: Added a red source contract, removed passive wrapper/trigger chrome, preserved active account states, rebuilt Docker, and completed 26-test, syntax, browser, and health validation.
