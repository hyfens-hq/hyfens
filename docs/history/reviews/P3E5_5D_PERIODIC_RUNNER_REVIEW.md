# P3E5-5D periodic reconciliation runner review

<!-- markdownlint-disable MD013 -->

Status: implementation complete; maintainer decision required

Date: 2026-08-24

Task: 73

## 1. Recommendation

Recommendation: `PROCEED TO P3E5-5E WITH CONDITIONS`

This closes the bounded P3E5-5D engineering slice only. The conditions are
that a maintainer separately authorizes P3E5-5E, the frozen authority model
remains unchanged, and the open provider, independent-application, mobile,
store, privacy, legal, beta, and production gates are not relabeled by this
runner work.

P3E5-5E is not started by this review.

## 2. Frozen authority model

The runner is orchestration only. It calls an existing
`BoundedReconciliationService` and does not discover candidates, interpret
findings, persist evidence, execute repairs, advance cursors, write lifecycle,
write rollouts, or apply automatic halts.

The following remain authoritative and unchanged:

- P3A is the rollout mutation authority.
- P3E-4 is the automatic-halt application path.
- finding, repair, work-version, lifecycle, and cursor CAS remain in the
  existing persistence/executor seams;
- audit-before-repair and fresh postcondition verification remain mandatory;
- exact organization/application/environment scope remains mandatory;
- non-executable/report-only action dispositions remain fail-closed.

## 3. Runner lifecycle

`ReconciliationPeriodicRunner.start()` is idempotent. Disabled configuration
starts no timer. Enabled configuration schedules one first tick after the
configured startup delay plus bounded jitter, then schedules one-shot timers
after each completed tick. `stop()` cancels future timers, clears the due time,
and waits for an active bounded invocation for only the configured shutdown
budget. It never force-cancels an authoritative persistence operation.

There is no durable scheduler state, missed-tick replay, queue, or hidden
worker. Runner state is intentionally process-local.

## 4. Configuration

`ControlPlaneConfig.reconciliationPeriodic` is disabled by default. Explicit
environment variables are parsed by `ReconciliationPeriodicConfig`:

| Setting | Default | Bound |
| --- | --- | --- |
| enabled | `false` | explicit boolean |
| interval | 5 minutes | 5 seconds to 24 hours |
| jitter | 30 seconds | zero to half the interval |
| startup delay | interval | zero to 24 hours |
| maximum backoff | 30 minutes | at least interval, at most 24 hours |
| shutdown timeout | 30 seconds | greater than zero, at most 5 minutes |

Negative, zero-prohibited, over-bound, or malformed values throw an argument
error. Dangerous values are not silently clamped.

## 5. Interval and jitter

Scheduling uses a one-shot `Timer`, not `Timer.periodic`. The default interval
is five minutes and the minimum is five seconds, preventing tight polling. The
default jitter source samples a random duration in `[0, jitter)`; the injected
test source is bounded by the same configured duration. Jitter is not seeded
from tenant or application identifiers and is not part of reconciliation
semantics.

After a successful tick, the next base delay is the normal interval. Consecutive
failures double the base delay up to the configured maximum; success resets the
failure count.

## 6. Overlap policy

An active tick is a single in-memory future. A second scheduled or direct
composition call returns `OVERLAP_SKIPPED` immediately and is not queued. The
shared `ReconciliationExecutionGate` rejects concurrent startup, manual, and
periodic service entry when the host supplies the same gate to the bounded
service. The overlap counter is fixed-key process-local observability.

## 7. Startup and manual coexistence

Existing `runStartup` and `runAdministrator` entry points remain unchanged.
They retain exact-scope authorization, caps, cursor/fairness, audit, CAS, and
postcondition behavior. A host can pass a shared `ReconciliationExecutionGate`
to the bounded service and have the periodic callback use that same service;
the periodic runner therefore does not create a second semantic execution
path. The first periodic tick is delayed by the configured startup delay and
is not run simultaneously with startup by the runner itself.

## 8. PostgreSQL ownership lock

`PostgresReconciliationPeriodicOwnership` calls
`PostgresReconciliationStore.runIfPeriodicOwner`. The store obtains the
constant session-scoped advisory key with `pg_try_advisory_lock`, which
returns immediately on contention. It runs the bounded callback only after
acquisition, verifies the session after the callback, and attempts unlock in a
`finally` block. PostgreSQL releases the lock when its session is lost.

Ownership uses a dedicated pool separate from the persistence pool. This is
required because the callback legitimately acquires persistence sessions; a
single-connection shared pool would deadlock. The lock protects only periodic
runner ownership, not semantic reconciliation authority.

## 9. File single-process behavior

File ownership is `LocalReconciliationPeriodicOwnership`: it performs no
multi-process election and adds no lock file or second writer. The existing
File store remains one-process/single-writer. Deployments enabling File
periodic reconciliation must therefore remain single-process.

## 10. Contention and handoff

