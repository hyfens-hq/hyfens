# P3E5-5B bounded reconciliation review

<!-- markdownlint-disable MD013 -->

Status: final closure complete; maintainer decision required
Date: 2026-08-24
Task: 70

## Decision boundary

Task 70 authorized the File/PostgreSQL bounded reconciliation slice only. This
review records what was implemented and executed. It does not authorize
P3E5-5C metrics/readiness/diagnostics, a periodic worker, queues/Redis, new
rollout behavior, P3F/P3G, provider deployment, runtime/mobile changes, or
production/store/legal claims.

## Implementation summary

`packages/control_plane/lib/src/reconciliation_persistence.dart` adds a
separate reconciliation boundary with:

- append-only `ReconciliationFinding` and `ReconciliationRepairAttempt`
  persistence;
- canonical body comparison, deterministic identity replay, and immutable
  changed-body conflicts;
- versioned finding lifecycle and resumable cursor records with File/PostgreSQL
  compare-and-set updates;
- hashed tenant-separated File paths, atomic replacement, restart durability,
  and a non-blocking single-process/single-writer guard;
- migration 008 for PostgreSQL findings, repair attempts, lifecycle, and
  cursor tables, with advisory-locked fresh/upgrade bootstrap;
- bounded startup execution and explicit exact-scope administrator execution;
- stable ordering, per-tenant/global caps, policy caps, backlog reporting, and
  persisted cursor advancement;
- a composite detector seam for authoritative-store readers with duplicate
  identity conflict detection;
- report-only handling for immutable divergence and a typed repair-executor
  seam for existing CAS/projection adapters;
- pre-repair audit, fresh precondition reload support, persisted outcomes,
  postcondition verification, safe audit-outage failure, and lost-response
  replay by deterministic repair identity;
- `ControlPlaneReconciliationAuditSink`, which verifies the existing audit
  chain before appending and never rewrites it.

The reconciler contains no rollout writer, P3E-4 call, P3A transition, timer,
queue, Redis dependency, metrics/readiness/diagnostic endpoint, or runtime/mobile
dependency.

## Evidence matrix

| Requirement | Evidence | Status |
| --- | --- | --- |
| File finding persistence | `reconciliation_persistence_test.dart`: create, replay, changed-body conflict, restart | VERIFIED |
| File repair-attempt persistence | Same test: immutable create/replay and restart read | VERIFIED |
| PostgreSQL finding/repair persistence | Same test against the local PostgreSQL 17 fixture (`HYFENS_TEST_POSTGRES_URL`, SSL disabled) | VERIFIED |
| Migration fresh/upgrade/concurrent startup | migration test, PostgreSQL two-instance initialization, migration 008/schema version 8 | VERIFIED |
| Lifecycle and cursor CAS | File focused test; PostgreSQL lifecycle readback | VERIFIED |
| Bounded startup/manual execution | service tests for startup, exact principal scope, caps, cursor, replay | VERIFIED |
| Report-only immutable divergence | orphan-work test does not invoke executor or create a repair attempt | VERIFIED |
| Audit-before-repair | injected audit outage prevents executor invocation and records `AUDIT_UNAVAILABLE` | VERIFIED |
| Audit-chain tamper handling | Existing audit-chain digest tampering prevents reconciliation audit append | VERIFIED |
| Postcondition gate | `APPLIED` is accepted only when the executor reports a fresh postcondition read | VERIFIED |
| Lost repair response | deterministic existing attempt is replayed without a second executor call | VERIFIED |
| File single-writer behavior | second initialized File store is rejected | VERIFIED |
| Tenant isolation | foreign scope cannot list/read another tenant's finding | VERIFIED |
| Malformed persistence | noncanonical/unknown-version File record fails closed | VERIFIED |
| Two-instance PostgreSQL immutable race | concurrent equal finding writes converge to one create and one replay | VERIFIED |
| Taxonomy discovery | all 19 typed codes remain in the frozen 5A taxonomy; concrete schedule/work, P3E, rollout, audit, stale, lease, retry, malformed, and report-only paths read authoritative stores | PARTIAL — model-invariant decision-link and separate completion/derived-projection paths remain intentionally unbound |
| Real projection/operational CAS repairs | evaluation link, halt completion/link path, stale, and retry terminal CAS adapters use existing schedule-store methods with fresh digests and postconditions | PARTIAL — `LINK_EXISTING_DECISION`, separate `COMPLETE_WORK_FROM_EXISTING_APPLICATION`, and `REBUILD_DERIVED_PROJECTION` have no safe existing seam |
| Two reconcilers with a real projection mutation | two PostgreSQL reconcilers use one actual work projection; one semantic mutation and one work-version increment | VERIFIED |

