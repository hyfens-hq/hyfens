# P3E5-4 gated automatic halt design

<!-- markdownlint-disable MD013 -->

Status: `DESIGN COMPLETE — READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/62-p3e5-4-automatic-halt-design-review.md`

Implementation status: `NOT AUTHORIZED`

## 1. Purpose and non-goals

P3E5-4 defines when an immutable, scheduled `HALT_NEW_OFFERS` decision may be
submitted automatically to the already implemented P3E-4 conservative halt
service. Its purpose is to stop future offers when exact, current, sealed
patch-safety evidence passes a separately approved policy and authorization
gate.

The design does not implement automatic halt, a timer, queue, worker loop,
heartbeat, automatic expansion, `HOLD`-to-pause, runtime rollback, unhalt,
dashboard, alerting, provider infrastructure, or production values. It does
not grant implementation, beta, production, provider, store, or legal
readiness.

## 2. Frozen invariants

P3E5-4 preserves all accepted boundaries:

| Invariant | Automatic-halt consequence |
| --- | --- |
| Architecture B and stock Flutter | Health policy remains control-plane delivery eligibility; no compiler/runtime architecture changes. |
| Patch Format v1 and capability v1 | Halt evidence cannot change patch bytes, capability declarations, or compatibility. |
| Exact release/patch/function/capability binding | Every candidate reloads the complete exact target and immutable evidence chain. |
| State-v4 high-water | A halt cannot lower, reset, or bypass sequence admission. |
| Runtime signature authority | Runtime verification remains authoritative for installed/downloaded content. |
| Signed rollback and AOT fallback | A halt is not rollback and cannot invalidate or replace installed code. |
| Customer/local signing custody | No signing key enters evaluation or halt orchestration. |
| Artifact immutability | No artifact is fetched, rewritten, revoked, or deleted. |
| P3A rollout semantics | Only the existing expected-revision CAS may create a new immutable rollout revision. |
| P3D/P3E-1/P3E-2/P3E-3 | Observation, aggregation, persistence, and deterministic decision semantics are reused, not reinterpreted. |
| P3E-4 | Existing evidence validation, idempotency, application evidence, and P3A transition path remain the sole mutation authority. |
| P3E5-1/2/3 | Logical work identity, claims, fencing, and explicit evaluator semantics remain authoritative; historical v1 work is never reinterpreted. |

Automatic halt changes who may receive a candidate artifact in future. It is
never runtime trust.

## 3. Existing P3E5-3 state

P3E5-3 is implemented and verified through File and two-instance PostgreSQL
evidence. It claims exact work, enforces authoritative readiness, invokes the
existing P3E-3 evaluator, and persists aggregate/evaluation/decision links.
Non-halt decisions become `COMPLETED`; `HALT_NEW_OFFERS` deliberately remains
`EVALUATED` under a fenced lease. It neither requires nor consumes
`rollout:halt` and never calls P3E-4.

P3E5-4 begins only from that durable `EVALUATED` state. A free-floating manual
decision, raw counter, alert, metric, HTTP response, or operator assertion is
not an automatic-halt candidate.

## 4. Sole mutation chain

The only permitted future mutation chain is:

```text
ScheduledEvaluationWork(EVALUATED)
  -> exact linked P3E-3 HealthEvaluation
  -> exact linked RolloutDecision(HALT_NEW_OFFERS)
  -> P3E5-4 applicability + two-authority gate
  -> ScheduledEvaluationWork(HALT_APPLYING)
  -> existing P3E-4 application core
  -> existing P3A expected-revision CAS
  -> immutable HALTED rollout revision
  -> immutable HealthHaltApplication
  -> ScheduledEvaluationWork(COMPLETED)
```

P3E5-4 may not write a rollout row, revision, pointer, or idempotency result
directly. A future implementation must expose the existing P3E-4 validator and
application core to the narrow auto-halt authorization path rather than copy
or weaken it. The manual P3E-4 endpoint remains unchanged.

## 5. Enablement model

The controls remain independent and default off:

```text
scheduledEvaluationEnabled = false unless explicitly configured
automaticHaltEnabled = false unless explicitly configured
```

Automatic application additionally requires an approved automatic-halt policy
binding and environment enablement. A production environment also requires a
separate production-enablement approval record. A true schedule flag alone is
insufficient.

No source value enables automatic halt. Test fixtures must label enablement and
numeric inputs `TEST VECTOR ONLY — NOT PRODUCTION POLICY`.

## 6. Eligible evidence

An automatic-halt candidate must satisfy every condition below:

