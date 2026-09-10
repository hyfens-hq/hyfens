# P3E-5 scheduled-evaluation design

<!-- Wide design tables disable MD013. -->
<!-- markdownlint-disable MD013 -->

Status: `DESIGN COMPLETE — MAINTAINER REVIEW REQUIRED`

Date: 2026-08-24

Task: `tasks/58-p3e5-scheduled-evaluation-design.md`

Implementation status: `NOT AUTHORIZED`

## 1. Decision boundary

P3E-5 is an orchestration design for scheduling one exact P3E-3 evaluation.
It does not define a new evaluator or rollout state machine. The only permitted
mutation chain remains:

```text
scheduled work
  -> existing P3E-3 evaluation
  -> immutable HealthEvaluation and RolloutDecision
  -> existing P3E-4 apply, only for HALT_NEW_OFFERS when enabled
  -> existing P3A expected-revision CAS
  -> future candidate offers stop
```

The scheduler never writes a rollout pointer or revision, never interprets
patch bytes, and never becomes runtime trust. At-least-once work execution plus
P3E-3/P3E-4/P3A idempotency is the safety model. Exactly-once execution and a
distributed transaction are explicitly not required.

This document contains no scheduler, timer, worker, queue, work table,
migration, API, or automatic halt implementation.

## 2. Evidence and frozen invariants

The design relies on these already implemented and tested facts:

- `ObservationWindow.phaseAt(serverNow)` derives `OPEN`, `CLOSED`, and
  `SEALED` only from an explicit server-time reference;
- P3E-3 binds one evaluation to the exact tenant, rollout revision, aggregate
  revision, window, policy versions, input digest, and target-binding digest;
- a deterministic P3E-3 idempotency key reuses the same immutable evaluation
  and decision or rejects a conflicting body;
- P3E-4 accepts only `HALT_NEW_OFFERS`, revalidates exact current evidence,
  and uses the P3A halt transition with expected-revision CAS;
- P3E-4 equal retries, different-key retries, manual-halt races,
  expansion races, and two-instance PostgreSQL races cannot create a second
  halt revision; and
- File persistence is single-node while PostgreSQL is the tested
  multi-instance consistency boundary.

P3E-5 must not change Architecture B, Patch Format v1, capability v1, exact
application/environment/release/patch/function/capability binding, state-v4
high-water, runtime signature authority, signed rollback, fail-closed
recovery, AOT fallback, customer/local signing custody, artifact immutability,
P3A, P3D, or P3E-1 through P3E-4 semantics.

## 3. Canonical domain language

| Term | Meaning |
| --- | --- |
| Evaluation schedule | Stable tenant-scoped identity for the intent to create future evaluation work for one rollout. It is not a cron expression or rollout authority. |
| Schedule revision | Immutable version of schedule configuration, policy references, readiness phase, and enablement flags. A change creates a new revision and generation. |
| Logical evaluation key | Canonical immutable identity of one scheduled evaluation meaning. Equal keys must converge to the same work ID. |
| Scheduled evaluation work | Durable orchestration record for one logical evaluation key. It links downstream evidence but never overrides it. |
| Work attempt | Append-only record of one claim/execution attempt, including safe outcome codes and lease identity. |
| Lease | Time-bounded, token-guarded permission for one scheduler principal to advance one work item. It is not ownership of evaluation or rollout truth. |
| Automatic halt | Optional routing of an already-persisted `HALT_NEW_OFFERS` decision through P3E-4. It is distinct from scheduled evaluation and defaults off. |
| Reconciliation | Idempotent comparison of work state with immutable P3E-3/P3E-4/P3A evidence after retries or crashes. It does not repair evidence by mutation. |

Avoid the overloaded term “job” in public contracts. Use “scheduled evaluation
work” for the logical unit and “work attempt” for one execution.

## 4. Scheduler ownership options

| Option | Single-node self-host | Two-instance behavior | Duplicate/failure behavior | Complexity and portability | Disposition |
| --- | --- | --- | --- | --- | --- |
| Single control-plane process with local lease | Simple while exactly one process runs | Requires separate leader election or allows duplicate ownership | Process loss can strand memory-owned timing; durable recovery must be added separately | Low initial complexity but couples request serving and scheduling | Rejected as the ownership model |
| Database-backed cooperative scheduler | One scheduler instance can use the same durable model | PostgreSQL row claim, lease token, expiry, and CAS allow safe cooperative execution | At-least-once attempts; downstream idempotency and reconciliation handle crashes | No new queue dependency; portable across self-hosted and provider PostgreSQL | Recommended default |
| External scheduler invoking an endpoint | Easy wake-up integration | External system may invoke concurrently; durable internal work is still required | External retries alone cannot preserve logical identity, leases, or crash reconciliation | Provider-specific timers can remain optional wake-up adapters | Not authoritative; optional wake-up only |
| Separate worker using shared PostgreSQL claims | Natural process isolation and independent scaling | Same safe behavior as database-backed cooperation | Same lease/idempotency model | Extra deployment role, but no distinct consistency model | Supported deployment shape after the domain seam is proven |

### Recommendation

Scheduling ownership belongs to the durable work store, not an HTTP process,
external cron, or queue message. The first implementation should use a
database-backed cooperative scheduler:

- PostgreSQL is authoritative for multi-instance work claims and operational
  work state;
- one or more scheduler executors may claim work through that store;
- the executor may initially run as one explicit process/command and later as
  a separate replicated worker without changing ownership semantics;
- File mode uses the same domain state machine but is strictly one process,
  one writer, with restart recovery and no distributed lease claim; and
- an external timer may wake the scheduler later, but cannot define work,
  bypass claims, or call P3E-3/P3E-4 without the durable record.

Kafka, Redis, Kinesis, Pub/Sub, Celery, and managed queues are not needed for
this boundary.

## 5. Component and authority map

```text
authorized schedule command
        |
        v
EvaluationSchedule -> immutable EvaluationScheduleRevision
        |
        v
deterministic ScheduledEvaluationWork <- PostgreSQL claim / File single writer
        |
        v
lease holder revalidates rollout + window + policy
        |
        v
existing P3E-3 evaluation -------------------------+
        |                                           |
        | CONTINUE / HOLD / INSUFFICIENT / REVIEW   | HALT_NEW_OFFERS
        v                                           v
     COMPLETED                         automaticHaltEnabled?
                                               /          \
                                             no            yes
                                             |              |
                                             v              v
                                         COMPLETED   existing P3E-4 apply
                                                            |
                                                            v
                                                  existing P3A CAS
```

The work projection may say an attempt completed, but the immutable P3E-3
evaluation, P3E-4 application, and P3A revision are authoritative for their
own domains.

## 6. Conceptual entities

### `EvaluationSchedule`

Stable tenant-scoped schedule identity:

```text
scheduleId
organizationId
applicationId
environmentId
rolloutId
currentScheduleRevision
createdAt
createdBy
```

The current-revision pointer is an operational CAS pointer. It does not make
old revisions mutable and does not authorize rollout behavior.

### `EvaluationScheduleRevision`

Immutable configuration revision:

