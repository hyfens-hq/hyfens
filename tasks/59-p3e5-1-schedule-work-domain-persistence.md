# Task 59 — P3E5-1 schedule/work domain and persistence

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — maintainer review required

## Goal

Prove that the control plane can persist immutable, tenant-scoped, versioned
scheduling intent, deterministic scheduled-evaluation work identity, and
append-only attempt evidence behind a least-privilege scheduler-principal
boundary without claiming or executing work.

## Scope and Non-goals

Scope: strict schedule/revision/work/attempt models; canonical codecs and
deterministic identities; state-transition validation; exact target and tenant
binding; application/environment-scoped scheduler credentials and narrow
authorization scopes; explicit schedule create/revise and work materialization;
File and PostgreSQL persistence; migration, restart, concurrency, corruption,
audit, and resource-bound tests; factual implementation-review documentation.

Non-goals: work claiming or leasing; due-work polling; timers, cron, queues,
workers, retries, evaluation execution, automatic halt, automatic expansion,
HOLD-to-pause, runtime/mobile changes, P3E5-2 onward, P3F/P3G, dashboard,
production defaults, or beta/production/store/legal claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E5-1 maintainer-review
gate.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK59_P3E5_1_SCHEDULE_WORK_DOMAIN_PERSISTENCE.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `tasks/58-p3e5-scheduled-evaluation-design.md`;
- P3A rollout target/CAS records, P3E-2 persistence conventions, P3E-3
  deterministic evaluation identity, P3E-4 halt idempotency, and existing
  File/PostgreSQL migration locking.

## Assumptions

- P3E5-1 extends the existing control-plane Dart package and its File and
  PostgreSQL deployment profiles.
- Trusted service/database time supplies operational creation/update times;
  callers do not provide authoritative readiness, retry, or lease times.
- Work materialization is an explicit authenticated service operation only;
  no clock/window scanning is introduced.
- Existing worktree content is maintainer-owned baseline and must be
  preserved; only Task 59-scoped files and seams will be changed.

## Work Items

- [x] Map existing domain, authentication, persistence, migration, audit, and
  service conventions and confirm the frozen-invariant boundary.
- [x] Implement typed P3E5-1 models, canonical serialization, bounded parsing,
  deterministic logical/work/attempt identities, and transition validation.
- [x] Implement dedicated scoped scheduler credentials, narrow scopes,
  expiry/revocation, and negative authorization boundaries.
- [x] Implement schedule create/revise, explicit work materialization, and
  tenant-safe reads with target/policy validation and audit.
- [x] Implement File and PostgreSQL persistence plus the next migration,
  immutability, CAS, idempotency, and read-only consistency validation.
- [x] Add focused domain/auth/service/persistence/migration/restart/race/
  corruption/audit/resource-bound tests.
- [x] Update the P3E5 design, aggregation/halt design, threat model, glossary,
  and create the P3E5-1 implementation review using factual evidence only.
- [x] Review the complete Task 59 diff, run the approved consolidated
  validation matrix, record skips and blockers, and stop before P3E5-2.

## Validation

Completed affected-scope validation:

- Task-owned Dart formatting check — passed;
- `dart analyze --fatal-infos` for `packages/control_plane` — passed;
- focused domain/File/auth/service/migration tests without PostgreSQL — 11
  passed and the environment-gated PostgreSQL case skipped as expected;
- focused File/PostgreSQL persistence and migration tests against the running
  repository PostgreSQL 17 fixture — 6 passed, including concurrent equal
  writes and explicit close/reopen durability;
- complete control-plane suite with PostgreSQL enabled — 113 passed; one
  unchanged MinIO test skipped because `HYFENS_TEST_S3_*` is not configured;
- root `dart analyze --fatal-infos` — passed; root `dart test` — one passed;
- Markdown lint, local links, trailing whitespace, secret patterns, and
  prohibited claim/lease/execution-call scans — passed.

The full suite initially exposed a PostgreSQL unique-logical-key race: the
insert handled primary-key conflicts but not the independent logical-key
constraint. The adapter now handles every uniqueness conflict by reading and
comparing the canonical body; the complete suite passed after the regression
fix.

## Next Action

Maintainers review `docs/P3E5_1_SCHEDULE_WORK_PERSISTENCE_REVIEW.md` and decide
whether to authorize P3E5-2 claim/recovery. Do not begin P3E5-2, P3E5-3,
P3E5-4, P3E5-5, P3F, or P3G without a new explicit authorization.

## Blockers

None for P3E5-1. Existing P1D, provider, beta, production, store, and legal
readiness gates remain open.

## Outcome

P3E5-1 is implemented and validated for its bounded scope. The control plane
now persists strict immutable schedule revisions, deterministic pending work,
and append-only attempt evidence through File and PostgreSQL adapters. A
dedicated app/environment-scoped scheduler credential and independent
`health:schedule`/`health:work:claim` scopes enforce the least-privilege seam.
Explicit materialization reloads trusted rollout identity and creates no lease
or execution. P3E5-2 onward was not started.

## References

- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `docs/P3E5_1_SCHEDULE_WORK_PERSISTENCE_REVIEW.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Reserved Task 59 after explicit maintainer approval of the
  P3E-5 design and authorization of P3E5-1 only. P3E5-2 onward and P3F/P3G
  remain unauthorized.
- 2026-08-24: Implemented strict domain/codecs, canonical identities, state
  validation, scoped scheduler credentials, explicit schedule/materialization
  services, File persistence, PostgreSQL migration 005, and focused tests.
- 2026-08-24: The full PostgreSQL suite found and drove a regression fix for
  concurrent logical-key uniqueness. After the fix, 113 control-plane tests
  and the root test passed; one unrelated MinIO integration remained skipped.
- 2026-08-24: Completed factual design/security/review documentation and
  stopped at the required P3E5-1 maintainer-review gate.
