# P3E5-5 reconciliation and service-observability design

<!-- markdownlint-disable MD013 -->

Status: DESIGN ONLY — READY FOR MAINTAINER REVIEW
Date: 2026-08-24
Task: 68 — P3E5-5 reconciliation and observability design

This document is a design gate. It does not describe implemented P3E5-5 code.

## 1. Maintainer boundary and decision

Task 67/P3E5-4E is closed for its declared bounded File/local-PostgreSQL
scope. The supplied maintainer instruction authorizes this design only:

```text
P3E5-4 IMPLEMENTATION — CLOSED FOR DECLARED BOUNDED SCOPE
P3E5-5 DESIGN — AUTHORIZED WITH CONDITIONS
P3E5-5 IMPLEMENTATION — NOT AUTHORIZED
P3F / P3G — NOT AUTHORIZED
```

The design recommendation is:

```text
AUTHORIZE P3E5-5 DESIGN ONLY — COMPLETE
```

That is a design completion recommendation, not implementation approval.

The later Task 73/74 implementation gates are historical follow-on decisions
that supersede the design-time rejection of a periodic worker for their
explicitly bounded scope. They do not authorize provider scheduling, queues,
Redis, or production operations.

The proposed architecture is a hybrid of bounded startup reconciliation and
explicit tenant-scoped administrator invocation. There is no periodic worker,
managed queue, Redis dependency, new rollout writer, or control action from
observability.

## 2. Evidence labels

This document distinguishes:

- **VERIFIED** — present in repository code/tests or accepted Task 67 evidence;
- **PROPOSED** — design contract for a future separately authorized task;
- **UNKNOWN** — requires implementation evidence or maintainer decision;
- **REJECTED** — incompatible with frozen authority or scope.

## 3. Existing foundation

### 3.1 Verified immutable evidence boundary

The existing `P3ePersistenceStore.reconcile(organizationId)` validates
aggregate/revision lineage, evaluation references, decision/evaluation
references, halt-application references, cursors, missing parents, cycles, and
bounded persistence input. Its `P3eReconciliationReport` is report-only; it
does not rewrite immutable P3E evidence.

The existing artifact reconciliation report checks content-addressed artifact
inventory and quarantine state. It is separate from P3E schedule/work
reconciliation.

The immutable sources below remain authoritative for their own domains:

| Source | Authority preserved in P3E5-5 |
| --- | --- |
| `HealthAggregate` / `HealthAggregateRevision` | aggregate content, lineage, window, input, and policy digests |
| `HealthEvaluation` | evaluation identity, aggregate reference, target binding, decision, and policy semantics |
| `RolloutDecision` | decision identity, evaluation reference, expected rollout revision, and decision class |
| `HealthHaltApplication` | P3E-4 application identity, idempotency, target, and resulting transition reference |
| rollout revision history | immutable P3A state transitions and current revision pointer semantics |
| schedule revision | schedule generation, readiness, policy, and automatic-halt enablement |
| logical work identity | tenant/application/environment/rollout/release/patch/window and policy binding |
| audit chain | append-only actor, request, action, and bounded metadata evidence |

### 3.2 Verified operational projections

`ScheduledEvaluationWork` is a durable operational projection with immutable
logical-key fields and CAS-controlled `status`, `workVersion`, attempt,
lease, link, and error fields. Its state machine includes `PENDING`, `LEASED`,
`EVALUATING`, `EVALUATED`, `HALT_APPLYING`, `RETRY_WAIT`, `COMPLETED`,
`STALE`, `FAILED_PERMANENT`, and `CANCELLED`.

The existing schedule-store interfaces expose consistency reporting, bounded
claim/reclaim, `markAutomaticHaltStale`, `failClaim`, `manualRetry`, execution
advancement, automatic-halt intent, and automatic-halt completion. These are
future implementation seams, not Task 68 changes.

### 3.3 Verified storage boundaries

| Boundary | Verified behavior | P3E5-5 implication |
| --- | --- | --- |
| File | One process, one writer, atomic replacement, one host clock; no HA claim | Startup/manual reconciliation must run under the existing writer boundary |
| PostgreSQL | Tenant-scoped rows, row locks/CAS, database-time leases, `SKIP LOCKED`-compatible claim model, existing advisory lock for rollout transitions | Concurrent reconciliation must use existing row/version fencing; no Redis or 2PC |
| P3E persistence | File/PostgreSQL immutable evidence and bounded report-only reconciliation | Findings can drive projection checks, never source rewrites |
| Control/audit stores | Separate JSON/rollout/audit records and cross-store at-least-once behavior | Repair must be deterministic and audit divergence must remain visible |

### 3.4 Verified automatic-halt boundary

Task 67 verifies that the P3E5-3 executor and Auto-Halt Principal remain
separate. The existing P3E-4 adapter validates exact evidence and uses the P3A
expected-revision CAS. The deterministic `scheduled-halt:<workId>` key,
two-authority boundary, and evidence-first recovery remain mandatory.

### 3.5 Existing health endpoint fact

Earlier control-plane documentation names `/healthz` as a liveness endpoint,
`/readyz` as a metadata/migration readiness check, and `/metrics` as
process-local aggregate measurement. P3E5-5 proposes `/livez` as the canonical
liveness name while preserving a compatibility alias decision for a future
implementation task. No endpoint is changed here.

## 4. Goals and non-goals

### Goals

P3E5-5 should eventually:

1. detect and classify divergence across schedule, work, P3E evidence,
   automatic-halt application, rollout state, and audit evidence;
2. repair only safe operational/projection state from exact immutable sources;
3. report immutable conflicts without rewriting history;
4. provide bounded low-cardinality service metrics and reconciliation signals;
5. define liveness/readiness semantics that distinguish service failure from a
   tenant-scoped health finding;
6. provide safe tenant-scoped diagnostics;
7. remain usable in File single-node and PostgreSQL multi-instance modes; and
8. make future implementation and validation entry criteria explicit.

### Non-goals

P3E5-5 is not:

