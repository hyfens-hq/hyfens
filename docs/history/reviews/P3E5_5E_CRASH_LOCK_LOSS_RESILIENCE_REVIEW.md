# P3E5-5E crash and lock-loss resilience review

<!-- markdownlint-disable MD013 -->

Status: implementation complete; maintainer decision required

Date: 2026-08-24

Task: 74

## 1. Recommendation

Recommendation: `PROCEED TO NEXT P3E5 PHASE WITH CONDITIONS`

The bounded P3E5-5E engineering slice is complete for the local File and
PostgreSQL process/session-loss scenarios listed below. The recommendation is
not a provider-HA, power-loss, beta, production, App Store, Google Play,
privacy, or legal-readiness claim. Stop here for maintainer review.

Conditions:

- Architecture B, Patch Format v1, capability v1, exact-release binding,
  state-v4 high-water, signed rollback, fail-closed behavior, AOT fallback,
  customer/local signing custody, and runtime-authoritative verification remain
  frozen.
- The runner remains orchestration only. Existing detector, audit, CAS,
  lifecycle, cursor, postcondition, rollout, and halt authority is unchanged.
- File persistence remains one-process/one-writer. PostgreSQL advisory locking
  is local coordination, not provider HA or repair authority.
- Process-local metrics, timestamps, backoff, and runner state reset on
  restart; no synthetic continuity is introduced.
- Physical machine power loss, PostgreSQL provider failover, independent real
  applications, capacity/latency, and operational deployment evidence remain
  separate open gates.
- No next P3E5 phase, provider-resilience design, queue, Redis, scheduler
  table, alert, dashboard, rollout writer, runtime/mobile/compiler work, or
  production enablement starts without maintainer authorization.

## 2. Frozen authority model

The existing `ReconciliationPeriodicRunner` still invokes only an already
constructed `BoundedReconciliationService`. It does not discover candidates,
interpret findings, execute repairs, write audit records, advance cursors,
write lifecycle, mutate rollout state, or apply automatic halts.

The crash harness uses a test-only typed executor and durable projection to
exercise the same service and runner seams. It does not introduce a second
production repair path. The existing audit-before-repair, exact scope,
fresh-postcondition, immutable-attempt, work-version/CAS, lifecycle-CAS, and
cursor-CAS contracts remain authoritative.

## 3. Process-kill harness

`packages/control_plane/test/fixtures/reconciliation_crash_worker.dart` is a
disposable Dart child process. The parent test starts it with an isolated File
root, waits for a durable marker, and terminates the child with
`ProcessSignal.sigkill`. A restart child then reads the same durable state.
No production service is killed and no HTTP kill endpoint exists.

The fixture's semantic projection starts at work version `1`. Its typed CAS
increments the version to `2` and increments a durable mutation counter once.
The existing bounded service persists the finding, repair attempt, lifecycle,
cursor, and audit events around that projection. The fixture is deliberately
small; it is evidence for orchestration/recovery, not a provider or workload
simulator.

Evidence labels used here are `PROCESS_KILL`, `CRASH_RESTART`,
`FILE_RESTART`, `PROCESS_KILL_HANDOFF`, `POSTGRESQL_SESSION_KILL`,
`POSTGRESQL_LOCK`, `POSTGRESQL_DISCONNECT`, `TENANT_ISOLATION`,
`TENANT_FAIRNESS`, `AUDIT_TAMPER`, `MALFORMED_INPUT`, `METRICS`, and
`DIAGNOSTICS`.

## 4. Kill-before-mutation

The focused process test covers three pre-mutation positions:

| Position | Harness marker | Result after kill | Result after restart |
| --- | --- | --- | --- |
| runner idle, no lock | `IDLE` | no finding, no projection mutation | one normal bounded repair |
| ownership acquired before callback | `OWNERSHIP_ACQUIRED` | no finding, no projection mutation | one normal bounded repair |
| callback before projection CAS | `BEFORE_CAS` | finding remains durable, no projection mutation | one repair and one work-version increment |

The process does not self-spin and no synthetic missed-run replay is used.
The next invocation is an ordinary bounded run.

## 5. Kill-after-CAS