```text
work exists and status == EVALUATED
work is linked to one aggregate revision, evaluation, and decision
work provenance is P3E5 scheduled evaluation
decision == HALT_NEW_OFFERS
decision reasonClass == PATCH_SAFETY
decision is not superseded or already applied under another transition
evaluation and decision canonical/digest bindings validate
aggregate and aggregate-revision canonical/digest bindings validate
evaluationInputDigest and aggregateInputDigest validate
schedule and schedule revision exist and remain current
scheduledEvaluationEnabled == true
automaticHaltEnabled == true
automatic-halt policy version/digest remain current and approved
work readinessPhase == SEALED
decision and aggregate are fresh under explicit policy
rollout revision/state/target remain exact and current
release/patch/sequence/platform/application/environment remain exact
threshold/evaluation/window/privacy/aggregation versions and digests match
current lease owner/token/workVersion/state/expiry all match
P3E-4 applicability validation passes again
```

Any missing, malformed, ambiguous, cross-tenant, or mismatched evidence means
no mutation. Automatic halt never reconstructs links by guesswork.

## 7. Scheduled-only boundary

The first implementation consumes only a decision whose ID is linked from one
P3E5 work item and whose evaluation was created with that work's deterministic
`scheduled-evaluation:<workId>` idempotency key. The work logical key supplies
the exact schedule generation, window, target, and policy provenance.

Manual P3E-3 `HALT_NEW_OFFERS` decisions remain manually applicable through
the existing P3E-4 route. They cannot be attached retroactively to scheduled
work or selected by the automatic path.

## 8. Principal decision

The design selects a separate **Auto-Halt Principal**, not an evaluator with an
extra halt grant.

| Model | Benefit | Risk | Decision |
| --- | --- | --- | --- |
| Add `rollout:halt` to the evaluation scheduler | Fewer credentials and one invocation identity | Compromise of claim/evaluate worker immediately gains rollout mutation authority | Rejected |
| Separate exact-scope auto-halt principal | Independent custody, revocation, audit actor, and smaller combined blast radius | Requires explicit two-authority orchestration and credential lifecycle | Selected |

No bootstrap/control credential, patch-signing identity, delivery credential,
or observation token may stand in for this principal.

## 9. Authorization scopes and two-authority rule

The conceptual auto-halt profile is application/environment scoped and fixed
to:

```text
health:work:apply-halt
rollout:read
rollout:halt
```

It has no generic work claim, evaluation, observation read/write, schedule
administration, release/artifact mutation, promotion, credential
administration, signing, or runtime scope.

A future application request requires both:

1. the current unexpired P3E5 lease token/owner/work version for the exact
   `EVALUATED` work; and
2. a valid, unexpired, unrevoked Auto-Halt Principal for the exact tenant,
   application, and environment.

The lease alone cannot halt. The auto-halt credential alone cannot select or
advance work. Neither raw credential is persisted, audited, or passed into
P3E-4 evidence.

Existing `applyHealthHalt` currently requires an organization-wide control
credential with `health:evaluate`, `rollout:read`, and `rollout:halt`. A future
implementation must add the narrow exact-scope authorization adapter while
reusing the same internal P3E-4 validation/application core. It must not grant
the broad control credential to an automated process.

## 10. Exact currentness checks

Currentness is revalidated while entering `HALT_APPLYING` and immediately
before P3E-4 invocation:

- credential tenant/application/environment;
- work logical-key digest and version;
- current schedule ID, revision ID, generation, and both enablement flags;
- automatic-halt policy version, digest, approval, and environment binding;
- aggregate/revision, evaluation, and decision IDs and digests;
- rollout ID, current revision, current state, and full target digest;
- platform, release, patch, sequence, and runtime target identities;
- readiness/window identity and authoritative server time;
- aggregation, evaluation, threshold, window, and privacy policy bindings;
- decision supersession/application state; and
- lease token digest, owner, work version, status, and expiry.

P3E-4 then independently reloads and validates the decision, evaluation,
aggregate, target, digests, current rollout revision, and P3A transition
precondition. Checks are deliberately repeated across trust boundaries.

## 11. Readiness phase

Initial automatic halt is **SEALED only**. `CLOSED` evidence is preliminary and
never automatically applied, even when it says `HALT_NEW_OFFERS`. There is no
early emergency auto-halt mode in the first implementation. Operators retain
the manual P3E-4 path for urgent cases.

Readiness is derived from authoritative database/server time and the immutable
aggregate window. Client timestamps cannot make work sealed.

## 12. Reason-class eligibility

Initial automatic eligibility is exactly:

```text
decision == HALT_NEW_OFFERS
reasonClass == PATCH_SAFETY
```

`DELIVERY_HEALTH`, `OBSERVATION_HEALTH`, `DATA_QUALITY`, and
`OPERATOR_POLICY` are never automatically applied. Delivery outage, telemetry
outage, missing data, small-cohort suppression, quarantine/rejection excess,
provider latency, and missing threshold policy remain `HOLD`,
`INSUFFICIENT_DATA`, or `MANUAL_REVIEW` outcomes.

## 13. Poisoning protections

The gate relies on the complete existing defense chain:

- P3D exact-scope, authenticated, rate-limited, idempotent observations;
- deterministic event lifecycle validation and quarantine;
- P3E-1 per-installation/event contribution caps;
- minimum sample, activation, health-confirmation, and coverage requirements;
- privacy, freshness, and data-quality gates;
- immutable aggregate inputs and digests;
- deterministic P3E-3 evaluation under an explicit threshold set;
- exact P3E5 schedule/work/policy binding; and
- independent enablement, principal, P3E-4 validation, and P3A CAS.

A single installation cannot dominate broad-rollout evidence beyond its
bounded contribution. A compromised tenant observer or an unsafe approved
threshold can still cause availability harm within that tenant; calibration,
audit, and two-person production policy remain necessary.

## 14. Versioned automatic-halt policy

Automatic application uses a separate immutable policy identity:

```text
automaticHaltPolicyVersion
automaticHaltPolicyDigest
eligibleSource = SCHEDULED_ONLY
eligibleReadiness = SEALED_ONLY
eligibleReasonClass = PATCH_SAFETY_ONLY
maximumAggregateAgeFromLateCutoff
maximumDecisionAgeFromEvaluation
resourcePolicyReference
approvalReference
```

Both durations and every resource value are required explicit inputs; this
design selects no number. Unknown versions/digests fail closed.

The schedule revision and logical work meaning must bind the policy version
and digest. Historical logical-key v1 work lacks that binding and is therefore
ineligible for automatic halt. A future implementation must introduce a
reviewed new logical-key/policy version rather than reinterpret old work.
Changing or downgrading policy creates a new schedule generation and fresh
work/evaluation; it never authorizes an old decision.

## 15. Decision freshness

At both applicability transition and P3E-4 call time, authoritative time must
satisfy:

```text
now <= aggregate.window.lateCutoff + maximumAggregateAgeFromLateCutoff
now <= evaluation.createdAt + maximumDecisionAgeFromEvaluation
```

The decision, evaluation, and aggregate must also remain unsuperseded under the
same rollout revision and automatic-halt policy. An explicit successor decision
or current schedule/policy generation makes the older candidate historical.

Clock failure or unavailable authoritative time produces no mutation. File
mode inherits its documented single-host clock limitation; PostgreSQL uses
database time.

## 16. Schedule and policy staleness

Any change to schedule generation, enablement, automatic-halt policy,
evaluation policy, threshold set, readiness, target, or rollout revision makes
the old candidate `STALE`. Evidence remains readable and immutable but cannot
be rebound to the new configuration.

Disabling automatic halt before entering `HALT_APPLYING` completes the work as advisory
`HALT_NOT_ENABLED`; disabling it after `HALT_APPLYING` but before the P3E-4 call
prevents the call and records a stale/disabled outcome. It cannot undo a P3A
halt already committed.

## 17. Work-state design

The mutation-capable path is:

```text
EVALUATED
  --current lease + auto-halt principal + all guards-->
HALT_APPLYING
  --P3E-4 APPLIED/ALREADY_APPLIED + verified linkage-->
COMPLETED
```

Entering `HALT_APPLYING` is a schedule-store CAS over exact scope, work ID,
expected work version, `EVALUATED` status, lease owner, token digest, and
unexpired authoritative time. It persists the automatic-halt policy identity
and application intent before the downstream call.

`HALT_APPLYING → COMPLETED` requires the same fencing plus a verified immutable
`HealthHaltApplication` whose decision/evaluation/aggregate/rollout identities,
idempotency key, transition reference, and P3A history all match the work.

Ineligible non-stale HALT evidence may become `COMPLETED` with an advisory code
such as `HALT_NOT_ENABLED`, `READINESS_NOT_ELIGIBLE`, or
`REASON_NOT_ELIGIBLE`; no halt credential is consumed for mutation. Stale
meaning becomes `STALE`. Malformed/security evidence becomes
`FAILED_PERMANENT`.

## 18. Existing P3E-4 reuse

The future automatic adapter constructs the same canonical P3E-4 request from
trusted persisted evidence:

```text
rolloutId
decisionId
expectedRolloutRevision
targetBindingDigest
evaluationInputDigest
aggregateInputDigest
aggregateDigest
operatorReason = deterministic scheduled-auto-halt reason
idempotencyKey = scheduled-halt:<workId>
```

No caller supplies counters, target fields, digests, or a variable operator
reason. P3E-4 continues to create immutable `HealthHaltApplication` evidence
and to reject non-HALT, stale, conflicting, cross-tenant, or malformed input.

## 19. P3A CAS authority

Only P3E-4 may request `RolloutAction.halt`, and only the existing P3A
expected-revision CAS may change the current pointer. P3A remains authoritative
for allowed source states and immutable revision creation.

The initial automatic policy additionally limits candidates to current
`INTERNAL`, `CANARY`, or `EXPANDING` rollouts. `PAUSED` may be halted manually
through P3E-4 but is excluded from first automatic application because it is
already serving no new offers. `DRAFT`, `READY`, `COMPLETED`, `HALTED`, and
`RETIRED` are ineligible.