- a rollout control plane or a second P3A writer;
- a patch/runtime trust mechanism;
- a scheduler loop, queue, heartbeat, or distributed transaction;
- product analytics, user analytics, or installation telemetry;
- a dashboard, alert provider, hosted operations platform, or P3F/P3G;
- a repair mechanism for immutable evidence, audit history, signed artifacts,
  high-water state, or native/mobile state;
- a production SLO, provider-HA, beta, App Store, Google Play, privacy, or
  legal-compliance claim.

## 5. Frozen invariants

P3E5-5 must preserve all of the following:

```text
Architecture B
Patch Format v1
capability v1
exact application/environment/release/patch/function/capability binding
state-v4 high-water
runtime signature authority
signed rollback
fail-closed recovery
AOT fallback
customer/local signing custody
artifact immutability
P3A rollout CAS/state semantics
P3D/P3E semantics
P3E-4 sole halt-application authority
P3A sole rollout-mutation authority
P3E5-1 schedule/work identity/auth
P3E5-2 claim/recovery
P3E5-3 explicit executor
P3E5-4 automatic-halt semantics
```

Observability never triggers `pause`, `expand`, `rollback`, `resume`,
`unhalt`, replacement rollout, or automatic percentage change.

## 6. Reconciliation ownership options

| Model | File behavior | PostgreSQL behavior | Strength | Risk | Decision |
| --- | --- | --- | --- | --- | --- |
| Explicit admin-triggered | One writer performs a bounded request | Any authorized instance performs tenant-scoped bounded request | Smallest lifecycle; operator-visible | Crash divergence waits for an operator | Retain as a required path |
| Startup reconciliation | Run after store initialization under writer lock | Every instance may run a bounded scan with row fencing | Catches restart divergence without a worker | Startup latency and concurrent duplicate scans | Retain as a required path |
| Periodic worker | Adds a second File lifecycle and overlap risk | Adds worker ownership, timers, backpressure, and deployment policy | Continuous detection | Scope expansion, queue/lease complexity, hidden authority | Reject for P3E5-5 design |
| Hybrid startup + explicit admin | Startup scan plus targeted operator request | Startup and manual requests share deterministic CAS/idempotency | Covers restart and targeted repair without a permanent worker | Requires bounded startup budget and clear ownership | **Recommended** |

### 6.1 Recommended ownership

The recommended model is **hybrid startup plus explicit administrator
invocation**:

- startup performs one bounded, read-first scan and repairs only safe
  operational projections;
- an administrator can request a bounded tenant/application/environment scan;
- both paths use the same typed finding/action contracts and idempotency keys;
- startup never blocks on a single tenant's stale work; it records backlog and
  continues within global bounds;
- PostgreSQL concurrent invocations use row/version fencing and skip locked
  selection; a losing invocation records a deterministic replay outcome;
- File startup/manual execution is serialized by the existing writer lock;
- there is no background timer or automatic operator control.

The periodic-worker option can be reconsidered only after P3E5-5 evidence
proves bounded scan cost, fairness, storage behavior, and failure semantics.

Tasks 73/74 later supplied that bounded local runner and crash/lock-loss
evidence under separate maintainer approvals. The design's worker rejection
therefore remains the correct Task 68 design-gate record; it is not a claim
that provider HA or production scheduling has been implemented.

## 7. Proposed reconciliation domain

The following are **PROPOSED** future domain records. They are not implemented
in Task 68.

### 7.1 Invocation

```text
ReconciliationInvocation
  schemaVersion
  invocationId
  organizationId
  applicationId?
  environmentId?
  actorId
  principalKind
  storageMode
  policyVersion
  startedAt
  lookbackHorizon
  maximumRecords
  maximumTenants
  maximumLinkageDepth
  maximumRepairs
  maximumRetryAttempts
  cursor?
```

The invocation is scoped before any read. Its bounds are required inputs; no
production numeric defaults are introduced by design.

### 7.2 Finding

```text
ReconciliationFinding
  schemaVersion
  findingId
  scope
  code
  severity
  repairability
  entityType
  entityId
  sourceDigests
  observedVersions
  firstObservedAt
  lastObservedAt
  status
  safeDetailCode
```

`findingId` is deterministic over scope, taxonomy code, entity identity,
source digests, and observed versions. Timestamps and free-form errors are not
identity inputs. A finding is an observation, not a new source of truth.

### 7.3 Repair attempt

```text
ReconciliationRepairAttempt
  schemaVersion
  repairId
  findingId
  action
  actorId
  expectedWorkVersion?
  expectedScheduleRevision?
  preconditionDigest
  result
  safeErrorCode?
  createdAt
```

`repairId = reconcile-repair:<findingId>:<action>` is the deterministic
idempotency key. A changed precondition or source digest is a conflict, never
an invitation to overwrite the prior attempt.

### 7.4 Source-of-truth map

| Data | Read source | Repair target, if any |
| --- | --- | --- |
| Aggregate/evaluation/decision/application | P3E immutable store | None; report conflicts |
| Rollout/revision history | Control store/P3A history | None; report conflicts |
| Schedule/revision | P3E5 schedule store | None for immutable revision; current pointer only through existing CAS |
| Work status/link fields | P3E5 schedule store | Typed work projection CAS |
| Audit chain | Existing append-only audit store | None; report missing/tampered evidence |
| Metrics/readiness | Process-local/derived view | Rebuild or expire derived view only |

## 8. Repairability classes

### 8.1 `REPAIRABLE_PROJECTION`

The projection is missing or stale, and one exact immutable source proves the
only valid value. The repair updates only the projection through expected
version/CAS, uses a deterministic repair ID, and records an audit event.

Examples: linking an existing evaluation, decision, or halt application to
work; rebuilding a derived read model from validated source records.

### 8.2 `RECOVERABLE_OPERATIONAL_STATE`

The state is operational and bounded recovery is already defined. The repair
may mark stale, make an expired lease reclaimable, complete work from an exact
existing application, or mark a retry-exhausted item permanently failed. It
must reuse the existing schedule-store transition and P3E5-4 recovery
contracts. It may not call a rollout writer directly.

### 8.3 `REPORT_ONLY_IMMUTABLE_DIVERGENCE`

The conflict concerns immutable evidence, identity, tenant scope, audit
history, target binding, or unknown schema/version. The reconciler records a
bounded finding, fails closed where the affected path requires trust, and
requires operator/maintainer action. It never selects one conflicting record,
rewrites history, deletes evidence, or manufactures a link.

