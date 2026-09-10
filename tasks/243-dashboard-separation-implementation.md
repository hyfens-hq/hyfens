# Dashboard Separation Implementation

Status: [x] Completed

## Goal

Implement the bounded dashboard separation milestone: explicit Customer Workspace and Hyfens Platform Console shells, shared authentication/API/UI infrastructure, an explicit platform audience contract, and the minimum platform/customer read and credential/member foundations required by the approved separation plan.

## Scope and Non-goals

Scope:

- Split the current static dashboard into explicit customer and platform entry/shell modes without introducing a frontend framework.
- Preserve and reuse shared session, API transport, error, token, formatting, and UI primitives.
- Move tenant-scoped customer routes into the Customer Workspace and platform metrics into the Platform Console.
- Add bounded platform organization listing/detail projections and explicit platform authorization.
- Add the minimum customer credential/member foundations only where existing backend contracts support them.
- Separate customer/platform settings and audit concepts in route/navigation copy and documentation.
- Update architecture/product documentation and create `docs/HYFENS_DASHBOARD_SEPARATION_IMPLEMENTATION_REVIEW.md`.
- Add focused tests for audience boundaries, tenant isolation, routing, shell navigation, and credential secrecy.

Non-goals:

- No React/Next/Vue/Svelte or other framework migration.
- No production DNS changes, public deployment, or repository changes.
- No enterprise SSO/SCIM, advanced support impersonation, full billing, advanced incidents, or multi-region operations.
- No arbitrary cross-tenant data access or customer-session impersonation.
- No changes to the Patch Format, runtime trust boundary, CLI architecture, or release tags.
- No deletion or reset of unrelated working-tree changes.
- No Task 210 or additional microtask generation.

## Owner

Coordinator — dashboard separation architecture and integration

## Dependencies

- `docs/HYFENS_DASHBOARD_SEPARATION_AUDIT.md`
- Current static dashboard under `dashboard/`
- Current control-plane HTTP/auth/service modules under `packages/control_plane/`
- Existing dashboard and control-plane tests
- Existing managed/self-hosted profile and discovery contracts

## Assumptions

- `app.hyfens.com` remains the Customer Workspace host concept.
- `platform.hyfens.com` is the Platform Console host concept; DNS is out of scope for this task.
- Managed Cloud and Self-Hosted use one Customer Workspace information architecture with capability-driven differences.
- Existing tenant overview and platform metrics projections are preserved and not broadened for convenience.
- Platform APIs will fail closed for customer sessions and customer APIs will remain tenant-scoped.
- Existing unrelated dirty changes belong to the user and must remain untouched.

## Work Items

- [x] Freeze shared audience, route, and authorization contracts.
- [x] Add explicit platform audience/capability authorization and bounded platform organization projections.
- [x] Split dashboard entry points, shells, navigation, context models, and route guards.
- [x] Rehome customer pages and separate settings/audit/credential/member concepts.
- [x] Add focused backend/frontend regression tests for audience and tenant boundaries.
- [x] Update domain/product/architecture documentation and implementation review.
- [x] Run consolidated validation, review the task-owned diff, and record outcome.

## Validation

- `dart format lib/src/human_auth.dart test/human_auth_test.dart` — PASS.
- `dart analyze .` from `packages/control_plane` — PASS.
- Focused control-plane tests (`human_auth_test.dart`, `platform_metrics_http_test.dart`, `demo_seed_test.dart`) — PASS, 9 tests.
- `python3 -m unittest dashboard.test_serve` — PASS, 34 tests.
- `node --check dashboard/app.js`, `dashboard/auth-flow.js`, and `dashboard/test_auth_flow.js` — PASS.
- `node --test dashboard/test_auth_flow.js` — PASS, 4 tests.
- `git diff --check` — PASS.
- Full `dart test` — 262 completed, 34 skipped for unavailable PostgreSQL/S3/process environments, and 16 unrelated pre-existing reconciliation/P3E applicability failures involving expired test credentials/CAS expectations; no separation-focused failure.
- Browser visual/runtime capture — unavailable because no browser environment was exposed; static route serving and markup contracts passed. Production DNS/deployment validation was not run by scope.

## Next Action

No further implementation action in this task. Production DNS/deployment and the explicitly listed capability backlog require separate authorization.

## Blockers

None currently.

## Outcome

Implemented with backlog. Customer Workspace and Platform Console are separate
logical shells and route/audience models over shared auth, transport, UI, and
formatting infrastructure. Platform projections fail closed for customer
sessions; customer member projections exclude platform-audience memberships.
No production DNS or deployment changes were made.

## References

- `docs/HYFENS_DASHBOARD_SEPARATION_AUDIT.md`
- `dashboard/index.html`
- `dashboard/app.js`
- `dashboard/serve.py`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/operator_overview.dart`
- `packages/control_plane/lib/src/platform_metrics.dart`
- `docs/architecture/control-plane.md`

## History

- 2026-09-03 — Reserved task 243 for the authorized dashboard separation implementation; scope frozen to two shells, shared infrastructure, bounded authorization/projections, and required acceptance evidence.
- 2026-09-03 — Implemented explicit customer/platform shells, route topology, audience-bound control-plane projections, customer settings foundations, focused negative tests, and architecture/review documentation. Final focused validation passed; unrelated full-suite failures and unavailable integration environments were recorded as non-blocking.
