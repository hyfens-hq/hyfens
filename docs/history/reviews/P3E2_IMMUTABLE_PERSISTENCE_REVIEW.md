# P3E-2 immutable persistence review

Status: `READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: `tasks/55-p3e2-immutable-persistence.md`

<!-- markdownlint-disable MD013 -->

## Decision and scope

Task 54/P3E-1 was approved. Task 55 implements only immutable persistence for
P3E-1 evidence and stops before P3E-3. The aggregate domain remains pure Dart;
storage adapters are separate from aggregation and runtime trust.

## Verified implementation

| Area | Evidence | Result |
| --- | --- | --- |
| Aggregate codec | `HealthAggregate.fromJson`, codec tests | Canonical aggregate JSON round-trips; unknown fields, states, metric status, policy versions, and malformed values fail closed. |
| Aggregate/revision lineage | `HealthAggregateRecord`, `HealthAggregateRevision`, lineage tests | Exact identity/window/input-count/input-digest binding is validated; recomputation is represented by a new immutable revision. |
| Evaluation evidence | `HealthEvaluation`, reference tests | Versioned decision vocabulary, reason class, coverage/freshness/sample state, audit reference, rollout revision, and aggregate digest are persisted only after a matching revision exists. |
| Decision reference | `RolloutDecisionRecord`, reference tests | Decision records are immutable evidence and require matching evaluation/revision/rollout scope; no transition is executed. |
| Cursor | `AggregationCursor`, cursor tests | Cursor is bound to aggregate identity/input digest/version and can be deleted without deleting aggregate evidence. |
| File adapter | `FileP3ePersistenceStore`, File tests | Canonical JSON, hashed tenant paths, atomic writes, restart/backup-copy round-trip, immutable conflicts, corruption rejection, and single-node-only boundary are verified. |
| PostgreSQL adapter | `PostgresP3ePersistenceStore`, migration 003, integration tests | Tenant-scoped immutable tables, indexes, migration-lock reuse, transactional aggregate/revision writes, reconnect/restart, equal retry acknowledgement, and changed-body conflict are verified when PostgreSQL is configured. |
| Tenant isolation | File/PostgreSQL tests | Wrong-tenant reads/listing return no records; all owned rows carry tenant scope. |
| Reconciliation | `P3eReconciliationReport`, reconciliation tests | Missing parent/reference and binding mismatch are reported without rewriting evidence. |
| Runtime boundary | source review and forbidden-boundary scan | No rollout mutation, evaluator API, scheduler, dashboard, mobile/runtime, signing, high-water, or artifact-trust path was changed. |

## Persisted entities

The adapter persists only the approved P3E-2 conceptual entities:

```text
HealthAggregate
HealthAggregateRevision
HealthEvaluation
RolloutDecision reference/record
AggregationCursor
```

Aggregate/revision/evaluation/decision/cursor records include an explicit
`entityVersion`. PostgreSQL schema version 3 is forward-only from the existing
version-2 observation schema. Unknown future entity or policy versions are
rejected rather than silently reinterpreted.

## Validation evidence

Evidence labels used by this task are:

```text
UNIT
PERSISTENCE_FILE
PERSISTENCE_POSTGRESQL
RESTART_RECOVERY
CONCURRENCY
MIGRATION
MALFORMED_PERSISTED_INPUT
BACKUP_RESTORE
RECONCILIATION
ENVIRONMENT_GATED
```

The focused persistence suite covers codec, File round-trip/restart, backup
copy, tenant isolation, immutable retries/conflicts, cursor deletion,
references, corruption, unknown versions, missing parents, PostgreSQL
reconnect, migration 003, and two-instance writes. PostgreSQL evidence is
environment-gated and must be reported with its exact configured result.

Executed validation:

- `dart format` for changed aggregation, persistence, PostgreSQL, export,
  migration-test, and P3E persistence-test files — passed.
- `cd packages/control_plane && dart analyze --fatal-infos .` — passed.
- `cd packages/control_plane && HYFENS_TEST_POSTGRES_URL='postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable' dart test test/p3e_persistence_test.dart`
  — 8 tests passed.
- `cd packages/control_plane && dart test test/migration_test.dart` — 1 test
  passed.
- `cd packages/control_plane && HYFENS_TEST_POSTGRES_URL='postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable' dart test`
  — 79 tests passed; one MinIO integration skipped because its environment
  variables were not configured.
- Fresh disposable PostgreSQL database migration/bootstrap plus P3E-2 and
  existing PostgreSQL-store suites — passed; the disposable database was
  removed after validation.
- `dart analyze .` at repository root — passed.
- `dart test` at repository root — 1 test passed.

No test is labelled `AUTOMATIC_HALT`, `PHYSICAL`, `BETA`, or `PRODUCTION`.

## Frozen boundaries

Unchanged: Architecture B, Patch Format v1, capability v1, exact release/
function/capability binding, state-v4 high-water, runtime signature authority,
signed rollback, fail-closed recovery, AOT fallback, customer/local signing,
artifact immutability, P3A rollout state, P3D observation ingestion, and P3E-1
deterministic aggregation semantics.

Not started: P3E-3 evaluation API/evaluator workflow, P3E-4 halt/hold
integration, P3E-5 scheduler/worker, P3F operator tooling, P3G dashboard,
automatic expansion, production thresholds, provider deployment, mobile/runtime
changes, and store/legal review.

## Known limits and unresolved gates

The File adapter is single-node and makes no multi-process safety claim. Backup
evidence is limited to the existing PostgreSQL dump and a bounded local
directory-copy test; no RPO/RTO, HA, encryption, residency, or provider-SLO
claim follows. Retention periods and deletion policy values remain injected
policy, not production defaults. A compromised storage/operator boundary can
destroy or expose evidence; reconciliation reports this state but does not
rewrite immutable history.

P1D-01 true power loss, P1D-03 iOS diagnostics, P1D-04 iOS performance, P1D-07
independent-app validation, P1D-09 interpreter attribution, P1D-18
Apple/Google/legal review, provider-production gates, beta readiness,
production readiness, and store readiness remain open.

## Recommendation

`AUTHORIZE P3E-3 WITH CONDITIONS`

This is a recommendation for maintainer review, not automatic authorization.
Conditions are that P3E-3 keep persistence append-only and tenant-scoped,
consume only validated immutable revisions, preserve all digest/version
bindings, keep evaluation results non-authoritative to runtime and rollout
state until a separately approved P3E-4 boundary, and add API authorization,
negative cross-tenant, stale-input, and audit-reference tests. Do not begin
P3E-3 automatically.
