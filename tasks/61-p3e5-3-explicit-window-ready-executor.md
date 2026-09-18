# Task 61 — P3E5-3 explicit window-ready executor

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Prove that an explicitly invoked, authenticated scheduler executor can claim,
revalidate, and evaluate bounded window-ready work through the existing P3E-3
deterministic evaluator while preserving lease fencing, idempotency, tenant
fairness, crash recovery, and the no-automatic-rollout-mutation boundary.

## Scope and Non-goals

Scope: typed/versioned executor resource policy; explicit cursor-based
cross-tenant round-robin dispatch; scheduler authorization requiring claim,
evaluate, observation-read, and rollout-read scopes; P3E5-2 claim reuse;
current schedule/rollout/target/window/policy revalidation; persisted aggregate
revision linkage; fenced `LEASED → EVALUATING → EVALUATED` and non-halt
`EVALUATED → COMPLETED` transitions; existing P3E-3 evaluator invocation;
deterministic evaluation idempotency; bounded ambiguous-outcome recovery;
File/PostgreSQL duplicate/crash/fairness/security tests; factual documentation.

Non-goals: timers, cron, loops, queues, heartbeats, P3E-4 halt invocation,
automatic rollout mutation/expansion/pause, P3E5-5 broad reconciliation or
metrics, P3F/P3G, runtime/mobile changes, production numeric defaults,
dashboard/operator tooling, or readiness/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E5-3 maintainer-review
gate.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK61_P3E5_3_EXPLICIT_WINDOW_READY_EXECUTOR.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_2_CLAIM_RECOVERY_REVIEW.md`;
- `tasks/60-p3e5-2-claim-and-recovery.md`;
- existing P3E-3 evaluator/persistence, P3E5-2 claim/fencing, P3A rollout
  records, scheduler credentials, and redacted audit chain.

## Assumptions

- Explicit invocations carry all lease, retry, evaluation, and executor
  resource policies; source code selects no production value.
- Cross-tenant fairness is deterministic and restart-safe through an explicit
  caller-retained cursor returned by each bounded invocation; no hidden worker
  or timer owns dispatch state.
- A matching immutable P3E-2 aggregate revision is selected only from bounded
  persisted records and linked to work before evaluator invocation.
- Existing worktree content is maintainer-owned baseline and must be preserved.

## Work Items

- [x] Inspect the approved Task 61 boundary and map P3E5-2 claim, work-state,
  P3E-3 evaluator, persistence, authorization, and audit seams.
- [x] Implement typed executor resource/fairness policy, aggregate linkage,
  and fenced execution-state transitions.
- [x] Add a scheduler-only admission path that reuses existing P3E-3
  evaluation semantics and does not grant halt authority.
- [x] Implement explicit bounded dispatch, cross-tenant cursor rotation,
  currentness/window/policy checks, outcome handling, and narrow recovery.
- [x] Add focused File/PostgreSQL auth, outcome, idempotency, expiry/replay,
  duplicate, crash, fairness, malformed-evidence, and redaction tests.
- [x] Update only factual P3E5 design, threat model, and P3E5-3
  implementation-review documentation.
- [x] Review the complete Task 61 change, run consolidated validation, record
  evidence and skips, and stop before P3E5-4.

## Validation

- `dart format packages/control_plane/lib packages/control_plane/test/p3e_executor_test.dart` — PASS.
- package and root `dart analyze --fatal-infos` — PASS, no issues.
- focused File executor suite — PASS, 18 tests; PostgreSQL-only test skipped.
- focused executor suite against local PostgreSQL — PASS, 19 tests including
  genuinely independent two-adapter executor convergence.
- full control-plane suite against local PostgreSQL — PASS, 139 tests; one
  unchanged MinIO test skipped because `HYFENS_TEST_S3_*` was unavailable.
- root `dart test` — PASS, 1 test.
- `markdownlint` over all Task 61 documents — PASS.
- changed-scope whitespace, secret-pattern, and prohibited halt/worker/runtime
  scans — PASS. No SQL migration was required because operational links live
  in the existing JSON work body and old bodies decode with null links.

## Next Action

Maintainer review. Do not begin P3E5-4 without separate authorization.

## Blockers

None within the approved Task 61 scope. P3E5-4 remains an authorization gate,
not an implementation blocker for this completed slice.

## Outcome

Implemented an explicit, least-privilege, versioned and resource-bounded
executor over P3E5-2 claims and the existing P3E-3 evaluator. It persists
aggregate and evaluation evidence links, enforces authoritative window
readiness/currentness, recovers idempotently from every required ambiguity,
and leaves HALT_NEW_OFFERS at EVALUATED without rollout mutation. File and
two-instance PostgreSQL evidence passed. Recommendation:
`AUTHORIZE P3E5-4 DESIGN/REVIEW FIRST`.

## References

- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Reserved Task 61 after explicit approval of P3E5-2 and
  authorization of P3E5-3 explicit evaluator execution only. P3E5-4 onward
  remain unauthorized.
- 2026-08-24: Completed implementation, self-review, File/PostgreSQL failure
  evidence, full control-plane/root validation, security/design addenda, and
  the maintainer review. Stopped before P3E5-4 as required.
