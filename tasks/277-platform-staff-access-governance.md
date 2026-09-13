# Task 277 - Platform staff access governance

Status: [x] Completed

## Goal

Expose only server-authorized, auditable platform staff access operations to
the Platform Console, with role selection and reviewed/cool-off handling for
privilege changes.

## Scope and Non-goals

Scope:

- extend the existing human-auth/platform projection and HTTP boundary for
  staff lifecycle operations;
- durable role-derived access review records with reason and audit evidence;
- protected staff invitation/role mutation seams required by the existing
  Platform Console client;
- explicit authorization and maker/checker safeguards;
- focused tests and operator documentation.

Non-goals:

- a generic workflow engine;
- arbitrary browser-supplied capability grants;
- changing customer membership/tenant authorization;
- replacing the existing audit or persistence systems;
- modifying `main` directly.

## Owner

Coordinator: Hyfens engineering; control-plane implementation owner is the
assigned specialist worker.

## Dependencies

- existing `HumanAuthService`, `ControlPlaneStore`, and audit chain;
- current platform capability constants and allowlist model;
- Cloud Platform Console task 265;
- current platform operations authorization boundary.

## Assumptions

- platform access is role-derived from a fixed supported role catalogue;
- changes that grant or expand access require explicit review and a bounded
  configured cool-off period;
- the bootstrap super-admin remains the initial authority and no customer
  identity can self-escalate.

## Work Items

- [x] Audit current platform user projection and active HTTP routes.
- [x] Define fixed staff roles and role-to-capability projection.
- [x] Add durable invitation/access-review operations with reason capture,
  approval, cool-off, and audit events.
- [x] Enforce server-side authorization and cross-tenant/actor safeguards.
- [x] Add contract/security/concurrency tests and documentation.

## Validation

Completed:

- `dart analyze lib test`;
- `dart test test/platform_staff_http_test.dart test/platform_operations_http_test.dart test/platform_metrics_http_test.dart`;
- Cloud client typecheck/lint/build and platform route/edge contract tests;
- `git diff --check`.

Evidence:

- fixed managed staff roles derive capabilities server-side;
- invitations and access changes are durable, reason-bound, idempotent,
  maker/checker protected, and subject to cool-off before application;
- staff sessions are revoked through the platform-audience boundary only;
- customer memberships cannot authorize platform staff routes; and
- the focused control-plane and paired Cloud validation commands passed.

## Next Action

Protected deployment and operator smoke acceptance through the existing
managed process.

## Blockers

None currently.

## Outcome

Completed. The Platform Console now has a truthful staff projection and the
control plane owns role, review, cool-off, idempotency, and authorization
semantics without introducing a second workflow or authorization model.

## References

- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/platform_console.dart`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/persistence.dart`
- `apps/web/src/lib/platform-client.ts`
- `tasks/265-platform-console-access-and-error-surfaces.md`

## History

- 2026-09-13 - Reserved after audit found the Cloud client advertising staff
  mutations that the active control plane did not implement, while the
  platform identity model still only supported the bootstrap owner.
- 2026-09-13 - Implemented and validated the fixed-role staff governance
  contract, durable invitations and access reviews, maker/checker approval,
  cool-off processing, session revocation, and HTTP authorization boundary.