## 20. Idempotency

The P3E5 application key is fixed:

```text
scheduled-halt:<workId>
```

Equal retries must present the same canonical P3E-4 body and replay one
application. A changed body under the same key is a security/permanent
conflict. P3E-4's existing deterministic transition key derived from the
decision and P3A CAS prevent a second rollout revision even across a different
application attempt.

At-least-once execution is accepted. Exactly-once invocation is neither
required nor claimed; one semantic halt is required.

## 21. Retry classification

| Class | Examples | Result |
| --- | --- | --- |
| `TRANSIENT` | database unavailable, bounded dependency timeout, response lost before outcome can be reconciled | `RETRY_WAIT` when budget remains; same work and idempotency keys |
| `STALE` | rollout/schedule/policy/target changed, freshness expired, source state ineligible | `STALE`; no automatic retry |
| `PERMANENT` | unsupported version, malformed immutable evidence, impossible application linkage, retry exhaustion | `FAILED_PERMANENT`; explicit operator correction/new work |
| `SECURITY` | tenant mismatch, wrong principal scope, token/owner mismatch, digest conflict, changed idempotency body | `FAILED_PERMANENT`; bounded security audit, no retry |
| `ALREADY_APPLIED` | matching P3E-4 application or P3A history proves the same semantic halt | Link evidence and `COMPLETED`; not a failure |

Semantic results are not retried. Retry counts, delay, jitter, total
applications, and records inspected are explicit versioned bounds with no
production values in source.

## 22. Lease expiry

No heartbeat is introduced. The lease is checked immediately before entering
`HALT_APPLYING` and before the P3E-4 call. If it expires before the call, the
claimant cannot invoke automatically. If it expires while P3E-4 is executing,
P3E-4 may still commit through its own authorization, idempotency, and P3A CAS,
but the stale claimant cannot update work.

After expiry, a new attempt receives a fresh token/owner/version, reconciles
immutable P3E-4/P3A evidence first, and either completes the work or retries
the same idempotency key. Old-token replay is always rejected.

## 23. Crash and lost-response recovery

| Failure point | Required recovery |
| --- | --- |
| Before `HALT_APPLYING` | No application intent exists; revalidate and retry applicability under a current lease. |
| After `HALT_APPLYING`, before P3E-4 | Lease expiry/reclaim; find no application, revalidate everything, call once with the same key. |
| During P3E-4 | Reclaim and query deterministic application/history before retrying. |
| After P3E-4/P3A commit, before application evidence response | P3E-4 history-marker recovery produces/replays `ALREADY_APPLIED`; no second revision. |
| After application evidence, before work completion | Verify application/transition linkage and complete under the new lease. |
| After `COMPLETED`, before response | Retry observes terminal work and returns/reports existing evidence without mutation. |

Recovery never fabricates an application link, lowers high-water, unhalts a
rollout, or uses stale cached counters.

## 24. Concurrency and manual races

| Race | Deterministic outcome |
| --- | --- |
| Automatic halt vs manual expansion | If auto halt CAS wins, expansion is stale; if expansion wins, automatic evidence is stale. |
| Automatic halt vs manual halt | One P3A halt revision wins. Auto work links only matching P3E-4 evidence; a manual-only halt makes it stale. |
| Automatic halt vs manual pause | One expected-revision CAS wins. If pause wins, old evidence is stale and no automatic halt of the paused revision occurs. |
| Automatic halt vs retire/terminal workflow | Current P3A does not directly retire an active rollout. Any valid intervening revision or terminal workflow changes the expected revision and makes old automatic evidence stale; it is never overwritten. |
| Automatic halt vs automatic halt | Work fencing selects one current claimant; P3E-4 idempotency/P3A CAS converge duplicate downstream calls. |
| Schedule/policy/target changes before apply | Applicability fails stale before P3E-4; a race after the check is rejected by P3E-4/P3A. |

No last-write-wins path exists.

## 25. Terminal HALTED semantics

P3A `HALTED` remains terminal. Automatic halt does not roll back installed
devices, retry the patch, resume the rollout, create a replacement, or lower
runtime high-water. Recovery after halt is an explicit operator/new-rollout
workflow under existing governance.

## 26. Audit events

Future bounded audit vocabulary:

```text
health.auto_halt_eligible
health.auto_halt_requested
health.auto_halt_applied
health.auto_halt_already_applied
health.auto_halt_stale
health.auto_halt_rejected
health.auto_halt_failed
health.auto_halt_security_rejected
health.auto_halt_recovered
```

Metadata may include exact tenant-scoped work/schedule/policy/evaluation/
decision/application/rollout revision IDs, result code, attempt number, and
bounded latency. It never includes raw credentials, lease tokens, installation
IDs/buckets, observation payloads, counters that violate privacy policy,
business/user data, patch bytes, keys, stacks, paths, or arbitrary errors.

