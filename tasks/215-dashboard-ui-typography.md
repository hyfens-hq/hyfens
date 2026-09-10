# Task 215: Dashboard UI typography

Status: [x] Completed

## Goal

Reduce the heavy visual weight of the dashboard's dense UI while preserving the stronger Hyfens display treatment where it supports hierarchy, and verify that the apparent top strip is not an app-level layout offset.

## Scope and Non-goals

Scope:

- Use a lighter, neutral UI typeface for dashboard body text, navigation, controls, labels, and metadata.
- Keep Bricolage Grotesque available for the brand lockup and page headings where its distinctive display character is useful.
- Reduce only the dense-interface weight choices that contribute to the heavy feel.
- Version the static CSS URLs so a refreshed document fetches the current typography tokens instead of retaining a prior cached stylesheet.
- Preserve the current sidebar/header geometry unless live evidence shows an app-level offset.
- Add focused source-contract coverage and redeploy the local dashboard.

Non-goals:

- No browser theme or browser chrome changes.
- No changes to authentication, data fetching, navigation, icons, layout dimensions, or API behavior.
- No new font package or local asset dependency; use the existing web-font loading convention.
- No broad content rewrite or unrelated visual cleanup.

## Owner

Coordinator with one disjoint Luna Max implementation worker for `dashboard/tokens.css` and `dashboard/styles.css`; coordinator owns `dashboard/test_serve.py`, task evidence, and integration review.

## Dependencies

- Existing typography tokens in `dashboard/tokens.css`.
- Existing dashboard typography and component rules in `dashboard/styles.css`.
- Existing dashboard contract tests in `dashboard/test_serve.py`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The brown strip in the supplied crop is browser chrome because the live app viewport and `.sidebar-header` both begin at `y=0`.
- IBM Plex Sans is an acceptable lighter UI companion because IBM Plex Mono is already used by the dashboard and the UI needs a neutral, readable sans face.
- Bricolage Grotesque remains useful for display hierarchy and the brand, but should not be the global dense-UI face.
- Existing uncommitted repository contents belong to the user and must remain untouched outside this task.

## Work Items

- [x] Audit the live shell geometry, computed fonts, and font loading state; reserve task 215.
- [x] Implement a UI/display font split and soften dense UI weights without changing page structure.
- [x] Ensure refreshed documents load the current static typography assets.
- [x] Add focused source-contract coverage for the typography roles.
- [x] Review, rebuild, and validate the deployed dashboard.

## Validation

Completed checks:

- The new typography contract was red before the font-role implementation and passed after the implementation.
- `python3 -m unittest dashboard.test_serve` passed: 14 tests.
- `node --check dashboard/app.js` passed.
- `sh scripts/local-dashboard.sh up` passed after the final typography and asset-version changes.
- Served `index.html?audit=215b` contains `tokens.css?v=215` and `styles.css?v=215`.
- The fresh signed-in browser document computed IBM Plex Sans for body, navigation, and buttons, and Bricolage Grotesque for headings and the brand; both fonts reported loaded.
- The live app viewport, sidebar, and sidebar header all computed `y=0`; the brown strip in the supplied crop is outside the app viewport and was not reproduced by dashboard CSS.
- `http://127.0.0.1:18083/` and `http://127.0.0.1:18082/healthz` returned 200.
- Dashboard, control-plane, Postgres, and object-store containers are healthy.

## Next Action

No further action is required within this task. The refreshed local dashboard is available at `http://127.0.0.1:18083/`.

## Blockers

None.

## Outcome

Completed. Dashboard dense UI now uses IBM Plex Sans with softened navigation and button weights, while Bricolage Grotesque remains on headings and the brand. Versioned stylesheet URLs ensure refreshed documents receive the current typography tokens. The shell remains flush to the top of the app viewport; the supplied brown strip is browser chrome.

## References

- User-provided crop showing the brown strip above the Hyfens brand row and the request for a lighter dashboard font.
- `dashboard/tokens.css`
- `dashboard/styles.css`
- `dashboard/index.html`
- `dashboard/test_serve.py`
- `tasks/214-dashboard-field-states-and-wide-layout.md`

## History

- 2026-09-01: Reserved task 215 after live inspection showed the app viewport and sidebar header begin at `y=0`, while body, navigation, and headings all compute to Bricolage Grotesque.
- 2026-09-01: Added the IBM Plex Sans UI/display font split, softened dense UI weights, added typography and stylesheet-version contracts, rebuilt the local stack, and passed fresh-document browser validation.
- 2026-09-01: Initial post-rebuild browser audit found a stale cached `tokens.css`; versioned both CSS URLs and verified the fresh page computes the intended font roles.