```text
scheduleRevisionId
scheduleId
scheduleGeneration
organizationId
applicationId
environmentId
rolloutId
scheduledEvaluationEnabled
automaticHaltEnabled
readinessPhase              CLOSED | SEALED
triggerPolicyVersion
schedulePolicyVersion
evaluationPolicyVersion
evaluationPolicyDigest
thresholdSetVersion
thresholdSetDigest
aggregationVersion
windowPolicyVersion
privacyPolicyVersion
retryPolicyReference
resourcePolicyReference
supersedesScheduleRevisionId
createdAt
createdBy
reason
```

No cadence, retry, lease, or resource values receive production defaults in
this task. References identify a separately approved versioned policy.

### `ScheduledEvaluationWork`

Durable projection for one immutable logical key:

```text
workId
logicalKey
status
workVersion
attemptCount
notBefore
leaseOwner
leaseToken
leaseAcquiredAt
leaseExpiresAt
createdAt
updatedAt
lastAttemptAt
lastErrorClass
lastErrorCode
evaluationId
decisionId
haltApplicationId
```

All logical-key fields are immutable. Only operational fields advance through
expected-work-version CAS. A work record cannot create, alter, or override a
P3E evaluation, decision, halt application, or rollout revision.

### `ScheduledEvaluationAttempt`

Append-only attempt evidence:

```text
attemptId
workId
attemptNumber
leaseOwner
leaseTokenDigest
startedAt
finishedAt
outcome
errorClass
safeErrorCode
evaluationId
decisionId
haltApplicationId
actorIdentity
```

Tokens, raw observations, installation identities, stack traces, patch bytes,
and business data are never stored in attempt evidence. Only a one-way lease
token digest may be retained after the attempt.

## 7. Logical key and deterministic IDs

The canonical logical evaluation key is a versioned object containing at
least:

```text
logicalKeyVersion
organizationId
applicationId
environmentId
platformId
rolloutId
rolloutRevision
releaseId
patchId
sequence
targetBindingDigest
windowId
readinessPhase
observationSchemaVersion
aggregationVersion
aggregatePolicyDigest
evaluationPolicyVersion
evaluationPolicyDigest
thresholdSetVersion
thresholdSetDigest
windowPolicyVersion
privacyPolicyVersion
scheduleId
scheduleRevisionId
scheduleGeneration
```

`readinessPhase` is part of the key so a `CLOSED` preliminary evaluation and a
later `SEALED` final evaluation can never collide. A policy, target, rollout
revision, schedule generation, or readiness change creates a new logical key.
An existing work item is never edited to mean the new configuration.

Deterministic identities are derived from canonical bytes:

```text
workId = hash("hyfens.p3e5.work.v1" || canonicalLogicalKey)
evaluationIdempotencyKey = "scheduled-evaluation:" || workId
haltIdempotencyKey = "scheduled-halt:" || workId
attemptId = hash("hyfens.p3e5.attempt.v1" || workId || attemptNumber)
```

The implementation must collision-check the canonical logical key when a
derived ID already exists. Equal keys acknowledge the existing work; unequal
keys with the same ID fail closed.

## 8. Schedule registration and revision semantics

Schedule creation is explicit and authenticated. It creates an
`EvaluationSchedule` plus revision 1. `scheduledEvaluationEnabled` and
`automaticHaltEnabled` are independent:

```text
scheduledEvaluationEnabled = false unless explicitly selected
automaticHaltEnabled = false unless explicitly selected
```

Updating cadence, trigger phase, policy, thresholds, privacy policy, or either
enablement flag creates a new immutable schedule revision and increments
`scheduleGeneration`. It never edits the previous revision.

Activation of the new revision:

1. validates exact tenant/application/environment/rollout scope;
2. records the new revision and its audit event;
3. makes the schedule pointer reference the new revision through CAS;
4. stops creation of work from the superseded revision; and
5. cancels only its still-pending or retry-wait work. Claimed work is allowed
   to finish only after it revalidates the active schedule revision; otherwise
   it becomes `STALE`.

Completed evaluations, decisions, halt applications, attempts, and audit
history are never deleted or rewritten by a schedule update.

## 9. Work state machine

The bounded states are:

```text
PENDING
LEASED
EVALUATING
EVALUATED
HALT_APPLYING
RETRY_WAIT
COMPLETED
STALE
FAILED_PERMANENT
CANCELLED
```

`COMPLETED`, `STALE`, and `CANCELLED` are terminal. `FAILED_PERMANENT` is
terminal for automatic processing; only an authenticated manual retry may
move it to `RETRY_WAIT` with a new attempt.

```text
PENDING --------claim--------> LEASED ----start----> EVALUATING
   |                              ^                       |
   | cancel                       | reclaim expired       | evaluation stored
   v                              | lease after reconcile v
CANCELLED                  RETRY_WAIT <------------- EVALUATED
                                  ^                    /     \
                                  | transient         /       \ no halt action
                                  |                  v         v
                         HALT_APPLYING            COMPLETED  COMPLETED
                                  |
                                  +----applied/already applied----> COMPLETED

Any active state --stale binding--> STALE
Any execution state --permanent/security--> FAILED_PERMANENT
```

### Allowed transitions and guards

| From | To | Guard |
| --- | --- | --- |
| `PENDING` | `LEASED` | Work is due, enabled, current, within resource bounds, and claimed by work-version CAS. |
| `RETRY_WAIT` | `LEASED` | `notBefore` has passed in server/database time and attempts remain. |
| `LEASED` | `EVALUATING` | Caller presents the current unexpired lease token and revalidation succeeds. |
| `EVALUATING` | `EVALUATED` | Existing P3E-3 returned or replayed immutable evaluation and decision IDs. |
| `EVALUATED` | `HALT_APPLYING` | Decision is `HALT_NEW_OFFERS`, automatic halt is enabled, phase is eligible, and all current preconditions pass. |
| `EVALUATED` | `COMPLETED` | Decision requires no mutation, automatic halt is disabled, or the result is advisory only. |
| `HALT_APPLYING` | `COMPLETED` | P3E-4 returned `APPLIED` or `ALREADY_APPLIED`, or reconciliation found the matching application. |
| Active state | `RETRY_WAIT` | Error is transient, attempts remain, and bounded backoff computes a future `notBefore`. |
| Active state | `STALE` | Any immutable rollout/window/schedule/policy binding is no longer current. |
| Active state | `FAILED_PERMANENT` | Error is permanent/security, or transient retry budget is exhausted. |
| `PENDING` or `RETRY_WAIT` | `CANCELLED` | Authorized cancellation CAS wins before a claim. |
| `FAILED_PERMANENT` | `RETRY_WAIT` | Explicit authorized manual retry creates a new attempt and passes staleness checks. |

No generic `RUNNING` state exists. Every non-terminal execution state has an
explicit lease and purpose.

## 10. Initial trigger and window-readiness recommendation

The smallest initial trigger set is:

1. explicit schedule registration for one exact rollout/window policy;
2. one server-time `WINDOW_READY` trigger per schedule revision; and
3. explicit manual retry of failed work.

Each schedule revision chooses exactly one initial readiness phase:

- `CLOSED`: work is not due before `window.serverEnd`; its result is
  preliminary/advisory and automatic halt is prohibited in the initial
  implementation; or
- `SEALED`: work is not due before `window.lateCutoff`; its result is the
  initial recommended input for optional automatic halt.

