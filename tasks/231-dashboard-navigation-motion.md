# Task 231: Dashboard navigation motion

Status: [x] Completed

## Goal

Add a crisp, non-disruptive transition when moving between dashboard pages so route changes no longer feel abrupt.

## Scope and Non-goals

Scope:

- Animate the newly rendered page region during dashboard route navigation.
- Use transform and opacity only, with the existing dashboard easing and a sub-300ms duration.
- Cover sidebar navigation, search-result navigation, and browser back/forward navigation.
- Respect `prefers-reduced-motion` and preserve existing route, focus, and data-rendering behavior.
- Add focused source-contract coverage and bump the JavaScript asset version.

Non-goals:

- No routing model, URL, API, authentication, or data-loading changes.
- No animation on every filter/search re-render or initial session boot.
- No new animation library or dependency.
- No layout-property, height, width, or scroll-position animation.

## Owner

Coordinator (Codex)

## Dependencies

- Existing `navigateToView`, `handleLocationChange`, and `renderCurrentPage` flow in `dashboard/app.js`.
- Existing page-region layout and motion tokens in `dashboard/styles.css`.
- Existing dashboard source-contract tests in `dashboard/test_serve.py`.

## Assumptions

- A subtle page-region entrance is sufficient to communicate route continuity without delaying interaction.
- The page region should animate while persistent sidebar, topbar, and context controls remain stable.
- CSS transitions are preferred for this predetermined motion and can be cancelled cleanly on rapid navigation.

## Work Items

- [x] Add focused source-contract coverage for route-triggered page motion and reduced-motion behavior.
- [x] Add interruptible page-region transform/opacity transition and wire it to route changes.
- [x] Review the task diff, run targeted validation, and rebuild the local dashboard.
- [x] Update this task with outcome and validation evidence.

## Validation

- `python3 -m unittest dashboard.test_serve`
- `node --check dashboard/app.js`
- Static review of route call sites and motion declarations.
- `sh scripts/local-dashboard.sh status`
- Verify `http://127.0.0.1:18083/` serves the updated assets.

## Next Action

Complete; no further action remains within this task.

## Blockers

None.

## Outcome

Dashboard route changes now animate the newly rendered page region with a fast 220ms opacity and 8px translate transition using the existing ease-out curve. Sidebar, search-result, and browser history navigation use the same motion; persistent shell elements remain stable. Rapid rerenders cancel pending transitions, reduced-motion users get no movement, and no layout properties are animated. Focused tests and JavaScript syntax checks pass, and the local Docker dashboard was rebuilt and verified healthy.

## References

- User request: add motion design to dashboard page navigation.
- `dashboard/app.js`
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- Emil-style motion guidance used for transform/opacity-only, fast ease-out, interruptible transitions, and reduced-motion behavior.

## History

- 2026-09-01: Reserved task 231 and began implementation.
- 2026-09-01: Added route-triggered page-region motion with cancellation and reduced-motion handling, added focused coverage, passed 27 dashboard tests plus `node --check`, and rebuilt the local dashboard with app asset version 227.
