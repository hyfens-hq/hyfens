# Task 70 — P3E5-5B bounded reconciliation

Status: [x] Completed

## Goal

Implement the maintainer-authorized P3E5-5B File/PostgreSQL bounded
reconciliation slice: append-only finding and repair-attempt persistence,
bounded startup and explicit exact-scope administrator execution, safe
projection/operational CAS repair seams, audit-before-repair, currentness
checks, deterministic replay, fairness, and tenant isolation.

## Scope and Non-goals

In scope: a separate reconciliation persistence/execution boundary over the
existing authoritative stores and typed P3E5-5A contracts; File single-writer
and PostgreSQL migration/adapters; bounded candidate discovery and typed repair
callbacks; canonical idempotency/conflict and malformed-input rejection;
restart/reconnect behavior; tests and factual documentation addenda.

Out of scope: P3E5-5C metrics/readiness/diagnostics, periodic workers,
queues/Redis, new rollout behavior, direct P3A or P3E-4 calls, immutable
evidence or audit rewriting, runtime/mobile/compiler/patch changes, P3F/P3G,
provider deployment, and production/store/legal claims.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 69/P3E5-5A typed domain and taxonomy (`reconciliation_domain.dart`).
- Existing File and PostgreSQL control-plane stores, audit chain, and P3E5
  work/CAS seams.
- Maintainer authorization in `CODEX_TASK70_P3E5_5B_BOUNDED_RECONCILIATION.md`.

## Assumptions

- Existing immutable P3E evidence, rollout state, audit chain, P3A CAS, and
  P3E-4 authority remain unchanged and authoritative.
- The new module can use injected typed source readers and repair adapters,
  avoiding a second rollout writer or broad service coupling.
- PostgreSQL integration tests may remain skipped when
  `HYFENS_TEST_POSTGRES_URL` is unavailable; this is recorded rather than
  inferred as a pass.

## Work Items

- [x] Reserve task 70 and define the implementation boundary.
- [x] Add append-only File/PostgreSQL finding and repair-attempt persistence.
- [x] Add bounded startup/manual invocation and typed repair execution seams.
- [x] Add migration, malformed-input, idempotency, fairness, isolation, and
  concurrency tests.
- [x] Update P3E5-5B review and factual design/ADR/security/context addenda.
- [x] Run scoped/full validation and prohibited-scope scans.
- [x] Wire concrete authoritative detectors and existing projection-CAS
  adapters for every representable path, document intentionally unbound
  actions, and rerun the real two-reconciler race.
- [x] Resolve the action-model/disconnect evidence gaps under the
  maintainer-approved Task 71 continuation without adding authority paths.

## Validation

- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- focused `dart test test/reconciliation_persistence_test.dart` — PASS, 13
  tests plus one explicit PostgreSQL skip when the URL is absent;
- focused reconciliation tests with the local PostgreSQL 17 fixture and
  `sslmode=disable` — PASS, 14 tests;
- full control-plane `dart test` with PostgreSQL enabled — PASS, 222 tests;
  one existing MinIO/S3 environment skip;
- root `dart analyze --fatal-infos && dart test` — PASS, 1 bootstrap test;
- migration test — PASS for shipped/executable migration 008 and schema 8;
- scoped Markdownlint, local-link, trailing-whitespace, secret-pattern, and
  prohibited-worker/rollout/runtime scans — PASS.
- concrete detector/CAS suite without PostgreSQL — PASS, 9 tests with two
  explicit PostgreSQL skips;
- concrete detector/CAS suite with the local PostgreSQL fixture — PASS, 11
  tests;
- concrete PostgreSQL two-reconciler work-CAS race — PASS: one semantic
  mutation, one work-version increment, deterministic replay/conflict;
- concrete PostgreSQL malformed-row injection — PASS: all injected rows fail
  closed before repair;
