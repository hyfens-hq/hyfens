# Task 255 — Public Cloud self-service onboarding

Status: [x] Completed

## Goal

Allow an unaided developer to create a Hyfens Cloud account, receive a new
organization with an explicit Free plan, create the first application and
environment, and obtain a usable CLI scope without maintainer intervention.

## Scope and Non-goals

Scope:

- replace the fixed-organization public client registration seam with a safe
  customer-account and organization-creation flow;
- assign Free transactionally and idempotently during Cloud organization
  creation;
- create the initial owner membership with the capabilities required by the
  supported first-application workflow;
- expose organization/application/environment selection to the dashboard and
  CLI; and
- preserve organization isolation, auditability, rate limits, and retry safety.

Non-goals:

- changing Cloud prices, plan boundaries, or metering;
- weakening release-integrity checks;
- allowing Self-hosted deployments to create Cloud subscriptions; and
- building a general identity, email, or billing platform beyond the existing
  seams required for this journey.

## Owner

Codex

## Dependencies

- Tasks 248–254.
- `ControlPlaneService.bootstrap`, `BillingService.ensureCloudPlanAssignment`,
  `HumanAuthService`, and the existing customer dashboard/CLI contracts.
- Approved onboarding policy from the execution request: verified email,
  bounded single-use recovery, customer-owned organization, and internal Free
  provisioning.
- Task 259 remains responsible for wiring production email delivery/configuration.

## Assumptions

- The public `registerClient` route is not an acceptable Cloud signup model:
  it currently attaches a read-only client to one server-selected tenant.
- The organization remains the Cloud subscription owner.
- The same organization and data must survive future Starter and Team upgrades.
- Organization names are display names in the current domain model; immutable
  organization IDs remain the isolation and idempotency keys.
- The managed fixture may inject the existing auth-message delivery seam for
  acceptance tests; production delivery is intentionally outside this task.

## Work Items

- [x] Define the public account, organization, owner, and first-scope API
  contract.
- [x] Implement transactional, retry-safe organization and Free provisioning.
- [x] Grant only the intended initial-owner capabilities and record the audit
  events.
- [x] Add dashboard and CLI scope-selection/onboarding behavior.
- [x] Add focused tests for isolation, retries, Free assignment, and owner
  access.
- [x] Validate the complete unaided onboarding path against a managed Cloud
  fixture.

## Validation

Completed:

- `dart analyze` in `packages/control_plane`;
- focused control-plane onboarding/auth/plan tests: 30 passed;
- `dart analyze` and focused CLI profile/onboarding/process tests: 21 passed;
- dashboard JavaScript syntax/auth-flow tests: 4 passed;
- dashboard proxy tests: 35 passed;
- Python compilation and `git diff --check`; and
- manual browser-to-CLI acceptance against a managed local Cloud fixture:
  register, verify, receive Free, create application, create environment,
  authenticate CLI, and bind organization/application/environment without
  database edits, admin credentials, or Razorpay.

## Next Action

Task 259: configure the production email delivery provider and its operational
secrets. Task 256 separately owns production deployment/cutover.

## Blockers

None within Task 255. Production email delivery/configuration remains a
Task 259 dependency, and production cutover remains Task 256 scope. The
managed-fixture acceptance used the existing injected message-delivery seam.

## Outcome

Implemented. Public Cloud onboarding now uses a distinct human/customer flow:
registration creates an unverified identity, verification provisions a
customer-owned organization, owner membership, and internal Free assignment,
then returns a customer session. A verified identity with no membership can
resume provisioning through the authenticated organization endpoint after a
recoverable partial failure. The legacy `POST /v1/public/register` route is
preserved as a separate fixed-organization read-only client flow.

The dashboard supports verification, recovery, first-workspace continuation,
the first application/environment empty states, and actionable plan-limit
errors. The CLI can authenticate as the customer and persist explicit
organization/application/environment context without storing secrets in the
profile.

## References

- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `dashboard/app.js`
- `dashboard/serve.py`
- `dashboard/test_serve.py`
- `cli/lib/src/auth_command.dart`
- `cli/test/profile_cli_test.dart`
- `docs/getting-started.md`
- `docs/cli.md`
- `docs/product/customer-workspace.md`
- `packages/control_plane/test/customer_onboarding_test.dart`
- `tasks/254-cloud-commercial-launch-readiness-audit.md`

## History

- 2026-09-07: Created from the Task 254 P0 finding that public registration
  cannot create a Cloud organization or provision a usable Free workspace.
- 2026-09-07: Implemented verified customer registration, recovery, customer
  organization provisioning, internal Free assignment, owner scoping, audit
  events, dashboard onboarding/continuation, CLI resource binding, isolation
  and idempotency tests, and managed-fixture browser-to-CLI acceptance. The
  production email provider remains intentionally deferred to Task 259.