The default recommendation is `SEALED`. There is no production timing default;
the phase is an explicit policy choice. `OPEN` windows are never scheduled as
complete work. P3E-3 remains available for explicit partial/manual evaluation.

Minimum-event milestones, fixed periodic review, and continuous event-stream
triggers are deferred. They add rescheduling, fairness, and duplicate-pressure
semantics without being necessary to prove orchestration safety.

## 11. Late-data behavior

If a later schedule supports both phases, it creates two immutable logical work
items:

```text
windowId + CLOSED -> preliminary immutable evaluation, no automatic halt
windowId + SEALED -> new final immutable evaluation, optional halt eligibility
```

The sealed result does not overwrite or reinterpret the closed result. Late
events are included only according to existing P3E aggregation/window policy.
Client timestamps cannot extend `serverEnd`, move `lateCutoff`, or change the
work phase.

## 12. Timing and cadence policy shape

All time decisions use server/database time. A future versioned scheduling
policy must supply and validate:

```text
evaluation interval, if periodic review is later enabled
minimum reschedule interval
initial retry delay
maximum retry delay
retry jitter policy
lease duration
heartbeat interval, if heartbeat is enabled
maximum attempts
late-cutoff delay through the immutable ObservationWindow
lookahead horizon
```

Task 58 selects no numeric production values or SLOs. Future test values must
be labelled `DESIGN EXAMPLE ONLY — NOT PRODUCTION POLICY`.

## 13. PostgreSQL claim and lease semantics

PostgreSQL multi-instance claiming should use one transaction over durable
work rows:

1. obtain database time;
2. select a bounded due set ordered by fairness policy with row locks and
   `SKIP LOCKED` or equivalent;
3. recheck schedule enablement and non-terminal work state;
4. increment the attempt counter;
5. set `LEASED`, a new opaque lease token digest, lease owner, acquisition
   time, expiry, and work version; and
6. commit before performing P3E evaluation.

Every subsequent state advance compares organization ID, work ID, work
version, lease token, lease owner, and unexpired lease. A stale token cannot
extend or complete another worker's attempt.

The lease model contains:

```text
leaseOwner       bounded scheduler-principal/instance identity
leaseToken       random per-claim secret; only its digest persists in history
leaseAcquiredAt  database time
leaseExpiresAt   database time
heartbeat        optional bounded compare-and-set extension
```

Heartbeat is not required for the first proof if execution is demonstrably
bounded below the approved lease policy. If enabled later, it extends only the
current token's lease, cannot change logical work, and is not individually
audited.

After expiry another worker may reclaim the work. Reclaim creates a new
attempt and token only after reconciling downstream P3E-3/P3E-4 evidence and
revalidating the complete logical key. The old worker can no longer commit the
work projection, although its duplicate downstream call remains safe through
idempotency and P3A CAS.

## 14. File-mode ownership

File mode is a bounded self-host profile:

```text
one scheduler process
one writer
atomic work-state replacement
append-only attempt records
restart reconciliation
no cross-process lease or HA claim
```

It may retain lease-shaped fields for domain consistency, but those fields do
not establish distributed safety. Starting a second File scheduler must fail
operator validation rather than advertise cooperative scheduling.

## 15. Execution protocol

One leased attempt follows this order:

1. **Revalidate scope:** tenant, application, environment, rollout, target,
   schedule revision, generation, policy digests, and window phase.
2. **Reconcile first:** look for deterministic P3E-3 evaluation/decision and
   P3E-4 application IDs left by an earlier attempt.
3. **Evaluate if absent:** call the existing P3E-3 service with the exact
   aggregate revision and `scheduled-evaluation:{workId}` idempotency key.
4. **Persist links:** record evaluation and decision IDs in the work projection
   through lease/work-version CAS. P3E-3 evidence was already committed and
   remains authoritative if this write fails.
5. **Classify decision:** preserve the P3E-3 result without reinterpreting it.
6. **Apply halt only when allowed:** for eligible `HALT_NEW_OFFERS`, call the
   existing P3E-4 path with `scheduled-halt:{workId}` after another complete
   staleness and enablement check.
7. **Complete or retry:** link immutable downstream evidence and append the
   safe attempt result.

The worker never reads counters from a local cache after an authoritative
store failure and never performs a rollout write directly.

## 16. Decision routing

| P3E-3 decision | Scheduled-work result | Permitted mutation |
| --- | --- | --- |
| `CONTINUE` | `COMPLETED` with evaluation/decision links | None. It never expands, resumes, starts, or changes percentage. |
| `HOLD` | `COMPLETED` as advisory evidence, or a later separately scheduled evaluation | None. It never maps to pause. |
| `INSUFFICIENT_DATA` | `COMPLETED` as evidence; later windows may create new work | None. It is not treated as healthy. |
| `MANUAL_REVIEW` | `COMPLETED` with operator attention code | None. No automatic retry unless the underlying error is separately classified transient. |
| `HALT_NEW_OFFERS` with automatic halt disabled | `COMPLETED` with decision link and explicit `HALT_NOT_ENABLED` outcome | None. |
| `HALT_NEW_OFFERS` with automatic halt enabled and current sealed evidence | `HALT_APPLYING`, then P3E-4 result | Existing P3E-4/P3A halt only. |

Observation or delivery outages retain P3E-3 classification. The scheduler
cannot convert `HOLD`, `INSUFFICIENT_DATA`, or a delivery-only reason into a
patch-safety halt.

## 17. Automatic-halt enablement and preconditions

Scheduled evaluation and automatic halt are two independent controls.
Automatic halt defaults off and should require explicit schedule-revision
configuration plus a distinct, narrowly scoped Auto-Halt Principal. Task 62
supersedes the earlier combined scheduler-principal proposal: evaluation and
halt authority must not be carried by the same service credential.

Before P3E-4 is invoked, all of these must still hold:

```text
scheduledEvaluationEnabled == true
automaticHaltEnabled == true
decision == HALT_NEW_OFFERS
reason class is eligible under the exact approved evaluation policy
readinessPhase == SEALED for the initial implementation
schedule revision/generation is active
rollout revision and complete target are unchanged
window, aggregate, evaluation, threshold, privacy, and policy bindings match
P3E-4 applicability validation passes
worker holds the current lease token
```

Failure of any currentness check produces `STALE` or a completed advisory
result, never a direct state mutation. Even when all preconditions pass,
P3E-4 remains the authority and may reject the application.

No configuration enables automatic expansion, `HOLD` to pause, automatic
runtime rollback, artifact revocation, installed-patch invalidation, or
high-water change.

## 18. Rollout-state behavior

| Current P3A state | Scheduled evaluation | Automatic P3E-4 halt |
| --- | --- | --- |
| `INTERNAL`, `CANARY`, `EXPANDING` | Allowed only for an exact current revision and enabled schedule | Allowed only under all automatic-halt preconditions and existing P3A transition rules |
| `PAUSED` | May produce advisory evidence only from newly created work bound to the paused revision | May call P3E-4 only when explicitly enabled and P3A still permits halt from that paused revision |
| `HALTED` | No new automatic work; pending/active prior-revision work becomes stale | Never unhalt or create another halt revision |
| `COMPLETED` | No new automatic work; pending work becomes stale | Not applicable; P3A does not permit halt from completed |
| `RETIRED` | No new work; pending work becomes stale/cancelled | Never |
| `DRAFT`, `READY` | Initial design does not auto-schedule health work before offers begin | Never |