## 9. Severity vocabulary

Only these severities are permitted:

| Severity | Meaning | Default service effect |
| --- | --- | --- |
| `INFO` | Expected recoverable operational condition | Count and continue |
| `WARNING` | Bounded backlog, stale/retry condition, or missing secondary evidence | Count, expose diagnostics, continue unrelated work |
| `ERROR` | Repair failed or a projection is inconsistent | Bound retries, expose finding, do not infer success |
| `SECURITY` | Scope, digest, identity, or tamper signal | Fail affected operation closed and require review |
| `CRITICAL` | Service-wide integrity/dependency condition | May make readiness not-ready only when global, not for one tenant |

Service/database outage is an infrastructure error, not a patch-safety or
automatic-halt finding.

## 10. Divergence taxonomy and action policy

The following taxonomy is stable design vocabulary. “Automatic action” means a
future bounded reconciler action, not an action performed by Task 68.

| Code | Severity | Repairability | Automatic action | Operator action | Audit behavior |
| --- | --- | --- | --- | --- | --- |
| `WORK_EVALUATION_LINK_MISSING` | `ERROR` | `REPAIRABLE_PROJECTION` | Link one exact evaluation after aggregate/target/digest validation | Review if no unique match | Finding, repair requested/applied or failed |
| `WORK_DECISION_LINK_MISSING` | `ERROR` | `REPAIRABLE_PROJECTION` | Link one exact decision whose evaluation link matches | Review if absent/conflicting | Same deterministic repair record |
| `WORK_HALT_APPLICATION_LINK_MISSING` | `ERROR` | `REPAIRABLE_PROJECTION` | Link exact `HealthHaltApplication`; do not create one | Use existing P3E5-4 recovery if no application exists | Finding and link outcome |
| `HALT_APPLICATION_ROLLOUT_MISMATCH` | `SECURITY` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None; fail affected completion/recovery closed | Investigate P3E-4/P3A history | Security finding; no source rewrite |
| `ROLLOUT_APPLICATION_REFERENCE_MISSING` | `ERROR` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None | Reconcile control-plane/P3A history manually | Finding only |
| `SCHEDULE_WORK_VERSION_MISMATCH` | `ERROR` | `RECOVERABLE_OPERATIONAL_STATE` | Reload and CAS; mark stale only if currentness proves it | Retry with fresh scope if unresolved | Attempt and outcome |
| `WORK_LOGICAL_KEY_MISMATCH` | `SECURITY` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None | Quarantine affected processing and investigate | Security finding |
| `AUDIT_REFERENCE_MISSING` | `WARNING` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | Do not synthesize audit history | Use existing export/retention workflow | Finding; preserve chain |
| `AUDIT_CHAIN_INVALID` | `CRITICAL` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | Stop trust-sensitive repair for affected scope | Verify backup/export and incident response | Security/critical finding |
| `EVALUATION_AGGREGATE_MISMATCH` | `SECURITY` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None; reject use of evidence | Investigate immutable lineage | Security finding |
| `DECISION_EVALUATION_MISMATCH` | `SECURITY` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None; reject use of evidence | Investigate immutable lineage | Security finding |
| `TARGET_BINDING_MISMATCH` | `SECURITY` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | None; do not apply/retry halt | Review release/patch/rollout identity | Security finding |
| `TENANT_SCOPE_MISMATCH` | `CRITICAL` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | Return non-revealing failure; no cross-tenant read/repair | Security incident review | Redacted security event |
| `UNKNOWN_VERSION` | `ERROR` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | Reject unknown schema/policy/entity | Upgrade or explicit migration decision | Finding with version only |
| `ORPHAN_WORK` | `ERROR` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | No deletion or guessed parent; optionally mark stale only after exact proof | Repair source schedule or operator disposition | Finding and disposition |
| `ORPHAN_APPLICATION` | `WARNING` | `REPORT_ONLY_IMMUTABLE_DIVERGENCE` | Preserve application; do not attach by guess | Inspect P3A/rollout history | Finding only |
| `STALE_ACTIVE_WORK` | `WARNING` | `RECOVERABLE_OPERATIONAL_STATE` | Existing currentness check then `MARK_STALE` or bounded recovery | Retry/cancel only through authorized workflow | State transition audit |
| `EXPIRED_LEASE` | `INFO` | `RECOVERABLE_OPERATIONAL_STATE` | Evidence-first reclaim through existing P3E5-4 seam | Observe repeated expiry | Reclaim/attempt audit |
| `RETRY_EXHAUSTED` | `WARNING` | `RECOVERABLE_OPERATIONAL_STATE` | Leave terminal state; no unbounded retry | Explicit manual retry after review | Finding and operator action |

No taxonomy row can cause automatic expansion, pause, rollback, resume, unhalt,
or a direct rollout transition.

## 11. Typed repair action contracts

Each action requires all six fields: preconditions, authority, idempotency
key, immutable source evidence, postconditions, and audit event.

| Action | Preconditions | Authority | Source evidence | Postcondition | Audit event |
| --- | --- | --- | --- | --- | --- |
| `LINK_EXISTING_EVALUATION` | Work version current; exactly one evaluation matches logical key, aggregate revision, target, and digest | `health:reconcile` + `health:read` | Immutable evaluation and aggregate/revision | Work link set through CAS; no evaluation mutation | `reconciliation.evaluation_linked` |
| `LINK_EXISTING_DECISION` | Evaluation link validated; exactly one matching decision | `health:reconcile` + `health:read` | Immutable evaluation and decision | Work decision link set through CAS | `reconciliation.decision_linked` |
| `LINK_EXISTING_HALT_APPLICATION` | Exact decision/evaluation/target and application idempotency key match; P3A transition verifies | `health:reconcile` + `health:read` + `rollout:read` | Immutable application and rollout revision history | Work application link set through CAS | `reconciliation.halt_application_linked` |
| `COMPLETE_WORK_FROM_EXISTING_APPLICATION` | `HALT_APPLYING`, current lease/version, exact application and P3A transition exist | `health:reconcile` + `health:read` + `rollout:read` | HealthHaltApplication, P3E intent, P3A revision | Existing completion transition only; no new halt | `reconciliation.work_completed` |
| `MARK_STALE` | Fresh schedule/rollout/policy currentness proves stale binding; expected work version matches | `health:reconcile` + `health:read` | Current schedule/revision and work logical key | Work enters existing terminal `STALE` state | `reconciliation.work_marked_stale` |
| `MARK_FAILED_PERMANENT` | Permanent/security failure or exhausted policy; expected version matches | `health:reconcile` + `health:read` | Finding and retry policy | Work enters existing terminal failure state | `reconciliation.work_failed_permanent` |
| `REBUILD_DERIVED_PROJECTION` | Source set complete, version known, deterministic projection digest matches | `health:reconcile` + `health:read` | Immutable sources and projection schema | Derived view replaced atomically; sources unchanged | `reconciliation.projection_rebuilt` |
| `REPORT_ONLY` | Any immutable conflict, unknown version, or insufficient proof | `health:reconcile` + `health:read` | Finding inputs only | No state mutation | `reconciliation.finding_reported` |