Evidence labels:

- `POSTGRESQL_LOCK`: two independently initialized PostgreSQL stores contend
  on the same advisory key; one callback runs while the other returns false.
- `TWO_INSTANCE_CONTENTION`: the periodic runner reports
  `LOCK_CONTENTION`, does not invoke the losing callback, and later invokes it
  after the first owner releases the lock.
- `OWNERSHIP_HANDOFF`: the second store acquires and executes after the first
  owner completes.

These are two-instance, independent-connection tests, not provider HA or a
production scheduler claim.

## 11. Lock loss

The ownership boundary treats storage/session failures as bounded
`StorageUnavailable` failures. The runner records a failure, applies bounded
backoff, and does not continue assuming ownership. The PostgreSQL `finally`
unlock is best effort because a lost session releases its advisory lock.

Direct OS process kill or an external `pg_terminate_backend` experiment was not
run in this slice. The passing PostgreSQL failure/handoff test covers bounded
callback failure and lock release; direct crash-kill evidence remains a
P3E5-5E/operational condition rather than an inferred pass.

## 12. Fairness and cursors

The runner supplies no alternate ordering and no new cursor. It invokes the
same bounded service with its existing per-tenant/global caps, stable ordering,
persisted cursor, exact-scope reads, and currentness checks. The existing
reconciliation persistence/concrete suites, rerun as part of the full package
run, cover tenant isolation, fairness caps, cursor persistence, CAS convergence,
and replay. Periodic composition adds no bypass around those tests.

Evidence label: `TENANT_FAIRNESS` (inherited service tests plus periodic
existing-service integration).

## 13. Outage and backoff

`StorageUnavailable` from ownership or the bounded callback produces a
`FAILURE` outcome and increments the fixed store-failure counter. A consecutive
failure sequence uses exponential base delays capped at configuration; a
successful run resets the state to `NORMAL`. There is no independent reconnect
loop or retry queue.

The focused runner test proves failure, backoff growth, counter recording, and
reset. Existing PostgreSQL disconnect/recreation suites cover persistence
outage and explicit recovery. The runner's PostgreSQL contention test also
proves a later owner can proceed after the first owner exits.

Evidence label: `OUTAGE_RECOVERY`.

## 14. Audit behavior

The runner never calls the audit store directly. The existing bounded service
continues to append the repair-request audit record before an authorized
mutation and requires a fresh verified postcondition for `APPLIED`. Audit
outage, postcondition failure, replay, conflict, malformed records, and
report-only dispositions remain covered by the existing reconciliation
persistence/concrete tests rerun in the full package suite. A periodic
callback cannot bypass those seams.

Evidence labels: `UNIT`, `INTEGRATION`, `OUTAGE_RECOVERY` (existing service
tests and one periodic existing-service integration test).

## 15. Crash and restart

Runner timers, backoff, overlap state, and due timestamps are not persisted.
The focused restart-cadence test starts and stops one runner, creates a new
runner, and verifies that missed timer intervals are not replayed. Existing
File/PostgreSQL persistence restart tests verify that findings, repair
attempts, lifecycle, and cursor state remain the durable source of truth.

Evidence label: `CRASH_RESTART` for process-local restart semantics and
`INTEGRATION` for durable service restart behavior. An OS power-loss run is not
claimed.

## 16. Graceful shutdown

Shutdown cancels only future scheduling. An active callback is awaited for the
configured bounded timeout; on timeout, `shutdownTimedOut` is reported and the
callback is not force-cancelled. The focused test proves that the callback can
finish after the timeout without being interrupted by runner orchestration.

Evidence label: `GRACEFUL_SHUTDOWN`.

## 17. Metrics and diagnostics

The existing process-local metrics object now includes fixed outcome keys and
bounded counters for total runs, overlap skips, lock contention, store
failures, last duration, and last-run timestamps/outcome. No tenant, finding,
lock identifier, connection string, credential, or free-form exception is a
metric label.

When the same runner instance is passed to `ReconciliationObservability`, the
read-only diagnostics list/detail responses include enabled, started/running,
last-run, next-due, lock-owned, backoff, consecutive failures,
shutdown-timeout, and overlap state. HTTP bind/close starts/stops the runner
only through the host lifecycle; no runner-control endpoint exists.

Evidence labels: `METRICS`, `DIAGNOSTICS`.

## 18. Tenant isolation

The runner has no tenant input and no tenant-selection authority. Scope,
principal authorization, candidate discovery, caps, and persistence remain in
the existing bounded service. Full package tests rerun exact-scope, foreign
scope, malformed, fairness, and cross-tenant rejection cases. Runner metrics
and status contain no tenant identifiers.

## 19. Malformed behavior

Malformed configuration is rejected before scheduling. A malformed invocation
or persisted record is surfaced as a bounded failure/classification; the
runner does not crash-loop, reinterpret malformed content, or retry forever.
The focused malformed-invocation test proves one failure and one callback
attempt. Existing File/PostgreSQL malformed-row tests prove fail-closed
reconciliation behavior.

