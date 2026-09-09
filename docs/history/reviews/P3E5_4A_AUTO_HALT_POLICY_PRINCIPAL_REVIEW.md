# P3E5-4A automatic-halt policy and principal review

<!-- markdownlint-disable MD013 -->

Status: `IMPLEMENTED AND VALIDATED — READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/63-p3e5-4a-auto-halt-policy-principal.md`

## Decision boundary

Task 63 implements only the policy, principal, enablement-state, work-meaning,
and persistence foundation approved by the maintainer. It does not apply an
automatic halt.

```text
AUTO_HALT_IMPLEMENTED = PARTIAL / FOUNDATION ONLY
AUTO_HALT_POLICY_APPROVED = false
AUTO_HALT_PRODUCTION_ENABLED = false
```

P3E5-4B through P3E5-4E, P3E5-5, P3F, and P3G remain unauthorized.

## Implemented capabilities

### Immutable policy identity

`AutomaticHaltPolicy` is a strict tenant/application/environment-scoped model
with:

```text
automaticHaltPolicyVersion = 1
eligibleSource = SCHEDULED_ONLY
eligibleReadiness = SEALED_ONLY
eligibleReasonClass = PATCH_SAFETY_ONLY
maximumAggregateAgeFromLateCutoff = required input
maximumDecisionAgeFromEvaluation = required input
resourcePolicyReference = required input
approvalReference = required input
createdAt / createdBy = immutable provenance
```

The semantic digest includes scope, version, fixed eligibility semantics, both
freshness durations, resource-policy reference, and approval reference.
Creation metadata and the opaque policy ID do not alter an otherwise equal
semantic digest. Canonical JSON sorts keys, encodes durations as integer
microseconds, requires UTC timestamps, rejects extra/missing fields, and
recomputes the digest on decode. Unknown versions fail closed.

No freshness or resource duration has a source default. All executable tests
provide values explicitly and label policy references as
`TEST VECTOR ONLY — NOT PRODUCTION POLICY`.

### Approval and enablement separation

`AutomaticHaltEnvironmentState` is an immutable, contiguous state revision.
The foundation factory always creates:

```text
generation = 1
policyApproved = false
productionEnabled = false
productionEnableReference = null
```

The model rejects production enablement unless policy approval is true and an
explicit production-enable reference exists. Task 63 adds no approval or
production-enable workflow and cannot change either value through a service
API.

### Dedicated Auto-Halt Principal

`CredentialKind.autoHalt` is application/environment scoped and accepts one
exact fixed profile only:

```text
health:work:apply-halt
rollout:read
rollout:halt
```

Subsets and supersets are rejected. The principal has no claim, evaluation,
observation, schedule-administration, release/artifact, promotion,
credential-administration, signing, delivery, or runtime authority. Existing
scheduler scopes no longer include `rollout:halt`; the P3E5-3 evaluation-only
profile is unchanged in meaning.

Issuance still requires the existing control-plane credential-administration
authority, exact organization/application/environment records, optional
expiry, hash-only secret persistence, revocation, and bounded audit. Audit
actions are:

```text
health.auto_halt_principal_issued
health.auto_halt_principal_revoked
```

### Two-authority representation

`AutomaticHaltAuthority` can be constructed only from:

1. one typed `P3e5LeaseMutation`; and
2. one current, non-revoked, unexpired exact-scope Auto-Halt Principal with the
   complete fixed profile.

The organization/application/environment scopes must match. Control,
scheduler, delivery, observation, and other credential kinds cannot
substitute. This type performs no work transition and invokes neither P3E-4
nor P3A.

### Logical work meaning v2

Logical key v1 remains the default for compatibility. Its canonical bytes and
work-ID domain separator remain unchanged, and it is always automatically
ineligible—even when a historical schedule revision carried
`automaticHaltEnabled = true`.

Logical key v2 conditionally adds and digests:

```text
automaticHaltPolicyId
automaticHaltPolicyVersion
automaticHaltPolicyDigest
automaticHaltEnabled
automaticHaltEligibleSource = SCHEDULED_ONLY
automaticHaltEligibleReadiness = SEALED_ONLY
automaticHaltEligibleReasonClass = PATCH_SAFETY_ONLY
schedule revision and generation (existing binding)
```

V2 rejects missing fields, future versions, `CLOSED`, or any unsupported
eligibility semantic. Its evaluation idempotency remains
`scheduled-evaluation:<workId>`. A policy replacement appends a new immutable
environment state; schedule creation/revision accepts only the current exact
policy. The changed policy plus new schedule revision/generation produces a
new work identity and requires fresh materialization/evaluation.

### File and PostgreSQL persistence

File mode persists one versioned canonical automatic-halt bundle per hashed
tenant/application/environment scope. One atomic replacement contains policy
and environment-state histories together. Restart reads, immutable replay,
lineage, duplicate identity, extra-field, digest, malformed-record, and
cross-scope validation fail closed. File mode remains one process/one writer.

PostgreSQL migration 007 adds only:

```text
control_plane_p3e5_auto_halt_policies
control_plane_p3e5_auto_halt_states
```

Both carry explicit tenant/application/environment columns, canonical JSON,
immutable IDs, scope indexes, generation uniqueness, and policy foreign-key
binding. Migration execution remains under the existing advisory lock.
Transactional immutable insert/readback and generation locking make equal
two-instance writes converge and changed bodies conflict. There is no halt
application, rollout update, P3A CAS, artifact, runtime, or mobile SQL.