The source and repair adapters are intentionally injected rather than guessed:
the existing schedule/P3E/rollout stores have different authority and scope
models, and wiring them without a separate fixture would risk creating a second
mutation path. This is the remaining P3E5-5B implementation boundary, not an
inference that those integrations work.

## Validation executed for the original bounded core

The counts below are retained as historical evidence from the initial Task 70
slice. The continuation validation and final consolidated counts are recorded
in the addendum below.

From `packages/control_plane`:

- `dart analyze . --fatal-infos` — PASS;
- focused reconciliation tests without provider configuration — PASS, 13
  tests, 1 explicit PostgreSQL skip;
- focused reconciliation tests against the local PostgreSQL fixture — PASS,
  14 tests;
- full `dart test` against the local PostgreSQL fixture — PASS, 222 tests and
  1 explicit MinIO/S3 environment skip;
- migration test — PASS with migration 008 and schema version 8.

The local PostgreSQL result is bounded engineering evidence only. It is not
provider HA, production durability, beta, or deployment evidence.

## Authority and security findings

- Findings, repair attempts, source digests, scope, taxonomy, and identity are
  immutable after persistence.
- Lifecycle and cursor changes require the prior version and the next version;
  stale callers receive a precondition failure.
- Every public persistence read takes exact scope; there is no global read API.
- File paths reveal neither tenant IDs nor finding IDs; malformed records are
  rejected before use.
- PostgreSQL rows carry explicit scope columns and indexed bounded queries.
- A repair requires a typed precondition matching the finding and an audit
  request before the injected mutation adapter runs.
- An applied response without an adapter-verified postcondition is stored as a
  safe failure, never as success.
- Audit-chain invalidity is fail-closed through the existing audit adapter; no
  audit repair operation exists.
- The injected executor is the only mutation seam. Task 70 does not add or
  call P3A/P3E-4, does not lower high-water, and does not alter runtime trust.

## Known limitations and open evidence

1. The continuation now wires concrete schedule/work, P3E, rollout, and audit
   detectors and real schedule/CAS adapters for representable paths. The
   frozen decision-link action, a separate completion action, and derived
   projection rebuild remain intentionally unbound because no safe existing
   seam exists in this model.
2. The two-reconciler race around one real PostgreSQL work projection and stale
   precondition rejection are now verified. PostgreSQL malformed-row injection
   is also verified to fail closed.
3. Actual PostgreSQL connection close/reconnect injection at every repair
   boundary remains `INSUFFICIENT_EVIDENCE`; the File post-commit response-loss
   seam is not a network-disconnect substitute.
4. No metrics, readiness, diagnostics, dashboard, worker, queue, or alerting
   work was started.

## Readiness gates unchanged

P1D-01 true power loss, P1D-03 iOS diagnostics limitations, P1D-04 broad iOS
performance, P1D-07 independent real application, P1D-09 interpreter
attribution, P1D-18 Apple/Google/legal review, provider-production readiness,
beta readiness, production readiness, App Store readiness, Google Play
readiness, and legal/privacy readiness remain open.

## Recommendation

Recommendation: `CONTINUE P3E5-5B`

The persistence and bounded orchestration core is sufficiently evidenced to
continue, but the two integration boundaries explicitly listed above must be
implemented and tested before authorizing P3E5-5C. Do not begin P3E5-5C,
P3F, P3G, provider deployment, or production/store/legal work automatically.

## Task 70 continuation — concrete detector/CAS closure evidence

Date: 2026-08-24

The continuation was executed within the existing Task 70 boundary. The
implementation is in `packages/control_plane/lib/src/reconciliation_adapters.dart`
and the focused evidence is in
`packages/control_plane/test/reconciliation_concrete_test.dart`. No new task
number was created, and no P3E5-5C/5D/5E, worker, rollout writer, runtime, or
mobile work was started.

### Concrete detector wiring

`AuthoritativeReconciliationCandidateSource` now reads the existing
`P3ePersistenceStore` and `P3e5ScheduleStore` rather than reconciliation rows.
When the existing `ControlPlaneStore` is supplied it also reads rollout,
rollout-revision, and append-only audit-chain records. It emits deterministic
findings for the representable paths below:

