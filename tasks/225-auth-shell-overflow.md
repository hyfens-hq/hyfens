# Task 225: Fix auth shell overflow and secondary rail

Status: [x] Completed

## Goal

Make login and registration feel like focused, two-pane access screens: keep their content inside the viewport with predictable panel scrolling, remove onboarding capture from the auth surface, eliminate duplicate input focus borders, and remove the unnecessary host label from the secondary rail.

## Scope and Non-goals

Scope:

- Contain desktop auth scrolling within the auth panes and preserve normal document scrolling on the single-column mobile layout.
- Make the auth panel fill its grid track so the shell reads as two panes rather than a form plus an empty third-looking column.
- Remove waitlist/newsletter controls and the related prompt from the login/register page while retaining the public intake API implementation for a future dedicated surface.
- Replace the auth input’s stacked focus outline and 3px ring with one 0.5px accent border.
- Remove the `app.hyfens.com` rail topline and bump the HTML/JavaScript asset versions.

Non-goals:

- No change to login, registration, public intake API contracts, session semantics, dashboard routes, or control-plane behavior.
- No new dependency, font-family change, or unrelated dashboard redesign.

## Owner

Coordinator.

## Dependencies

- Existing auth markup and responsive rules in `dashboard/index.html` and `dashboard/styles.css`.
- Existing guarded public-intake handlers in `dashboard/app.js`.
- Canonical local Docker dashboard stack.

## Assumptions

- Waitlist/newsletter remains a supported API capability but should not be embedded in authentication; a separate public page can expose it later.
- Desktop auth panes may scroll internally when a small viewport cannot fit the complete form, while mobile should retain one natural page scroll.
- The existing 0.5px border convention is the intended focus treatment.

## Work Items

- [x] Record the reproducible overflow, extra auth content, duplicate focus treatment, and wide-track panel regression.
- [x] Remove auth-page waitlist/newsletter UI and safely detach its optional handlers.
- [x] Fix the two-pane sizing, rail label, and responsive scroll containment.
- [x] Unify auth input focus states and update the focused contract/versioning.
- [x] Run source validation, rebuild Docker, and verify login/register/live layout behavior.
- [x] Record outcome and validation evidence.

## Validation

Completed:

- The pre-fix browser repro captured the 1799px register document against a 1323px viewport, the embedded waitlist/newsletter content, duplicate focus treatments, and the capped 680px panel inside a wider grid track.
- The post-rebuild browser check confirmed login and register render at 2560x1267 without document-level vertical overflow; the auth panel fills its 1382.39px grid track, no onboarding/waitlist/newsletter or `app.hyfens.com` copy is rendered, and focused inputs have no box shadow or outline.
- Responsive source rules preserve natural page scrolling below 700px while keeping desktop auth pane scrolling contained.
- `python3 -m unittest dashboard.test_serve` — 24 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh scripts/local-dashboard.sh up` — rebuilt/recreated the dashboard and completed the normal local seed step.
- Docker health check — dashboard on `18083`, control plane on `18082`, PostgreSQL, and object store all healthy.

## Next Action

No further action is required for this task.

## Blockers

None.

## Outcome

Implemented the focused two-pane auth shell, removed auth-page onboarding capture and the exposed host label, contained desktop edge scrolling, preserved mobile document flow, and reduced focused inputs to a single accent hairline treatment. Public intake handlers remain available for a future dedicated surface.

## References

- User screenshots showing edge scrolling, duplicate focus borders, auth onboarding clutter, and the three-column-looking auth composition.
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/app.js`
- `dashboard/test_serve.py`

## History

- 2026-09-01: Reserved task 225 for auth-shell overflow, focus, and layout cleanup.
- 2026-09-01: Reproduced the register-flow regression on the running local dashboard: document height 1799px versus a 1323px viewport, waitlist/newsletter content present, duplicate focus styles present, and the 680px panel inside a 1374px grid track.
- 2026-09-01: Removed the auth waitlist/newsletter UI and rail host topline, guarded the optional intake handlers, changed the auth shell to bounded desktop panes with natural mobile flow, and unified focus styling.
- 2026-09-01: Rebuilt the canonical local Docker stack, bumped the stylesheet to `styles.css?v=226`, and verified the live login/register layout plus source and container checks.