A pause, expansion, completion, retirement, manual halt, target replacement,
or any other current-revision change makes old work stale. Evaluation of the
new state requires a new logical key. A scheduler never overwrites a newer
manual action.

## 19. Staleness checkpoints

Staleness is checked:

1. when work is materialized;
2. when it is claimed;
3. before P3E-3 evaluation;
4. after P3E-3 returns and before decision routing;
5. immediately before P3E-4 application; and
6. during retry/reconciliation.

A work item is `STALE` when any exact binding changes or is no longer eligible:

```text
rollout revision or target
rollout state becomes terminal
window identity/readiness phase
aggregate, evaluation, threshold, window, or privacy policy version/digest
schedule revision/generation or enablement
tenant/application/environment scope
```

Historical evaluation evidence is preserved if staleness is discovered after
P3E-3 commits. It cannot be applied to the new revision. P3E-4 and P3A provide
the final stale/race rejection even if a scheduler check races.

## 20. Retry taxonomy

| Class | Examples | Automatic behavior |
| --- | --- | --- |
| `TRANSIENT` | database/observation store temporarily unavailable, bounded dependency timeout, lease lost before downstream commit | Move to `RETRY_WAIT` if budget remains; use bounded policy delay and jitter |
| `STALE` | rollout revision changed, schedule superseded, window/policy binding replaced, rollout terminal | Mark `STALE`; never retry the old logical key |
| `PERMANENT` | unsupported version, invalid immutable configuration, malformed persisted evidence, retry budget exhausted | Mark `FAILED_PERMANENT`; require operator correction and explicit retry/new work |
| `SECURITY` | tenant mismatch, lease-token mismatch, scope violation, evidence digest conflict, worker impersonation signal | Fail closed to `FAILED_PERMANENT`, audit a bounded security code, and never auto-retry |

Observation unavailability may either produce an immutable P3E-3
`HOLD`/`INSUFFICIENT_DATA` result or a `TRANSIENT` orchestration error,
according to the exact approved evaluation policy. It never defaults to
healthy or halt.

## 21. Backoff and retry rules

A future versioned retry policy defines positive bounded values and relations:

```text
initialDelay
maximumDelay >= initialDelay
maximumAttempts
jitterMode and bounded jitter range
leaseDuration
optional heartbeat interval < leaseDuration
```

Task 58 selects no values. Retry delay is derived deterministically from the
work/attempt plus bounded jitter so restarts do not erase the backoff state.
`notBefore` uses server/database time.

Retries retain the same logical work ID and downstream idempotency keys while
creating a new append-only attempt. Permanent and security failures never loop
automatically. `FAILED_PERMANENT` is the bounded poison-work state; no external
DLQ platform is required.

## 22. Manual retry and cancellation

An authorized manual retry:

- retains the original logical key and work ID;
- records actor identity and a bounded reason;
- performs full staleness/current-policy validation;
- creates a new append-only attempt;
- moves only `FAILED_PERMANENT` or explicitly retryable work to `RETRY_WAIT`;
- reuses P3E-3 and P3E-4 idempotency keys; and
- cannot alter evaluation inputs, schedule generation, or rollout target.

If corrected policy or rollout identity is required, the operator creates a
new schedule revision and therefore new work instead of retrying the old key.

Manual cancellation is allowed only for `PENDING` or `RETRY_WAIT` work. It
creates an audit record and moves the work to `CANCELLED`. Claimed work cannot
be forcibly erased; cancellation of its schedule makes the worker fail the
next revalidation and become `STALE`. Cancellation never deletes evaluations,
decisions, applications, attempts, audit evidence, or rollout history.

## 23. Crash and restart recovery

| Failure point | Recovery behavior |
| --- | --- |
| Clean restart | Reload due work and current schedule revisions; claim normally. |
| Crash while `LEASED` before evaluation | Lease expires; next worker reconciles, finds no downstream evidence, and creates a new attempt. |
| Crash after P3E-3 evaluation before work update | Retry derives the same evaluation ID/idempotency key, reads/replays immutable evaluation and decision, links them, and continues. |
| Crash after work is `EVALUATED` | Retry routes the persisted decision; no reevaluation with new semantics. |
| Crash during P3E-4 call | Retry uses the same application idempotency key; P3E-4 returns/reconciles `APPLIED` or `ALREADY_APPLIED`. |
| Crash after P3E-4/P3A commit before work update | Reconciliation finds the halt application/transition, links it, and marks `COMPLETED`; no second rollout revision. |
| Worker continues after lease theft/expiry | Work-state CAS rejects its stale token; downstream duplicate calls remain bounded by idempotency and expected-revision CAS. |

No recovery path evaluates from stale cache or mutates immutable downstream
evidence. Installed runtime behavior is unaffected by scheduler availability.

## 24. Cross-store reconciliation

P3E work, P3E evidence, and P3A rollout state are separate persistence
boundaries. The design uses deterministic identities and reconciliation, not
two-phase commit.

| Observed condition | Reconciliation result |
| --- | --- |
| Work says `PENDING`/`EVALUATING`, matching evaluation and decision exist | Validate exact bindings, link IDs, advance to `EVALUATED` under work CAS |
| Active work lease expired and no evaluation exists | Revalidate currentness, then make it reclaimable with a new attempt |
| Evaluation is `HALT_NEW_OFFERS`, automatic halt disabled | Link decision and complete with `HALT_NOT_ENABLED` |
| Evaluation is `HALT_NEW_OFFERS`, matching halt application exists | Validate application/transition linkage and complete |
| Halt application exists but work is incomplete | Link application; confirm P3A history; complete or fail closed if evidence conflicts |
| Rollout already halted manually with no matching P3E-4 application | Mark old work `STALE`; do not manufacture a health-halt link |
| Rollout revision/policy/schedule changed | Mark `STALE`; preserve all historical evidence |
| Conflicting deterministic ID/body | Mark security/permanent failure and audit; never select one silently |

Reconciliation itself is bounded, tenant-scoped, idempotent, paginated, and
safe to repeat. It never deletes or rewrites P3E-3/P3E-4/P3A evidence.

## 25. Authorization and service-principal design

Future authorization separates human schedule administration from work
execution:

| Actor/capability | Required scope | Explicitly absent |
| --- | --- | --- |
| Schedule administrator | `health:schedule` plus `rollout:read` in exact tenant/application/environment scope | Signing, artifact mutation, credential administration unless independently granted |
| Evaluation-only scheduler principal | `health:work:claim`, `health:evaluate`, `observation:read`, `rollout:read` | `rollout:halt`, signing, artifact mutation, rollout promotion |
| Auto-Halt Principal | `health:work:apply-halt`, `rollout:read`, and `rollout:halt`; application also requires the current fenced work lease | Generic claim/evaluate, observation, schedule administration, signing, artifact/release mutation, promotion, and credential administration |
| Manual retry/cancel operator | `health:schedule` and scoped work access | Evaluation/halt authority unless separately granted |