Evidence label: `UNIT` and `INTEGRATION`.

## 20. Prohibited-scope evidence

The Task 73 implementation and tests add no queue, Redis, alert, dashboard,
provider scheduler, provider deployment, rollout writer, P3A/P3E-4 mutation,
runtime/mobile/compiler import, or production default. The only scheduling
primitive is an in-process one-shot `Timer`; the only HTTP changes are
existing lifecycle wiring and read-only status inclusion.

No new SQL migration or persistent scheduler table was introduced.

## 21. Consolidated validation

Task 73 validation was run after the implementation and documentation batch:

- `dart format --output=none --set-exit-if-changed` over changed Dart files —
  PASS after formatting;
- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- focused periodic runner suite with local PostgreSQL — PASS, 15 tests;
- focused observability, HTTP, and periodic suites with local PostgreSQL —
  PASS, 26 tests;
- full `HYFENS_TEST_POSTGRES_URL=... dart test` in
  `packages/control_plane` — PASS, **263 tests passed**, one explicit MinIO/S3
  environment skip;
- root `dart analyze --fatal-infos` — PASS;
- root `dart test` — PASS, 1 test;
- migration regression `dart test test/migration_test.dart` in
  `packages/control_plane` — PASS, 1 test;
- Markdownlint, local links, whitespace, secret, and prohibited-boundary
  scans — PASS (details recorded in Task 73).

The root-level migration path does not exist; the shipped migration test lives
in `packages/control_plane/test/migration_test.dart` and was run there.

## 22. Residual limitations

- Periodic runner state and metrics are process-local and reset on restart.
- PostgreSQL tests use independent store instances, not a deployed multi-node
  provider or OS-level process-kill harness.
- Direct `pg_terminate_backend`, power-loss, provider failover, capacity,
  latency, and long-running production workload evidence is not claimed.
- File remains single-process/single-writer.
- Runner configuration is exposed as a library/config seam; deployment wiring
  must explicitly choose and review the environment values.
- P1D-01, P1D-03, P1D-04, P1D-07, P1D-09, P1D-18, provider-production, beta,
  production, App Store, Google Play, privacy, and legal gates remain open.

## 23. Next-phase recommendation

P3E5-5E may be considered only after a new maintainer review of this document
and the residual lock-loss/crash evidence. If authorized, it must preserve the
bounded runner, existing CAS/audit/currentness seams, exact scope, and
non-authoritative observability. This review does not authorize P3E5-5E,
queues, Redis, provider schedulers, alerts, dashboards, rollout mutation,
runtime/mobile/compiler work, or production/store/legal claims.

## Final disposition

`PROCEED TO P3E5-5E WITH CONDITIONS`

Stop at this maintainer-review gate.

## P3E5-5E factual addendum (2026-08-24)

Task 74 was separately authorized after this review and closed the bounded
crash/lock-loss evidence slice. The original Task 73 statement above remains
historically accurate: direct OS process kill and external
`pg_terminate_backend` were not run in Task 73 itself. Task 74 added a
disposable external Dart process harness and real local PostgreSQL session
termination tests without changing the runner's authority model.

Task 74 verified kill-before-mutation, kill-after-CAS, audit-boundary crash,
File restart, direct `SIGKILL` PostgreSQL handoff,
`pg_terminate_backend` ownership-session loss, existing persistence disconnect
recovery, tenant isolation/fairness, malformed/audit-tamper fail-closed
behavior, and process-local metrics/diagnostic reset. It also exposed and
fixed idempotent replay of an earlier File audit event and reconstruction of a
missing lifecycle projection from an already committed repair attempt.

These are local `PROCESS_KILL`, `POSTGRESQL_SESSION_KILL`,
`PROCESS_KILL_HANDOFF`, `POSTGRESQL_DISCONNECT`, `FILE_RESTART`, and
`CRASH_RESTART` results only. They do not close provider failover, physical
power-loss, independent-app, beta, production, App Store, Google Play,
privacy, or legal gates. See
`docs/P3E5_5E_CRASH_LOCK_LOSS_RESILIENCE_REVIEW.md` and Task 74 for the
complete evidence and final maintainer disposition.

## P3E5-5F factual addendum (2026-08-25)

Task 75 reused the existing PostgreSQL advisory ownership and persistence
seams in a disposable two-instance Compose rehearsal. No new repair path or
runner wiring was added. The local evidence covers instance loss in both
directions, dependency-aware readiness, passive reverse-proxy retry, and
recovery. The current HTTP host remains disabled-by-default/not wired for the
periodic runner; host wiring is therefore an explicit deployment decision.

Provider failover, active readiness-aware routing, power loss, provider RPO/RTO,
soak, beta, production, store, privacy, and legal gates remain open. See
`docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md` and Task 75.