| Path | Evidence | Result |
| --- | --- | --- |
| schedule/work consistency and current revision | real schedule list, work list, and `validateConsistency` | PASS |
| missing work → evaluation link with matching immutable evidence | real P3E aggregate/revision/evaluation/decision reads | PASS |
| work → decision linkage | frozen `ScheduledEvaluationWork` constructor requires evaluation and decision as a pair; no valid persisted partial-link state exists | INTENTIONALLY UNBOUND |
| work → halt-application linkage | real P3E halt application and scheduled work/intent reads | PASS for recoverable link candidate |
| P3E aggregate/evaluation/decision lineage | real `P3ePersistenceStore.reconcile` and identity-scoped records | PASS |
| rollout/application reference and target binding | real `ControlPlaneStore` rollout/revision records plus P3E records | PASS |
| audit reference and chain divergence | real audit-chain read/verification | PASS |
| stale active work, expired lease, retry exhaustion | real schedule/work timestamps, revision pointer, and retry policy | PASS |
| malformed rollout records | File raw-row injection is reported as `UNKNOWN_VERSION` | PASS |
| orphan/unknown immutable divergence | P3E report is mapped to frozen report-only taxonomy | PASS/report-only |

The source never treats a reconciliation finding as authoritative input and
does not synthesize missing immutable evidence. Narrow application scopes are
filtered using the identity present in authoritative records; unbound records
are not attributed to a tenant by inference.

### Real mutation seams

`AuthoritativeReconciliationRepairExecutor` wires only existing
`P3e5ScheduleStore` CAS methods:

| Action | Existing seam | Result |
| --- | --- | --- |
| `LINK_EXISTING_EVALUATION` | `advanceExecution` from evaluating to evaluated, carrying validated existing aggregate/revision/evaluation/decision links | PASS |
| `LINK_EXISTING_HALT_APPLICATION` | `completeAutomaticHalt`, the existing P3E5-4 fenced completion seam, after validating existing applied halt evidence and (when supplied) the exact halted rollout revision | PASS for the existing completion path |
| `MARK_STALE` | `markAutomaticHaltStale` with lease/work-version CAS | PASS |
| `MARK_FAILED_PERMANENT` | `failClaim` with the existing retry policy and lease CAS | PASS |
| `LINK_EXISTING_DECISION` | no safe standalone projection CAS exists; the work model rejects a partial evaluation/decision link | INTENTIONALLY UNBOUND |
| `COMPLETE_WORK_FROM_EXISTING_APPLICATION` | no separate public seam beyond the completion method above | INTENTIONALLY UNBOUND as a separate action |
| `REBUILD_DERIVED_PROJECTION` | no existing derived projection writer in the authorized scope | INTENTIONALLY UNBOUND |

The completion adapter does not call P3A or P3E-4. With a control-store
adapter it independently checks the same resulting halted revision constraints
used by the existing recovery path: tenant, current revision, halted state,
previous revision, transition reference, reason marker, and target digest.
Precondition work digests are re-read before mutation; a changed work body is
rejected as `PRECONDITION_CONFLICT`.

### Concrete execution evidence

| Requirement | Test/evidence | Result |
| --- | --- | --- |
| real startup with detector and evaluation-link CAS | File P3E/schedule/reconciliation stores | PASS |
| exact-scope administrator path with real detector, CAS, and audit sink | stale-work test with `ReconciliationPrincipal` and `ControlPlaneReconciliationAuditSink` | PASS |
| pre-repair audit blocks real mutation | same stale-work fixture with a sink failing only `repairRequested`; work remains version 4/`HALT_APPLYING` | PASS |
| real completion lost-response recovery | existing File completion seam commits then throws at `afterCommit`; adapter reloads and returns `REPLAYED` | PASS |
| File restart with concrete path | close/reopen P3E and schedule stores; links and work version persist and no duplicate finding is emitted | PASS |
| two-tenant isolation and fairness | two real work projections, narrow app scope, broad startup caps 1/2 | PASS |
| no direct P3A/P3E-4 mutation path | source scan plus boundary test rejecting rollout-transition and halt-service imports/calls | PASS |
| immutable divergence remains report-only | rollout/audit/P3E mismatch findings have no executable precondition | PASS |

### PostgreSQL race and malformed-row evidence

Against the local PostgreSQL fixture (`HYFENS_TEST_POSTGRES_URL`, SSL
disabled), two independent `PostgresP3e5ScheduleStore` instances and two
independent reconciliation stores used the same stale finding and one real
work projection. Exactly one semantic CAS changed work version 4 → 5; the
other invocation converged through deterministic repair-attempt identity. A
subsequent invocation using the old work digest returned
`PRECONDITION_CONFLICT` and left version 5 unchanged.