The worker identity is a bounded non-human service principal scoped to one
organization/application/environment, with rotation/expiry, revocation, and
audit actor identity. It has no signing authority, artifact access, broad
credential administration, or runtime authority.

### Current-code prerequisite

P3E5-1 provides a dedicated application/environment-scoped scheduler
credential, and P3E5-3 accepts its evaluation-only scope profile. P3E-4 still
requires a control credential for health-halt application. Task 62 therefore
selects a separate exact-scope Auto-Halt Principal plus a narrow authorization
adapter into the existing P3E-4 application core. The existing optional
scheduler halt grant is not selected for automatic halt. A future automatic
application must prove both a current fenced work lease and the distinct
Auto-Halt Principal; disabling automatic halt grants neither mutation
authority nor an alternative route around P3E-4.

## 26. Tenant isolation, fairness, and resource bounds

Every schedule, revision, work item, attempt, lease claim, query, audit event,
and metric dimension is tenant-bound. A claim cannot be made by work ID alone;
the storage predicate includes tenant scope and the authenticated executor's
application/environment boundary. Foreign IDs and enumeration return
non-revealing results.

The first fairness design is bounded and intentionally modest:

- claim a bounded number of work items per transaction;
- enforce a versioned per-tenant active-lease cap;
- order eligible tenants by oldest due work, then apply round-robin or an
  equivalent starvation-resistant selection;
- enforce a global executor concurrency bound; and
- never allow one tenant's retry storm to consume every claim slot.

Future implementation policy must define, without source-code production
defaults:

```text
maximum schedules per tenant/application
maximum pending work per tenant
maximum active leases per tenant and worker
maximum attempts per work item
maximum work/attempt payload bytes
maximum claim batch
maximum lookahead horizon
maximum reconciliation batch
maximum retained safe error-code cardinality
```

Cross-tenant schedule reads, work enumeration, claims, evaluation, halt
application, retry, cancellation, and metrics-label leakage require negative
tests before implementation acceptance.

## 27. Persistence boundary

| Capability | PostgreSQL profile | File profile |
| --- | --- | --- |
| Schedule/revision durability | Immutable revisions plus CAS current pointer | Immutable files plus single-writer atomic pointer |
| Work identity | Unique tenant/logical-key digest and canonical-body collision check | Hashed tenant path and canonical immutable logical fields |
| Claim | Transaction, row lock/`SKIP LOCKED`, work-version CAS, lease token, database time | One process only; in-process serialized claim plus durable state |
| Multi-instance | Required future two-worker evidence | Explicitly unsupported |
| Lease expiry | Database-time comparison and token-guarded reclaim | Restart/single-process recovery only; no distributed claim |
| Attempt history | Append-only rows | Append-only canonical files |
| Reconciliation | Bounded tenant query joining by deterministic references | Bounded single-node scan |

No table, migration, or adapter is implemented by Task 58. A future schema
must follow existing migration locks, tenant keys, immutable-body comparison,
and restart/two-instance tests.

## 28. Conceptual command boundary

Future implementation may expose narrow service commands, not a broad
operator console:

```text
createSchedule(exact scope, immutable schedule revision, idempotency key)
reviseSchedule(scheduleId, expected revision, new immutable revision)
cancelSchedule(scheduleId, expected revision, reason)
retryWork(workId, expected work version, reason)
cancelPendingWork(workId, expected work version, reason)
read/list schedules and work within exact tenant scope
```

Claim/heartbeat/complete operations should be internal service-principal
boundaries, not public unauthenticated endpoints. Task 58 selects no HTTP
routes or wire format.

## 29. Audit model and privacy

The design requires bounded audit events:

```text
health.schedule_created
health.schedule_updated
health.schedule_cancelled
health.evaluation_scheduled
health.work_claimed
health.evaluation_completed
health.evaluation_stale
health.evaluation_failed
health.work_retried
health.work_cancelled
health.auto_halt_requested
```

Lease heartbeat is not audited individually. Audit metadata is limited to
tenant-scoped schedule/work/attempt/evaluation/decision/application IDs,
versions, state transitions, safe error codes, bounded reasons, request ID,
and actor identity.

Audit must not contain raw observations, installation IDs/buckets, user or
business data, patch bytes, tokens, lease tokens, private keys, stack traces,
file paths, or arbitrary exception text.

## 30. Service metrics and alert concepts

Minimal service/operator metrics are:

```text
pending, leased, evaluating, completed, stale, retrying, failed work counts
oldest pending age
claim and lease-expiry counts
evaluation duration
halt-apply duration
reconciliation outcomes
safe error-class counts
```

Dimensions must be bounded and must not include work IDs, installation
identity, tokens, or unbounded error text. These are scheduler-service metrics,
not runtime telemetry and not product/user analytics.

Potential later alerts are backlog growth, lease churn, permanent-failure
growth, evaluation latency, stale-work spike, scheduler unavailability, retry
storm, and halt-apply conflict. Task 58 integrates no provider, notification,
dashboard, or alerting system and defines no production threshold or SLO.

## 31. Deployment and OSS boundary

| Mode | Scheduled-evaluation design behavior |
| --- | --- |
| Single-node self-host | One explicit scheduler executor, File or PostgreSQL store, no distributed claim, full restart reconciliation |
| Multi-instance self-host | Shared PostgreSQL work store, cooperative claims/leases, bounded executor replicas, no required queue |
| Future managed hosted | Same logical identities and safety boundaries; provider may operate larger worker fleets and alerting without changing P3E-3/P3E-4/P3A authority |

The proposed open-source/self-host boundary includes schedule/work domain,
File/PostgreSQL adapters, claim/lease logic, idempotent P3E-3/P3E-4
orchestration, reconciliation, tests, and basic service metrics.

Possible future managed/commercial concerns are large worker fleets,
multi-region scheduling, hosted alerts, advanced policy governance, hosted UI,
and enterprise approvals. Those concerns cannot move runtime trust, signing
keys, patch validity, high-water, or rollout CAS into a managed scheduler.

## 32. Threat analysis