## 27. Metric concepts

Conceptual service metrics are bounded counts/histograms for eligible,
attempted, applied, stale, already-applied, failed, recovered, and application
latency. Dimensions are limited to deployment, tenant-safe internal scope,
policy version, and bounded result code; no installation, user, business,
patch content, or unbounded ID dimension is allowed.

No metric collector, dashboard, alert, SLO, or telemetry backend is authorized.

## 28. Tenant isolation

Every lookup and transition includes authenticated organization/application/
environment plus work, schedule, rollout, decision, and evidence scope. Foreign
IDs return non-revealing not-found/security outcomes and cannot be used to
forge audit links. P3E-4 independently repeats organization and rollout scope
validation.

A tenant A principal can harm availability only within its exact authorized
scope; it cannot halt tenant B, sign a patch, change artifact validity, or
alter installed runtime trust.

## 29. Resource bounds

A versioned future policy must explicitly bound:

```text
halt applications per invocation
eligible candidates considered
recovery/application records inspected per work
stale candidates processed per invocation
retries and total attempts per work
concurrent HALT_APPLYING work per tenant
total tenants/scopes per invocation
dependency-call and invocation start budget
audit/metric metadata cardinality
```

No production value is selected here. Hitting a limit stops new work and
returns a bounded transient/resource outcome; it does not partially weaken
validation or turn an outage into a halt.

## 30. File boundary

File mode remains one process, one writer, and one host clock. It may implement
the same domain and explicit application flow for local/self-host testing, but
it makes no multi-process, shared-filesystem, HA, failover, or production claim.
Atomic work replacement and immutable downstream records remain required.

## 31. PostgreSQL boundary

A future PostgreSQL implementation must prove with independent adapters:

- same-work duplicate auto-halt claim/application;
- exact work/version/token fencing and old-token replay rejection;
- one semantic P3A halt and immutable revision;
- crash/lost-response convergence at every boundary;
- stale schedule/rollout/policy/target rejection;
- manual expansion/pause/halt race behavior; and
- tenant-isolated audit/evidence linkage.

Local two-instance evidence will not establish provider failover, capacity,
backup, SLO, or production readiness.

## 32. Cross-store reconciliation

Schedule/work, P3E evidence, halt applications, and P3A rollout state remain
separate stores. Safety is exact immutable references, repeated currentness,
idempotency, fencing, P3A CAS, and bounded reconciliation—not two-phase commit.

| Observed state | Reconciliation result |
| --- | --- |
| `EVALUATED`, no application, eligible/current | Enter `HALT_APPLYING` under both authorities, then call P3E-4. |
| `EVALUATED`, disabled/ineligible but not stale | Complete advisory with no application. |
| `HALT_APPLYING`, no application | Revalidate after reclaim; retry same key only when still eligible. |
| `HALT_APPLYING`, matching applied application | Verify P3A history, link application, complete. |
| `COMPLETED`, matching application | No mutation; acknowledge terminal evidence. |
| Rollout already HALTED by matching P3E-4 | Recover/link `ALREADY_APPLIED`, complete. |
| Rollout revision advanced manually | Mark stale; never manufacture a scheduled halt link. |
| Decision exists but auto halt disabled | Preserve decision; complete advisory/no mutation. |
| Conflicting application/body/digest | Security/permanent failure; never choose one silently. |

P3E5-4 recovery is narrow to one claimed work item. Fleet-wide repair and
metrics remain P3E5-5.

## 33. Production-disabled state model

Three states remain distinct:

```text
AUTO_HALT_IMPLEMENTED
AUTO_HALT_POLICY_APPROVED
AUTO_HALT_PRODUCTION_ENABLED
```

After any future implementation, the required state is:

```text
AUTO_HALT_IMPLEMENTED = yes
AUTO_HALT_POLICY_APPROVED = no
AUTO_HALT_PRODUCTION_ENABLED = no
```

until maintainers approve calibrated policy values and environment-specific
enablement. Implementation tests cannot satisfy policy approval or production
enablement.

## 34. Policy calibration

Before policy approval, maintainers need representative replay/dogfood evidence
for false-positive/false-negative rates, contribution caps, coverage, minimum
samples, freshness, late/quarantine behavior, observer/delivery outages, and
manual race recovery. Independent-application and interpreter-attribution gates
remain open.

No conformance fixture, local PostgreSQL race, or existence of another OTA
product establishes safe production thresholds.

## 35. Operator and two-person control

Production approval or change of automatic-halt policy, freshness/resource
values, threshold set, principal provisioning, or environment enablement
requires two distinct authorized maintainers and immutable approval/audit
references. One actor cannot propose and approve the same high-risk change.

Per-decision automatic application does not require a human click once all
three production states are approved; that is the purpose of automation.
Manual override, replacement after halt, and any future disable/exception
workflow remain explicit governed operations. Task 62 implements none of this
approval machinery.