### Administration and audit

`P3e5ScheduleService.registerAutomaticHaltPolicy` validates the exact tenant
application/environment, creates a new immutable policy and a default-off
environment-state revision, persists them together, and records one of:

```text
health.auto_halt_policy_created
health.auto_halt_policy_revised
health.auto_halt_policy_rejected
```

Audit metadata is bounded to scoped IDs, versions, digests, generations,
boolean state, and safe result codes. Tests prove that credential secrets and
raw lease tokens are absent.

## Explicitly not implemented

```text
EVALUATED -> HALT_APPLYING
automatic candidate scanning
P3E-4 invocation
scheduled-halt:<workId> application
P3A CAS invocation
rollout mutation
halt recovery or reconciliation
heartbeat
automatic expansion
HOLD -> pause
rollback
resume or unhalt
production policy values
provider deployment
runtime/mobile changes
```

The pre-existing schedule-domain enum and transition vocabulary still mention
`HALT_APPLYING`; Task 63 did not add, call, or expose a path that enters it.

## Security findings

| Boundary | Evidence |
| --- | --- |
| Credential compromise isolation | Evaluator/scheduler lacks halt scopes; Auto-Halt Principal lacks claim/evaluate/schedule scopes. |
| Exact scope | Principal, policy, state, schedule, logical key, File path, PostgreSQL predicates, and service lookups bind organization/application/environment. |
| Historical work | V1 has no automatic-halt fields and its eligibility getter is always false. |
| Policy downgrade | Only the policy referenced by the current environment-state revision can configure a new v2 schedule revision. |
| Malformed state | Strict fields, enums, versions, timestamps, digests, lineage, canonical bundle shape, and persistence readback reject corruption. |
| Secret handling | Raw credential and lease material are never policy/state fields or audit metadata. |
| Runtime trust | No patch, capability, signature, high-water, rollback, AOT, artifact, runtime, or mobile code changed. |

## Validation evidence

- `dart analyze --fatal-infos` in `packages/control_plane`: PASS, no issues.
- Full `packages/control_plane` suite with the live PostgreSQL 17 fixture:
  PASS, 153 tests; the unchanged MinIO test was the only skip because
  `HYFENS_TEST_S3_*` was not configured.
- Root `dart analyze --fatal-infos`: PASS, no issues.
- Root `dart test`: PASS, 1 test.
- Live PostgreSQL upgrade: schema v6 advanced to v7; both automatic-halt
  tables exist and two independent schedule stores converged on one immutable
  policy/state result.
- Fresh/concurrent PostgreSQL migration: two control stores initialized one
  isolated empty database concurrently, followed by two schedule stores and
  the immutable race; PASS, 15 tests. The temporary database was removed.
- File restart, immutable replay/conflict, malformed bundle, cross-scope, and
  audit-redaction tests: PASS as part of the full suite.
- Markdown lint, local-reference, trailing-whitespace, and secret-pattern
  scans: PASS.
- Prohibited-call scan over the new policy/authority/service/migration paths:
  no `applyHealthHalt`, `RolloutAction`, `scheduled-halt`, `HALT_APPLYING`, or
  `advanceExecution` use.
- Runtime/compiler/fixture/experiment files newer than the Task 63 start
  boundary: none.

## Completion matrix

| Requirement | Status |
| --- | --- |
| AutomaticHaltPolicy model and digest | PASS |
| No production defaults | PASS |
| Approval and production enablement separation | PASS |
| Dedicated exact-scope Auto-Halt Principal | PASS |
| Scheduler remains unable to halt | PASS |
| Principal expiry/revocation and tenant scope | PASS |
| Two-authority representation | PASS |
| Logical-key/work meaning v2 | PASS |
| Historical v1 ineligibility | PASS |
| Policy change creates fresh work meaning | PASS |
| Scheduled/SEALED/PATCH_SAFETY bindings | PASS |
| File persistence/restart/malformed input | PASS |
| PostgreSQL migration/persistence/two-instance race | PASS |
| P3E5-4B applicability transition | NOT STARTED |
| P3E5-4C P3E-4 invocation | NOT STARTED |
| P3E5-4D recovery/race evidence | NOT STARTED |
| P3E5-4E broader integration evidence | NOT STARTED |
| P3E5-5/P3F/P3G | NOT STARTED |

## Open readiness gates

Task 63 does not close or relabel P1D-01, P1D-03, P1D-04, P1D-07, P1D-09,
P1D-18, provider-production gates, beta readiness, production readiness, or
store readiness. P3E5-4A success is not automatic-halt policy approval or a
production claim.

## Recommendation

`AUTHORIZE P3E5-4B APPLICABILITY TRANSITION WITH CONDITIONS`

Conditions: P3E5-4B may validate only current v2 scheduled work under the
exact current policy/state, authoritative freshness, fencing, and the separate
Auto-Halt Principal, then persist the bounded `EVALUATED -> HALT_APPLYING`
intent. It must not invoke P3E-4/P3A, mutate a rollout, approve policy, enable
production, introduce production values, or begin P3E5-4C and later work.
P3E5-4B must have a separate task and stop at its maintainer-review gate.
