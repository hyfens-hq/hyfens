# Task 213: Dashboard account, workspace, and header polish

Status: [x] Completed

## Goal

Clean up the dashboard shell shown in the latest screenshots: keep one username avatar, make the account popover opaque, remove the redundant organization ID display, and center the desktop brand header.

## Scope and Non-goals

Scope:

- Remove the redundant profile icon from the account trigger while retaining the username initials avatar.
- Use an opaque account-popover surface so footer content cannot show through it.
- Remove the organization ID from the workspace card without removing the ID from runtime context or API requests.
- Center the desktop sidebar brand header while preserving the mobile close-button layout.
- Add focused regression coverage for the exact shell conditions and redeploy the local dashboard.

Non-goals:

- No changes to authentication, session persistence, account actions, navigation routes, or API authorization.
- No organization-context data-model changes; IDs remain available to application logic where required.
- No brand-mark asset redesign, new icon family, or unrelated dashboard-content restyling.

## Owner

Coordinator with one disjoint Luna Max implementation worker for `dashboard/index.html` and `dashboard/styles.css`; coordinator owns `dashboard/app.js`, tests, task evidence, and integration.

## Dependencies

- Existing dashboard shell in `dashboard/index.html`, `dashboard/app.js`, and `dashboard/styles.css`.
- Existing dashboard tokens in `dashboard/tokens.css`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The initials circle is the intended account avatar and the extra profile glyph is redundant.
- The account popover should remain location-aware and use a fully opaque surface in both themes.
- Desktop brand centering applies when the sidebar close control is hidden; mobile navigation retains its current spacing.
- Existing uncommitted repository contents belong to the user and must remain untouched outside this task.

## Work Items

- [x] Reproduce the four screenshot conditions with a live shell audit and inspect the direct implementation.
- [x] Update account/workspace markup and desktop popover/header styling.
- [x] Remove only the now-unused workspace display binding and add focused contract coverage.
- [x] Review, rebuild, and validate the deployed dashboard.

## Validation

Completed checks:

- The new shell contract was red before the fix and passed in the consolidated run.
- `python3 -m unittest dashboard.test_serve` passed: 12 tests.
- `node --check dashboard/app.js` passed.
- `sh scripts/local-dashboard.sh up` passed and rebuilt/restarted the local dashboard image.
- Browser shell audit after reload found zero redundant account-trigger profile icons, no `#workspace-id`, an opaque `rgb(12, 12, 12)` popover, centered desktop sidebar header, and 24/24 icons loaded.
- `http://127.0.0.1:18083/` and `http://127.0.0.1:18082/healthz` returned 200.
- Dashboard, control-plane, Postgres, and object-store containers are healthy.

## Next Action

Open `http://127.0.0.1:18083/` after signing in normally for the final visual confirmation at the target desktop viewport.

## Blockers

None.

## Outcome

Completed. The account trigger now uses only the username initials avatar, the account popover is opaque, the sidebar organization card shows name and membership scope without the raw ID, and the desktop brand header is centered while mobile navigation remains unchanged.

## References

- User-provided screenshots showing account popover bleed-through, redundant avatar icon, workspace ID clutter, and off-center brand header.
- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/styles.css`
- `dashboard/tokens.css`
- `dashboard/test_serve.py`
- `tasks/212-dashboard-header-icon-rendering.md`

## History

- 2026-09-01: Reserved task 213 after a live shell audit reproduced all four reported conditions at desktop width.
- 2026-09-01: Removed redundant account/workspace display nodes, made the popover opaque, centered desktop branding, updated the binding and contracts, rebuilt the stack, and passed the live shell audit.
