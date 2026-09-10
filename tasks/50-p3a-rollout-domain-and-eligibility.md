# Task 50 — P3A rollout domain and eligibility

Status: [x] Completed — bounded P3A implementation validated; maintainer review required

## Goal

Implement the smallest P3A slice authorized by the maintainer: typed rollout
records and immutable revisions, a fail-closed rollout state machine,
deterministic cohort/percentage eligibility, tenant-scoped control
authorization, audit integration, and rollout-aware runtime update lookup.

## Scope and Non-goals

Scope: add a pure-Dart rollout domain module; persist rollout records and
immutable revisions through the existing control-plane store; add explicit
control scopes and service methods for create/read/transition; validate exact
application/environment/release/patch/artifact ownership; evaluate
percentage/internal cohort eligibility from an app-install-scoped identifier;
and make existing `/v1/runtime/update-check` withhold candidates when an
active rollout says the installation is ineligible.

Non-goals: changing Architecture B, Patch Format v1, capability v1, exact
release/function binding, state-v4 high-water, runtime signature authority,
customer/local signing custody, artifact bytes, or rollback semantics; health
event ingestion; automatic halt; dashboard; alerting; billing; managed
KMS/HSM; SSO/SCIM; enterprise RBAC; React Native; store submission; provider
deployment; or percentage/cohort telemetry.

## Owner

Coordinator. No commit is authorized. Stop at the P3A maintainer-review gate.

## Dependencies

- `tasks/49-p2-exit-p3-design.md`;
- `docs/P2_EXIT_REVIEW.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- existing `packages/control_plane` domain, persistence, auth, audit, and
  runtime update-check implementation;
- maintainer decision: `AUTHORIZE P3 IMPLEMENTATION WITH CONDITIONS`.

## Assumptions

- P2 is accepted closed only for its bounded engineering scope; all listed
  readiness/provider/store gates remain open and are not relabelled by P3A.
- Existing generic JSON persistence is sufficient for the first local/self-
  hosted rollout records; no database migration is required for this slice.
- A missing installation identifier is safe to treat as ineligible whenever an
  active rollout exists, while update behavior remains unchanged when no
  rollout targets the request.
- The current control credential model is the authorization boundary for P3A;
  delivery credentials remain read-only and cannot mutate rollout state.
- The generic store interface provides immutable create and replacement but no
  cross-process compare-and-swap. Transition serialization and stale-revision
  rejection are therefore proven for one service instance; multi-process
  rollout conflict locking remains a follow-up before distributed operation.

## Work Items

- [x] Reserve Task 50 and record the explicit maintainer conditions.
- [x] Implement typed rollout target, policy, record, revision, snapshot,
  state, action, and eligibility models with canonical validation.
- [x] Persist immutable revisions and mutable current-state pointers through
  the existing store; reject stale/concurrent transitions and invalid target
  relationships.
- [x] Add least-privilege rollout control scopes, tenant/application/
  environment authorization, delivery-token denial, and audit events.
- [x] Integrate active rollout eligibility into update lookup without changing
  runtime trust decisions or artifact fetch verification.
- [x] Add unit, service, persistence, malformed-input, authorization,
  transition, determinism, monotonicity, and update-eligibility tests.
- [x] Run formatting, static analysis, focused tests, and the affected full
  control-plane suite; review the task-owned diff.
- [x] Stop at the P3A maintainer-review gate; do not begin health ingestion,
  automatic halt, dashboard, or subsequent P3 work.

## Validation

Planned scope:

- pure rollout-domain unit tests;
- FileControlPlaneStore service/integration tests for create, immutable
  revisions, transition preconditions, audit, tenant isolation, and lookup;
- malformed persisted rollout input and invalid policy/target tests;
- `dart format`, `dart analyze --fatal-infos`, focused package tests, and the
  full affected control-plane test suite.

No physical-device, provider, health-event, dashboard, or runtime bytecode
tests are expected: P3A changes control-plane eligibility only and does not
change the installed runtime or Patch Format.

Validation completed on 2026-08-23:

- `dart format packages/control_plane/lib/src/rollout.dart
  packages/control_plane/lib/src/service.dart
  packages/control_plane/lib/src/persistence.dart
  packages/control_plane/lib/src/domain.dart packages/control_plane/lib/src/http.dart
  packages/control_plane/lib/control_plane.dart
  packages/control_plane/test/rollout_test.dart
  packages/control_plane/test/rollout_service_test.dart` — passed.
- `dart analyze packages/control_plane` — no issues.
- `cd packages/control_plane && dart analyze --fatal-infos .` — no issues.
- `cd packages/control_plane && dart test test/rollout_test.dart
  test/rollout_service_test.dart` — 10 tests passed.
- `cd packages/control_plane && dart test` — 37 tests passed, 3 optional
  integration tests skipped because `HYFENS_TEST_S3_*` and
  `HYFENS_TEST_POSTGRES_URL` were not configured.
- `dart analyze .` — no issues.
- `dart test` — 1 repository bootstrap test passed.

The task-owned review checked that rollout policy only filters delivery lookup,
that Patch Format v1/runtime verification/high-water/signing/rollback code was
not changed, and that no health-ingestion, automatic-halt, dashboard, provider,
mobile, store, or legal claim was introduced.

## Next Action

Maintainer reviews the P3A state machine, cohort/percentage semantics,
authorization/audit boundary, and lookup behavior before authorizing any
health-event ingestion or later P3 slice.

## Blockers

The following remain open and binding: P1D-01 true power loss; P1D-03 iOS
diagnostics; P1D-04 iOS performance; P1D-07 independent application;
P1D-09 interpreter attribution; P1D-18 Apple/Google/legal review; provider
public edge/durability/HA/DR/secrets/provenance/monitoring/RPO/RTO gates; and
all beta/production claims.

## Outcome

P3A is implemented and validated as a bounded control-plane slice. Rollout
records and immutable revisions use a fail-closed lifecycle; percentage and
internal cohorts are deterministic; stale transitions and conflicting targets
are rejected; tenant/control scopes and audit events are enforced; and active
rollout eligibility gates update lookup without changing runtime trust. The
next health/automatic-halt/dashboard work is explicitly stopped for review.
Cross-process compare-and-swap is intentionally not claimed by this generic
store-backed slice and remains a prerequisite for distributed rollout writes.

## References

- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `docs/P2_EXIT_REVIEW.md`;
- `tasks/49-p2-exit-p3-design.md`;
- maintainer authorization supplied on 2026-08-23.

## History

- 2026-08-23: Reserved Task 50 after explicit maintainer authorization for
  P3 implementation with conditions. Scope is limited to P3A rollout domain,
  revisions, state transitions, deterministic eligibility, authorization,
  audit, and update lookup; health ingestion and later P3 slices remain
  prohibited until a new review.
- 2026-08-23: Implemented the typed rollout domain, filesystem persistence,
  immutable revision transitions, deterministic BigInt-backed unsigned
  64-bit cohorts, internal-to-canary promotion, tenant-scoped authorization,
  audit integration, and rollout-aware update lookup. Added focused service and
  malformed-input tests and completed the full control-plane validation; 3
  external integration tests remain skipped because their environments are not
  configured. Stopped at the maintainer-review gate; no later P3 work started.
