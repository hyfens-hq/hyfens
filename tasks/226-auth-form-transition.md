# Task 226: Smooth auth form transition

Status: [x] Completed

## Goal

Switch between sign-in and create-account forms without changing the auth shell’s layout height or causing a jarring centered-panel reflow.

## Scope and Non-goals

Scope:

- Keep the auth form region at a stable height while the two form states crossfade and move into place.
- Use an interruptible CSS transition with a short, professional duration and existing motion tokens.
- Preserve the current tab semantics, form visibility, focus behavior, and mobile layout.
- Respect `prefers-reduced-motion` by removing movement and retaining only a brief opacity change.

Non-goals:

- No changes to authentication requests, validation, session behavior, or form fields.
- No new animation dependency or broad dashboard motion redesign.
- No changes to the secondary rail, waitlist/newsletter API, or Docker topology.

## Owner

Coordinator.

## Dependencies

- Existing auth tab state in `dashboard/app.js`.
- Existing auth markup and motion tokens in `dashboard/index.html` and `dashboard/styles.css`.
- Existing dashboard contract tests and canonical local Docker stack.

## Assumptions

- The form switch is an occasional navigation action, so a restrained transition improves spatial continuity without delaying the user.
- The taller create-account form should determine the stable desktop form-region height; the shorter sign-in form can leave intentional breathing room during the transition.
- On small screens, the page should remain naturally scrollable and the stable region should not create unnecessary blank space.

## Work Items

- [x] Record the current form-height/layout shift and review the existing tab-switch implementation.
- [x] Add a stable form region and interruptible crossfade/translate transition.
- [x] Add reduced-motion and responsive behavior without changing auth semantics.
- [x] Add/update source contract coverage and run browser/source/Docker validation.
- [x] Record outcome and validation evidence.

## Validation

Completed:

- The pre-fix browser repro showed the login form at 365.2px and the create-account form at 485.9px, with the surrounding content moving when `hidden` toggled.
- The post-rebuild browser check confirmed a stable 485.9px form stage, unchanged panel/document heights, correct `aria-hidden`/`inert` states, and successful forward, reverse, and rapid tab switches.
- The transition is CSS-based and interruptible, using 220ms `opacity`/`transform`/`visibility` transitions; the existing reduced-motion block explicitly removes auth-form movement.
- `python3 -m unittest dashboard.test_serve` — 25 tests passed.
- `node --check dashboard/app.js` — passed.
- `sh scripts/local-dashboard.sh up` — rebuilt/recreated the dashboard and completed the local seed step.
- Docker health check — dashboard on `18083`, control plane on `18082`, PostgreSQL, and object store all healthy.

## Next Action

No further action is required for this task.

## Blockers

None.

## Outcome

Implemented a stable auth form stage that prevents layout reflow while switching modes. The active form crossfades and settles upward from an 8px offset, the inactive form is non-interactive and hidden from assistive technology, and reduced-motion users receive no movement.

## References

- User screenshot and report that clicking Sign in/Create account changes form height and feels abrupt.
- `dashboard/index.html`
- `dashboard/styles.css`
- `dashboard/app.js`
- `dashboard/test_serve.py`

## History

- 2026-09-01: Reserved task 226 for the auth form-switch transition.
- 2026-09-01: Reproduced the intrinsic-height shift and added a red regression contract before changing the auth switch seam.
- 2026-09-01: Added the stacked auth form stage, accessible `aria-hidden`/`inert` state management, 220ms interruptible motion, and reduced-motion handling.
- 2026-09-01: Rebuilt Docker and verified the live transition states; 25 source tests and JavaScript syntax validation passed.