## 36. OSS/provider boundary

The open-source/self-host boundary may later include the typed policy and
principal profiles, explicit application API/service, File/PostgreSQL adapters,
reconciliation, deterministic simulations, and security tests. Customers keep
credential and patch-signing custody.

Managed workload identity, replicated dispatch, approval UI, hosted metrics,
alerts, on-call routing, cross-region operations, and SLOs are separate provider
work. They cannot weaken the domain gate or become runtime trust.

## 37. Threat model

| Threat | Required mitigation | Residual risk |
| --- | --- | --- |
| Automatic halt abuse | Default off, approved policy, scheduled-only sealed patch-safety evidence, split authority, P3E-4/P3A reuse | An approved false positive can stop future offers. |
| Compromised evaluator | No halt scope; current lease alone is insufficient | Compromise can disrupt/retry work and expose bounded evidence. |
| Compromised auto-halt principal | Exact app/environment scope and no generic claim/evaluate capability; current lease still required | Combined principal/worker compromise can harm in-scope availability. |
| Observation poisoning | P3D rate/idempotency, contribution caps, samples/coverage/privacy/quality, deterministic evaluation | Coordinated or tenant-admin poisoning within approved thresholds remains possible. |
| Stale decision/policy downgrade | Immutable version/digest binding, current schedule generation, explicit approval, freshness, no v1 reinterpretation | Unsafe authorized policy approval remains a governance risk. |
| Manual/automatic race | Repeated currentness plus existing P3A expected-revision CAS | Losing attempts create historical audit/evidence. |
| Duplicate execution | Work fencing, scheduled idempotency, P3E-4 application idempotency, P3A CAS | Duplicate compute and audit attempts remain possible. |
| Crash after halt commit | History-marker/application reconciliation and same idempotency key | Completion may wait for lease expiry/dependency recovery. |
| Cross-tenant halt | Exact dual-principal/work/evidence scope and non-revealing reads | Database/operator compromise is outside application isolation. |
| Production misconfiguration | Separate implemented/approved/enabled states and two-person approval | Human governance can still authorize unsafe values. |

A compromised authorized halt path can cause availability harm inside its exact
scope. It still cannot forge patch signatures, broaden capabilities, alter
artifact bytes, lower high-water, command runtime rollback, or change installed
runtime trust.

## 38. Design simulation vectors

| Vector | Expected result |
| --- | --- |
| Valid scheduled sealed PATCH_SAFETY HALT | Enter HALT_APPLYING; P3E-4/P3A create or replay one halt; complete with linked application. |
| CONTINUE | Already/non-mutating completion; never selected for halt. |
| HOLD | Advisory completion; never pause or halt. |
| INSUFFICIENT_DATA | Advisory completion; never halt. |
| MANUAL_REVIEW | Advisory completion; never halt. |
| Auto halt disabled | `HALT_NOT_ENABLED` advisory completion; no P3E-4 call. |
| Wrong reason class | `REASON_NOT_ELIGIBLE` advisory completion; no P3E-4 call. |
| CLOSED, not SEALED | `READINESS_NOT_ELIGIBLE` advisory completion; manual P3E-4 remains possible. |
| Stale rollout revision | STALE; no application. |
| Stale schedule revision | STALE; no application. |
| Stale/unknown auto-halt policy | STALE or permanent unsupported-version failure; no application. |
| Changed target digest | STALE/security digest failure; no application. |
| Duplicate auto-halt executors | One current work claimant and one semantic P3A halt. |
| Manual expansion race | One P3A CAS wins; loser is stale. |
| Manual halt race | One halt revision; auto work links only matching P3E-4 evidence, otherwise stale. |
| Manual pause race | One P3A CAS wins; a paused new revision is not auto-halted by old evidence. |
| Rollout terminal/intervening-revision race | Any valid new revision makes automatic work stale; current P3A does not directly retire an active rollout. |
| Crash before halt call | Reclaim HALT_APPLYING, find no application, revalidate, retry same key. |
| Crash after halt commit | Reconcile application/history, return ALREADY_APPLIED, complete. |
| Lease expiry during halt | Old claimant cannot update; new claimant reconciles one P3A effect. |
| Lost P3E-4 response | Same-key replay or history recovery; no second revision. |
| Observation outage | HOLD/INSUFFICIENT_DATA; never halt. |
| Delivery outage | HOLD; never halt. |
| Cross-tenant decision/work | Non-revealing rejection plus security audit; no mutation. |
| Expired/revoked halt principal | Security rejection; no mutation or automatic retry. |
| Production enablement absent | Rejected/no invocation even if test implementation and schedule flag exist. |

Future tests must assert immutable bytes, audit/result vocabulary, work/P3E-4/
P3A linkage, no duplicate revision, and absence of runtime-trust side effects.