The PostgreSQL malformed-row test injected, directly into the reconciliation
tables, unknown schema, invalid canonical payload, scope mismatch, body-digest
mismatch, same-ID repair-body conflict, invalid lifecycle version, and invalid
cursor version. Every case failed closed before an adapter mutation.

### Disconnect/reconnect boundary

Actual PostgreSQL connection close/reconnect injection around every individual
finding write, pre-repair audit, projection commit, repair-attempt write,
postcondition reload, and post-repair audit boundary was not safely isolated by
the existing adapter APIs. The post-commit response-loss case above is real
adapter evidence, but it is not a network disconnect. These per-boundary
disconnect cases remain `INSUFFICIENT_EVIDENCE`; no PASS is inferred.

### Continuation validation

- `dart format lib/src/reconciliation_adapters.dart test/reconciliation_concrete_test.dart` — PASS;
- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- concrete suite without PostgreSQL — 9 passed, 2 explicit PostgreSQL skips;
- concrete suite with local PostgreSQL — 11 passed, 0 skips;
- full control-plane suite against the local PostgreSQL fixture — PASS, 232
  tests, one explicit MinIO/S3 environment skip;
- root `dart analyze --fatal-infos && dart test` — PASS, one bootstrap test;
- migration test — PASS;
- changed-scope Markdownlint, trailing-whitespace, secret-pattern, and
  prohibited-worker/rollout/runtime/metrics scans — PASS.

### Continuation disposition

The concrete representable detectors and existing CAS adapters are now wired,
but the separate decision-link/completion action boundaries remain
intentionally unbound and PostgreSQL disconnect/reconnect evidence is still
insufficient. Therefore the Task 70 disposition remains:

**`CONTINUE P3E5-5B`**

P3E5-5C metrics/readiness/diagnostics, P3E5-5D/5E, P3F/P3G, provider
production, beta, store, and legal work remain unauthorized. This addendum is
ready for maintainer review; no subsequent phase was started automatically.

## Task 71 final closure addendum (2026-08-24)

Task 71 was executed under the final-closure instruction without changing the
authority model. The test-only PostgreSQL seam closes the actual `Pool` at a
named boundary and requires explicit recreation of the store for recovery. The
injector is null in production construction; it adds no retry worker, public
fault endpoint, transaction rewrite, rollout writer, or P3E-4 call.

### Exhaustive action-binding matrix

| Action | Detection source | Preconditions | Binding/disposition | Postcondition | Evidence | Limitation |
| --- | --- | --- | --- | --- | --- | --- |
| `LINK_EXISTING_EVALUATION` | Scheduled work with immutable P3E evidence and missing evaluation link | Fresh work digest/version, aggregate/revision/evaluation/decision lineage, valid lease | `BOUND` to existing `advanceExecution` CAS | Work is `EVALUATED` with the complete link pair and version +1 | File and PostgreSQL concrete CAS tests; two-reconciler PostgreSQL race | Only representable current work states are eligible |
| `LINK_EXISTING_DECISION` | Frozen work-decision taxonomy code | Valid `ScheduledEvaluationWork` model | `MODEL_UNREACHABLE`; no executor | No mutation; partial link cannot be constructed or decoded | Constructor/decode rejection tests and unsupported-action executor test | A future model change would require a new review |
| `LINK_EXISTING_HALT_APPLICATION` | Existing applied halt evidence and `HALT_APPLYING` work | Fresh digest, exact halted rollout revision, fenced lease | `BOUND` through existing completion operation | Work links the application and becomes `COMPLETED` exactly once | File completion replay and concrete detector/CAS tests | The action uses the existing completion seam; no new writer exists |
| `COMPLETE_WORK_FROM_EXISTING_APPLICATION` | Existing applied halt application with incomplete work status | Same exact evidence and lease checks as completion | `COVERED_BY_EXISTING_OPERATION`; no second public CAS | Existing `completeAutomaticHalt` postcondition | Completion replay and exact halted-revision validation | Separate action name remains taxonomy-only |
| `MARK_STALE` | Expired/stale active work | Fresh work digest, lease/version CAS | `BOUND` to `markAutomaticHaltStale` | Work is `STALE`, version +1, lease cleared | File and PostgreSQL pre/post-commit disconnect tests | No generic force-state path |
| `MARK_FAILED_PERMANENT` | Retry exhaustion | Fresh digest, active lease, retry policy and version CAS | `BOUND` to `failClaim` | Work is terminal failed, version +1 | File and PostgreSQL retry tests | Retry policy remains authoritative |
| `REBUILD_DERIVED_PROJECTION` | No authorized derived projection owner in P3E5-5B | None | `NOT_APPLICABLE` / report-only; no executor | No authoritative mutation or `APPLIED` attempt | Total disposition map and fail-closed executor tests | A future owner must be authorized separately |
| `REPORT_ONLY` | Immutable divergence, malformed or security evidence | No executable precondition | `REPORT_ONLY` | Finding/audit only; no mutation | Detector and malformed-row tests | Operator investigation remains outside this task |