`LINK_EXISTING_HALT_APPLICATION` never invokes P3E-4 and never creates a new
application. If no application exists for `HALT_APPLYING`, the reconciler may
invoke only the separately authorized P3E5-4 evidence-first recovery contract;
it may not substitute a repair action or call P3A.

## 12. Currentness before every repair

Before an action, a future implementation must:

1. reload the authoritative records from storage, not a prior scan cache;
2. revalidate organization/application/environment scope and principal scope;
3. reload the work row and compare `workVersion`, lease owner/token/expiry when
   relevant, and expected state;
4. reload the current schedule revision and schedule generation;
5. reload rollout current revision/state and exact target binding;
6. run the existing P3E reconciliation report for relevant immutable evidence;
7. recompute source and precondition digests; and
8. commit one typed CAS action or return a bounded conflict.

An observation made from stale memory is never enough to repair. A lost repair
response is resolved by rereading the deterministic repair ID and target
projection; it is not retried with a new identity.

## 13. Idempotency and audit protocol

The proposed sequence is:

```text
scope and bounds authorize
        ↓
fresh read and finding digest
        ↓
reconciliation.repair_requested audit
        ↓
one typed CAS/projection mutation
        ↓
re-read postcondition
        ↓
reconciliation.repair_applied / repair_failed audit
```

If the pre-repair audit append is unavailable, do not mutate. If a projection
CAS commits and the post-repair audit append is unavailable, do not roll back
the projection or immutable evidence; persist/recover the repair result from
the deterministic repair record and surface `AUDIT_REFERENCE_MISSING`.

Audit metadata is limited to scope-safe opaque IDs, taxonomy/action codes,
source/precondition digests, safe result codes, and bounded counts. It never
contains raw tokens, lease tokens, observations, patch bytes, user data,
stacks, paths, or arbitrary exception text.

## 14. PostgreSQL multi-instance design

The PostgreSQL implementation should reuse existing primitives:

- select bounded candidates with tenant scope, deterministic ordering, and
  `FOR UPDATE SKIP LOCKED` where a candidate row is claimed;
- use work-version CAS for every projection mutation;
- use the existing advisory-lock convention only for the narrow shared
  transition where already required;
- make finding and repair IDs unique by tenant scope and canonical digest;
- treat a unique-key conflict as deterministic replay if the body matches;
- treat a changed body or precondition as a conflict/security finding;
- use database time for lease and `notBefore` decisions; and
- close/reopen the store on failure and rediscover the result by ID.

Reconciliation does not add Redis, a distributed lock service, or two-phase
commit. A repair may commit its projection and audit evidence in separate
stores; immutable source state remains authoritative if the second write is
lost.

## 15. File single-node design

File reconciliation runs inside the existing one-process/one-writer guard.
Startup and explicit admin requests serialize through the same atomic bundle
replacement. A second File process remains an operator error, not a supported
concurrent reconciler.

File restart reconciliation may reload all bounded tenant bundles, but it must
stop at configured scan and repair limits. It must report backlog instead of
running an unbounded catch-up. A host clock is sufficient only for the current
single-node design; File mode makes no distributed time or HA claim.

## 16. Scan bounds and fairness

Every invocation receives a versioned policy containing:

```text
maximumRecordsScanned
maximumTenantsScanned
maximumLinkageDepth
maximumFindings
maximumRepairs
maximumConcurrentRepairs
maximumRetryAttempts
lookbackHorizon
maximumDiagnosticHistory
maximumAuditLookupDepth
cursor/fairness policy
```

No numeric production defaults are selected here. A future implementation must
reject zero, negative, or internally inconsistent bounds.

Fairness rules:

1. order tenants by a stable cursor plus oldest due/unresolved age;
2. cap records, findings, and repairs per tenant and globally;
3. advance the cursor even when a tenant is report-only or unavailable;
4. use `SKIP LOCKED` in PostgreSQL so a locked tenant does not block others;
5. use the single File writer queue only inside one bounded invocation; and
6. expose remaining backlog and the oldest unresolved age.

One noisy tenant must not consume the entire invocation budget indefinitely.

## 17. Reconciliation principal

The proposed principal is exact-scope and non-control-authoritative:

```text
health:reconcile
health:read
rollout:read
```

It is scoped to one organization/application/environment unless an explicit
future operator policy grants a bounded organization-wide scan. It has no:

```text
rollout:halt
rollout:expand
rollout:promote
artifact/release mutation
patch signing
credential administration
observation mutation
```

The current Auto-Halt Principal remains required only for the existing
P3E5-4 application/recovery path. A reconciliation principal cannot impersonate
it or manufacture a halt application.

## 18. Reuse of P3E5-4 recovery

For `HALT_APPLYING`:

1. inspect deterministic `scheduled-halt:<workId>` application evidence first;
2. validate the exact P3E intent, evaluation, decision, policy, target, and
   P3A transition;
3. if an application exists, link/complete operational work only;
4. if no application exists, use the existing evidence-first P3E5-4 recovery
   service with its fenced lease and separate Auto-Halt Principal; and
5. never create a rollout revision or call P3A from a reconciliation writer.