| Threat | Required mitigation | Residual risk |
| --- | --- | --- |
| Duplicate scheduler execution | Deterministic logical key/work ID, at-least-once model, P3E-3/P3E-4 idempotency, P3A CAS, append-only attempts | Duplicate compute/audit attempts remain possible and must be bounded. |
| Stale work | Exact revision/target/window/policy/schedule binding and repeated currentness checks | A race after a check remains possible; P3E-3/P3E-4/P3A provide final rejection. |
| Lease theft or stale lease completion | Random token, stored digest, owner/scope/work-version comparison, database time, expiry, CAS | A compromised database/operator can manipulate leases; deployment security remains required. |
| Worker impersonation | Narrow rotatable scheduler principal, tenant/app/environment scope, mTLS/TLS deployment responsibility, audit actor | Current auth does not yet provide the needed principal and must be changed before implementation. |
| Cross-tenant claim | Tenant in every key/query/claim plus negative tests and non-revealing errors | Storage/operator compromise remains outside application isolation. |
| Job starvation/noisy tenant | Per-tenant lease cap, bounded claim batch, starvation-resistant ordering, global cap | Exact fairness policy needs representative load evidence. |
| Retry storm | Versioned maximum attempts/backoff/jitter, per-tenant/global bounds, permanent/security no-retry | Correlated dependency recovery can still cause bursts. |
| Clock skew | Database/server time for readiness, leases, and `notBefore`; client timestamps ignored for scheduling | File single-node clock quality remains operator responsibility. |
| Schedule policy tampering | Immutable schedule revisions, digests/versions, expected-revision CAS, least privilege, audit, optional future two-person approval | An authorized administrator can still select unsafe policy; production policy approval remains open. |
| Automatic-halt abuse | Separate flag and scope, default off, sealed evidence, exact binding, P3E-4 validation, P3A CAS | False-positive approved policy can halt future offers; calibration remains open. |
| Crash/recovery divergence | Deterministic downstream IDs, append-only attempts, lease expiry, reconciliation, no 2PC claim | Cross-store outage can require operator reconciliation. |
| Observation outage interpreted as healthy | Preserve P3E-3 `HOLD`/`INSUFFICIENT_DATA` or retry; never expand or default healthy | Missing data can delay detection. |
| Delivery outage interpreted as patch failure | Preserve reason classes; delivery-only evidence cannot auto-halt under current policy | Correlated outages can complicate operator interpretation. |
| Work payload/resource exhaustion | Canonical bounded schema, payload/queue/attempt/lookahead/concurrency limits | Production limits require measurements. |
| Malformed or unsupported evidence | Strict version/digest/reference validation and permanent fail-closed outcome | Historical evidence is not automatically repaired. |

The scheduler is not available to the Flutter runtime and cannot authorize
executable content. Its outage may delay evaluation or future-offer halt, but
cannot block app startup, local admission, AOT fallback, signed rollback, or
already-installed behavior.

## 33. Future simulation and test matrix

All future numeric values are `DESIGN EXAMPLE ONLY — NOT PRODUCTION POLICY`.

| Vector | Setup/action | Expected outcome |
| --- | --- | --- |
| Healthy scheduled evaluation | Current sealed work produces `CONTINUE` | One evaluation/decision, work `COMPLETED`, no rollout revision |
| Scheduled halt | Current sealed work produces `HALT_NEW_OFFERS`, auto halt enabled | P3E-4 applies or acknowledges one P3A halt; work `COMPLETED` |
| Halt with auto halt disabled | Same decision, flag off/principal lacks halt scope | Evaluation persists, `HALT_NOT_ENABLED`, no rollout mutation |
| `HOLD` | Observation/delivery uncertainty | Work completes as advisory evidence; no pause/halt |
| `INSUFFICIENT_DATA` | Sample/privacy/freshness minimum unmet | Work completes as evidence; no mutation |
| Observation outage | Store unavailable or evaluator classifies outage | Bounded transient retry or persisted `HOLD`/`INSUFFICIENT_DATA`; never healthy/halt by conversion |
| Database outage | Claim/evidence/control state unavailable | No cached evaluation or mutation; bounded retry after recovery |
| Duplicate workers | Two executors target equal logical key | One work identity; at-least-once attempts; one semantic evaluation and at most one halt revision |
| Lease expiry | Worker stalls before completion | New token/attempt after expiry and reconciliation; stale worker CAS fails |
| Crash after evaluation | P3E-3 commits, work link does not | Retry reuses evaluation/decision and advances work without duplicate semantics |
| Crash after halt | P3E-4/P3A commits, work completion does not | Retry observes `ALREADY_APPLIED`/existing transition and completes |
| Revision changes before claim | Operator expands/pauses/halts/etc. | Work becomes `STALE`; no evaluation for new revision |
| Revision changes during evaluation | P3E-3 commits or rejects around manual action | Historical evidence may remain; P3E-4 cannot mutate new revision; work `STALE`/completed advisory |
| Manual halt race | Operator halt and auto halt race | One P3A CAS wins; work links existing halt only if P3E-4 evidence matches, otherwise stale |
| Expansion race | Expansion and auto halt race | Exactly one revision CAS wins; loser stale; no silent overwrite |
| Schedule cancelled | Pending work cancelled before claim | `CANCELLED`; prior evidence untouched; no new work from revision |
| Schedule revision changed | Policy/generation replaced | Old pending work cancelled/stale; new key/work; old completed evidence preserved |
| Closed then sealed | Both readiness phases configured later | Two distinct immutable work/evaluation IDs; closed is preliminary and cannot auto-halt initially |
| Permanent unsupported policy | Unknown evaluation/threshold/window version | `FAILED_PERMANENT`; no automatic retry or mutation |
| Transient budget exhausted | Dependency repeatedly fails | Append attempts, then `FAILED_PERMANENT`; explicit operator retry required |
| Cross-tenant schedule read | Tenant A requests tenant B schedule/work | Non-revealing rejection; no enumeration |
| Cross-tenant work claim | Worker A tries to claim tenant B work | Claim fails and security audit is bounded |
| Worker lacks halt scope | Evaluation returns halt but principal is evaluation-only | No P3E-4 call; complete advisory/authorization failure according to policy |
| Lease token replay | Expired/old token attempts state update | Work-version/token CAS rejects; no state or rollout mutation |
| Rollout already terminal | Work due after `HALTED`, `COMPLETED`, or `RETIRED` | Stale/cancelled; no new automatic work and no unhalt |
| File second scheduler | Two File executors configured | Startup/ownership validation rejects unsupported multi-process mode |

Future tests must include domain/unit state transitions, malformed codecs,
File restart, PostgreSQL two-worker claims/reclaims, authorization and tenant
isolation, idempotent downstream integration, failure injection, and bounded
resource behavior before implementation is accepted.

## 34. Two-person-control boundary

Task 58 does not implement approval workflows. A later governance review
should decide whether these high-risk actions require two-person approval:

```text
enabling automatic halt
creating a production schedule
changing evaluation/threshold/readiness policy
manually retrying a security/permanent failure
creating a replacement rollout after halt
```

No approval UI, RBAC expansion, SSO/SCIM, or enterprise workflow is implied.

## 35. Proposed implementation sequence

If and only if maintainers later authorize implementation:

1. **P3E5-1 — schedule/work domain, scoped principal, and persistence:** strict
   typed codecs, deterministic IDs, immutable revisions, the narrow scheduler
   credential/scopes, File/PostgreSQL adapters, malformed input,
   authorization, restart, tenant, and migration tests.
2. **P3E5-2 — claim and recovery:** PostgreSQL cooperative claims, File
   single-writer claims, lease token/version CAS, expiry/reclaim, retries,
   cancellation, fairness/resource bounds, and two-instance tests.
3. **P3E5-3 — explicit window-ready executor:** explicit registration,
   `CLOSED`/`SEALED` readiness, currentness checks, P3E-3 idempotent
   orchestration, crash recovery, audit, and no mutation.
4. **P3E5-4 — optional automatic halt:** separate enablement/scope, sealed-only
   initial policy, P3E-4 invocation, P3A race evidence, default-off behavior,
   and no HOLD/CONTINUE mutation.
5. **P3E5-5 — reconciliation and service metrics:** bounded repair projection,
   operator retry/cancel seam, metrics, failure injection, and review.

Each stage requires its own task, implementation authorization, tests, review,
and stop gate. Task 58 implements none of them.

## 36. Implementation entry criteria

Maintainers must explicitly approve before P3E-5 implementation:

