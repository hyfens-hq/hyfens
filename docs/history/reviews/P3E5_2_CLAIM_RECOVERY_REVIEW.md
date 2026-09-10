# P3E5-2 claim and recovery review

<!-- markdownlint-disable MD013 -->

Status: `READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/60-p3e5-2-claim-and-recovery.md`

## Decision and scope

P3E5-2 implements explicit, bounded claim and claim-side recovery operations
for the existing P3E5-1 scheduled-work model. P3E5-1 identities,
authorization, and immutable schedule history remain unchanged. No continuous
executor, health evaluation, automatic halt, rollout expansion, or runtime
behavior was added.

## Verified implementation

| Requirement | Executed evidence | Result |
| --- | --- | --- |
| Due selection | Exact scope and due-state/time filtering for `PENDING`, `RETRY_WAIT`, and expired `LEASED` work | PASS |
| PostgreSQL cooperation | Database time, bounded indexed query, `FOR UPDATE SKIP LOCKED`, one transaction, work CAS, and attempt append | PASS |
| Duplicate claimants | Two adapters raced one work item; exactly one initial current lease/attempt existed | PASS |
| Token fencing | Fresh opaque token, digest-only persistence, owner/scope/version/expiry checks, wrong-owner and old-token rejection | PASS |
| Expiry/reclaim | Expired claim produced a new owner, token, attempt number, and work version; prior token was fenced | PASS |
| Retry model | Typed four-class taxonomy, explicit versioned backoff, deterministic bounded jitter, retry wait, exhaustion, and manual-retry seam | PASS |
| Resource bounds | Explicit batch, consideration, recovery, attempt, owner/error, and active-lease limits; no production defaults | PASS |
| Fair selection | Oldest-due ordering plus round-robin across schedules inside an exact tenant scope and a per-tenant active cap | PASS (bounded scope) |
| File recovery | One-writer claim journal recovered a simulated crash after attempt persistence and preserved one work/attempt projection | PASS |
| PostgreSQL crash seams | Before-commit failure rolled back; after-commit/lost-response retained the lease and blocked a competitor | PASS |
| Least privilege | Claim accepted a scheduler with only `health:work:claim`; wrong app scope failed; evaluate/halt scopes were absent | PASS |
| Audit privacy | Claim audit omitted the raw lease token; action vocabulary covers claim/reclaim/retry/stale/cancel/manual/security outcomes | PASS |
| Migration | Migration 006 backfills timestamps, adds the claim index, upgrades under the advisory lock, and advances schema version to 6 | PASS |

## Failure and recovery behavior

PostgreSQL commits the work projection and immutable attempt in one short
transaction. A generated token is not authoritative before commit. If the
response is lost after commit, the persisted lease remains authoritative and
another claimant skips it until expiry. File mode writes a durable journal,
attempt, and work projection in that order; initialization completes any
remaining journal before serving reads or claims.

Claim-side mutation requires organization, application, environment, work ID,
expected work version, lease owner, token digest, `LEASED` state, and
unexpired authoritative time. Reclaim never reuses a token or silently rebinds
immutable work semantics.

## Fairness boundary

Every service call is intentionally bound to one scheduler credential and one
organization/application/environment. Inside that boundary, the active-lease
cap bounds consumption and selection rotates across schedules so one retry
source cannot consume the whole bounded batch. P3E5-2 does not create a global
cross-tenant worker or choose which tenant a future fleet invokes next;
P3E5-3 must preserve a starvation-resistant explicit invocation policy.

## Explicitly unchanged or not started

```text
P3E5-1 schedule/work identity and persistence semantics  UNCHANGED
P3E5-2 claim/recovery only                               IMPLEMENTED
P3E5-3 evaluation executor                              NOT STARTED
P3E5-4 automatic halt                                   NOT STARTED
P3E5-5 broad reconciliation/metrics                     NOT STARTED
P3F/P3G                                                  NOT STARTED
runtime/mobile                                           UNCHANGED
readiness gates                                          UNCHANGED
```

There is no timer, cron, daemon, queue, heartbeat, evaluation invocation, halt
invocation, automatic expansion, HOLD-to-pause, dashboard, production policy
value, or physical-device claim in this task.

## Residual risks and conditions

- Rollout target revalidation is performed after the schedule-store claim and
  before returning it; stale results are immediately fenced as `STALE`, but
  this cross-store check is not one distributed transaction.
- File persistence is single-process/single-writer and is not HA or safe for a
  shared multi-host filesystem.
- PostgreSQL evidence is local two-instance evidence, not provider failover,
  capacity, backup, or SLO evidence.
- Fleet-wide cross-tenant scheduling fairness and load calibration belong to
  the reviewed executor slice; P3E5-2 contains only bounded explicit calls.
- Existing P1D, provider, beta, production, store, and legal gates remain open.

## Recommendation

`AUTHORIZE P3E5-3 EXPLICIT WINDOW-READY EXECUTOR WITH CONDITIONS`

Conditions: retain explicit invocation and versioned resource policy; preserve
database-time fencing and exact tenant/target/currentness revalidation; add no
continuous loop, halt execution, expansion, or runtime trust in the first
executor slice; prove cross-tenant invocation fairness and evaluator
idempotency; and stop again before P3E5-4.

This recommendation does not authorize P3E5-3. Stop at the Task 60 maintainer
review gate.