This is a reuse requirement, not permission to broaden the existing automatic
halt path.

## 19. Audit divergence

| Condition | Reconciliation behavior |
| --- | --- |
| Application committed, secondary audit missing | Preserve application/P3A; report `AUDIT_REFERENCE_MISSING`; do not undo halt |
| Work completed, completion audit missing | Preserve work/evidence; record finding when audit becomes available |
| Duplicate audit event with equal canonical body | Treat as deterministic replay; no second semantic mutation |
| Duplicate audit ID with changed body | `AUDIT_CHAIN_INVALID`/security finding; never overwrite |
| Tampered audit chain | Fail trust-sensitive repair closed; retain bytes for investigation |
| Audit store unavailable | Block pre-repair mutation requiring an audit intent; expose degraded health |

Audit divergence never causes rollout mutation and never becomes patch-health
evidence.

## 20. Observability metrics

Metrics are derived, bounded service measurements, not product analytics. The
initial taxonomy is:

| Metric family | Safe values |
| --- | --- |
| `schedule_count` | count by `storage_mode`, `environment_type` |
| `work_count` | `pending`, `leased`, `evaluating`, `evaluated`, `halt_applying`, `retry_wait`, `stale`, `failed_permanent`, `completed` |
| `work_oldest_pending_age` | bounded age bucket, `storage_mode`, `environment_type` |
| `lease_expirations_total` / `reclaims_total` | `storage_mode`, `operation`, safe result |
| `retry_attempts_total` | `error_class`, `storage_mode` |
| `evaluation_outcomes_total` | `decision_class`, `environment_type` |
| `auto_halt_total` | `eligible`, `attempted`, `applied`, `stale`, `recovered`, safe result |
| `audit_divergence_total` | taxonomy code, `storage_mode` |
| `reconciliation_findings_total` | taxonomy code, severity, repairability |
| `reconciliation_repairs_total` | action, safe result, storage mode |
| `reconciliation_failures_total` | safe error class, storage mode |
| `reconciliation_backlog` | bounded count and oldest-age bucket, no tenant label |

Safe dimensions are limited to:

```text
storage_mode
work_state
decision_class
error_class
operation
environment_type
severity
repairability
action
```

Never use global metric labels for work ID, evaluation ID, decision ID,
installation ID, patch digest, raw tenant/application/rollout ID, user
identity, source path, or arbitrary error text. Tenant-scoped diagnostics may
show authorized opaque IDs, but metrics must remain aggregate and bounded.

## 21. Cardinality and privacy policy

Metric registration must reject labels outside the allow-list and cap the
number of active series. Unknown decision/error/action codes map to a bounded
`unknown` bucket and create a diagnostic finding rather than a new series.

Metrics contain no raw observation payloads, installation identifiers, user
content, patch bytes, signing material, tokens, stack traces, file paths, or
source maps. Small-cohort suppression and tenant deletion/retention policy
remain future reviewed policy, not a default in this design.

## 22. Service-health endpoints

### `/livez`

Liveness answers whether the process can serve a health response and its
request loop is functioning. It must not query every tenant or treat stale
work as a process crash. A process-wide fatal initialization failure may make
it fail.

### `/readyz`

Readiness answers whether the service can safely accept the class of request
being advertised. Proposed checks:

- storage initialized and schema/migration version supported;
- authentication and scope verifier available;
- required control/schedule/P3E stores readable;
- File writer lock held, or PostgreSQL connection/readiness probe succeeds;
- no global unknown schema or globally invalid audit trust boundary.

The following must not alone make global readiness fail:

```text
one tenant has stale work
one rollout is HALTED
one tenant has missing observations
one tenant has retry exhaustion
one tenant has a report-only divergence
```

`CRITICAL` global storage/schema/auth failures may return HTTP 503. A
tenant-scoped critical finding should return a degraded status with bounded
counts and fail only affected tenant operations closed. The exact HTTP body,
compatibility alias for `/healthz`, and readiness policy version require
implementation review.

### `/metrics`

The endpoint exposes only the bounded service metric families above. Exporter
failure cannot mutate reconciliation, rollout, runtime, or audit state.

## 23. Safe diagnostics

The future read-only diagnostic surface may expose, only after exact scope
authorization:

```text
schedule status and current revision
bounded work status and age bucket
evaluation/decision/halt-application linkage status
finding code, severity, repairability, and safe detail code
repair attempt result and timestamp
bounded error history
reconciliation backlog and oldest unresolved age
```

It must not expose raw lease tokens, credentials, observations, user/business
payloads, patch bytes/digests as global labels, stack traces, file paths, or
another tenant's counts. Page size, linkage depth, history depth, and response
bytes are required inputs. A foreign ID must return a non-revealing not-found
or forbidden result without confirming whether it exists.

This is a narrow read API, not a P3F dashboard or operator platform.

## 24. Alert concepts

Design-only alert concepts are:

```text
pending backlog growth
lease-expiry spike
reclaim spike
retry backlog
failed-permanent spike
HALT_APPLYING stuck
audit divergence
critical reconciliation finding
database unavailable
scheduler unavailable
```

No threshold, notification provider, webhook, dashboard, auto-halt policy,
rollout action, or alert-triggered mutation is selected here.

## 25. Retention

Future policy must separately define retention for:

| Data | Design rule |
| --- | --- |
| Service metrics | Bounded aggregate retention; no indefinite default |
| Findings | Retain safe finding/result history long enough for operator review; preserve deterministic identity |
| Repair attempts | Append-only outcome evidence subject to explicit retention/legal policy |
| Diagnostics | Short, bounded safe history; no raw payload retention |
| Immutable P3E/P3A/audit evidence | Existing immutable retention/export policy remains authoritative |

No deletion or retention operation may rewrite immutable source evidence or
make an invalid audit chain appear valid. Numeric periods require separate
security/legal/self-host review.

## 26. Failure behavior

