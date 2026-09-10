# Task 219: Sidebar logo vertical inset

Status: [x] Completed

## Goal

Keep the Hyfens brand lockup vertically centered inside the sidebar header so the logo does not touch the app viewport’s top edge.

## Scope and Non-goals

Scope:

- Correct the sidebar-specific alignment of the existing brand lockup.
- Add a focused dashboard source-contract regression test.
- Rebuild and verify the local dashboard image and live header geometry.

Non-goals:

- No changes to the brand asset, logo dimensions, header height, sidebar width, or browser chrome.
- No changes to the auth-page brand lockup or other responsive layout behavior.

## Owner

Coordinator: Codex. Implementation and review are single-threaded because the defect is isolated to the shared brand alignment cascade and one dashboard contract test.

## Dependencies

- Existing `.brand-lockup` and `.sidebar-header` rules in `dashboard/styles.css`.
- Sidebar markup in `dashboard/index.html`.
- Dashboard contract tests in `dashboard/test_serve.py`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The shared `.brand-lockup` rule intentionally aligns the auth-page brand to the start, but that inherited `align-self: flex-start` is incorrect for the sidebar header.
- The sidebar header’s existing `align-items: center` is the intended geometry; the smallest fix is a sidebar-scoped `align-self: center` override.
- The brown strip above the app is browser chrome and remains outside the dashboard’s layout.

## Work Items

- [x] Add a regression contract that fails when the sidebar brand lockup is aligned to the top edge.
- [x] Override the inherited brand alignment only within `.sidebar-header`.
- [x] Rebuild the dashboard image and verify header/logo bounds in the local browser.
- [x] Record validation and close the task.

## Validation

Completed:

- The new regression contract failed before the fix and passed after the fix.
- `python3 -m unittest dashboard.test_serve` — 18 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh -n scripts/local-dashboard.sh` — passed.
- Docker Compose config validation — passed.
- Rebuilt and recreated the canonical dashboard service with CSS cache version `219`.
- Control-plane health check and served HTML checks passed.
- Browser verification measured the logo `22px` below and `23px` above the `72px` sidebar header, with `align-self: center`.

## Next Action

No further action is required within this task.

## Blockers

None currently.

## Outcome

The sidebar brand lockup is now centered within its header. The auth-page brand alignment remains unchanged.

## References

- User-provided screenshot showing the sidebar Hyfens logo touching the app viewport top edge.
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/index.html`

Validation evidence:

- `dashboard/test_serve.py` — 18 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh -n scripts/local-dashboard.sh` and Docker Compose config validation — passed.
- Local Docker/browser verification passed on `127.0.0.1:18083`.

## History

- 2026-09-01: Reserved after live geometry measured the sidebar brand lockup at `top: 0` inside a `72px` header with inherited `align-self: flex-start`.
- 2026-09-01: Added the failing alignment regression, scoped the sidebar lockup to `align-self: center`, bumped static CSS cache version to 219, rebuilt Docker, and verified live header geometry.
