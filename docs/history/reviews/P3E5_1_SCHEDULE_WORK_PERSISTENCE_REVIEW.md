# P3E5-1 schedule/work domain and persistence review

<!-- markdownlint-disable MD013 -->

Status: `READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/59-p3e5-1-schedule-work-domain-persistence.md`

## Decision and scope

P3E5-1 implements the persistence and authorization foundation approved by
Task 59. It can create and revise one tenant/application/environment-scoped
evaluation schedule, explicitly materialize deterministic pending work for an
exact trusted rollout revision and window, and preserve append-only attempt
test evidence. It does not poll, claim, lease, retry, evaluate, halt, expand,
pause, or execute work.

The scheduler remains control-plane orchestration. It has no access to Flutter
runtime trust, signing keys, Patch Format, capabilities, high-water, artifacts,
or installed application state.

## Implemented findings

| Requirement | Implemented evidence | Result |
| --- | --- | --- |
| Typed domain | Strict `EvaluationSchedule`, `EvaluationScheduleRevision`, `LogicalEvaluationKey`, `ScheduledEvaluationWork`, and `ScheduledEvaluationAttempt` models with exact-key codecs and UTC timestamps | PASS |
| Safe defaults | Both schedule and automatic-halt enablement default to false; readiness accepts only `CLOSED` or `SEALED` | PASS |
| Immutable schedule history | New revision and generation plus expected-current-revision CAS; previous revision remains readable | PASS |
| State vocabulary | Exact ten P3E-5 states; no generic `RUNNING`; pure validator implements only approved transitions and terminal behavior | PASS |
| Deterministic identity | Versioned canonical logical key; domain-separated work and attempt hashes; deterministic evaluation/halt idempotency keys | PASS |
| Collision/mutation safety | Equal ID/body is acknowledged; changed canonical content conflicts; logical-key digest/work-ID mismatches fail closed | PASS |
| Target binding | Materialization reloads a trusted P3A rollout revision and derives platform/release/patch/sequence and target digest server-side | PASS |
| Scoped principal | New `scheduler` credential kind requires organization/application/environment and supports expiry, rotation-by-replacement, revocation, and audit identity | PASS |
| Least privilege | `health:schedule` is an independent control/admin scope; `health:work:claim` is scheduler-only; evaluation-only and optional halt scope sets are separate | PASS |
| File persistence | Tenant-hashed paths, canonical JSON, atomic replacement, restart recovery, immutable work/attempts, and non-blocking one-writer guard | PASS |
| PostgreSQL persistence | Schema migration 005, tenant keys/indexes, unique logical identity, immutable rows, transactional create/revise, and expected-pointer CAS | PASS |
| Multi-instance convergence | Two PostgreSQL adapters concurrently acknowledged the same schedule/revision and work bodies | PASS |
| Explicit materialization | One direct authenticated service call creates `PENDING` work with zero attempts and null lease fields; equal calls reuse it | PASS |
| Audit privacy | Schedule create/update, work materialization, and scheduler credential issue/revoke use the existing hash-chained redacted audit store; secret tokens are absent | PASS |
| Read-only consistency | Schedule pointer, revision scope, work binding, and attempt/work links can be checked without mutation | PASS |

## Domain and identity boundary

The stable schedule stores only its current immutable revision pointer. Every
configuration change creates a new `EvaluationScheduleRevision` with a
monotonic generation and explicit superseded revision. Policy, threshold,
aggregation, window, privacy, retry, and resource references are versioned or
digested; no lease duration, retry backoff, cadence, batch size, or production
resource value was selected.

The canonical logical evaluation key binds:

```text
organization/application/environment/platform
rollout and rollout revision
release/patch/sequence and trusted target digest
window and CLOSED/SEALED readiness
observation schema
aggregation and aggregate policy digest
evaluation policy version/digest
threshold version/digest
window/privacy versions
schedule/revision/generation
```

Changed target, rollout revision, window, readiness, policy, revision, or
generation therefore creates a different work identity. Persisted work cannot
be overwritten to acquire new scheduling meaning.

## Authorization boundary

`CredentialKind.scheduler` is distinct from the organization-wide control
credential and always requires application/environment scope. Its allowed
scope universe is deliberately limited to:

```text
health:work:claim
health:evaluate
observation:read
rollout:read
rollout:halt
```

