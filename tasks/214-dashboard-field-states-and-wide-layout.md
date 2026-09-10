# Task 214: Dashboard field states and wide layout

Status: [x] Completed

## Goal

Make collection filters use consistent hairline borders across normal, hover, and focus states, remove the duplicate heavy focus ring, and let the dashboard use more of a wide desktop viewport.

## Scope and Non-goals

Scope:

- Render collection input/select borders as visual `0.5px` inset hairlines instead of browser-clamped borders.
- Keep the existing accent focus treatment but remove the duplicate global `2px` outline from collection controls.
- Increase the desktop content width cap so wide dashboard pages do not sit in an overly narrow centered column.
- Preserve mobile stacking, collection filtering/sorting behavior, and all existing routes/data.
- Add focused regression coverage and redeploy the local dashboard.

Non-goals:

- No changes to API behavior, authentication, data fetching, filtering logic, or navigation.
- No new CSS framework, component library, or icon changes.
- No redesign of collection content or unrelated dashboard cards.

## Owner

Coordinator with one disjoint Luna Max implementation worker for `dashboard/styles.css`; coordinator owns `dashboard/test_serve.py`, task evidence, and integration review.

## Dependencies

- Existing dashboard collection toolbar and responsive styles in `dashboard/styles.css`.
- Existing dashboard contract tests in `dashboard/test_serve.py`.
- Local dashboard Docker service on `127.0.0.1:18083`.

## Assumptions

- The red focus ring in the screenshot is the global `:focus-visible` outline layered over the collection control’s custom focus treatment.
- A `0.5px` inset shadow is the appropriate visual hairline because Chromium clamps the declared border width to `1px`.
- A `1760px` desktop content cap improves wide-screen density without removing readable margins; mobile width remains fluid.
- Existing uncommitted repository contents belong to the user and must remain untouched outside this task.

## Work Items

- [x] Reproduce the field and wide-layout symptoms with a live browser/CSS audit.
- [x] Implement collection hairlines, focus-state cleanup, and the wider desktop content cap.
- [x] Add focused source contract coverage.
- [x] Review, rebuild, and validate the deployed dashboard.

## Validation

Completed checks:

- The new contract was red before the CSS fix and passed after implementation.
- `python3 -m unittest dashboard.test_serve` passed: 13 tests.
- `node --check dashboard/app.js` passed.
- `sh scripts/local-dashboard.sh up` passed and rebuilt/restarted the local dashboard image.
- Live signed-in patches view confirmed the collection field uses a `0px` browser border with a `0.5px` inset hairline and the desktop content width computes to `1760px` at a 2560px viewport.
- Served CSS contains the collection focus `outline: none` override, accent inset hairline, hover hairline, and 1760px content cap.
- `http://127.0.0.1:18083/` and `http://127.0.0.1:18082/healthz` returned 200.
- Dashboard, control-plane, Postgres, and object-store containers are healthy.

## Next Action

Open the patches page in the dashboard for any final visual comparison at another viewport size.

## Blockers

None.

## Outcome

Completed. Collection controls now render consistent visual hairlines in normal, hover, and focus states without the duplicate heavy focus outline. Wide desktop dashboard content uses a 1760px cap while responsive behavior remains intact.

## References

- User-provided screenshots showing thick collection-field normal/hover/focus borders and excessive wide-screen whitespace.
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/index.html`
- `tasks/213-dashboard-account-workspace-header-polish.md`

## History

- 2026-09-01: Reserved task 214 after reproducing the browser-clamped field borders, duplicate focus outline, and narrow 1440px content cap.
- 2026-09-01: Added collection hairlines and focus cleanup, widened the desktop content cap, updated contract coverage, rebuilt the stack, and passed live signed-in validation.