- database-backed cooperative ownership and File single-writer boundary;
- the four entities and immutable-versus-operational field split;
- canonical logical key and deterministic downstream idempotency keys;
- complete state machine and manual-retry exception;
- PostgreSQL claim, token, lease, heartbeat/reclaim, and database-time rules;
- the initial explicit registration/window-ready/manual-retry trigger set;
- `CLOSED` versus `SEALED` readiness and preliminary/final behavior;
- retry classes and versioned backoff-policy shape;
- independent scheduled-evaluation/automatic-halt flags and safe defaults;
- sealed-only initial automatic-halt eligibility;
- dedicated scoped scheduler-principal model and required auth changes;
- schedule revision/update/cancel semantics;
- staleness and terminal/paused rollout behavior;
- reconciliation outcomes and no-2PC boundary;
- tenant fairness and resource-limit policy shapes;
- audit events and bounded privacy contract;
- File/PostgreSQL persistence behavior;
- simulation/test matrix; and
- staged implementation sequence.

No production numeric cadence, lease, retry, resource, SLO, or halt-propagation
value may be inferred from this approval.

## 37. Existing gates and explicit non-claims

This design does not close or relabel:

```text
P1D-01 true power loss
P1D-03 iOS diagnostics limitations
P1D-04 broad iOS performance
P1D-07 independent real application
P1D-09 interpreter attribution
P1D-18 Apple/Google/legal review
provider production gates
beta readiness
production readiness
store readiness
```

It makes no beta, production, provider-HA/SLO, App Store, Google Play,
privacy-compliance, or legal-compliance claim. No physical Android/iOS result
is affected by a control-plane scheduling design.

## 38. Stop triggers

Return to maintainer review if implementation would require any of:

```text
Patch Format v1 or capability v1 change
high-water reset/lowering
scheduler becoming runtime trust
direct rollout-state writes
automatic expansion or resume
HOLD-to-pause
automatic runtime rollback
mandatory observations for runtime correctness
business/user analytics or raw installation identity
dashboard/P3F/P3G implementation
unbounded retries/work/metrics
P3E-5 implementation under Task 58
```

## 39. Recommendation

`AUTHORIZE P3E-5 IMPLEMENTATION WITH CONDITIONS`

This is a recommendation for maintainer review, not implementation authority.
The conditions are approval of every entry criterion above, continued freezing
of P3A/P3D/P3E/runtime trust boundaries, no production numeric defaults, and a
separate authorized task for each implementation stage.

The current authorization remains design-only until maintainers record that
new decision. Stop here and do not begin P3E-5 implementation automatically.

## P3E5-1 implementation addendum (2026-08-24)

Task 59 received separate maintainer authorization and implements only the
first staged slice. Strict schedule/revision/work/attempt codecs, canonical
logical identity, state-transition validation, a dedicated
application/environment-scoped scheduler credential, File persistence, and
PostgreSQL migration 005 now exist. Explicit authenticated materialization can
persist deterministic `PENDING` work after reloading the trusted P3A rollout
target; it does not determine that work is due.

File mode uses tenant-hashed paths, atomic schedule-bundle replacement, and a
one-writer process/OS-file guard. PostgreSQL uses transactional schedule
create/revise, expected-current-revision CAS, immutable revision/work/attempt
rows, and unique logical identity. Equal bodies are acknowledged and changed
bodies conflict. No production timing/retry/resource values were introduced.

The authorization gap identified by this design is closed for the domain
foundation: `CredentialKind.scheduler` is narrowly scoped to organization,
application, and environment; `health:schedule` and `health:work:claim` are
independent; evaluation-only and optional halt profiles remain separate.
This does not authorize or implement claims, leases, polling, retries,
evaluation, automatic halt, or any rollout/runtime mutation. Detailed evidence
is in `docs/P3E5_1_SCHEDULE_WORK_PERSISTENCE_REVIEW.md`.

## P3E5-2 claim/recovery implementation addendum (2026-08-24)

Task 60 separately authorized the claim/recovery slice. Explicit service calls
now select only due `PENDING`, due `RETRY_WAIT`, or expired `LEASED` work in an
exact organization/application/environment scope. Every lease, retry, batch,
consideration, recovery, and active-lease bound is supplied through a
versioned policy object; no production value is selected in source.

PostgreSQL migration 006 adds authoritative `not_before` and
`lease_expires_at` columns plus a scope/status/time claim index. One short
transaction uses database time, a bounded deterministic query, `FOR UPDATE
SKIP LOCKED`, work-version CAS, a fresh token digest, and immutable attempt
insertion. File mode remains one process/one writer and uses a durable claim
journal so restart completes an interrupted work/attempt commit.

Raw 256-bit lease tokens are returned only to the claimant. Durable work,
attempt, and audit records retain the digest, owner, attempt number, and work
version, never the raw token. Claim-side mutations validate exact scope,
owner, digest, expected work version, active state, and unexpired authoritative
time. Expiry creates a new attempt/token/version and fences the previous token.

Retry classes are `TRANSIENT`, `STALE`, `PERMANENT`, and `SECURITY`.
Transient failures enter bounded `RETRY_WAIT` using deterministic versioned
backoff; exhaustion enters `FAILED_PERMANENT`; manual retry preserves the
logical key and revalidates current schedule binding. Cancellation remains
limited to `PENDING` and `RETRY_WAIT`.

This slice contains no timer, polling loop, evaluator call, halt call,
heartbeat, rollout mutation, or runtime/mobile change. The claim API is exact
tenant scoped; active caps and round-robin selection across due schedules
prevent one schedule/retry source from monopolizing one bounded tenant request.
Fleet-wide cross-tenant invocation remains part of the future executor.

## P3E5-3 explicit executor implementation addendum (2026-08-24)

Task 61 separately authorizes and implements only explicit, authenticated,
bounded evaluation execution. The caller supplies exact tenant inputs plus
versioned lease, retry, claim, evaluation, and executor resource policies.
The executor owns no timer, polling loop, queue, heartbeat, production default,
or durable fleet scheduler. A caller-retained cursor rotates canonical tenant
scope order, so repeated capacity-constrained invocations do not always begin
with the same tenant.

Every invocation requires an application/environment-scoped scheduler
credential with `health:work:claim`, `health:evaluate`, `observation:read`, and
`rollout:read`. `rollout:halt` is neither required nor consumed. Work is
claimed only through the P3E5-2 fencing service, then revalidated against the
current schedule generation, policy/version digests, current rollout revision,
exact target binding, persisted aggregate revision, and `CLOSED`/`SEALED`
readiness at the authoritative lease-acquisition time.

The persisted execution path is:

```text
LEASED
  -> EVALUATING + exact aggregate/revision link
  -> existing P3E-3 evaluator with scheduled-evaluation:<workId>
  -> EVALUATED + exact evaluation/decision link
  -> COMPLETED for CONTINUE/HOLD/INSUFFICIENT_DATA/MANUAL_REVIEW
```

`HALT_NEW_OFFERS` deliberately remains `EVALUATED`. The executor does not enter
`HALT_APPLYING`, invoke P3E-4, pause, expand, resume, or otherwise mutate a
rollout. Recovery reclaims expired `EVALUATING` or `EVALUATED` work with a new
token/version. It reuses immutable evaluator evidence and validates all links
before completing the work; an expired or superseded claimant cannot advance
state.

