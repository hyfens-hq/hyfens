# Task 73 — P3E5-5D periodic reconciliation runner

Status: [x] Completed

## Goal

Add an explicitly enabled, bounded, non-overlapping in-process periodic
reconciliation runner that invokes the existing bounded reconciliation service
and preserves the established authority, audit, CAS, fairness, and
observability boundaries.

## Scope and Non-goals

In scope: validated runner configuration, interval/jitter/startup delay,
single-process overlap exclusion, startup/manual coexistence, PostgreSQL
single-runner advisory-lock ownership, File single-process behavior, bounded
backoff, outage/recovery, graceful shutdown, crash/restart semantics, runner
metrics and read-only diagnostic status, and evidence documentation.

Out of scope: repair logic, detector or CAS changes, queues, Redis,
distributed/provider schedulers, alerts, dashboards, rollout writers, P3A or
P3E-4 mutation calls, P3E5-5E, P3F/P3G, runtime/mobile/compiler changes,
provider deployment, and production/store/privacy/legal claims.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 70/71 bounded reconciliation execution and PostgreSQL persistence.
- Task 72 metrics, readiness, diagnostics, and exact-scope boundaries.
- Explicit authorization in `CODEX_P3E5_5D_PERIODIC_RUNNER.md`.

## Assumptions

- The runner invokes an already-constructed `BoundedReconciliationService`;
  it does not discover candidates or perform repairs itself.
- PostgreSQL advisory-lock ownership is process coordination only and never a
  rollout or repair authority.
- File deployments remain one process and one writer.
- Process-local runner state is intentionally non-durable; persisted findings,
  attempts, lifecycle, and cursor state remain authoritative.

## Work Items

- [x] Reserve Task 73 and define the bounded runner boundary.
- [x] Add validated disabled-by-default runner configuration and lifecycle.
- [x] Add local execution exclusion and PostgreSQL advisory-lock ownership.
- [x] Add bounded jitter, backoff, overlap handling, shutdown, and recovery.
- [x] Integrate runner metrics and read-only diagnostic status.
- [x] Add File, PostgreSQL, contention, handoff, outage, fairness, malformed,
  audit, CAS, and restart tests.
- [x] Update design/ADR/review documentation with factual evidence.
- [x] Run consolidated package/root/migration/documentation validation and
  stop at maintainer review.

## Validation

Executed: scoped formatting and analysis; runner configuration/lifecycle tests;
File runner tests; PostgreSQL runner-lock, contention, handoff, bounded
failure, fairness/CAS/audit preservation, malformed, and restart tests;
existing reconciliation/observability suites; full control-plane tests with
PostgreSQL; root analysis/tests; the package migration regression; Markdownlint,
local links, whitespace, secret, and prohibited-scope scans.

## Next Action

Stop at the maintainer-review gate. Do not begin P3E5-5E or any prohibited
infrastructure or product work.

## Blockers

None known at task start.

## Outcome

Task 73 is complete for its bounded engineering scope. The runner is
disabled-by-default, uses the existing bounded reconciliation service, and
stops at the maintainer-review gate. The final recommendation is
`PROCEED TO P3E5-5E WITH CONDITIONS`; P3E5-5E is not authorized by this task.

Validation evidence:

- package `dart analyze . --fatal-infos` — PASS;
- focused periodic suite with local PostgreSQL — PASS, 15 tests;
- focused periodic/observability/HTTP suites with local PostgreSQL — PASS, 26
  tests;
- full package `HYFENS_TEST_POSTGRES_URL=... dart test` — PASS, 263 tests, one
  explicit MinIO/S3 environment skip;
- root `dart analyze --fatal-infos` — PASS;
- root `dart test` — PASS, 1 test;
- `dart test test/migration_test.dart` in `packages/control_plane` — PASS, 1
  test;
- Markdownlint with MD013 disabled, local-link check, trailing-whitespace
  scan, high-confidence secret scan, and changed-source prohibited-scope scan
  — PASS.

The root migration path does not exist; the shipped migration test was run from
the owning control-plane package. No shell or Python source changed.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5D_PERIODIC_RUNNER.md`
- `docs/P3E5_5C_OBSERVABILITY_READINESS_REVIEW.md`
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`
- `docs/adr/0013-bounded-reconciliation-and-observability.md`

## History

- 2026-08-24 — Task 73 reserved under explicit authorization for P3E5-5D
  only. P3E5-5E and prohibited work remain unauthorized.
- 2026-08-24 — Implemented and validated the bounded periodic runner. A real
  PostgreSQL contention run exposed same-pool self-deadlock; the ownership
  session was isolated on a dedicated pool and contention/handoff, bounded
  failure, restart-cadence, File, metrics, diagnostics, and existing-service
  integration tests passed. Task stopped for maintainer review with the
  conditional P3E5-5E recommendation.