The default future execution profile omits `rollout:halt`. Adding that scope is
explicit and still grants no release, artifact, credential-administration,
signing, or arbitrary rollout-mutation permission. Human schedule
administration requires independent `health:schedule` and `rollout:read`
control scopes. P3E5-1 does not use the claim permission to claim anything;
the named scope gates explicit work persistence in this slice.

## Persistence and failure behavior

File persistence uses one atomic schedule bundle so pointer and immutable
revision history change together. Work and attempts are separate immutable
canonical records. Tenant directory names and record filenames are hashes,
and a process guard plus OS file lock rejects a second File writer. File mode
makes no high-availability or distributed-claim claim.

PostgreSQL migration 005 adds schedule, revision, work, and attempt tables.
Schedule creation and revision CAS are transactional. Unique tenant/work and
logical-key constraints make equal concurrent writes converge and changed
bodies fail. The existing advisory migration lock advances the control-plane
schema from 4 to 5, rejects future unknown schema versions, and remains safe
under concurrent startup.

Audit storage is separate from schedule persistence, so schedule persistence
and audit append are recoverable operations rather than a distributed
transaction. No execution result depends on this seam in P3E5-1.

## Executed evidence

Implemented tests cover:

- safe defaults, exact codecs, unknown versions/enums, malformed leases,
  timestamp/order constraints, encoded bounds, and mixed-scope binding;
- all approved and rejected state transitions;
- deterministic logical/work/evaluation/halt/attempt identities;
- File equal-write acknowledgement, immutable conflicts, tenant isolation,
  restart durability, second-writer rejection, corrupt JSON, CAS revision, and
  append-only attempt order;
- scheduler scope, wrong app/environment, missing halt permission, expiry,
  revocation, and forbidden credential-administration permission;
- service target validation, explicit work materialization, idempotent replay,
  schedule revision, non-revealing foreign scope, and redacted audit actions;
  and
- PostgreSQL migration 005 and two-adapter schedule/work convergence against
  the repository-managed PostgreSQL 17 fixture.

## Validation evidence

- `dart analyze --fatal-infos` in `packages/control_plane` — passed;
- focused domain/File/auth/service/migration tests without PostgreSQL — 11
  passed, one environment-gated PostgreSQL case skipped;
- focused persistence/migration tests with
  `HYFENS_TEST_POSTGRES_URL=postgresql://...@127.0.0.1:55433/...` — 6 passed,
  including the two-instance PostgreSQL case;
- full control-plane suite with PostgreSQL enabled — 113 passed; one unchanged
  MinIO integration test skipped because `HYFENS_TEST_S3_*` is not configured;
- root analysis — passed; root repository test — one passed; and
- Markdown lint, local links, whitespace, secret patterns, and prohibited
  claim/lease/execution-call scans — passed.

No Android/iOS/runtime code changed, so no physical-device test was required
or claimed.

## Explicitly not implemented

```text
due-work query or clock/window scan
claim or lease acquisition
lease token generation
lease expiry/reclaim
worker, timer, cron, queue, or executor
automatic retry
P3E-3 evaluation invocation
P3E-4 halt invocation
HOLD-to-pause
automatic expansion/resume/promotion
dashboard, alerts, P3F, or P3G
runtime/mobile change
production scheduling defaults
```

`automaticHaltEnabled` is persisted configuration only.

## Risks and open gates

- P3E5-2 must prove PostgreSQL claim fencing, recovery, lease-token handling,
  and File claim behavior without weakening this immutable identity model.
- The `health:work:claim` scope name anticipates that later behavior, but this
  task only authorizes explicit materialization; no claim path exists.
- File lock behavior is bounded to one host/filesystem and is not provider HA.
- PostgreSQL evidence proves local two-instance consistency, not provider SLO,
  backup, disaster recovery, or production capacity.
- HTTP schedule-admin endpoints and pagination were unnecessary for this
  domain slice and were not added.
- Existing P1D, provider, beta, production, store, and legal gates remain open.

## Recommendation

`AUTHORIZE P3E5-2 CLAIM & RECOVERY WITH CONDITIONS`

Conditions: preserve immutable schedule/work identity and exact tenant/target
binding; use database/server time; add no worker/evaluator/automatic halt in
the claim slice; prove token-digest fencing, work-version CAS, expiry/reclaim,
restart, duplicate claimant, fairness/resource bounds, and File/PostgreSQL
failure behavior; and stop again before P3E5-3.

This recommendation does not itself authorize P3E5-2. Stop at the Task 59
maintainer-review gate.