| Failure | Required behavior |
| --- | --- |
| Reconciliation DB outage | Stop repair, retain bounded failure/backlog signal, retry only through a new bounded invocation |
| Metrics exporter failure | Continue core service; increment internal safe exporter error if possible; never block runtime or rollout |
| Audit-store outage | Block pre-repair mutation requiring audit intent; do not undo committed projection/source state |
| Diagnostics read failure | Return bounded unavailable error; do not disclose partial cross-tenant data |
| Partial repair commit | Re-read deterministic repair ID/postcondition; complete or report conflict, never guess |
| Reconciler crash | Startup/manual invocation rediscovers finding and idempotency state |
| Two reconcilers race | One CAS winner; loser returns deterministic replay/conflict; no duplicate semantic repair |
| Unknown future schema | Report `UNKNOWN_VERSION` and fail affected operation closed |
| Runtime/mobile failure | No control-plane repair path may change runtime trust or high-water |

## 27. Cross-store consistency strategy

Reconciliation uses fresh reads, immutable references, deterministic IDs,
fencing, and CAS. It does not attempt distributed two-phase commit across
schedule, P3E, rollout, and audit stores.

The safe ordering is:

```text
read immutable sources
  → validate exact linkage
  → write one operational projection with CAS
  → verify postcondition
  → record secondary audit result
```

If stores disagree, the immutable source wins for its domain and the
projection is marked/report-only according to the taxonomy. A missing audit
record never authorizes rewriting the application or rollout history.

## 28. Backpressure and resource limits

The future reconciler must enforce all of:

```text
reconciliation batch size
tenant batch size
concurrent repairs
maximum linkage depth
maximum source records per finding
maximum diagnostic page size
maximum history depth
maximum audit lookup depth
maximum metric series
maximum invocation duration
maximum repair retries
```

When backlog exceeds capacity, process the bounded prefix, expose backlog and
oldest age, and return a resumable cursor. Never drop immutable evidence or
run unbounded catch-up. A single tenant's malformed or locked records must
not starve other tenants.

## 29. Required design vectors

The following table is the minimum future implementation/evidence matrix.

| Vector | Expected finding | Severity | Repairability/action | Audit/operator signal |
| --- | --- | --- | --- | --- |
| `HALT_APPLYING` + exact application exists | Missing or stale work link only | `ERROR` | Link application, then complete work from exact app | Repair applied; no new halt |
| `HALT_APPLYING` + no application | Pending existing P3E5-4 recovery | `WARNING` | Reuse evidence-first recovery or report | Recovery/retry signal |
| `COMPLETED` + missing application link | Terminal projection incomplete | `ERROR` | Link only if exact app/P3A evidence exists | Repair/result event |
| Work + missing evaluation link | Evaluation persisted, work update lost | `ERROR` | Link exact evaluation | Link event |
| Work + conflicting evaluation link | Immutable/source conflict | `SECURITY` | Report only; fail affected path | Security finding |
| Rollout/application mismatch | Target or transition conflict | `SECURITY` | Report only; no P3A call | Critical diagnostic |
| Stale active work | Current schedule/target changed | `WARNING` | Fresh CAS to `STALE` | State-transition audit |
| Expired lease | Lease no longer current | `INFO` | Existing bounded reclaim | Reclaim count/age |
| Retry exhausted | No automatic attempts remain | `WARNING` | Leave terminal; explicit manual workflow | Backlog/failed signal |
| Audit secondary event missing | Mutation evidence still authoritative | `WARNING` | Report only; never undo | Audit divergence |
| Audit chain tampered | Trust boundary invalid | `CRITICAL` | Report/fail closed | Security incident signal |
| Cross-tenant orphan | Scope cannot be proven | `CRITICAL` | Non-revealing reject; no repair | Redacted security audit |
| Unknown version | Unsupported persisted shape | `ERROR` | Report only | Upgrade/migration signal |
| PostgreSQL reconnect | Store response lost or reopened | `WARNING` | Rediscover deterministic result | Reconnect/backlog signal |
| File restart | Atomic bundle reload required | `WARNING` | Startup bounded scan under writer lock | Startup finding count |
| Two reconcilers race | CAS loser/replay | `INFO` | No second semantic mutation | Replay/conflict event |
| Repair response lost | Commit status ambiguous | `ERROR` | Read repair ID/postcondition | Recovered repair event |
| Metrics exporter failure | Visibility degraded only | `WARNING` | Continue core service | Exporter health signal |
| Reconciliation backlog overload | Capacity bound reached | `WARNING` or `CRITICAL` if global | Stop at cursor; do not catch up unboundedly | Backlog/oldest-age signal |

Each vector must be tested for tenant scope, malformed input, idempotency,
postcondition verification, bounded audit behavior, and no rollout mutation.

## 30. Threat model additions

| Threat | Required mitigation | Residual risk |
| --- | --- | --- |
| Reconciler privilege abuse | Exact `health:reconcile` scope, no rollout/signing/artifact authority, audit actor | A compromised scoped operator can repair its own projections |
| Repair replay | Deterministic finding/action ID, precondition digest, immutable repair record | Duplicate compute may occur before convergence |
| Stale repair | Fresh reload, work-version/lease/schedule/rollout CAS | Race after final read is rejected by downstream CAS |
| Cross-tenant reconciliation | Scope in principal, query, storage key, finding ID, diagnostics, and audit | Storage/operator compromise remains deployment responsibility |
| Repair-idempotency mutation | Canonical body comparison; changed body is conflict | Operator must resolve conflicting persisted records |
| Projection poisoning | Rebuild only from exact validated immutable sources | A compromised source store remains a system-level risk |
| Metrics-cardinality DoS | Allowlisted labels, bounded code registry, series limits, unknown bucket | Misconfigured limits can still reduce visibility |
| Diagnostic data leakage | Read-only scoped auth, opaque IDs, bounded safe fields, non-revealing foreign errors | Authorized operators can view their tenant's operational metadata |
| Alert spoofing | Alerts are derived from bounded service metrics/findings and have no mutation authority | False alerts can consume operator attention |
| Audit/reconciliation divergence | Append-only audit, deterministic repair evidence, fail-closed tamper handling | Cross-store audit durability remains unproven |

## 31. Tenant isolation contract

Future implementation must prove all of the following:

- tenant A cannot reconcile tenant B;
- tenant A cannot read tenant B diagnostics or repair history;
- tenant A cannot infer tenant B work counts through scoped APIs or metric
  labels;
