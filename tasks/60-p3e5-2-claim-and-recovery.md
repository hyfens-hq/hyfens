# Task 60 — P3E5-2 claim and recovery

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — maintainer review required

## Goal

Prove that authorized scheduler principals can select bounded due work, acquire
fenced leases, recover expired claims, and apply explicit bounded retry policy
through File and PostgreSQL persistence without executing health evaluation or
automatic halt behavior.

## Scope and Non-goals

Scope: typed/versioned lease, retry, and resource policies; cryptographically
strong opaque lease tokens with digest-only persistence; tenant-scoped bounded
claim selection; owner/token/work-version fencing; expiry/reclaim; stale-work
detection; retry wait/exhaustion; narrow manual retry and cancellation seams;
File single-writer and PostgreSQL cooperative claims; crash/restart recovery;
least-privilege scheduler authorization; redacted audit evidence; focused
concurrency, corruption, fairness, resource-bound, and recovery tests.

Non-goals: worker loops, timers, cron, queues, health evaluation, halt
application, automatic rollout mutation, HOLD-to-pause, heartbeats, production
policy values, P3E5-3 onward, P3F/P3G, runtime/mobile changes, dashboards, or
beta/production/store/legal claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E5-2 maintainer-review
gate.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK60_P3E5_2_CLAIM_AND_RECOVERY.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_1_SCHEDULE_WORK_PERSISTENCE_REVIEW.md`;
- `tasks/59-p3e5-1-schedule-work-domain-persistence.md`;
- existing P3E5-1 domain, authorization, File/PostgreSQL persistence, trusted
  rollout records, and audit chain.

## Assumptions

- PostgreSQL database time is authoritative for due, lease, expiry, reclaim,
  and retry timestamps; File mode uses an injected trusted UTC host clock.
- Policy objects and every numeric bound are supplied explicitly by the caller;
  the source selects no production values.
- File claim behavior remains one-process/one-writer and cannot establish
  cross-process distributed safety.
- Existing worktree content is maintainer-owned baseline and must be preserved;
  only Task 60-scoped seams and documents will change.
- A heartbeat is unnecessary for the bounded claim/recovery proof and remains
  outside this slice.

## Work Items

- [x] Map Task 59 domain/persistence/service seams and reserve the bounded
  implementation and validation plan.
- [x] Implement strict claim/retry/resource policy types, retry taxonomy,
  deterministic backoff, work projections, lease fencing, and malformed-input
  rejection.
- [x] Implement atomic File and PostgreSQL bounded claims, token-digest
  persistence, attempt append, SKIP LOCKED concurrency, fairness, expiry,
  reclaim, retry, cancellation, and restart recovery.
- [x] Implement exact-scope scheduler service operations and redacted audit
  events without requiring evaluation or halt scopes.
- [x] Add focused domain/auth/service/persistence/concurrency/restart/crash/
  corruption/fairness/resource-bound/audit tests.
- [x] Update only factual P3E5 design, threat-model, glossary, and P3E5-2 review
  documentation.
- [x] Review the combined Task 60 diff, fix in-scope findings, execute one
  consolidated affected/full validation pass, record evidence, and stop before
  P3E5-3.

## Validation

Completed validation after implementation and self-review:

- Dart format check over 48 control-plane library/test files — passed with zero
  changes after formatting;
- `dart analyze --fatal-infos` in `packages/control_plane` — passed;
- focused P3E5-2 tests with the repository PostgreSQL 17 fixture — seven
  passed, including File journal recovery, retry exhaustion/manual retry,
  two-instance claim, expiry/reclaim, old-token replay, and PostgreSQL
  before-/after-commit failure seams;
- complete control-plane suite with PostgreSQL enabled — 119 passed; one
  unchanged MinIO integration test skipped because `HYFENS_TEST_S3_*` is not
  configured;
- root `dart analyze --fatal-infos` — passed; root `dart test` — one passed;
- migration schema version/index sanity — version 6 and
  `control_plane_p3e5_work_claim_idx` present;
- Markdown lint for the five changed documents, local-reference existence,
  trailing-whitespace, secret-pattern, and prohibited evaluator/halt/worker
  scans — passed.

MinIO may remain skipped only if its existing environment variables are absent
and object-store behavior remains unchanged.

## Next Action

Maintainers review `docs/P3E5_2_CLAIM_RECOVERY_REVIEW.md` and choose whether to
authorize P3E5-3. Do not begin P3E5-3 or later work without a new explicit
authorization.

## Blockers

None for the bounded P3E5-2 slice. Existing P1D, provider, beta, production,
store, and legal readiness gates remain open.

## Outcome

P3E5-2 now provides explicitly invoked, exact-scope, bounded claim and
claim-side recovery through File and PostgreSQL adapters. PostgreSQL uses
database time, migration 006's indexed operational timestamps, row locks with
`SKIP LOCKED`, work-version CAS, and atomic attempt append. File mode retains
its one-writer boundary and uses a recovery journal. Fresh raw tokens are
returned only to claimants; durable state and audit retain digests. Expiry,
retry wait/exhaustion, manual retry, cancellation, stale binding, resource
caps, crash/restart, and replay fencing are implemented. P3E5-3 onward was not
started.

## References

- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Reserved Task 60 after explicit maintainer approval of P3E5-1
  and authorization of P3E5-2 claim/recovery only. P3E5-3 onward and P3F/P3G
  remain unauthorized.
- 2026-08-24: Implemented typed policies, fenced File/PostgreSQL claims,
  migration 006, retry/cancel/manual-retry seams, least-privilege service and
  audit boundaries, recovery journals/failure seams, and focused regression
  tests.
- 2026-08-24: Completed self-review, full control-plane/root validation,
  documentation, and the P3E5-2 review; stopped before P3E5-3.
