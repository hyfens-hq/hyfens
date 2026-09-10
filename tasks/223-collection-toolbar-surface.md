# Task 223: Remove collection toolbar surface treatment

Status: [x] Completed

## Goal

Make collection toolbars visually lighter by removing the wrapper surface treatment while retaining their layout and field-level controls.

## Scope and Non-goals

Scope:

- Remove `.collection-toolbar` padding, border, and background declarations, and bump the stylesheet asset version.
- Preserve toolbar gap, margin, responsive wrapping, labels, and individual input/select styling.

Non-goals:

- No changes to collection behavior, filtering, sorting, routing, API contracts, or field controls.
- No unrelated dashboard styling or dependency changes.

## Owner

Coordinator.

## Dependencies

- Existing `.collection-toolbar` layout and responsive rules in `dashboard/styles.css`.

## Assumptions

- The surrounding panel provides the required visual grouping; individual fields retain their own control treatment.

## Work Items

- [x] Remove the requested wrapper padding, border, and background.
- [x] Bump the stylesheet asset version so deployed browsers receive the change.
- [x] Run the focused dashboard validation.

## Validation

Completed:

- `python3 -m unittest dashboard.test_serve` — 23 tests passed.
- Live browser confirmed `.collection-toolbar` has `padding: 0`, no border, and a transparent background while retaining `12px` layout gap and `18px` bottom margin.
- Live browser confirmed individual fields retain their hairline inset border treatment and the default toolbar count remains suppressed.
- Rebuilt the canonical local Docker stack; dashboard `18083` and control plane `18082` are healthy.

## Next Action

No further action; the coordinator applied the focused CSS change, redeployed it, and completed validation.

## Blockers

None.

## Outcome

The collection toolbar wrapper is now visually unboxed; its field controls and layout spacing remain unchanged.

## References

- User request to remove `.collection-toolbar` padding, border, and background.
- `dashboard/styles.css`

## History

- 2026-09-01: Reserved task 223 for the focused collection-toolbar surface change.
- 2026-09-01: Removed wrapper padding, border, and background, bumped the stylesheet asset version to `223`, rebuilt Docker, and verified the live dashboard.
