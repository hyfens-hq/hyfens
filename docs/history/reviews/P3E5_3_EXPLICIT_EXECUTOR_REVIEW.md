# P3E5-3 explicit window-ready executor review

<!-- markdownlint-disable MD013 -->

Status: `READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/61-p3e5-3-explicit-window-ready-executor.md`

## Decision and scope

P3E5-3 implements an explicitly invoked evaluator executor over the existing
P3E5-2 claims and P3E-3 deterministic evaluator. It does not add a timer,
daemon, poll loop, queue, heartbeat, broad reconciliation, automatic halt,
rollout expansion, dashboard, production scheduling values, or runtime/mobile
change.

## Verified implementation

| Requirement | Executed evidence | Result |
| --- | --- | --- |
| Explicit bounded invocation | Typed version-1 policy bounds batch, total work, duration, aggregate load, retries, tenant scopes, and cursor fairness | PASS |
| Least privilege | Exact scheduler app/environment with claim + evaluate + observation-read + rollout-read; no halt scope required | PASS |
| Claim and fencing reuse | All acquisition/reclaim uses P3E5-2; every execution mutation verifies scope, owner, token digest, work version, state, and expiry | PASS |
| Currentness | Reloaded current schedule revision/generation, evaluation/threshold/window/privacy policy, current rollout/revision/state, and exact target digest | PASS |
| Window readiness | `CLOSED`/`SEALED` phase is derived from authoritative lease acquisition time and checked with `notBefore`; premature evidence is rejected | PASS |
| Evaluator reuse | Existing P3E-3 implementation and persisted aggregate/evaluation/decision stores are used without copied counters or alternate decision logic | PASS |
| Idempotency | Downstream key is exactly `scheduled-evaluation:<workId>` | PASS |
| Advisory outcomes | CONTINUE, HOLD, INSUFFICIENT_DATA, and MANUAL_REVIEW reach COMPLETED with no rollout revision | PASS |
| Halt boundary | HALT_NEW_OFFERS persists evidence and stops at EVALUATED; rollout remains CANARY revision 1 | PASS |
| Crash recovery | Failure injection after EVALUATING, evaluator commit, EVALUATED, and before response converges without duplicate semantic evidence | PASS |
| Lease expiry | Stale completion is fenced; a new claimant reuses committed evaluator evidence | PASS |
| Duplicate executors | Two PostgreSQL-backed executor instances race one work item and produce one evaluation and decision | PASS |
| Old-token/owner replay | Wrong owner and expired predecessor token cannot advance execution state | PASS |
| Retry taxonomy | Excess aggregate load enters bounded TRANSIENT retry; stale rollout becomes STALE; missing evidence becomes PERMANENT | PASS |
| Cross-tenant fairness | The exact cursor primitive used by dispatch rotates two constrained tenant scopes; tenant B is selected on the second one-slot invocation despite tenant A backlog | PASS (bounded algorithm) |
| File mode | All outcome/recovery tests pass in one-process/one-writer File mode | PASS (declared boundary) |
| Audit privacy | Invocation/start/completion events are present; raw credentials and raw lease tokens are absent while the non-secret lease digest remains auditable | PASS |

## State and recovery contract

```text
PENDING/RETRY_WAIT
  -> P3E5-2 claim -> LEASED
  -> EVALUATING (aggregate revision linked)
  -> P3E-3 idempotent evaluation
  -> EVALUATED (evaluation + decision linked)
       -> COMPLETED              non-halt advisory result
       -> remain EVALUATED       HALT_NEW_OFFERS
```

An expired `EVALUATING` or `EVALUATED` lease is reclaimed in the same state
with a new token, owner, attempt, and work version. Recovery does not infer
success from a response. It reloads immutable evidence and validates tenant,
rollout revision, aggregate revision, target digest, decision linkage,
idempotency key, and absence of a rollout transition reference.

## Validation evidence

The focused File suite passed 18 tests with one PostgreSQL-only skip when run
without a database variable. With the already-running local PostgreSQL fixture,
the same suite passed all 19 tests, including the two-instance executor race.
The full control-plane suite passed 139 tests with only the unchanged MinIO
integration skipped because S3 variables were not configured. Root analysis
and its repository test passed; scoped Markdown lint, whitespace, secret, and
prohibited-boundary scans also passed.

Commands are recorded in Task 61. Test values are deterministic vectors only,
not production defaults or SLOs.

## Limitations and residual risks

- Cross-tenant fairness is a bounded deterministic dispatcher/cursor proof,
  not provider fleet scheduling, durable cursor service, or load calibration.
- File mode remains single process and single writer.
- Aggregate selection uses the existing organization-scoped evidence listing
  and fails closed when the explicit load bound is exceeded; a future indexed
  exact lookup may be justified by measurements.
- The schedule, rollout, aggregate, evaluation, and work stores are not one
  distributed transaction. Currentness checks, idempotency, and fencing bound
  ambiguity but do not provide global serializability.
- No heartbeat exists. Evaluation exceeding its lease relies on fencing,
  expiry, and idempotent replay.
- Local PostgreSQL evidence is not provider failover, capacity, backup, SLO,
  beta, production, App Store, Google Play, or legal evidence.
- Existing P1D and provider-readiness gates remain open and unchanged.

## Explicitly unchanged or not started

```text
P3E5-4 automatic halt                              NOT STARTED
P3E5-5 broad reconciliation/metrics                NOT STARTED
P3F/P3G                                            NOT STARTED
continuous scheduler/timer/queue/heartbeat         NOT STARTED
automatic rollout expansion or HOLD-to-pause       NOT STARTED
runtime/mobile and cryptographic trust invariants  UNCHANGED
```

## Recommendation

`AUTHORIZE P3E5-4 DESIGN/REVIEW FIRST`

P3E5-3 is sufficient to close explicit advisory execution within its bounded
scope. P3E5-4 would introduce automatic rollout mutation and therefore should
receive a separate design/threat review before implementation. This
recommendation does not authorize P3E5-4; stop at this maintainer-review gate.
