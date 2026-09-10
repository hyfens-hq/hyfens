# Task 212: Dashboard header and icon rendering

Status: [x] Completed

## Goal

Make the deployed dashboard render its existing local icons and keep the desktop search/theme controls vertically aligned with the sidebar brand header.

## Scope and Non-goals

Scope:

- Include `dashboard/icons/` in the dashboard Docker image.
- Keep the desktop top bar controls on one aligned row, with the existing narrow-screen wrapping behavior preserved.
- Add a focused contract check for the image asset copy and the header rule.
- Rebuild the local dashboard and verify the served icon responses and affected shell checks.

Non-goals:

- No new icon family, remote asset dependency, or brand-mark redesign.
- No changes to authentication, account-menu behavior, routes, data views, or control-plane authority.
- No unrelated typography, spacing, or dashboard-content redesign.

## Owner

Coordinator with one disjoint Luna Max implementation worker for `dashboard/Dockerfile` and `dashboard/styles.css`.

## Dependencies

- Existing dashboard shell in `dashboard/index.html` and `dashboard/styles.css`.
- Existing local icon assets in `dashboard/icons/`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The existing source icon references are intentional and only need to be shipped by the image.
- Desktop top-bar controls should remain a single row; the existing mobile breakpoint may continue to wrap them.
- Existing uncommitted repository contents belong to the user and must remain untouched outside this task.

## Work Items

- [x] Reproduce the missing-icon response and inspect the current Docker/header rules.
- [x] Include local icons in the dashboard image and prevent unintended desktop top-bar wrapping.
- [x] Add focused source/asset contract coverage.
- [x] Review, rebuild, and validate the deployed dashboard.

## Validation

Completed checks:

- `python3 -m unittest dashboard.test_serve` passed: 11 tests.
- `node --check dashboard/app.js` passed.
- `sh scripts/local-dashboard.sh up` passed and rebuilt the dashboard image.
- All 21 unique referenced icon URLs returned `image/svg+xml` bodies beginning with `<svg`; the old pre-fix response was the SPA HTML fallback.
- Browser audit after reload found 25/25 icon elements loaded with no hidden icon elements.
- Desktop browser audit at 2560px found `.topbar-actions` computed as `nowrap`, with 72px top bar and sidebar headers.
- `http://127.0.0.1:18083/` and `http://127.0.0.1:18082/healthz` returned 200.
- Dashboard and control-plane containers are healthy; the dashboard container contains `/usr/share/nginx/html/icons/home_outline.svg`.

## Next Action

Open `http://127.0.0.1:18083/` after signing in normally and visually confirm the centered search/theme row alongside the sidebar brand header.

## Blockers

None.

## Outcome

Completed. The dashboard image now ships the existing local icon set, and desktop header controls remain on one centered row so the search field and theme control align with the sidebar brand header. Mobile wrapping remains unchanged at the existing breakpoint.

## References

- User-provided dashboard screenshots and header/icon feedback.
- `dashboard/Dockerfile`
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/icons/`
- `tasks/211-dashboard-session-shell-polish.md`

## History

- 2026-09-01: Reserved task 212 after the live dashboard audit confirmed missing local icons resolve to the HTML fallback and desktop top-bar controls can wrap inside the compact sticky header.
- 2026-09-01: Added the icon image copy, desktop no-wrap rule, and focused contract coverage; rebuilt the local stack and completed source, browser, asset-response, and health validation.