The executor policy bounds claim batch, total work, elapsed evaluation budget,
aggregate records loaded per work, retry exposure, tenant scopes, and fairness
mode. These are required inputs and test vectors only; no production values or
SLOs were selected. File mode remains single-process/single-writer. Local
PostgreSQL evidence demonstrates duplicate-executor convergence, not provider
failover, fleet capacity, or production readiness. Detailed evidence is in
`docs/P3E5_3_EXPLICIT_EXECUTOR_REVIEW.md`.

## P3E5-4 automatic-halt design addendum (2026-08-24)

Task 62 designs, but does not implement or authorize, the automatic-halt
application slice. Eligibility is default-off and limited initially to
scheduled evaluations with `SEALED` evidence, a `PATCH_SAFETY` halt reason,
an approved versioned policy, and fresh exact bindings. Existing logical-key
v1 work is ineligible because it does not bind that policy; it must never be
reinterpreted as automatic-halt work.

The proposed application requires two independent authorities: the current
unexpired fenced P3E5 work lease and a separate exact-scope Auto-Halt
Principal. The evaluation scheduler does not gain halt authority. Eligible
work may advance `EVALUATED -> HALT_APPLYING -> COMPLETED`, but the only
rollout mutation route remains the existing P3E-4 evidence validation and
P3A expected-revision CAS, using deterministic application idempotency
`scheduled-halt:<workId>`. The design does not permit expansion, start,
resume, promotion, `HOLD`-to-pause, rollback, unhalt, direct rollout writes,
runtime trust changes, or installed-patch invalidation.

Implementation and production enablement remain separately gated. Details
are in `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md` and ADR 0012.

## P3E5-4A policy/principal implementation addendum (2026-08-24)

Task 63 adds the versioned policy and work-provenance foundation without an
automatic application path. Existing v1 schedule/work records retain their
canonical meaning and are permanently automatic-halt ineligible. A new v2
schedule revision binds one current tenant/application/environment policy,
its version/digest, the automatic-halt enablement flag, and fixed
scheduled/SEALED/PATCH_SAFETY semantics. A policy change appends immutable
state and requires a new schedule revision/generation and fresh work.

The scheduler scope universe now excludes `rollout:halt`. The distinct
Auto-Halt Principal accepts exactly `health:work:apply-halt`, `rollout:read`,
and `rollout:halt`; a structural future authority also requires a matching
typed lease. No service consumes that authority to advance work or mutate a
rollout in P3E5-4A.

File and PostgreSQL persist policy/default-off state. Policy approval and
production enablement remain false, with no workflow or production values
implemented. P3E5-4B and later slices require a new maintainer decision.

## P3E5-4B scheduled intent addendum (2026-08-24)

Task 64 adds one narrow, fenced transition for current v2 scheduled halt work:

```text
EVALUATED + current lease + exact Auto-Halt Principal + all currentness gates
  -> HALT_APPLYING + canonical AutomaticHaltIntent
```

The work record and intent are one persistence unit. Equivalent retries report
the existing intent; changed semantic intent conflicts. File mode remains one
process/one writer, while PostgreSQL serializes the work row and increments one
work version. Failure before commit leaves `EVALUATED`; a lost response after
commit leaves discoverable `HALT_APPLYING` evidence.

This transition does not invoke the conservative halt service, create a
rollout revision, or complete the work. The scheduler/evaluator principal is
still insufficient, v1 work is still permanently ineligible, and production
automatic halt remains disabled by default.

## P3E5-4C application addendum (2026-08-24)

Task 65 adds one separate application adapter after `HALT_APPLYING`. It
reloads all current schedule, policy, freshness, P3E evidence, rollout/target,
intent, lease, and Auto-Halt Principal bindings, then calls the existing P3E-4
application core. The existing P3A expected-revision CAS remains the only
rollout mutation authority.

The adapter uses `scheduled-halt:<workId>` and verifies one immutable
`HealthHaltApplication` plus the exact resulting `HALTED` revision before the
schedule store accepts a fenced completion proof. File and PostgreSQL tests
cover atomic completion, restart/lost-response recovery, lease expiry, and two
independent PostgreSQL application callers. No global transaction or provider
HA claim is made.

No automatic expansion, pause, rollback, resume, unhalt, production approval,
or production enablement was added. P3E5-4D/4E remain separately unauthorized.

## P3E5-4D recovery/race-hardening addendum (2026-08-24)

Task 66 adds a separate recovery/reclaim command for expired
`HALT_APPLYING` work. It is not part of the generic scheduler claim path:
expired automatic-halt work is excluded from `claimDue` and may be reclaimed
only after evidence-first lookup and exact current work/intent scope checks.
The reclaim CAS changes the work fence and lease but preserves the semantic
attempt, intent, target binding, evaluation, decision, and expected rollout
revision. It never writes rollout state directly.

The recovered lease is passed to the existing P3E5-4C adapter. That adapter
repeats the P3E-4/P3A application and completion proof, so a lost response is
resolved by immutable application evidence rather than a blind retry. A stale
currentness result is fenced to terminal stale work; corrupt, duplicate,
foreign, incompatible, or oversized evidence fails closed. File and
PostgreSQL tests cover restart, response loss, old-token rejection, one-winner
reclaim, and a second PostgreSQL instance completing an application after the
first loses its response.

This remains bounded engineering evidence only. Recovery limits are explicit
test/worker inputs, there is no heartbeat or provider-HA claim, and rollout
actions, runtime/mobile behavior, production defaults, and enablement remain
unchanged.

## P3E5-4E integration evidence addendum (2026-08-24)

Task 67 records File single-node and local PostgreSQL two-instance evidence for
audit faults, lease timing, close/reopen recovery, and bounded contention. The
campaign preserved v2/SEALED/PATCH_SAFETY eligibility, deterministic
`scheduled-halt:<workId>` evidence, P3E-4/P3A sole mutation, and fail-closed
recovery. It did not add a scheduler timer, heartbeat, rollout action, or
production policy.

The exact PostgreSQL response-fault boundaries before and after claim and
before and after the P3A transaction were independently exercised. A narrow
single-call P3E5-3-to-P3E5-4 coordinator rehearsal also exercised all five
decision classes with separate evaluation and Auto-Halt principals. These are
bounded local vectors only; provider HA, production capacity, and readiness
claims remain open. The sanitized evidence bundle and SHA-256 manifest are
under `docs/research/evidence/p3e5-4e-2026-08-24/`.

## P3E5-5 design addendum (2026-08-24)

Task 68 is design-only. It proposes a hybrid of bounded startup
reconciliation and explicit tenant-scoped administrator invocation for
operational/work projections. It does not add a periodic worker, queue,
heartbeat, rollout writer, or P3A/P3E-4 bypass. The existing immutable P3E
reconciliation report remains report-only for immutable evidence.

The proposed taxonomy separates repairable projections, recoverable
operational state, and report-only immutable divergence. Metrics, readiness,
diagnostics, retention, and alerts are bounded service visibility only and
cannot trigger rollout actions. P3E5-5 implementation remains unauthorized
pending maintainer review of `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`.
