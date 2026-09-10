# Task 237: Auth single-scroll layout

Status: [x] Completed

## Goal

Remove the nested vertical scroll containers from the split-screen authentication
surface so desktop and mobile use one coherent document scroll context.

## Scope and Non-goals

Scope:

- Update the shared dashboard auth layout styles.
- Preserve the existing split-screen composition, auth fields, form transition,
  responsive collapse, and brand treatment.
- Validate login and registration at desktop and narrow viewports.

Non-goals:

- No auth protocol or endpoint changes.
- No redesign of the dashboard shell or unrelated collection surfaces.
- No dependency or icon-library changes.

## Owner

Coordinator, with design review informed by Mobbin web auth references.

## Dependencies

- Existing dashboard static shell in `dashboard/index.html` and
  `dashboard/styles.css`.
- Existing auth transition and responsive rules.

## Assumptions

- The document is the intended scroll owner when auth content exceeds the
  viewport.
- The right-side statement rail may grow with the page but must not create an
  independently scrolling column.
- The current Hyfens dark split composition remains the product direction.

## Work Items

- [x] Confirm the nested scroll root and affected CSS rules.
- [x] Replace bounded desktop pane scrolling with normal document flow.
- [x] Add a focused regression contract for the single-scroll behavior.
- [x] Run static tests and browser-level layout checks for both auth modes.
- [x] Review the task-owned diff and record validation evidence.

## Validation

- `python3 -m unittest dashboard.test_serve` -> 30 tests passed.
- Browser inspection of login and registration at 2560x1267, 1024x768, and
  680x900.
- Both auth panes reported `overflowY: clip` and no vertical scroll-container
  behavior; document horizontal overflow was false at all checked widths.

## Next Action

No further action in this task. A Docker rebuild or deployment remains separate
from this source/layout correction.

## Blockers

None.

## Outcome

PASS. The desktop split-screen auth surface now uses one document scroll
context, while the narrow layout continues to collapse to one column without
horizontal overflow. The CSS query version was bumped to `v235` to invalidate
the previous cached stylesheet.

## References

- Mobbin web auth references: SchoolAI, Midday, Clay, and lululemon.
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/test_serve.py`

## History

- 2026-09-02: Created to track the auth nested-scroll correction.
- 2026-09-02: Removed bounded pane scrolling, added the single-scroll contract,
  and validated the rendered auth states in Chrome.
