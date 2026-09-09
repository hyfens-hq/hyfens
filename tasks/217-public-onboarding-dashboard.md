# Task 217: Public onboarding dashboard UI

Status: [x] Completed

## Goal

Give unauthenticated visitors a clear registration path for a client account plus lightweight waitlist/newsletter forms, using the control-plane API without requiring manual endpoint editing in the local Docker deployment.

## Scope and Non-goals

Scope:

- Add a sign-up view reachable from sign-in with email, password, and confirmation fields.
- Connect the form to the task 216 registration contract and establish the returned session through the existing dashboard session flow.
- Add waitlist and newsletter intake controls with success/error/duplicate-safe messaging.
- Reuse existing icon assets and dashboard styling conventions; keep typography readable and control borders/focus states consistent with the current UI.
- Keep the API base derived from the configured dashboard metadata by default.

Non-goals:

- Redesigning authenticated dashboard pages or changing existing navigation/data permissions.
- Exposing organization selectors, role selectors, or administrative intake management.
- Adding external email-provider SDKs or client-side persistence of passwords.

## Owner

Coordinator: Codex. Implementation owner: delegated `gpt-5.6-luna` worker, max reasoning, priority/fast service tier. The worker owns only dashboard files listed in Work Items and must not alter control-plane source.

## Dependencies

- Task 216 must define and validate the public API contract first.
- Task 215 dashboard typography and Docker cache-busting baseline.
- Existing `dashboard/auth-flow.js` and `DashboardApi` session behavior.

## Assumptions

- Registration route is `POST /v1/public/register` with `{email,password}` and returns the existing login/session JSON.
- Intake routes are `POST /v1/public/waitlist` and `POST /v1/public/newsletter` with `{email}` plus optional bounded `name`/`source`, returning a stable success status for new and duplicate submissions.
- Local Docker serves the dashboard and control plane on the configured metadata endpoint; the UI should not force users to type `http://127.0.0.1:18082/`.

## Work Items

- [x] Add accessible sign-in/sign-up switching and client registration form states.
- [x] Wire registration to the existing API/session flow and route successful users into the authenticated app.
- [x] Add waitlist/newsletter forms and feedback states without leaking credential or PII details.
- [x] Use existing `/dashboard/icons` assets for new icon buttons and status affordances; preserve the current icon loading contract.
- [x] Add/update focused dashboard contract tests and version static assets as needed for Docker/browser cache correctness.

## Validation

Completed checks:

- `node --check dashboard/app.js` — passed.
- `python3 -m unittest dashboard.test_serve` — 16 tests passed.
- `dart analyze` and focused control-plane tests — passed; 19 tests passed.
- `sh -n scripts/local-dashboard.sh` and Docker Compose config validation — passed.
- Rebuilt the canonical local dashboard/control-plane images and confirmed all four stack services are healthy.
- Live API smoke tests passed for registration, duplicate registration, client overview access, waitlist, newsletter, and login.
- Live browser smoke tests passed for Create account, automatic session establishment, logout, waitlist submission, and product-updates submission.
- Served HTML contains the versioned `tokens.css?v=217`/`styles.css?v=217` assets plus the registration and intake forms.

## Next Action

No further action is required within this task. Optional future work is email verification, delivery-provider integration, and an authenticated intake-management view.

## Blockers

None currently.

## Outcome

Implemented the public onboarding experience. Visitors can create a client account without entering an API endpoint, are signed in immediately on success, and can submit idempotent waitlist or product-update requests. The dashboard uses the configured control-plane metadata and bounded fixed proxy routes.

## References

- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/auth-flow.js`
- `dashboard/styles.css`
- `dashboard/test_serve.py`
- `dashboard/Dockerfile`

Validation evidence:

- `node --check dashboard/app.js` — passed.
- `python3 -m unittest dashboard.test_serve` — 16 tests passed.
- `dart analyze` — passed with no issues.
- Focused control-plane tests — 19 tests passed.
- `sh -n scripts/local-dashboard.sh` and Docker Compose config validation — passed.
- Local Docker/browser/API smoke tests — passed on `127.0.0.1:18083` dashboard and `127.0.0.1:18082` control plane.

## History

- 2026-09-01: Reserved as the dashboard-only package dependent on task 216.
- 2026-09-01: Integrated the dashboard worker handoff, reviewed the bounded routes and UI bindings, rebuilt Docker, and passed live browser/API onboarding checks.
