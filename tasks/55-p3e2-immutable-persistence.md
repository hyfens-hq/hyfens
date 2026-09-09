# Task 55 — P3E-2 immutable persistence

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — P3E-2 implementation and validation complete; maintainer review required

## Goal

Persist and recover immutable P3E-1 aggregate evidence, recomputation lineage,
evaluation evidence, rollout-decision references, and rebuildable aggregation
cursors without changing aggregate meaning, tenant scope, version/digest
binding, rollout state, or runtime trust.

## Scope and Non-goals

Scope: storage-agnostic typed P3E persistence interfaces; strict aggregate
decode/round-trip validation; immutable aggregate/revision/evaluation/decision/
cursor records; File/local adapter; PostgreSQL adapter; schema migration;
transactional lineage writes; idempotent retry/conflict semantics; tenant and
scope isolation; restart/reconnect/concurrency evidence; malformed/version/
corruption handling; bounded reconciliation; factual design/threat-model
addenda; executable persistence tests.

Non-goals: P3E-3 evaluation API or evaluator workflow, P3E-4 rollout mutation
or automatic halt, P3E-5 scheduler/worker, P3F operator tooling, P3G dashboard,
production thresholds, mobile/runtime changes, Patch Format/capability/high-
water/signing changes, raw installation APIs, business analytics, provider
deployment, React Native, billing, enterprise features, store submission, or
legal/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E-2 maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK55_P3E2_IMMUTABLE_PERSISTENCE.md`;
- approved `docs/P3E1_AGGREGATION_CORE_REVIEW.md`;
- `tasks/54-p3e1-deterministic-aggregation-core.md`;
- `packages/control_plane/lib/src/aggregation.dart`;
- existing `ControlPlaneStore`, migration advisory lock, audit, and observation
  persistence boundaries.

## Assumptions

- Task 55 authorization is limited to P3E-2 immutable persistence.
- P3E-1 `HealthAggregate` remains pure domain and is the only aggregate source
  of meaning; adapters store canonical JSON plus validated binding metadata.
- Existing PostgreSQL schema version 2 and migration advisory lock are reused;
  P3E-2 adds one forward-only schema version.
- File storage is single-node only and makes no multi-process safety claim.
- Test thresholds, policy versions, retention markers, and decision values are
  fixtures or caller-supplied values, never production defaults.

## Work Items

- [x] Preserve P3E-1 semantics and frozen runtime/rollout trust invariants.
- [x] Add strict `HealthAggregate.fromJson` decoding and canonical digest checks.
- [x] Define typed immutable aggregate, revision, evaluation, decision-reference,
  cursor, and reconciliation domain boundaries.
- [x] Implement append-only File/local persistence with atomic writes,
  tenant-separated paths, restart recovery, and fail-closed corruption checks.
- [x] Add PostgreSQL migration 003 with tenant-scoped immutable tables,
  indexes, constraints, and migration-lock reuse.
- [x] Implement transactional PostgreSQL aggregate/revision lineage writes,
  immutable idempotency/conflict semantics, and reference validation.
- [x] Implement PostgreSQL/File tenant isolation, exact scope/version binding,
  digest preservation, cursor rebuildability, and bounded reconciliation.
- [x] Add unit, File persistence, PostgreSQL integration, restart, reconnect,
  two-instance concurrency, migration, malformed/version, and corruption tests.
- [x] Update P3E design and threat-model documents with factual P3E-2 addenda.
- [x] Run consolidated validation, complete the review, and stop before P3E-3.

## Validation

Completed validation:

- `dart format` for changed control-plane source/export/tests — passed.
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
- `dart analyze .` — passed.
- `dart test` — 1 test passed.
- Markdown lint, local path/link, whitespace, diff, secret, and forbidden-
  boundary scans — passed.

No physical Android/iOS rerun is authorized: P3E-2 must not modify runtime or
mobile code. MinIO remains environment-gated unless artifact behavior changes.

## Next Action

Maintainer review of `docs/P3E2_IMMUTABLE_PERSISTENCE_REVIEW.md` and its
recommendation `AUTHORIZE P3E-3 WITH CONDITIONS` is the next action. Do not
begin P3E-3 automatically.

## Blockers

None known. Existing readiness gates remain open: P1D-01 power loss, P1D-03
iOS diagnostics, P1D-04 iOS performance, P1D-07 independent app, P1D-09
interpreter attribution, P1D-18 Apple/Google/legal review, provider production,
beta, production, and store readiness.

## Outcome

P3E-2 is complete for its authorized bounded scope: immutable aggregate,
revision, evaluation, decision-reference, and cursor persistence with File and
PostgreSQL adapters, strict decoding, digest/version/scope binding, restart and
concurrency evidence, and reconciliation. No evaluation API, rollout mutation,
automatic halt, scheduler, dashboard, mobile/runtime, or readiness claim was
added. Stop at maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK55_P3E2_IMMUTABLE_PERSISTENCE.md`;
- `/Volumes/970EvoPlus/Downloads/P3E1_AGGREGATION_CORE_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/54-p3e1-deterministic-aggregation-core.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`;
- `docs/security/productization-threat-model.md`.

## History

- 2026-08-24: Reserved Task 55 after explicit maintainer approval of P3E-1
  and authorization of P3E-2 immutable persistence only.
- 2026-08-24: Implemented strict aggregate decoding, typed P3E-2 entities,
  File/PostgreSQL adapters, migration 003, lineage/reference validation,
  reconciliation, and executable persistence evidence.
- 2026-08-24: Focused P3E-2 tests (8), migration test (1), full control-plane
  suite (79; one MinIO integration skipped), root analysis/tests, and boundary
  scans passed. Task is complete pending maintainer review and the P3E-3
  decision.