- tenant A cannot repair tenant B's projection;
- finding, repair, cursor, audit, and idempotency identities include tenant
  scope; and
- a foreign or malformed identifier returns a non-revealing response.

Global metrics may expose aggregate counts only. They must not include raw
tenant/application/rollout IDs.

## 32. OSS/self-host and commercial boundary

### Open-source/self-host design boundary

The eventual open-source core may include:

```text
reconciliation domain and taxonomy
File/PostgreSQL adapters
startup/manual bounded invocation
typed projection repair contracts
basic service metrics
livez/readyz/metrics
safe diagnostics
audit/reconciliation evidence
```

### Future managed/commercial concerns

These are explicitly future design concerns, not Task 68 work:

```text
managed dashboards
large-scale alert routing
multi-region reconciliation
advanced policy governance
long-term hosted metrics retention
enterprise approval workflows
provider-specific operations
```

Managed operation cannot move runtime trust, signing keys, high-water, patch
validity, or P3A CAS into a reconciliation service.

## 33. Proposed implementation sequence

No stage below is authorized by Task 68:

1. **P3E5-5A — reconciliation domain and taxonomy:** typed findings,
   repairability, bounds, principal, deterministic IDs, report-only core.
2. **P3E5-5B — File/PostgreSQL bounded reconciliation:** startup/manual
   ownership, CAS/locking, repair actions, restart/reconnect evidence.
3. **P3E5-5C — metrics/readiness/diagnostics:** low-cardinality metrics,
   health endpoints, safe scoped read API, exporter failure behavior.
4. **P3E5-5D — failure/concurrency/resource hardening:** races, lost repair
   responses, backlog fairness, audit divergence, retention limits.
5. **P3E5-5E — integration evidence:** required simulation vectors,
   physical deployment only if separately approved, and maintainer review.

Each stage requires its own authorization, task file, tests, review, and
bounded evidence. P3E5-5E is not a production or store-readiness gate by
itself.

## 34. Implementation entry criteria

Before implementation, maintainer approval must explicitly cover:

```text
reconciliation ownership
divergence taxonomy
repairable vs report-only boundary
repair action vocabulary
reconciliation principal/scopes
scan/locking model
File/PostgreSQL behavior
fairness/resource policy shape
metrics taxonomy
label/cardinality policy
readiness semantics
diagnostic API boundary
retention policy shape
alert concepts
implementation sequence
```

No item is inferred from this design's existence. A missing approval keeps the
affected implementation stage blocked.

## 35. Design-only validation plan

The Task 68 validation boundary is documentation only:

- Markdownlint over the design, task, ADR, and approved factual addenda;
- local Markdown-link checks for repository-relative references;
- trailing-whitespace and high-confidence secret scans;
- required-section completeness check;
- taxonomy completeness check for all required codes;
- simulation-vector completeness check for all required scenarios;
- frozen-invariant and prohibited-control scans;
- source/test/SQL unchanged check;
- no device, server, migration, runtime, mobile, or deployment execution.

No test result in this document is an implementation result. The future stages
must add unit, persistence, malformed-input, concurrency, integration, and
physical validation proportionate to their scope.

## 36. Risks and unknowns

### Technical

- Existing schedule/work projection APIs may need new typed CAS methods;
- cross-store repair evidence may require a carefully bounded append-only
  record without becoming a second source of truth;
- startup scans can increase launch latency if bounds are not enforced;
- metric series limits and tenant privacy need implementation measurements;
- readiness semantics for global audit-chain invalidity need maintainer choice.

### Security

- A reconciler with projection write access can damage availability within its
  tenant scope even without rollout authority;
- malformed findings and repair bodies must be treated as untrusted input;
- diagnostics can leak operational metadata if pagination/scope checks fail;
- audit divergence must not be hidden by a “successful” repair result.

### Operational

- PostgreSQL provider failover and HA are not proven;
- File remains single-node and single-writer;
- no production latency, capacity, retention, or alert threshold is selected;
- a permanently unresolved immutable conflict requires operator/maintainer
  handling.

### Unknown

The following remain unknown until separately implemented and tested:

```text
whether startup scan cost is acceptable for representative tenants
whether one principal can safely serve startup and manual invocation
whether repair evidence belongs in the existing audit chain or a separate
append-only operational store
whether /healthz compatibility is required when /livez is introduced
whether global audit-chain invalidity should make all writes not-ready
whether the taxonomy remains stable after real corruption fixtures
```

## 37. Readiness gates that remain open

This design does not close or relabel:

```text
P1D-01 true power loss
P1D-03 iOS diagnostics limitations
P1D-04 broad iOS performance
P1D-07 independent real application
P1D-09 interpreter attribution
P1D-18 Apple/Google/legal review
provider-production readiness
beta readiness
production readiness
App Store readiness
Google Play readiness
legal/privacy readiness
```

## 38. Recommendation

`AUTHORIZE P3E5-5 DESIGN ONLY — COMPLETE`

The design is coherent enough for a separate maintainer decision about
implementation, but Task 68 itself does not grant that authority. The next
authorized action is maintainer review of this document, Task 68, and ADR 0013.

Do not begin P3E5-5A, P3F, P3G, a periodic worker, dashboard, provider
deployment, runtime/mobile work, or production/store/legal work automatically.

## 39. P3E5-5A implementation addendum (2026-08-24)

Task 69 implemented the domain-only foundation authorized by the maintainer:
typed invocations, findings, preconditions, repair attempts, explicit policy
bounds, cursor/fairness state, the complete stable taxonomy, repairability and
severity vocabularies, typed action metadata, immutable-source/projection
classification, deterministic canonical identities, exact-scope principal
authority, and bounded audit-safe fields.

The implementation is pure control-plane domain code. It adds no persistence,
startup/manual scanning, projection repair, metrics, readiness, diagnostics,
worker, queue, rollout mutation, P3E-4 application, runtime/mobile change, or
production default. P3E5-5B remains a separate maintainer-authorized slice.

## P3E5-5B factual implementation addendum (2026-08-24)