## 39. Implementation sequencing

If separately authorized:

```text
P3E5-4A automatic-halt policy identity + dedicated principal/scope
P3E5-4B fenced EVALUATED -> HALT_APPLYING applicability transition
P3E5-4C shared P3E-4 core invocation + idempotent completion
P3E5-4D crash/stale/security/manual-race recovery tests
P3E5-4E File + independent two-instance PostgreSQL evidence
```

Each stage needs its own task boundary and validation. P3E5-4A must version new
policy/work meaning without reinterpreting logical-key v1. No stage is
implemented by Task 62.

## 40. Implementation entry criteria and unresolved decisions

The design resolves the architectural choices as follows:

```text
eligible source                    scheduled P3E5 work only
principal model                    dedicated Auto-Halt Principal
authority                          current work lease + auto-halt principal
required auto-halt scopes          apply-halt + rollout read + rollout halt
readiness                          SEALED only
reason class                       PATCH_SAFETY only
policy                             separate version + digest, bound to new work meaning
freshness                          aggregate age + decision age, authoritative time
state path                         EVALUATED -> HALT_APPLYING -> COMPLETED
mutation path                      existing P3E-4 core -> P3A CAS only
idempotency                        scheduled-halt:<workId>
heartbeat                          none
automatic expansion/pause         prohibited
production default                disabled
```

Maintainers must approve these choices before implementation. Numeric
freshness, retry, concurrency, inspection, and calibration values remain
intentionally unresolved and must be explicit approved policy inputs. The
credential representation (new kind versus equivalently fixed profile),
approval-record API/storage shape, and provider workload-identity integration
are implementation details that must preserve the selected boundaries.

## 41. Open readiness gates and recommendation

Task 62 does not close or relabel:

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

Automatic-halt design is not release-readiness evidence.

Recommendation for maintainer review:

`AUTHORIZE P3E5-4 IMPLEMENTATION WITH CONDITIONS`

Conditions: approve every resolved boundary and require explicit non-production
test values; implement the five stages separately; preserve split authority,
scheduled-only SEALED PATCH_SAFETY eligibility, P3E-4/P3A sole mutation, and
default-off production state; keep all readiness gates open; and stop after
P3E5-4 evidence before P3E5-5/P3F/P3G. This recommendation is not authorization.

## P3E5-4A implementation addendum (2026-08-24)

Task 63 implements only the approved foundation: strict versioned
`AutomaticHaltPolicy`, immutable default-off environment state, a dedicated
exact-scope Auto-Halt Principal, structural two-authority proof, logical work
meaning v2, historical-v1 ineligibility, and File/PostgreSQL persistence.

The evaluator/scheduler does not gain halt authority. Logical key v1 remains
the compatibility default and can never become an automatic-halt candidate.
V2 binds the current policy ID/version/digest, enablement flag,
`SCHEDULED_ONLY`, `SEALED_ONLY`, `PATCH_SAFETY_ONLY`, and the existing schedule
generation. Replacing policy creates a new immutable environment-state
generation and requires a new schedule revision and work identity.

Task 63 implements no `EVALUATED -> HALT_APPLYING` operation, candidate scan,
P3E-4/P3A call, rollout mutation, application idempotency call, recovery,
heartbeat, expansion, pause, rollback, resume, unhalt, runtime/mobile change,
or production value. Policy approval and production enablement remain false.
Evidence is in `docs/P3E5_4A_AUTO_HALT_POLICY_PRINCIPAL_REVIEW.md`.

## P3E5-4B applicability implementation addendum (2026-08-24)

Task 64 implements only the separately authorized applicability and intent
boundary. `P3e5AutomaticHaltApplicabilityService` reloads current v2 scheduled
work, schedule/revision, policy/environment state, application/environment,
rollout/revision/target, aggregate/revision, evaluation, decision, successor
evidence, and the exact Auto-Halt Principal. It requires `EVALUATED`,
`SCHEDULED_ONLY`, `SEALED`, `HALT_NEW_OFFERS`, `PATCH_SAFETY`, approved and
explicitly test-enabled state, fresh evidence, an eligible current rollout
state, and the current fenced lease.

The sole mutation is one work-version CAS to `HALT_APPLYING`. Its canonical
`AutomaticHaltIntent` is embedded in that new work version, making the File
atomic replacement and PostgreSQL row transaction include both state and
intent. The intent binds work/attempt/evaluation/decision, schedule revision,
policy version/digest, expected rollout revision, target digest, principal,
and authorization time. Authorization time is evidence but is excluded from
semantic identity, so equivalent concurrent attempts converge on one digest.

The generic executor cannot enter `HALT_APPLYING` without intent. P3E-4 and
P3A are not dependencies of the applicability service; no rollout row,
revision, state, or eligibility is changed. `HALT_APPLYING -> COMPLETED`,
`scheduled-halt:<workId>`, and automatic halt application remain unimplemented
pending P3E5-4C review. Production defaults and enablement workflows remain
absent.