The `AFTER_CAS` process is killed after the durable projection write and before
the service returns. Before restart the projection is already exactly
`version=2, mutations=1`. The restart sees the deterministic repair identity,
does not execute a second semantic mutation, and completes the missing durable
bookkeeping.

Verified after restart:

- projection mutation count is exactly `1`;
- work version is exactly `2` (one increment from the fixture's version `1`);
- one immutable repair attempt exists with the deterministic repair ID;
- lifecycle is `REPAIRED`, version `1`;
- cursor is version `1` at the deterministic finding ID;
- the audit chain verifies;
- a second semantic CAS is not performed.

The bounded service now reconstructs a missing lifecycle projection from an
already committed immutable repair attempt. It never re-enters the executor on
that replay path. This was required by the after-CAS crash test.

## 6. Audit-boundary crash behavior

Three external-kill scenarios are exercised:

1. before `repairRequested` is appended;
2. after `repairRequested` is appended and before mutation;
3. after projection/attempt/lifecycle mutation and before the terminal audit
   event.

All three restart through the ordinary service path. Required pre-repair audit
ordering is preserved, the append-only history is not rewritten, the
projection mutation remains at most once, and the chain verifies after
recovery. A File audit replay bug was found: replaying an earlier identical
event after later chain entries incorrectly rebuilt its previous-link tail and
reported a conflict. File audit append now compares an existing immutable body
before deriving a new tail link, so identical replay is idempotent while a
different body remains a conflict.

## 7. PostgreSQL ownership-session termination

The worker's PostgreSQL mode uses the real
`PostgresReconciliationPeriodicOwnership` and the dedicated ownership pool.
The parent queries `pg_locks` for the fixed periodic advisory key and calls
`pg_terminate_backend` only for the marked ownership session.

Observed behavior:

- the callback is entered while the dedicated advisory lock is held;
- session termination is surfaced as bounded runner `FAILURE`;
- the runner does not report successful ownership after the session disappears;
- PostgreSQL releases the session-scoped lock;
- a subsequent process acquires the lock and reports `SUCCESS`.

The test also runs a direct OS `SIGKILL` against process A and starts process B
against the same local PostgreSQL fixture. B acquires ownership and completes;
this is labeled `PROCESS_KILL_HANDOFF`, not provider HA.

## 8. Persistence-session termination

The existing `PostgresDisconnectInjector` is reused; no retry loop or new
failure model is introduced. Two periodic runs are exercised:

- connection loss at `findingCommitBefore`: no mutation is applied; a fresh
  store/process later performs exactly one repair;
- connection loss at `repairAttemptCommitAfter`: the projection mutation and
  immutable repair attempt commit, the persistence session then disappears,
  and the next run reconstructs lifecycle/cursor state without a second
  projection mutation.

This is `POSTGRESQL_DISCONNECT` evidence through the existing Task 71 seam,
not a provider outage or failover claim.

## 9. Two-process handoff and lock release

The OS-kill PostgreSQL process test has the sequence:

```text
A owns advisory lock and enters callback
→ SIGKILL A
→ PostgreSQL releases the session lock
→ B starts against the same database
→ B owns the lock and completes the bounded callback
```

No simultaneous ownership is observed, and no stuck advisory lock remains.
The separate `pg_terminate_backend` test proves the same handoff after
explicit ownership-session loss.

## 10. Restart cadence, File behavior, and shutdown

The existing runner restart-cadence tests continue to prove that process-local
timers do not replay missed firings. The new child-process callback-completion
test kills after the bounded invocation has completed and verifies no duplicate
repair after File restart. A readiness probe succeeds after reopening the File
store.

File behavior remains deliberately single-process/single-writer. The harness
does not claim multi-process File coordination. Graceful shutdown and bounded
timeout behavior remain covered by Task 73 tests; the crash harness uses abrupt
termination only at controlled test markers.

## 11. Tenant isolation and fairness

The File restart integration creates two application-scoped tenants under one
organization, runs with `perTenantCap=1` and `globalCap=2`, closes/reopens the
store, and re-runs the same source. Both tenant findings are processed once,
both immutable attempts replay without executor calls, and reads for a third
application scope are empty. No cross-scope record is returned.

This is local `TENANT_ISOLATION`/`TENANT_FAIRNESS` evidence. It does not claim
cross-provider fairness or an unbounded workload guarantee.

## 12. Malformed input and audit tamper

The malformed-projection restart test writes invalid JSON to the typed
projection. The executor converts the format failure into a durable failed
attempt; the runner completes the bounded pass without crashing or spinning,
and the malformed projection is not overwritten.

The audit-tamper test changes a persisted audit-chain body after a successful
run. On restart, verification fails closed, the runner reports bounded
`FAILURE`, the invalid chain remains invalid, and no new chain entry or
semantic projection mutation is created. There is no audit repair or rewrite.

## 13. Metrics, diagnostics, and readiness

The new restart test confirms that a new runner starts with zero process-local
run counters, no prior outcome, no running/owned lock, and no fabricated
continuity. Existing Task 72 read-only diagnostics and readiness suites remain
unchanged and were rerun. The File crash test explicitly reopens and probes
store readiness. No endpoint, metric label, or durable scheduler state was
added.

## 14. Consolidated validation

The final validation pass completed successfully. The PostgreSQL commands used
the disposable local test fixture configured through `HYFENS_TEST_POSTGRES_URL`;
no credential is part of the repository evidence.

Final validation results:

- `dart format --output=none --set-exit-if-changed lib test` in
  `packages/control_plane`: pass; 73 files inspected, 0 changed.
- `dart analyze . --fatal-infos` in `packages/control_plane`: pass; no issues.
- The new crash-resilience suite: 10 tests pass, including process kill,
  PostgreSQL ownership-session termination, persistence disconnect, restart,
  tenant, malformed-input, tamper, metrics, and readiness scenarios.
- Full `HYFENS_TEST_POSTGRES_URL=... dart test -r compact` in
  `packages/control_plane`: 273 tests passed and 1 explicit MinIO/S3 test was
  skipped because its external service environment was not configured.
- Root `dart analyze --fatal-infos`: pass; no issues.
- Root `dart test`: 1 test passed.
- `dart test test/migration_test.dart` in `packages/control_plane`: 1 test
  passed.
- Markdownlint over the changed review/task/design/ADR documents: pass.
- Read-only local-link, trailing-whitespace, high-confidence secret, and
  targeted prohibited-dependency/import scans: pass.

No provider, power-loss, queue, Redis, scheduler-table, dashboard, alert,
rollout-writer, P3E-4, runtime/mobile/compiler, beta, production, store,
privacy, or legal claim is included in these commands.

## 15. Residual limitations

- Physical machine power loss was not tested and is not inferred.
- PostgreSQL provider failover, managed service behavior, backup/restore,
  capacity, latency, and multi-node deployment were not tested.
- The process harness is a disposable local Dart fixture, not a production
  supervisor or independent real application.
- File remains single-process/single-writer.
- Metrics, diagnostics timestamps, backoff, and runner lifecycle are
  process-local and reset after restart.
- Long-running soak was not required for closure and was not run.
- Independent-application, native/mobile, App Store, Google Play, privacy,
  legal, beta, and production gates remain open.

## 16. Final disposition

`PROCEED TO NEXT P3E5 PHASE WITH CONDITIONS`

Stop at this maintainer-review gate. Do not begin the next phase automatically.

## P3E5-5F factual addendum (2026-08-25)

Task 75 was separately authorized for provider-neutral, disposable resilience
evidence. The extended two-instance Compose rehearsal passed both instance-loss
directions, passive proxy retry, direct and proxied readiness, separate
PostgreSQL/object-store outages, exact artifact recovery, audit verification,
and a bounded local capacity sample. The coupled backup/restore rehearsal and
bounded image-provenance inventory also passed with their existing directional
and provenance limits.

This addendum does not change the bounded Task 74 result or imply provider
failover, physical power-loss, public TLS, production SLO, beta, store,
privacy, or legal readiness. See
`docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md` and Task 75. The 5F
recommendation is `PROCEED TO PROVIDER DEPLOYMENT DESIGN WITH CONDITIONS` and
stops at maintainer review.
