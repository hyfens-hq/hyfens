# Task 74 — P3E5-5E crash and lock-loss resilience

Status: [x] Completed

## Goal

Use disposable local integration infrastructure to prove that abrupt runner
process loss, PostgreSQL ownership-session loss, persistence-session loss, and
restart do not create duplicate semantic repair, stuck periodic ownership,
unsafe restart behavior, audit bypass, cursor corruption, or tenant-scope
loss in the existing P3E5-5D runner and Task 70/71 reconciliation seams.

## Scope and Non-goals

In scope: a test-only external process-kill harness; kill-before-mutation and
kill-after-CAS recovery; observable audit and persistence boundaries; real
PostgreSQL advisory-session termination; two-process local handoff; File
crash/restart; restart cadence, fairness, tenant isolation, malformed and audit
tamper behavior; metrics/readiness/diagnostics restart semantics; and evidence
documentation.

Out of scope: changing repair authority, CAS/idempotency semantics, rollout or
halt mutation, queues, Redis, persistent scheduler tables, provider HA or
deployment, alerts, dashboards, runtime/mobile/compiler work, physical
power-loss, beta/production/store/privacy/legal claims, or any new control
endpoint.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 70/71 bounded reconciliation execution and persistence.
- Task 72 observability/readiness/diagnostic seams.
- Task 73 disabled-by-default periodic runner and PostgreSQL ownership pool.
- Explicit authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5E_CRASH_LOCK_LOSS_RESILIENCE.md`.

## Assumptions

- The process harness is disposable and local; it is not provider HA or a
  production supervisor.
- Existing typed executor/CAS, audit-before-repair, exact scope, and durable
  persistence remain authoritative.
- PostgreSQL session termination is targeted only at the dedicated periodic
  ownership session.
- File persistence remains single-process/single-writer; a killed process
  releases its OS file lock and a restarted process may reopen the root.
- Process-local metrics, timestamps, and runner state may reset on restart;
  no false continuity will be fabricated.

## Work Items

- [x] Reserve Task 74 and freeze the integration-only boundary.
- [x] Add a bounded external Dart process-kill fixture and parent harness.
- [x] Prove kill-before-mutation, kill-after-CAS, audit boundaries, callback
  completion, restart cadence, and File crash/restart using durable state.
- [x] Prove PostgreSQL advisory ownership-session termination, lock release,
  two-process handoff, and persistence-session disconnect convergence.
- [x] Prove tenant isolation/fairness, malformed and audit-tamper fail-closed
  behavior, metrics/diagnostics restart semantics, and readiness preservation.
- [x] Run focused and consolidated package/root/migration/documentation/
  prohibited-scope validation.
- [x] Update the 5D factual addendum, design/ADR references, and the 5E review;
  stop at maintainer review.

## Validation

Completed validation:

- `dart format --output=none --set-exit-if-changed lib test` passed in
  `packages/control_plane` (73 files, 0 changed).
- `dart analyze . --fatal-infos` passed with no issues.
- The new crash-resilience suite passed all 10 tests.
- The full package run passed 273 tests with 1 explicit MinIO/S3 skip.
- Root analysis passed; root tests passed (1 test); migration regression passed
  (1 test).
- Markdownlint, local-link, trailing-whitespace, high-confidence secret, and
  targeted prohibited-dependency/import scans passed.

The package run used the disposable local PostgreSQL fixture through
`HYFENS_TEST_POSTGRES_URL`.

## Next Action

Stop at the maintainer-review gate. Do not begin the next P3E5 phase or any
provider-resilience work without explicit authorization.

## Blockers

None within the bounded Task 74 scope. Physical power loss, provider failover,
deployment/capacity, independent applications, mobile/store/privacy/legal,
beta, and production gates remain open and are not satisfied by this task.

## Outcome

The bounded local crash/lock-loss resilience slice is complete. The disposable
process harness verified kill-before and kill-after-CAS recovery, audit-boundary
replay, File restart, PostgreSQL ownership-session termination and two-process
handoff, persistence-session disconnect convergence, tenant isolation/fairness,
malformed-input and audit-tamper fail-closed behavior, and process-local
metrics/readiness reset semantics. One real defect was found and fixed: an
identical replay of an earlier reconciliation audit event incorrectly conflicted
with the later chain tail; replay now compares the immutable event body before
deriving a new tail link. An already-committed repair attempt also now rebuilds
the missing lifecycle projection without re-entering the executor after an
after-CAS crash. Recommendation: `PROCEED TO NEXT P3E5 PHASE WITH CONDITIONS`,
subject to maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5E_CRASH_LOCK_LOSS_RESILIENCE.md`
- `docs/P3E5_5D_PERIODIC_RUNNER_REVIEW.md`
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`
- `docs/adr/0013-bounded-reconciliation-and-observability.md`

## History

- 2026-08-24 — Task 74 reserved under explicit authorization for P3E5-5E
  only. Provider resilience, power-loss, and product/platform work remain
  unauthorized.
- 2026-08-24 — Implemented the disposable process/session-loss harness,
  recovery fixtures, and bounded reconciliation fixes; updated the 5D factual
  addendum, design/ADR references, and the 5E review.
- 2026-08-24 — Final validation passed: 273 package tests passed with 1
  explicit MinIO/S3 skip; the 10 new resilience tests passed; root analysis and
  test passed; migration regression passed; documentation and scope scans
  passed. Stopped at maintainer review as required.