The typed `reconciliationRepairBindingDispositions` map is total over all
eight frozen action values. No action is represented as unexplained
`UNBOUND`. Non-executable dispositions return a safe typed failure and cannot
be silently mapped to another mutation.

The `ScheduledEvaluationWork` constructor and canonical decoder reject a
partial evaluation/decision link. A valid persisted work record therefore
cannot reach `LINK_EXISTING_DECISION`; malformed raw rows fail closed.

### PostgreSQL disconnect/reconnect evidence

The concrete suite passed 16 tests with the local PostgreSQL 17 fixture. The
following are actual pool-close/recreate cases, not response-loss substitutions:

| Boundary | Result | Evidence label |
| --- | --- | --- |
| Finding write before/after commit | No row on pre-commit fault; committed finding is recovered and replayed after post-commit fault | `POSTGRESQL_DISCONNECT` |
| Repair-attempt write before/after commit | Pre-commit leaves no attempt; post-commit reload finds one immutable attempt and replay does not mutate twice | `POSTGRESQL_DISCONNECT` |
| Pre-repair audit | Second audit append closes the pool before commit; service records `AUDIT_UNAVAILABLE` and the counting executor is never called | `POSTGRESQL_DISCONNECT` |
| Authoritative projection/CAS before/after commit | Pre-commit leaves work unchanged; post-commit recovery observes exactly one status/version change and an old lease is rejected | `POSTGRESQL_DISCONNECT` |
| Postcondition reload | A real read closes before result; a recreated store reloads the committed version | `POSTGRESQL_DISCONNECT` |
| Post-repair audit | Chain commit survives connection loss; recreated store appends the companion immutable record without a duplicate chain entry | `POSTGRESQL_DISCONNECT` |
| Lifecycle/cursor CAS before/after commit | Pre-commit leaves no projection; post-commit recreation observes version 1 | `POSTGRESQL_DISCONNECT` |
| Two independent reconcilers | One CAS result is lost after commit; the recreated second instance sees the winner and stale retry returns `StorageConflict` | `TWO_RECONCILER_RACE` + `POSTGRESQL_DISCONNECT` |
| Tenant isolation/fairness | Recreated store preserves exact organization rows and bounded list visibility for a second tenant | `POSTGRESQL_DISCONNECT` |
| Administrator reconnect | Exact-scope `ReconciliationPrincipal` survives the fault; no executor call occurs after audit loss | `POSTGRESQL_DISCONNECT` |
| Startup outage | Unavailable PostgreSQL fails within the bounded timeout; a later explicit store recreation initializes successfully | `POSTGRESQL_DISCONNECT` |

The audit verifier now checks positive sequence ordering, cryptographic
previous-link continuity, and canonical body digests. PostgreSQL audit
sequence allocation is serialized under the existing chain lock so idempotent
or rolled-back inserts do not consume future chain positions. Tampered audit
content remains fail-closed; no reconnect path repairs or rewrites history.

### Final validation

- `dart format` on all changed Dart files — PASS;
- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- concrete suite with PostgreSQL — PASS, 16 tests;
- full `packages/control_plane` suite with PostgreSQL — PASS, 237 tests and
  one explicit MinIO/S3 environment skip;
- root `dart analyze --fatal-infos && dart test` — PASS, 1 test;
- migration regression — PASS;
- malformed PostgreSQL rows, File restart/lost-response, two-reconciler CAS,
  tenant/fairness, audit tamper, Markdownlint, local links, trailing
  whitespace, secret scan, and prohibited-boundary scans — PASS.

No physical/runtime/mobile/compiler/provider/store/legal work was started by
Task 71.

## Final disposition

For the declared bounded P3E5-5B scope, the previously open action-model and
disconnect evidence gaps are closed. Task 70 is marked `Completed` and this
review stops at maintainer review.

Recommendation: **`PROCEED TO P3E5-5C WITH CONDITIONS`**.

This is a recommendation only; it does not authorize P3E5-5C implementation.
The authority model, append-only evidence, exact-scope authorization,
fail-closed behavior, and no-second-writer constraints remain frozen. Provider
HA, beta, production, App Store/Google Play, legal, and the previously open
P1D readiness gates remain unresolved and must not be relabeled by this
closure.