- concrete File lost-response and restart paths — PASS;
- actual per-boundary PostgreSQL disconnect/reconnect injection —
  INSUFFICIENT_EVIDENCE; no adapter-level safe hook exists for isolation.
- continuation final full control-plane suite with PostgreSQL — PASS, 232
  tests and one explicit MinIO/S3 environment skip; root suite and migration
  test — PASS.
- Task 71 action-disposition and concrete disconnect suite with PostgreSQL —
  PASS, 16 tests; model-invariant partial-link rejection, all non-executable
  dispositions, real pool close/recreate, pre/post-commit finding/repair/
  lifecycle/cursor cases, audit-before/after, postcondition reload, bounded
  administrator recovery, tenant scope, and projection CAS convergence.
- consolidated control-plane `dart test` with PostgreSQL — PASS, 237 tests;
  one explicit MinIO/S3 environment skip.
- root `dart analyze --fatal-infos && dart test` — PASS, 1 bootstrap test;
  migration regression — PASS.
- audit-chain verification after reconnect — PASS; PostgreSQL sequence
  allocation is serialized under the existing audit lock and cryptographic
  previous-link/digest verification remains fail-closed.

## Next Action

Stop at the Task 70/71 maintainer-review gate. P3E5-5C remains prohibited from
this implementation task; its execution requires a separate maintainer
authorization.

## Blockers

None known at task start.

## Outcome

The bounded persistence/orchestration core is implemented and locally verified.
Task 71 proves the final action dispositions and exercises actual PostgreSQL
pool disconnect/recreate at the hard closure boundaries. No second rollout or
completion authority was introduced. Task 70 can close for its bounded scope;
provider, beta, production, store, legal, and broader readiness gates remain
outside this task.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK70_P3E5_5B_BOUNDED_RECONCILIATION.md`
- `docs/P3E5_5A_RECONCILIATION_DOMAIN_REVIEW.md`
- `tasks/69-p3e5-5a-reconciliation-domain-taxonomy.md`
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`
- `docs/adr/0013-bounded-reconciliation-and-observability.md`

## History

- 2026-08-24 — Task reserved; implementation authorized under Task 70
  conditions.
- 2026-08-24 — File/PostgreSQL persistence, bounded service, migration 008,
  focused tests, and review addenda implemented; final validation pending.
- 2026-08-24 — Added audit-chain tamper regression coverage; focused PostgreSQL
  run passed 14 tests and the full control-plane run passed 222 tests with one
  explicit MinIO/S3 environment skip.
- 2026-08-24 — Consolidated package/root analysis and tests, migration and
  documentation scans, local-link/trailing-whitespace checks, secret-pattern
  scan, and prohibited-scope scans passed. Task remains in review/in progress
  because concrete detector/CAS integration evidence is intentionally open.
- 2026-08-24 — Existing audit-store tenant envelope was covered by the tamper
  regression; the focused suite (14 with PostgreSQL) and full package suite
  (222 with one explicit MinIO/S3 skip) were rerun successfully.
- 2026-08-24 — Task 70 continuation added concrete authoritative detectors,
  evaluation/halt/stale/retry CAS adapters, rollout/audit validation, real
  File restart and audit-before-repair evidence, a PostgreSQL work-projection
  race, stale-precondition rejection, and malformed-row injection. Concrete
  suite passed 11 tests with PostgreSQL. Decision-link, separate completion,
  derived-projection, and per-boundary disconnect paths remain explicitly open;
  disposition remains `CONTINUE P3E5-5B` pending maintainer review.
- 2026-08-24 — Task 71 final closure added the exhaustive action-binding
  disposition map, model-invariant/unsupported-action tests, real PostgreSQL
  disconnect/reconnect evidence across append-only, audit, lifecycle, cursor,
  projection, postcondition, and two-instance CAS recovery paths, plus bounded
  outage and administrator-scope recovery. Consolidated package/root/migration
  validation passed; Task 70 is now Completed pending maintainer review.