## P3E5-4C P3E-4 application addendum (2026-08-24)

Task 65 implements the downstream application adapter for one committed
`HALT_APPLYING` work item. The adapter independently reloads current v2
scheduled/SEALED/PATCH_SAFETY evidence, policy/freshness, target, rollout,
P3E records, intent, fenced lease, and exact Auto-Halt Principal before
invoking the existing P3E-4 application core. P3E-4 then uses the existing P3A
expected-revision CAS; the adapter has no rollout writer.

The application key is `scheduled-halt:<workId>`. The immutable
`HealthHaltApplication` and exact resulting `HALTED` revision must be verified
before a narrow completion proof permits `HALT_APPLYING -> COMPLETED`. File
uses atomic work replacement and PostgreSQL uses a work-row transaction/CAS.
Crash, lost-response, lease-fencing, File restart, and two-instance PostgreSQL
tests cover the bounded path.

Automatic expansion, pause, rollback, resume, unhalt, production approval, and
enablement remain unimplemented. P3E5-4D/4E require a separate maintainer
decision; this addendum is not a production or store-readiness claim.

## P3E5-4D recovery/race-hardening addendum (2026-08-24)

Task 66 adds an auto-halt-specific recovery seam for the residual lease-expiry
case. `P3e5AutomaticHaltRecoveryService` first reloads the exact scheduled
work and searches immutable halt-application evidence using the deterministic
`scheduled-halt:<workId>` key. A found application and its P3E-4/P3A linkage
must validate before a retry is considered. If no application exists, only an
expired `HALT_APPLYING` work item with its bound intent may be reclaimed.

Reclaim increments the fenced work version and installs a fresh lease while
preserving the same semantic automatic-halt attempt and intent; it never
inherits a successor rollout revision and never creates a second semantic
halt. The fresh lease is consumed only by the existing Task 65 application
adapter, which still delegates rollout mutation to P3E-4/P3A. Generic
`claimDue` no longer selects `HALT_APPLYING`; the auto-halt recovery seam is
the only reclaim route for that state.

Recovery returns the bounded vocabulary `APPLICATION_FOUND_AND_VALID`,
`APPLICATION_NOT_FOUND_RETRYABLE`, `APPLICATION_STALE`,
`APPLICATION_CONFLICT`, `APPLICATION_CORRUPT`, and `SECURITY_REJECTED`.
Stale currentness is fenced into terminal `STALE` work with the intent cleared;
malformed or foreign evidence is rejected without guessing or repair. File
replacement and PostgreSQL row-lock/CAS paths are covered by recovery,
lost-response, restart, old-token, and competing-claimant tests. Explicit
application/linkage/retry limits are required inputs; no production defaults,
heartbeat, provider-HA, rollout action, runtime/mobile, or enablement behavior
was added. Task 66 review evidence is in
`docs/P3E5_4D_RECOVERY_RACE_HARDENING_REVIEW.md`.

## P3E5-4E integration evidence addendum (2026-08-24)

Task 67 adds evidence only. The File and local PostgreSQL campaigns exercise
audit outage/divergence, bounded lease timing, close/reopen recovery, and
eight-caller contention without adding a mutation route. The PostgreSQL
close/reopen test loses a reclaim response, reloads authoritative work after
lease expiry, and completes one immutable application and one halted revision.

The measured File critical path was 199,846 µs minimum, 251,585 µs median,
275,379 µs p95/max under an explicit two-second test lease. The bounded
PostgreSQL campaign used eight independent callers and produced one
application and one completed work item. These are local test envelopes, not
provider HA or production capacity.

Audit append remains secondary evidence: pre-P3E-4 outage blocks that request;
post-P3A outage does not undo the committed halt and is reconciled from
immutable application/work evidence; duplicate File replay fails closed with
`StorageConflict`; tamper detection rejects the chain. Exact PostgreSQL
pre/post claim and P3A response-fault vectors and the narrow two-authority
single-call rehearsal pass. Bundle:
`docs/research/evidence/p3e5-4e-2026-08-24/`.

## P3E5-5 reconciliation/observability design addendum (2026-08-24)

Task 68 proposes bounded startup and explicit-admin reconciliation around
P3E5-4 operational projections. A missing exact halt application may use only
the existing evidence-first P3E5-4 recovery contract; reconciliation cannot
create a HealthHaltApplication or write a rollout revision. Immutable P3E
evidence, P3A history, target bindings, and audit history remain report-only
when conflicting.

The proposed `health:reconcile` principal has no `rollout:halt`, promotion,
signing, artifact, release, or credential authority. Metrics, `/livez`,
`/readyz`, `/metrics`, diagnostics, and alerts are non-authoritative and
cannot pause, expand, roll back, resume, or unhalt a rollout. No P3E5-5
implementation is authorized by this addendum.
