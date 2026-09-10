# P3E aggregation and conservative halt design

Status: `DESIGN COMPLETE — READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: `tasks/53-p3e-aggregation-and-conservative-halt-design.md`

<!-- markdownlint-disable MD013 -->

The design sections are the P3E gate; they do not define implementation of
health evaluation, automatic halt, a scheduler, an operator API, a dashboard,
or any storage schema. All production thresholds and policy defaults remain
unselected until maintainers approve the entry criteria in section 44.

Task 54 subsequently authorizes only the P3E-1 deterministic, storage-agnostic
aggregation core. The factual implementation addendum at the end records that
slice; P3E-2 persistence, P3E-3 evaluation API, P3E-4 halt integration, and
P3E-5 scheduling remain unauthorized.

## 1. Purpose and non-goals

P3E defines a deterministic, privacy-minimized way to turn the bounded P3D
observation stream into delivery-policy evidence. Its only safety action is to
stop future rollout offers when a sufficiently evidenced patch-safety problem
is found. It cannot make installed code invalid, change runtime admission, or
perform a rollback.

The design covers:

- event inclusion, exclusion, deduplication, late data, quarantine, and
  rejected-input accounting;
- immutable, exact-scope aggregates and versioned evaluations;
- explicit metric denominators, sample requirements, freshness, coverage, and
  missing-data behavior;
- privacy and poisoning resistance for pseudonymous installation buckets;
- conservative decisions and an audited halt transition through the existing
  P3A state machine;
- recomputation, retention, deletion, APIs, concurrency, and implementation
  entry criteria.

It does not cover product analytics, user behavior, crash analytics, source
diagnostics, arbitrary client telemetry, automatic expansion, runtime trust,
patch signing, artifact storage, native changes, provider deployment, or
store/legal approval.

## 2. Frozen invariants

P3E must preserve every boundary that was accepted by P3A/P3D:

| Invariant | P3E consequence |
| --- | --- |
| Architecture B/source instrumentation | Aggregation is control-plane evidence; it does not require a Flutter/Dart fork or alter the instrumented runtime. |
| Patch Format v1 | Aggregate input identifies a format version but never changes, decodes, or authorizes patch bytes. |
| Capability v1 | A capability declaration is evidence only; an evaluation cannot add, remove, or broaden a capability. |
| Exact application/environment/release/patch/function/capability binding | Every aggregate key is exact-scope. Events from another identity are excluded and audited. |
| State-v4 high-water | No decision can lower, reset, or bypass the runtime sequence high-water. |
| Runtime signature authority | The runtime remains the sole authority for signature, digest, compatibility, and admission. |
| Signed rollback and AOT fallback | A halt is not a rollback. Any rollback remains an existing signed/local operation, and AOT fallback remains local runtime behavior. |
| Customer/local signing custody | P3E never receives, stores, or reuses a patch signing key. |
| Artifact bytes | Aggregation never fetches, rewrites, deletes, or substitutes executable artifact bytes. |
| Fail-closed recovery | Missing or malformed health evidence can prevent future offers, but cannot make an invalid patch valid. |

Observations are advisory. A healthy evaluation is not a runtime admission
proof, and an unhealthy evaluation is not permission to invalidate a healthy
installation.

## 3. P3D input contract

P3D provides a versioned `ObservationEvent` containing the bounded event type,
opaque event ID, client timestamp, trusted identity claims, platform, exact
release/patch/rollout references, pseudonymous `installationBucket`, runtime
and Patch Format versions, bounded diagnostic code, and allow-listed scalar
metadata. `ObservationRecord` adds server `receivedAt` and a disposition.

The P3D event vocabulary is fixed for this design:

```text
lookup_attempt
candidate_offered
download_succeeded
download_failed
admission_verified
admission_rejected
activation_started
activation_succeeded
activation_failed
healthy_confirmed
runtime_fault
rollback
fallback_to_aot
restart_survived
store_release_required
```

The canonical wire value is `download_succeeded`; a parser or test vector must
not accept a prefixed or otherwise altered spelling.

P3E trusts only the P3D service validation and server receipt metadata. Client
time is diagnostic context, not a window boundary. No raw installation ID,
source path, stack, token, patch bytes, user payload, or unrestricted native
diagnostic may enter an aggregate.

## 4. Event inclusion and exclusion

P3E distinguishes the disposition of an accepted record from the outcome of a
request that never became an observation record.

| Input class | Stored by P3D | Primary health aggregate | Quality/visibility aggregate | Decision effect |
| --- | --- | --- | --- | --- |
| `accepted` | Yes | Eligible after event-type and logical-contribution checks | Counted as accepted | May support a decision. |
| Exact duplicate | Existing record acknowledged; no new logical record | Never counted twice | Increment duplicate counter outside health rates | No additional evidence. |
| Mutated event ID | No new record | Excluded | Security/audit counter, redacted | Lowers data-quality confidence; never a patch failure. |
| `late` | Yes, with disposition | Excluded from a sealed primary window; optionally included in a clearly labelled open-window late context | Late count and age bucket | Cannot silently reverse a published decision. |
| `quarantined` | Yes, with disposition | Excluded from health numerators and denominators | Visible quarantine counters by reason | Causes `INSUFFICIENT_DATA` or `MANUAL_REVIEW` when material; never automatic rollback. |
| Rejected input | No observation record | Excluded | Bounded rejection/security audit evidence only | May indicate observation/data quality; never patch health. |
| Security-rejected input | No observation record | Excluded | Security audit counter, without raw payload | Never makes a patch look unhealthy or healthy. |

An exact duplicate is identified by the P3D event identity and canonical body;
it is not a second installation contribution. A request rejected before a
record exists must not be fabricated into a denominator.

P3E must expose separate `accepted`, `duplicate`, `late`, `quarantined`,
`rejected`, and `securityRejected` counters. A single `totalEvents` number is
not sufficient to explain evidence quality.

## 5. Aggregate identities

An aggregate is immutable and is never allowed to mix rollout revisions or
release identities. The canonical aggregate key is:

```text
organizationId
applicationId
environmentId
platformId
exact releaseId
exact patchId
sequence
rolloutId
rolloutRevision
windowId
windowStart (server UTC)
windowEnd (server UTC)
lateCutoff (server UTC)
observationSchemaVersion
aggregationVersion
```

The canonical serialization is sorted, exact, and versioned. `windowId` is an
opaque ID derived from the immutable window definition, not from a local clock.
The exact release/patch/sequence binding is repeated even when a rollout
record already contains it, so a storage or query bug cannot merge unrelated
artifacts.

Aggregates may be compared across revisions only in a separately labelled
non-authoritative report. Such a report cannot create a rollout decision and
must retain each revision's independent denominator.

## 6. Event category mapping

Every P3D event maps to exactly one primary category for aggregation. The raw
event type remains in the evidence record.

| Category | Event types | Meaning |
| --- | --- | --- |
| Delivery | `lookup_attempt`, `candidate_offered`, `download_succeeded`, `download_failed` | Whether an eligible candidate was looked up, offered, and downloaded. |
| Admission | `admission_verified`, `admission_rejected` | Runtime-authoritative signature, format, identity, capability, and compatibility outcome. P3E reports the event; it does not reproduce the admission decision. |
| Activation | `activation_started`, `activation_succeeded`, `activation_failed` | Attempted activation lifecycle. |
| Post-activation health | `healthy_confirmed`, `runtime_fault` | Confirmation and bounded fault evidence after activation. |
| Rollback/fallback | `rollback`, `fallback_to_aot` | Runtime rollback/fallback signals, separated from operator halt. |
| Restart survival | `restart_survived` | A subsequent process start observed the patch still healthy. Absence is not failure. |
| Store-bound exclusion | `store_release_required` | The change is outside OTA scope; it is not a patch-health failure. |

## 7. Deduplication semantics

P3E has two layers of deduplication:

1. **Event identity.** P3D's event ID and canonical body provide exact retry
   idempotency. An exact retry returns the original disposition and contributes
   nothing new. Mutated reuse is rejected and audited.
2. **Logical installation contribution.** A client may generate many valid
   IDs. Rate limits and a canonical contribution key cap evidence for one
   installation bucket, event type, exact target, and window. Health rates use
   at most one logical lifecycle contribution per checkpoint. Attempt counters
   may retain a bounded attempt count, but cannot create an unbounded
   denominator.

The contribution key is conceptually:

```text
aggregateKey + installationBucket + eventType + lifecycleCheckpoint
```

The first eligible record in canonical `(receivedAt, eventId, body)` order is
the contributor. Later records are visible as duplicates or excess contributions
and are excluded from health rates. A future implementation must persist or
recompute this choice deterministically; arrival order must not change a sealed
aggregate.

If raw rows or idempotency keys have been deleted, a replay cannot be proven to
be an old exact event. The safe result is rejection/quarantine outside the
declared replay window, never a new health contribution.

## 8. Late and quarantined event semantics

Server receipt time determines whether an event belongs to the primary window.
The policy has three conceptual phases:

```text
OPEN   -> CLOSED (window end) -> SEALED (window end + late cutoff)
```

Events received during `OPEN` or before the declared grace/cutoff may be
included according to the evaluation version. Events received after `SEALED`
remain useful quality context but do not mutate the primary aggregate or
decision.

An evaluation that includes a late context must record `lateIncluded: true`,
the late cutoff, the late count, and a new aggregate/evaluation version. It must
not overwrite the prior result. A recomputation is an append-only new result,
with an audit event explaining the change.

Quarantine reasons are separate and bounded:

- impossible lifecycle sequence;
- identity mismatch discovered during reconciliation;
- scope mismatch discovered during reconciliation;
- unsupported schema or event type;
- invalid clock or sequence metadata;
- security or poisoning suspicion;
- other explicitly registered data-quality reason.

Quarantined rows are visible to operators as data-quality evidence but never
enter a health numerator or denominator.

The aggregate quality object keeps separate counters for
`identityMismatch`, `scopeMismatch`, `impossibleSequence`, `clockInvalid`,
`schemaUnsupported`, `securitySuspicion`, and `otherQuarantine`. A combined
`quarantinedEvents` total may be displayed only alongside these components.

## 9. Deterministic aggregation

For the same accepted event set, immutable revision/window, aggregation version,
and policy inputs, the aggregate must be byte-for-byte deterministic. A future
implementation will:

1. validate the exact aggregate key and reject mixed-scope input;
2. normalize timestamps to UTC and scalar values to their canonical wire form;
3. sort records by `(receivedAt, eventId, canonical event body)`;
4. apply event-ID idempotency, then logical contribution caps;
5. count integer numerators, denominators, exclusions, and quality fields;
6. serialize sorted keys with canonical JSON or the approved deterministic
   encoding; and
7. record the input count, accepted ID range/digest, and aggregation version.

Rates are represented as integer numerator/denominator pairs. A display
percentage is derived later and must not affect a decision. No floating-point
rounding, current time, hash-map iteration order, or database row order may
change a result.

An incremental cursor is an optimization, not the authority. Its checkpoint
must contain the aggregate key, last canonical input position, and input digest;
on mismatch the evaluator must rebuild or fail closed.

## 10. Aggregate counters

The candidate counter set is intentionally explicit:

| Counter | Definition | Health use |
| --- | --- | --- |
| `eligibleInstallationsObserved` | Unique installation buckets with an eligible lookup/offer observation, not the total configured population. | Sample context only; never claim complete population coverage. |
| `lookupAttempts` | Bounded logical lookup attempts. | Delivery denominator context. |
| `candidateOffers` | Bounded logical candidate offers. | Primary offer denominator. |
| `downloadSucceeded` / `downloadFailed` | Logical download outcomes. | Download rate and delivery diagnosis. |
| `admissionVerified` / `admissionRejected` | Runtime-reported admission outcomes. | Admission anomaly evidence; rejection is not automatically a patch defect. |
| `activationStarted` / `activationSucceeded` / `activationFailed` | Logical activation lifecycle checkpoints. | Activation success metric. |
| `healthyConfirmed` | First bounded confirmation per installation/checkpoint. | Healthy-confirmation numerator. |
| `runtimeFaults` | Bounded diagnostic-code contributions after activation. | Patch-safety signal with denominator. |
| `rollbacks` / `fallbacksToAot` | Separate runtime outcomes. | Safety signal; not an operator rollback count. |
| `restartSurvived` | Positive post-restart observation. | Survival numerator; absence is missing. |
| `staleOrReplayRejects` | Rejected stale/replay safety inputs. | Data-quality/security context only. |
| `lateEvents` | Records outside the primary window but inside retention. | Freshness/completeness context. |
| `quarantinedEvents` | Records excluded for semantic/data-quality reasons. | Confidence/data-quality context. |
| `missingExpectedEvents` | Expected lifecycle evidence absent from a documented denominator. | Causes insufficient data or manual review, never failure by itself. |

`eligibleInstallationsObserved` must never be reported as total eligible
installations. P3A knows assignment policy, not the number of installations
that were offline or never looked up.

## 11. Health metrics

Every metric stores numerator, denominator, excluded count, minimum sample
requirement reference, late count, missing-data flag, and small-cohort state.
The initial metric definitions are:

| Metric | Numerator / denominator | Exclusions and caveat |
| --- | --- | --- |
| Download success | logical `downloadSucceeded` / (`downloadSucceeded` + `downloadFailed`) | Missing lookup/offline installations are not failures. |
| Admission success | `admissionVerified` / (`admissionVerified` + `admissionRejected`) | Rejection subcategories remain separate. |
| Activation success | `activationSucceeded` / (`activationSucceeded` + `activationFailed`) | An unstarted activation is missing, not failed. |
| Healthy confirmation | `healthyConfirmed` / logical `activationSucceeded` | A confirmation window and lifecycle checkpoint are required. |
| Runtime-fault rate | installations with a bounded post-activation fault / healthy or activated installations, policy-selected | One installation contribution is capped; diagnostic-code counts are context. |
| Rollback/fallback rate | installations with `rollback` or `fallback_to_aot` / activated installations | Runtime fallback is distinct from operator halt and store rollback. |
| Restart survival | `restartSurvived` / installations expected to restart in the observation protocol | No restart observation is missing, not failure. |
| Freshness | server receipt age and age of the newest accepted event | A freshness flag, not a health percentage. |
| Quarantine rate | quarantined records / all received candidate records | Data quality only; never a patch-health numerator. |

The exact denominator for runtime faults, healthy confirmation, and restart
survival is an entry criterion, not an implicit default. A metric whose
denominator cannot be justified is `NOT_EVALUABLE` and cannot trigger a halt.

## 12. Minimum samples and confidence/coverage

The evaluator requires policy-provided minimums for at least:

```text
minimumEligibleObserved
minimumOffers
minimumActivated
minimumHealthyConfirmations
minimumCoverage
```

No numeric production threshold is selected in P3E. Any number used in a unit
or simulation vector is labelled `TEST VECTOR ONLY — NOT PRODUCTION POLICY`.

Confidence is not a fabricated score. An evaluation carries explicit fields:

```text
sample counts by lifecycle stage
coverage transitions and missing denominators
freshness status
late-event count and age range
quarantine count and reason classes
small-cohort suppression state
minimum-sample pass/fail per metric
```

The result is `sufficient`, `insufficient`, or `manual-review-required` only
when those flags are derived from the approved policy version. A healthy rate
with low coverage remains insufficient.

## 13. Observation windows

An immutable observation window contains:

```text
windowId
serverStart
serverEnd
lateCutoff
minimumDuration
maximumDuration
windowPolicyVersion
```

The control plane's server clock is authoritative. Client timestamps can
explain skew and ordering but cannot open, close, or extend a window. Evaluation
before `serverEnd` is explicitly partial and cannot authorize expansion. After
`lateCutoff`, the primary window is sealed.

The implementation must define a bounded grace period and reject nonsensical
duration combinations. It must not use an indefinite open window or a local
device clock to make a halt decision.

## 14. Missing data and observation outage

Missing data defaults to `INSUFFICIENT_DATA` or `HOLD`, with `MANUAL_REVIEW`
when the cause is uncertain. It never defaults to an automatic runtime
rollback. Examples include:

- no accepted event after a candidate was offered;
- absent restart evidence where a restart was not observed;
- stale event receipt beyond the freshness policy;
- a control-plane/observation endpoint outage;
- material quarantine or rejection volume.

Delivery failures and observation failures are separate. A service outage can
prevent evidence upload while the installed runtime continues patch admission,
activation, high-water, rollback, and AOT fallback normally. The conservative
delivery decision is no expansion and, if explicitly configured, a rollout
`HOLD`; it is not a patch-health halt solely because the observer was offline.

## 15. Small-cohort privacy

Aggregates never contain raw installation IDs. `installationBucket` remains a
pseudonymous, app-scoped value and is never exposed as a row-level API field.
For cohorts below an approved privacy minimum, operators receive suppressed or
coarsened counts and an explicit `SMALL_COHORT` flag. A decision may still be
`INSUFFICIENT_DATA` even if an internal aggregate has exact counts.

Every aggregate is tenant-bound. Cross-tenant or cross-application joins are
not part of P3E. The API must not permit differencing two small-cohort reports
to reconstruct a bucket. Retention and deletion must not create a new linkage
identifier.

## 16. Decision vocabulary

Only these decisions are valid:

| Decision | Meaning | Permitted effect |
| --- | --- | --- |
| `INSUFFICIENT_DATA` | Minimum sample, coverage, freshness, or privacy requirements are not met. | No expansion; request more evidence or review. |
| `CONTINUE` | Evidence is sufficient and no approved halt rule is met. | Continue the current rollout only. It is not automatic expansion. |
| `HOLD` | Delivery/observation quality or policy uncertainty requires a pause in progression. | No expansion; an explicitly approved operator transition may pause offers. |
| `HALT_NEW_OFFERS` | Sufficient patch-safety evidence meets an approved halt rule. | Stop future eligibility through an audited P3A transition. |
| `MANUAL_REVIEW` | Evidence is contradictory, stale, poisoned, or outside policy. | No automatic transition; require an authorized operator. |

The following are intentionally invalid P3E decisions:

```text
FORCE_ROLLBACK
INVALIDATE_INSTALLED_CODE
RESET_HIGH_WATER
LOWER_SEQUENCE
UNSIGNED_ROLLBACK
AUTO_EXPAND
```

## 17. Automatic-halt semantics

An automatic halt is a conservative control-plane action, not a runtime
command. It may be considered only when:

- the aggregate key exactly matches the current immutable rollout revision;
- the observation window is sufficiently complete and fresh;
- minimum samples and coverage pass;
- the signal is classified as patch safety rather than only delivery or
  observation health;
- the approved policy and threshold version explicitly allow the rule; and
- an idempotency key and expected rollout revision are supplied.

The evaluator creates an immutable `RolloutDecision`, then asks the existing
rollout service to apply `RolloutAction.halt` with compare-and-swap. The
transition must create a new immutable P3A revision, current-state pointer,
and signed/audited control-plane record atomically. The audit signature is the
existing control-plane audit-export mechanism, never a patch-signing key. If
the expected revision is stale, no halt is applied; the evaluator returns a
stale result for re-evaluation.

The effect is only that future update lookup is ineligible. It does not:

- revoke a signature or alter Patch Format v1;
- delete or rewrite an artifact;
- invalidate a healthy installed patch;
- lower or reset high-water;
- force a runtime rollback or unsigned code path;
- bypass the runtime's fail-closed admission; or
- override AOT fallback.

`HOLD` can remain an evaluation result without changing lifecycle state. If a
future implementation chooses to transition to `paused`, that must be an
explicitly approved policy and an audited P3A action, not an implicit meaning
of every missing-data result.

## 18. No automatic expansion rule

P3E never expands a rollout. `CONTINUE` means the current eligibility policy
may continue serving its existing cohort. Starting internal/canary/expanding,
increasing percentage, reaching 100%, and production start remain explicit
operator actions with stale-revision protection and future approval controls.

This prevents a false positive in the health evaluator from widening exposure.

## 19. Failure classification

Every decision reason belongs to one safety class:

| Class | Examples | Default result |
| --- | --- | --- |
| `PATCH_SAFETY` | activation failures, verified admission anomalies, bounded runtime faults, rollback/fallback excess | `HALT_NEW_OFFERS` only with sufficient evidence; otherwise `MANUAL_REVIEW` |
| `DELIVERY_HEALTH` | download outage, lookup outage, object-store latency | `HOLD` or `INSUFFICIENT_DATA`; never patch halt from delivery alone |
| `OBSERVATION_HEALTH` | token/upload endpoint outage, stale collector, missing receipt | `INSUFFICIENT_DATA`/`HOLD`; runtime continues |
| `DATA_QUALITY` | quarantine, duplicate mutation, replay, mixed identity, schema mismatch | `MANUAL_REVIEW` or `INSUFFICIENT_DATA` |
| `OPERATOR_POLICY` | manual pause, emergency hold, approved override | Explicit audited action; no evaluator self-approval |

Download and admission signals must retain subcategories. For example, a
missing artifact or network timeout is not equivalent to a signature rejection.
Candidate inputs include activation failure, bounded runtime fault,
rollback/fallback, admission-rejection anomaly, download failure,
restart-survival anomaly, observation staleness/outage, and quarantine spike.
Each is classified before evaluation; only a sufficiently evidenced
`PATCH_SAFETY` class can produce a halt candidate. Restart absence, telemetry
outage, and a quarantine spike without a valid denominator remain
`INSUFFICIENT_DATA` or `MANUAL_REVIEW`.

## 20. Runtime faults

Only bounded post-activation fault codes may be aggregated. Raw stacks, source
paths, memory addresses, request bodies, and arbitrary logs are outside the
P3D contract. A logical installation can contribute at most the policy cap for
one fault checkpoint, and diagnostic-code cardinality is bounded.

A fault rule requires an activated/healthy denominator and sufficient coverage.
Repeated reports from one installation cannot dominate a cohort. Fault evidence
may recommend or execute `HALT_NEW_OFFERS` only under the patch-safety criteria
in section 17; a fault from an observation outage cannot.

## 21. Rollback and fallback handling

`rollback` and `fallback_to_aot` are separate positive runtime observations.
P3E records their counts and release/sequence scope but does not issue either
operation. Operator halt, signed runtime rollback, local AOT fallback, and a
store-release rollback remain four separate concepts.

Absence of a rollback event is not proof that no rollback occurred when
observations are stale or disabled. A high rollback/fallback signal can stop
future offers after the same minimum-sample and freshness checks as other
patch-safety signals. It never changes already-installed state.

## 22. Metric poisoning resistance

The design assumes an observation credential or client can be compromised and
tries to bound impact:

- short-lived, application/environment-scoped observation tokens;
- exact tenant/release/patch/rollout identity validation;
- event-ID idempotency and mutated-ID rejection;
- bounded event, metadata, token, installation, and event-type rates;
- no raw installation identity or unrestricted diagnostic payload;
- deterministic per-installation contribution caps;
- separate counts for rejected, quarantined, duplicate, and late data;
- no client-controlled window or decision state;
- minimum samples and coverage before a halt;
- no automatic expansion and no runtime trust dependency.

One installation cannot dominate a rate by sending many event IDs. A tenant
administrator can still poison its own observation stream; audit and manual
review remain necessary. The design does not claim perfect Byzantine
resistance.

## 23. Contribution limits

Before implementation, maintainers must approve bounded limits for:

```text
events per token and receipt window
events per installation bucket and receipt window
events per installation/event type/checkpoint/window
diagnostic-code cardinality
late-event volume
aggregate input rows and byte size
```

Limits are safety controls, not production health thresholds. When a limit is
hit, excess records are excluded and labelled; they must not be silently
counted as failures or dropped without a quality counter.

## 24. Manual override

An authorized control principal may record a manual `HOLD`,
`HALT_NEW_OFFERS`, or review disposition when evidence is insufficient, the
observer is degraded, a false positive is confirmed, or an emergency is being
managed. Every override requires:

```text
organization/application/environment
rolloutId and expected revision
decision and reason code
human-readable reason
evidence/aggregate/evaluation references
actor and request idempotency key
createdAt and expiry/review time where applicable
```

An override cannot make a runtime-invalid patch valid, reset high-water, or
create an unsigned rollback. An override that says `CONTINUE` still cannot
expand a rollout or bypass a runtime admission result.

## 25. Resume semantics

P3A `HALTED` is terminal for its immutable rollout record. Resuming after a
halt therefore creates a new rollout or an explicitly linked replacement
rollout with:

- a new immutable revision and fresh observation window;
- a reason and references to the halted rollout/decision;
- an explicit target and exact artifact identity;
- authorized approval and audit records; and
- no mutation of the halted history or high-water state.

The replacement may still be ineligible until a manual start action occurs.
Resumption requires explicit operator review and approval; there is no “unhalt”
pointer flip and no reuse of the prior decision as current health evidence.

## 26. Two-person control

The implementation design reserves two-person approval for:

- resume/replacement after halt;
- production start or 100% exposure;
- manual override of an insufficient or halted evaluation;
- disabling an automatic-halt rule; and
- any future key/trust-related action.

The two principals must be distinct, authorized for the same tenant scope, and
recorded in the append-only audit chain. One principal cannot create and
approve its own high-risk action. The workflow is design-only in P3E.

## 27. Audit integration

The existing durable audit chain is the audit authority. P3E proposes these
additional event names:

```text
health.evaluation_created
health.insufficient_data
rollout.auto_hold_recommended
rollout.auto_halt_triggered
rollout.manual_override
rollout.resume_requested
```

Audit metadata contains exact scope, aggregate/evaluation/decision IDs,
algorithm and policy versions, reason classes, expected/current revision, and
redacted counts. The existing signed off-box audit-export boundary remains the
control-plane audit trust mechanism, with audit-export keys separate from
patch-signing keys. It never contains raw installation IDs, event payloads,
stacks, tokens, patch bytes, or signing keys. Health decisions are not patch
signatures and must not reuse a signing-key custody path.

## 28. Persistence model

The following are conceptual append-only entities; no tables or adapters are
created by Task 53.

### `HealthAggregate`

Contains the immutable aggregate key, counters, metric pairs, quality flags,
privacy state, input count/digest, aggregation version, created time, and a
pointer to its revision.

### `HealthAggregateRevision`

Contains a new aggregate ID, parent aggregate ID when recomputed, exact scope,
window definition, input range/digest, reason for recomputation, and an
immutable creation record. It is never updated in place.

### `HealthEvaluation`

Contains aggregate ID, rollout ID/revision, evaluation version, policy/threshold
version, decision vocabulary value, reason classes/codes, confidence/coverage
flags, and creation/audit references.

### `RolloutDecision`

Contains rollout ID, expected revision, evaluation ID, decision, reason,
aggregate ID, actor (`system` or control principal), idempotency key, created
time, previous decision reference, and the resulting transition ID. A decision
is immutable even when its requested transition becomes stale.

### `RolloutTransition`

References the existing P3A immutable revision transition and records the
precondition/result. P3E cannot create a pointer update outside the P3A
transition service.

### `AggregationCursor`

An operational checkpoint containing aggregate key, canonical input position,
input digest, and aggregation version. It is rebuildable and never the source
of truth.

### Aggregate integrity binding

Every aggregate and evaluation records the tenant/query scope, exact rollout
revision, window definition, aggregation/evaluation/policy versions, input
range or immutable event-ID set, input count, and canonical input digest. A
digest mismatch, scope mismatch, or count mismatch invalidates the derived
result for new decisions; it does not cause a runtime action. This binding is
evidence integrity, not a replacement for patch signature verification.

## 29. Recomputability and retention

The canonical model is **raw plus derived**:

- P3D raw observations are the source for recomputation while retained;
- aggregates and evaluations are immutable derived evidence;
- a cursor accelerates incremental processing but can be discarded;
- any recomputation creates a new aggregate/evaluation/decision version.

Retention is independently configured for raw observations, aggregates,
evaluations, rollout decisions, and audit records. P3E does not choose an
indefinite default or a compliance period. After raw deletion, historical
aggregates remain evidence but are marked non-recomputable from raw data.

Residency and locality are deployment-specific future decisions. A self-hosted
deployment must document where raw and derived records reside and must not
silently replicate them across regions. Multi-region aggregation, residency
routing, and cross-region failover are not P3E claims. Future provider review
must cover region-local observation storage, tenant deletion locality,
cross-region access restrictions, and aggregate residency.

Late data received after a decision never silently changes the decision. A
new evaluation can be generated only with an explicit recomputation reason,
version, and audit link.

## 30. Privacy deletion

Tenant-scoped deletion may remove raw observation rows and idempotency material
according to the approved retention/privacy policy. It must not rewrite a
historical rollout decision or audit chain. A deleted-data marker records that
the aggregate is no longer fully recomputable; it contains no deleted
installation identity.

Derived aggregates must already be privacy-minimized and cannot reconstruct a
single installation through API differencing. If deletion would make a small
cohort newly identifiable, the API returns suppression/coarsening instead of
the exact count.

## 31. API design boundary

These are conceptual candidates, not implemented routes:

```text
GET  /v1/rollouts/{rolloutId}/health
GET  /v1/rollouts/{rolloutId}/health/evaluations
POST /v1/rollouts/{rolloutId}/evaluate
```

The evaluate request would identify the immutable rollout revision, window,
aggregation version, policy version, and idempotency key. It would reject
unknown/mixed scopes and return a typed evaluation. A future operator API may
expose suppressed aggregate summaries, but raw observations remain outside the
operator response.

P3E implementation may add the minimal manual evaluation seam. Broad CLI,
operator workflows, dashboard, alerting, and scheduled workers are P3F/P3G
or later and are not authorized here.

## 32. Rollout-transition integration

The evaluator is not a second rollout state machine. A halt request must:

1. load the current P3A snapshot;
2. verify exact rollout/revision/target identity;
3. create an immutable `RolloutDecision` with the expected revision;
4. invoke the existing `RolloutAction.halt` transition service;
5. commit the new immutable revision, current pointer, idempotency record, and
   audit record atomically; and
6. report whether the transition applied, was already applied, or was stale.

The P3D PostgreSQL expected-revision CAS is the distributed boundary. A local
File adapter remains a bounded single-node adapter and cannot claim
cross-process safety.

## 33. Stale evaluation protection

An evaluation is authoritative only for the exact rollout revision and window
named in its key. If an operator pauses, halts, expands, completes, retires,
or changes the rollout while evaluation runs, the result is historical and
cannot apply a transition. The service returns a precondition/stale result;
there is no last-write-wins behavior.

An already halted rollout cannot be re-halted to reset its revision. A new
replacement rollout is required for a resume attempt.

## 34. Concurrency

The following races require deterministic outcomes:

| Race | Required outcome |
| --- | --- |
| Manual pause vs automatic halt | One expected-revision CAS wins; the other is recorded stale and not silently applied. |
| Manual halt vs automatic halt | One immutable halt transition; duplicate idempotency is acknowledged. |
| Expansion vs automatic halt | Expansion loses if the halt commits first; otherwise the stale evaluation cannot halt the new revision. |
| Two evaluators for one window | Same canonical aggregate/evaluation ID or an idempotent duplicate; no double transition. |
| Resume request vs new halt | Halted history remains immutable; replacement creation requires fresh authorization and revision. |

No evaluator may write a current-state pointer directly. Cross-process tests
must exercise the existing PostgreSQL transaction/CAS seam before claiming
distributed rollout safety.

## 35. Scheduling

The first implementation entry point is an explicit, authenticated evaluation
request. There is no scheduler, queue, worker, retry fleet, or periodic
automatic halt in Task 53.

A later scheduler must use one immutable key per rollout/revision/window,
idempotent work claims, bounded retries, server-time windows, and visible
staleness. It must fail closed to no expansion when the aggregate source is
unavailable. Scheduling design cannot turn observation availability into a
runtime requirement.

## 36. Versioning

Persist and compare all interpretation inputs:

```text
observationSchemaVersion
aggregationVersion
evaluationVersion
threshold/policyVersion
windowPolicyVersion
privacyPolicyVersion
```

Unknown versions are rejected or quarantined for new decisions. Historical
aggregates and decisions remain readable under their original versions and are
never reinterpreted silently after a code upgrade. A threshold change creates a
new evaluation; it does not edit the old decision.

## 37. Deterministic simulation vectors

The following vectors are design fixtures for future unit tests. They are not
executed by Task 53 and any sample minimum of three is explicitly
`TEST VECTOR ONLY — NOT PRODUCTION POLICY`.

| Vector | Input condition | Expected bounded result |
| --- | --- | --- |
| Healthy complete window | Sufficient accepted offers, downloads, admissions, activation, healthy, and fresh restart evidence | `CONTINUE`; never auto-expand. |
| Activation failures | Test-only minimum met and activation failure rule exceeded | `HALT_NEW_OFFERS` candidate, with immutable decision and P3A CAS required. |
| Runtime faults | Capped per-installation faults with sufficient healthy denominator | Patch-safety halt candidate; no rollback command. |
| Delivery outage | Download failures with no admission/activation evidence and stale observer | `HOLD`/`INSUFFICIENT_DATA`, not patch halt. |
| Observation outage | No upload receipts while runtime remains healthy | `INSUFFICIENT_DATA`; runtime path unaffected. |
| Late events | Events arrive after window end but before/after cutoff | Late context only; sealed decision unchanged. |
| Quarantine | Impossible lifecycle sequence and schema rejection | Excluded health evidence; quality flag and manual review if material. |
| Exact duplicate | Same event ID/body repeated | One contribution and duplicate counter. |
| Mutated duplicate | Same ID with different body | Rejected/security evidence; no contribution. |
| Noisy installation | One bucket sends many valid IDs | Per-installation cap; cannot dominate rate. |
| Mixed revisions | Events for two patch/revision identities | Two aggregates; no combined decision. |
| Stale evaluation | Rollout revision changes during evaluation | Decision retained as historical; transition rejected as stale. |
| Concurrent pause/halt | Two valid control actions race | One CAS outcome, one stale result, audit for both. |

Each vector must check deterministic bytes, exact counter totals, explicit
exclusions, decision vocabulary, and absence of runtime-trust side effects.

## 38. Calibration plan

Thresholds require evidence, not intuition. Calibration should proceed in this
order after implementation authorization:

1. pure deterministic fixtures and property tests;
2. the intentionally small conformance application;
3. an independent real Flutter application (P1D-07 remains open);
4. controlled dogfood with observation opt-out and outage injection;
5. production-like canary evidence with representative delivery/observer
   failure modes; and
6. historical replay/simulation with false-positive and false-negative review.

The fixture alone cannot establish a production threshold. Calibration must
measure sample coverage, late/quarantine rates, ordinary runtime fault rates,
delivery outages, and the cost of a false halt. No beta, production, or store
readiness claim follows from these design vectors.

## 39. Independent-application dependency

P1D-07 independent application validation is still open. P3E can be designed
without it, but implementation cannot claim broad ecosystem health evidence
until the aggregator is exercised against an application not built solely as
the conformance fixture. The open gate must remain visible in all reviews and
must not be relabelled as satisfied by a simulation.

P1D-09 interpreter-stage attribution also remains open. P3E may consume the
bounded runtime fault/activation events but must not infer whether interpreted
execution or AOT execution caused a performance change unless a separately
validated event contract provides that attribution.

## 40. Provider boundary

The open-source/self-hosted P3E boundary is a pure-Dart aggregation and
evaluation engine, deterministic test vectors, PostgreSQL/File persistence
adapters, tenant-scoped audit integration, and a minimal manual evaluation
seam. A single-node self-host deployment may run this boundary with existing
P3D storage.

Managed streaming, cross-region aggregation, hosted retention, alert delivery,
high-availability workers, and a hosted dashboard are future commercial or
separately reviewed provider work. Kafka, Kinesis, a queue fleet, and managed
KMS/HSM are not prerequisites or implementation targets for P3E design.

## 41. OSS/commercial split

| Open-source/self-host boundary | Future managed/commercial boundary |
| --- | --- |
| Typed aggregate/evaluation domain | Hosted ingestion/stream processing at scale |
| Deterministic evaluator and versioned policy interface | Managed retention, alerting, and cross-region operations |
| Test vectors, malformed-input tests, and simulation harness | Dashboard, notification routing, and hosted SLOs |
| Tenant-scoped persistence/audit adapters | Managed provider HA/DR, billing, and enterprise controls |

The split does not place runtime trust, signing keys, or patch bytes in a
managed service. No commercial feature is implemented by Task 53.

## 42. Threat model

| Threat | Mitigation in this design | Residual risk |
| --- | --- | --- |
| Aggregate poisoning | Scoped short-lived tokens, event identity, caps, contribution bounds, minimum samples | A compromised tenant can distort its own evidence within bounds. |
| Threshold manipulation | Versioned policy/threshold records, least privilege, audit, two-person high-risk changes | An authorized operator can choose an unsafe policy; review is required. |
| Stale evaluation | Exact revision/window key and PostgreSQL expected-revision CAS | A local adapter cannot claim multi-process safety. |
| Small-cohort leakage | Suppression/coarsening, no raw IDs, no differencing API | Tenant context can still make aggregate data sensitive; legal review remains. |
| One-client domination | Per-installation/event-type/checkpoint limits and one-install contribution caps | Bucket compromise can still contribute one bounded signal. |
| Override abuse | Scoped control credentials, reason/evidence, immutable audit, two-person actions | Emergency operations remain a human risk. |
| Halt loop | Terminal P3A `HALTED`, idempotency, cooldown/fresh replacement window, manual resume | Repeated replacement rollouts can still be operationally noisy. |
| Outage misclassification | Separate delivery/observation/data-quality classes and no runtime dependency | Correlated outages can reduce evidence and delay a safe halt. |
| Store corruption | Aggregate input digest, immutable revisions, audit chain, fail-closed parser | Storage/provider compromise requires deployment recovery controls. |
| Tenant leakage | Exact tenant/application/environment query scope and isolation tests | Misconfigured self-host deployment remains customer responsibility. |
| False negative | Small cohorts, minimum samples, bounded coverage and freshness | A real defect may expose more installations before evidence matures. |
| False positive | Conservative classes, manual review, no automatic runtime rollback | Future offers may be halted unnecessarily. |

P3E cannot claim zero risk, perfect detection, or store compliance.

## 43. Implementation sequencing proposal

If maintainers authorize implementation, the smallest sequence is:

```text
P3E-1 deterministic aggregation core and simulation vectors
P3E-2 immutable aggregate/evaluation persistence model
P3E-3 explicit manual evaluation API
P3E-4 conservative halt integration through P3A CAS
P3E-5 scheduled evaluation only after a new review
```

Each slice must complete source, tests, malformed-input handling,
documentation, and the relevant task record before the next slice begins.
No P3F operator expansion, P3G dashboard, health-event queue, or automatic
expansion is implied.

## 44. Implementation entry criteria

Maintainers must explicitly approve all of the following before P3E code is
started:

- event inclusion and exclusion policy;
- aggregate identities and exact-scope rules;
- metric numerator/denominator definitions;
- minimum-sample and coverage behavior;
- missing, late, duplicate, rejected, and quarantine behavior;
- decision vocabulary and no-auto-expansion rule;
- automatic-halt and P3A transition semantics;
- manual override and resume/replacement semantics;
- privacy/small-cohort and contribution-limit rules;
- raw/derived retention and deletion model;
- evaluation, aggregation, window, and policy versioning;
- calibration plan including independent-app evidence; and
- OSS/self-host versus managed-provider boundary.

## 45. Unresolved decisions

The following are intentionally unresolved rather than guessed:

1. Production numeric thresholds and minimum samples.
2. The exact denominator for eligible population, healthy confirmation,
   runtime faults, and restart survival.
3. Whether an automatic `HOLD` ever transitions to P3A `paused` or remains an
   evaluation-only state.
4. Late cutoff duration, window duration bounds, and recomputation schedule.
5. Privacy suppression/coarsening values and anti-differencing policy.
6. Exact contribution/rate limits after representative load measurements.
7. Aggregate raw retention and legal deletion periods per deployment.
8. The minimal manual API shape and which operator routes belong in P3E versus
   P3F.
9. Scheduler ownership and retry semantics for a later task.
10. Independent-application calibration and interpreter-attribution evidence.

None of these may be silently selected during implementation.

## P3E-4 conservative halt integration addendum (2026-08-24)

Task 57 implements the approved narrow mutation boundary for a previously
persisted `HALT_NEW_OFFERS` decision. The new immutable `HealthHaltApplication`
record is tenant-scoped, canonically encoded, and linked to the exact
decision, evaluation, aggregate revision, rollout revision, and resulting P3A
transition. File persistence and PostgreSQL migration 004 preserve append-only
outcomes; the original `RolloutDecision` is never rewritten.

The authenticated route is:

```text
POST /v1/rollouts/{rolloutId}/health/decisions/{decisionId}/apply
```

It requires `health:evaluate`, `rollout:read`, and `rollout:halt`, an
`Idempotency-Key`, the expected rollout revision, the target-binding digest,
evaluation and aggregate input digests, the aggregate digest, and an operator
reason. The service reloads and validates all referenced evidence and the
complete trusted rollout target. The target-binding digest is persisted by
P3E-3 evaluations as an optional backwards-compatible field; P3E-4 requires
it, so legacy evaluations without it are rejected for halt application.

Only `HALT_NEW_OFFERS` reaches the existing P3A expected-revision CAS. `HOLD`,
`CONTINUE`, and other decisions produce immutable `REJECTED` application
evidence and do not pause or otherwise mutate the rollout. A successful halt
changes future offer eligibility only. Runtime admission, Patch Format v1,
capability authority, signing, artifact bytes, state-v4 high-water, signed
rollback, and AOT fallback remain outside this path.

The P3A transition idempotency key is deterministically derived from the
decision. Equal application retries replay their immutable record; a changed
body conflicts; a different key for an already-applied decision records
`ALREADY_APPLIED`; stale expected revisions fail closed. Manual-halt versus
health-halt, expansion versus health-halt, and two PostgreSQL service races
reuse the same CAS boundary and cannot create two halt revisions. Deterministic
history markers allow a retry to link an already committed transition after a
cross-store persistence interruption, without claiming a distributed
transaction.

Executable evidence is recorded in `tasks/57-p3e4-conservative-halt-integration.md`
and `docs/P3E4_CONSERVATIVE_HALT_REVIEW.md`. P3E-5 scheduling, automatic
evaluation, automatic expansion, dashboards, provider deployment, mobile or
runtime changes, beta, production, store, and legal claims remain outside this
slice and require a separate maintainer decision.

### P3E5-4 automatic-halt design relationship (2026-08-24)

Task 62 is design evidence only and does not change P3E-4 semantics. Manual
health-halt decisions remain manual. The proposed automatic path is limited
to exact scheduled `HALT_NEW_OFFERS` evidence that is `SEALED`, classified
`PATCH_SAFETY`, fresh under an approved versioned policy, and still bound to
the current rollout and target. It requires both the current fenced P3E5 work
lease and a separate exact-scope Auto-Halt Principal.

The future worker would build the existing P3E-4 request from persisted
evidence and use `scheduled-halt:<workId>` as its deterministic application
idempotency key. P3E-4 remains the sole evidence-validation authority and P3A
expected-revision CAS remains the sole rollout mutation authority. Automatic
halt stays production-disabled until separate policy approval and production
enablement decisions; no implementation is authorized by this addendum.

## 46. Existing gates that remain open

P3E design does not close or relabel:

```text
P1D-01 true power loss
P1D-03 iOS diagnostics limitations
P1D-04 broad iOS performance
P1D-07 independent application
P1D-09 interpreter attribution
P1D-18 Apple/Google/legal review
provider production edge, durability, HA/DR, secrets, provenance,
monitoring, RPO/RTO, beta readiness, production readiness, store readiness
```

No App Store, Google Play, beta, production, provider-SLO, or legal-compliance
claim is made by this design.

## 47. Maintainer decision gate

The design is internally coherent and preserves the frozen runtime and trust
invariants. It is ready for a maintainer decision, but this document does not
grant implementation authority.

`AUTHORIZE P3E IMPLEMENTATION WITH CONDITIONS`

This is the recommendation for review only. If approved, the conditions are:

- all entry criteria in section 44 are explicitly accepted;
- P3A/P3D/runtime invariants remain frozen;
- automatic actions can stop future offers only and must use the existing
  revision/CAS/audit boundary;
- no automatic expansion, runtime rollback, high-water change, or trust
  weakening is introduced;
- P1D, provider, beta, production, store, and legal gates remain open; and
- implementation stops after the P3E-4 review boundary before scheduling,
  dashboard, or broader operator tooling.

Until that decision is recorded by maintainers, the only authorized outcome is
`AUTHORIZE P3E DESIGN ONLY — COMPLETE` and no P3E implementation may begin.

## P3E-1 implementation addendum (2026-08-24)

Task 54 records `P3E DESIGN REVIEW — APPROVED` and authorizes the first bounded
implementation slice with conditions. The repository now contains a pure-Dart
`DeterministicAggregator` in
`packages/control_plane/lib/src/aggregation.dart`, exported by the control-plane
library. It implements:

- exact aggregate identity and UTC-normalized `OPEN`/`CLOSED`/`SEALED` window
  models with supported version checks;
- P3D event-category mapping, accepted/late/quarantined handling, explicit
  external rejected/security-rejected quality context, and exact event-ID
  deduplication with mutated-ID security accounting;
- deterministic logical installation contribution caps and canonical
  `(receivedAt, eventId, canonical event body)` ordering;
- integer counter and numerator/denominator metric output, explicit
  `NOT_EVALUABLE` denominators, sample/coverage/freshness/missing-data states,
  small-cohort privacy state, resource bounds, and policy/input digests; and
- immutable JSON-ready aggregate output with no installation-bucket values and
  no rollout-state mutation.

Executable simulation, malformed-input, property-style permutation,
deduplication, mixed-scope, late/quarantine, privacy, digest, and resource
bound vectors live in `packages/control_plane/test/aggregation_test.dart`.
This evidence is limited to the P3E-1 domain core. It does not implement or
validate aggregate persistence, evaluation APIs, automatic halt/hold, rollout
transitions, scheduling, dashboards, mobile behavior, beta, production, or
store readiness.

## P3E-2 immutable persistence addendum (2026-08-24)

The maintainer accepted Task 54 and authorized Task 55 with conditions. Task 55
implements only the immutable evidence-storage boundary for P3E-1 output. The
P3E-1 aggregate remains a pure-Dart domain object; strict decoding now rejects
unknown entity/evaluation/policy/privacy/window versions, unknown enum values,
missing fields, digest mismatches, malformed metric pairs, and invalid scope.

The implementation adds typed immutable records for `HealthAggregate`,
`HealthAggregateRevision`, `HealthEvaluation`, `RolloutDecision` references,
and rebuildable `AggregationCursor` values. Aggregate and revision writes bind
the exact tenant/application/environment/platform/release/patch/sequence/
rollout/revision/window/version identity, input count, input digest, policy
versions, and recomputability state. A recomputation creates a new revision;
previous records are never overwritten. Evaluation and decision records require
existing, correctly scoped immutable references and preserve the aggregate input
digest. Cursors are disposable and cannot delete or replace aggregate evidence.

PostgreSQL schema version 3 adds tenant-scoped immutable P3E tables and indexes.
The existing advisory migration lock is reused. Aggregate plus revision lineage
is inserted in one transaction; equal retries acknowledge the canonical body,
while changed bodies fail with an immutable conflict. Evaluation, decision, and
cursor writes use the same idempotent rule and reference checks. File/local
storage uses hashed tenant-separated paths, canonical JSON, atomic writes, and
is explicitly single-node only. Both adapters return no record for a wrong
tenant, preserve canonical digests across restart/reconnect, and expose bounded
reconciliation reports rather than rewriting historical evidence.

Task 55 adds no evaluation route or evaluator workflow, rollout transition,
automatic halt/hold, scheduler/worker, dashboard, operator API, mobile/runtime
change, production threshold, raw installation API, or runtime trust authority.
Backup/restore evidence is bounded to the existing PostgreSQL dump and local
File-directory copy model; no new disaster-recovery architecture or provider
claim is made. P3E-3/P3E-4/P3E-5 and all P1D/provider/beta/production/store/legal
gates remain separately reviewed and open.

## P3E-3 manual evaluation addendum (2026-08-24)

Task 56 implements the first narrow evaluation seam while preserving the
P3E-1/P3E-2 and runtime boundaries. `ManualP3eEvaluator` is a storage- and
clock-independent pure-Dart evaluator. It consumes one validated immutable
aggregate/revision pair and one explicit `ManualEvaluationPolicy`; it never
accepts client counters, raw observations, installation identity, patch bytes,
or a rollout action.

The policy requires all interpretation inputs and quality/sample controls,
including evaluation, aggregation, threshold-set, window, and privacy versions;
a threshold-set digest; minimum samples; freshness behavior; explicit
non-recomputable handling; quarantine/rejection/late limits; and optional
test-vector-only patch-safety thresholds. No production numeric threshold is
selected in source. A canonical policy digest and evaluation-input digest bind
the exact aggregate revision identity/digest, window, aggregate policy digest,
quality/privacy state, recomputability, policy versions, and threshold-set
identity.

The conservative precedence is executable and deterministic: malformed or
scope-mismatched evidence is rejected; privacy suppression and unmet caller
minimums produce `INSUFFICIENT_DATA`; observation outage produces `HOLD`;
material quality limits produce `MANUAL_REVIEW`; delivery-only outage produces
`HOLD`; an explicitly configured patch-safety threshold can produce
`HALT_NEW_OFFERS` evidence; and otherwise sufficient healthy evidence produces
`CONTINUE`. `HALT_NEW_OFFERS` is persisted evidence only and cannot mutate a
P3A rollout, high-water, runtime admission, or installed patch.

The narrow API is:

```text
POST /v1/rollouts/{rolloutId}/health/evaluations
GET  /v1/rollouts/{rolloutId}/health/evaluations/{evaluationId}
GET  /v1/rollouts/{rolloutId}/health/evaluations
```

POST references exact tenant/application/environment/platform/release/patch/
sequence/rollout revision/aggregate revision/window/input/policy digests and
requires an `Idempotency-Key`. It loads counters and metrics only from the
tenant-scoped P3E-2 adapter, rechecks current rollout target/revision, and
persists immutable `HealthEvaluation` plus `RolloutDecision` evidence. Equal
retries acknowledge the original body; changed requests conflict. GET/list
are bounded, stable-order, opaque-cursor reads over the authorized tenant.
The required scopes are `health:evaluate`, `rollout:read`, and
`observation:read`; evaluation authority does not include a rollout transition
call. The service records redacted requested, created, replayed, conflict,
scope-rejection, stale, and evidence-rejection audit actions. File remains
single-node; PostgreSQL two-instance equal-key races are tested when the
configured integration environment is available.

Executable evidence lives in
`packages/control_plane/test/p3e_evaluation_test.dart` and
`packages/control_plane/test/p3e_manual_api_test.dart`. It covers healthy,
threshold, privacy, observation-outage, non-recomputable, malformed,
scope/stale, API, tenant, audit, idempotency, restart, and PostgreSQL
two-instance cases. This addendum is manual-evaluation evidence only:
P3E-4 halt integration, P3E-5 scheduling, dashboards, production thresholds,
provider readiness, beta, production, store, and legal gates remain open.

## P3E-5 scheduled-evaluation design addendum (2026-08-24)

Task 58 defines orchestration only. The recommended ownership model is a
durable database-backed cooperative scheduler: PostgreSQL owns multi-instance
work claims through server/database-time leases, lease tokens, and
expected-work-version CAS; File mode remains one process and one writer. An
external timer may wake an executor but cannot define work or bypass durable
claims. No queue is required for the first implementation.

The proposed domain separates stable `EvaluationSchedule`, immutable
`EvaluationScheduleRevision`, deterministic `ScheduledEvaluationWork`, and
append-only `ScheduledEvaluationAttempt`. A versioned canonical logical key
binds tenant/application/environment, complete rollout target and revision,
window/readiness phase, aggregate/evaluation/threshold/window/privacy policy
versions and digests, and schedule revision/generation. Changed policy or
rollout meaning creates new work; old work is never reinterpreted.

The design accepts at-least-once execution. Duplicate attempts converge through
deterministic work and P3E-3 idempotency, P3E-4 idempotency, and P3A CAS. Work
states make leases and purpose explicit; stale bindings terminate without
mutation, transient faults use bounded versioned retry policy, and cross-store
crash gaps are reconciled by immutable downstream IDs rather than 2PC.

Initial triggers are explicit registration, one server-time window-readiness
phase, and manual retry. `SEALED` is recommended; `CLOSED` is preliminary and
not auto-halt eligible initially. Scheduled evaluation and automatic halt are
separate flags and both default off. `CONTINUE`, `HOLD`,
`INSUFFICIENT_DATA`, and `MANUAL_REVIEW` never mutate rollout state. Only a
current sealed `HALT_NEW_OFFERS`, with automatic halt explicitly enabled and
the optional halt scope present, may call the existing P3E-4 path.

Current code has no `health:schedule`/work-claim scope and rejects
application/environment scoping for control credentials. A dedicated narrow
scheduler-principal authorization model is therefore an explicit future entry
criterion, not an implemented fact. The complete design, ownership comparison,
state machine, failure/reconciliation rules, threat analysis, and future
vectors are in `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`.

Task 58 adds no scheduler, worker, timer, queue, table, migration, endpoint,
automatic evaluator/halt, dashboard, rollout/runtime mutation, production
cadence, or readiness claim. P3E-5 implementation remains unauthorized until a
new maintainer decision.

## P3E5-1 schedule/work persistence addendum (2026-08-24)

Task 59 adds only the authorized P3E5-1 foundation. Evaluation schedules now
have immutable versioned revisions and a CAS-protected current pointer.
Explicit materialization derives a deterministic logical work identity from
the trusted P3A target/revision plus window, readiness, policy, and schedule
bindings, then persists `PENDING` work with no lease or attempt.

The new scheduler credential kind is application/environment scoped and cannot
administer credentials, mutate releases/artifacts, sign patches, or perform
generic rollout mutation. `health:schedule`, `health:work:claim`, evaluation,
observation-read, rollout-read, and optional rollout-halt grants remain
independent. File and PostgreSQL persistence enforce tenant isolation,
immutability, equal-body idempotency, changed-body conflicts, and bounded
decoding.

P3E-3 and P3E-4 are not invoked. `automaticHaltEnabled` is configuration only;
`HOLD` remains advisory; no expansion, pause, retry, claim, lease, worker,
timer, or executor exists. The runtime trust and rollout CAS boundaries are
unchanged.