Task 70 implemented the bounded persistence/orchestration core in
`packages/control_plane/lib/src/reconciliation_persistence.dart`. Findings and
repair attempts are append-only and canonical in File and PostgreSQL storage;
lifecycle and cursor projections use versioned CAS; File is hashed,
atomic, restart-safe, and single-writer; PostgreSQL migration 008 is advisory
lock protected; startup and exact-scope administrator invocations enforce
explicit policy/fairness bounds; and report-only immutable divergence never
rewrites evidence. A composite detector seam and typed existing-CAS executor
seam are provided, with audit-before-repair and postcondition verification.

The implementation was validated by 14 focused reconciliation tests,
PostgreSQL two-instance persistence/reconnect evidence, and the full
control-plane suite (222 tests, with one explicit MinIO/S3 environment skip).
Concrete schedule/P3E source detectors and concrete projection/CAS adapters
remain an explicit P3E5-5B continuation; they were not inferred from the
generic seams. No P3E5-5C metrics/readiness/diagnostics, worker, queue, rollout
writer, P3E-4 call, runtime/mobile change, or production claim was added.

## P3E5-5C factual implementation addendum (2026-08-24)

Task 72 implements the bounded observability slice around the closed P3E5-5B
core. The existing `ControlPlaneHttpServer` now provides `/livez` (with
`/healthz` preserved), reconciliation-aware `/readyz`, the existing
process-local JSON `/metrics` contract with bounded reconciliation counters,
and exact-scope read-only `/v1/reconciliation/diagnostics` plus
`/v1/reconciliation/findings/<id>` routes when a host supplies the
`ReconciliationObservability` adapter.

The adapter requires an explicit host authorization callback for the exact
organization/application/environment scope. It never infers a principal from
a bearer token, runs a migration, starts reconciliation, advances a cursor,
changes finding lifecycle, calls P3A/P3E-4, or writes rollout state. Diagnostic
lists have bounded limits and filters; responses expose safe digests, typed
taxonomy/action dispositions, lifecycle/repair summaries, cursor metadata, and
audit validity without raw payloads, credentials, SQL, or unbounded errors.

Readiness performs read/verify-only persistence, schema, authoritative-store,
and optional audit-chain checks. A PostgreSQL outage returns a bounded
not-ready code and explicit store recreation restores readiness; `/livez`
remains process liveness. File and PostgreSQL stores expose the same readiness
contract. Metrics are process-local and reset on restart; they are not durable
audit evidence or fleet-wide availability claims. No worker, queue, Redis,
alert, dashboard, rollout writer, runtime/mobile/compiler, provider, store, or
legal work was added by Task 72.

Task 72 validation passed the focused observability suite (11 tests), the full
control-plane suite against the local PostgreSQL fixture (248 tests passed and
one explicit MinIO/S3 environment skip), root analysis/tests, the migration
regression, Markdownlint, local-link, whitespace, secret, and prohibited-scope
scans. The resulting recommendation is `PROCEED TO P3E5-5D WITH CONDITIONS`,
subject to a new maintainer authorization; no P3E5-5D work was started.

## P3E5-5D factual implementation addendum (2026-08-24)

Task 73 implements the explicitly enabled, bounded periodic orchestration
slice. `ReconciliationPeriodicRunner` invokes an already-constructed
`BoundedReconciliationService`; it contains no detector, repair, CAS, audit,
cursor, rollout, or halt logic. The runner uses a one-shot `Timer`, a minimum
five-second interval, a default five-minute interval, bounded jitter, a
bounded startup delay, exponential failure backoff capped by configuration,
and a bounded shutdown wait. Missed timer firings are not replayed.

The runner rejects local overlap rather than queueing work. Startup and manual
reconciliation retain their existing service entry points and can share the
process-local `ReconciliationExecutionGate`. A disabled-by-default
`ControlPlaneConfig` field is populated from explicit environment variables;
invalid interval, jitter, backoff, startup-delay, and shutdown-timeout values
are rejected rather than silently clamped.

PostgreSQL periodic ownership uses a session-scoped `pg_try_advisory_lock`
with a dedicated ownership pool, so the bounded reconciliation callback can
use the persistence pool without a one-connection self-deadlock. Acquisition
contention returns immediately, the lock is released in a `finally` block, and
session loss relies on PostgreSQL session semantics. File remains explicitly
single-process/single-writer. The ownership lock is coordination only; finding
CAS, repair CAS, work currentness, audit ordering, tenant scope, and the P3A /
P3E-4 authority boundaries remain unchanged.

P3E5-5C process-local metrics now include fixed-key periodic run totals,
outcomes, overlap skips, lock contention, store failures, duration, and a
bounded last-run summary. When the host wires the same runner into
`ReconciliationObservability`, read-only diagnostics include enabled/running,
last-run, next-due, lock, backoff, shutdown-timeout, and overlap status. No
runner-control HTTP endpoint was added. Metrics and diagnostics never start,
stop, retry, or mutate reconciliation.

Task 73 added unit, File, PostgreSQL ownership/contention/handoff, bounded
outage/backoff, restart-cadence, malformed-input, shutdown, metrics,
diagnostics, and existing-service integration evidence. The real PostgreSQL
contention test initially exposed a same-pool deadlock; the dedicated
ownership-pool correction is now covered by the passing contention/handoff
test. The final recommendation and remaining external readiness gates are
recorded in `docs/P3E5_5D_PERIODIC_RUNNER_REVIEW.md`; P3E5-5E remains a separate
maintainer decision.

## P3E5-5F factual addendum (2026-08-25)

Task 75 validated the provider-neutral deployment seams without changing the
authority model. A disposable two-instance Compose topology passed both
instance-loss directions, passive proxy retry, direct/proxied liveness and
readiness, separate PostgreSQL/object-store outages, exact artifact recovery,
audit verification, and a bounded local load sample. The existing advisory
ownership, CAS, audit, currentness, postcondition, tenant, and
BoundedReconciliationService boundaries were reused.

The local proxy does not actively remove a backend from service based on
`/readyz`; provider failover, public TLS, rolling upgrade, soak, provider RPO/
RTO, and production supply-chain evidence remain open. The current HTTP host
does not wire the optional diagnostics adapter or periodic runner. See Task 75
and `docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md`; this addendum does
not authorize provider deployment or the next phase.
