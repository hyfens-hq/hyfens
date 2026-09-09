# Task 211: Dashboard session and shell polish

Status: [x] Completed

## Goal

Keep an authenticated dashboard session across a page refresh while retaining tab-scoped security, and refine the dashboard shell so it is lighter, icon-consistent, and easier to operate.

## Scope and Non-goals

Scope:

- Restore and validate the current dashboard session after reload, without storing a password.
- Reduce excessive text weight and visual density in the dashboard shell.
- Use the provided local icon assets, with the existing outline/twotone/bold preference.
- Move account actions into a location-aware account popover with profile-oriented entries and sign out.
- Preserve the existing control-plane boundaries, routes, data behavior, and read-only semantics.

Non-goals:

- No password reset or credential rotation.
- No new authentication backend or persistent cross-device login.
- No redesign of dashboard data views beyond shell typography, icons, and account-menu behavior.
- No cleanup of unrelated pre-existing untracked files.

## Owner

Coordinator with two disjoint GPT-5.6 Luna Max workers: auth/session and dashboard shell.

## Dependencies

- Existing dashboard source in `dashboard/`.
- Local icon source at `/Volumes/970EvoPlus/Development/templates/icons`.
- Local control plane on port 18082 and dashboard on port 18083 for validation.

## Assumptions

- A refresh should preserve a session in the current browser tab; closing the tab should clear it through normal `sessionStorage` lifetime.
- Session material must not include or retain the password.
- The bottom account card opens upward; an account control near the top would open downward.
- Existing user changes and the completed task `210-dashboard-interaction-upgrade.md` remain untouched except for this additive follow-up.

## Work Items

- [x] Inspect the current shell and reproduce logout on refresh in the signed-in local dashboard.
- [x] Implement tab-scoped session persistence and restoration with invalid-session cleanup.
- [x] Refine typography, local icon usage, and account-popover markup/placement.
- [x] Review the combined change for selector, accessibility, and behavior regressions.
- [x] Rebuild the local dashboard image and validate refresh, account actions, icons, and targeted checks.

## Validation

Completed checks:

- `node --check dashboard/app.js` passed.
- `python3 -m unittest dashboard.test_serve` passed: 10 tests.
- Local dashboard rebuilt and reseeded via `sh scripts/local-dashboard.sh up`; named volumes were preserved.
- `http://127.0.0.1:18083/` and control-plane health on `http://127.0.0.1:18082/healthz` returned 200.
- Redacted real local auth check passed: login 200 with both session fields and `auth/me` 200 with one profile.
- Served dashboard markers confirmed the updated login copy, account popover, dynamic placement hook, and session restoration code.
- All 20 referenced dashboard icons exist locally; new icons match the provided template assets and no external icon dependency was introduced.
- The pre-change signed-in browser tab reproduced the refresh logout; post-change browser login was not automated because entering the password into Chrome requires action-time confirmation. The deployed UI is ready for the user’s normal sign-in/refresh check.

## Next Action

Open `http://127.0.0.1:18083/`, sign in normally, and refresh once to confirm the tab-scoped restore in the user’s browser session.

## Blockers

None.

## Outcome

Completed. The dashboard now restores authenticated state across reloads within the browser tab, keeps sign out inside the location-aware account popover, uses the supplied local icons, reduces heavy type weights, and keeps the requested 0.5px field/focus borders.

## References

- User-provided dashboard screenshots and UX transcript.
- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/styles.css`
- `dashboard/icons/`
- `/Volumes/970EvoPlus/Development/templates/icons`
- `tasks/210-dashboard-interaction-upgrade.md`

## History

- 2026-09-01: Reserved task 211 after reproducing the refresh logout in the user’s signed-in dashboard tab.
- 2026-09-01: Delegated auth and shell packages to Luna Max workers, reviewed the combined change, rebuilt the local Docker stack, and completed targeted validation.
