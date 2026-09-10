# P3E-4 conservative halt integration review

<!-- markdownlint-disable MD013 -->

Status: `READY FOR MAINTAINER REVIEW`
Date: 2026-08-24
Task: `tasks/57-p3e4-conservative-halt-integration.md`

## Decision and scope

P3E-4 implements one bounded mutation: an authorized operator can apply one
immutable P3E-3 `HALT_NEW_OFFERS` decision through the existing P3A rollout
expected-revision compare-and-set transition. It stops new offer eligibility
for the rollout. It does not revoke an installed patch, lower state-v4
high-water, change runtime signature authority, alter artifacts, invoke
rollback, or mutate the original `RolloutDecision`.

P3E-5 scheduling, automatic evaluation, automatic expansion, dashboards,
workers, mobile/runtime changes, provider deployment, and store/legal claims
were not started.

## Findings

| Required outcome | Evidence | Result |
| --- | --- | --- |
| Immutable decision-to-transition linkage | `HealthHaltApplication` entity v1; File canonical JSON and PostgreSQL migration 004; original decision remains unchanged | PASS |
| Exact evidence binding | P3E-4 reloads decision, evaluation, aggregate revision, aggregate, target-binding digest, evaluation-input digest, aggregate-input digest, aggregate digest, versions, and reconciliation state before transition | PASS |
| Full rollout-target binding | P3E-3 evaluations now persist an optional `targetBindingDigest` over the complete rollout target; P3E-4 requires and compares it to the trusted current target | PASS |
| Only `HALT_NEW_OFFERS` mutates state | Non-HALT and `HOLD` decisions persist `REJECTED` evidence and return `HEALTH_DECISION_NOT_APPLICABLE`; no pause mapping exists | PASS |
| Existing P3A CAS remains authoritative | P3E-4 calls the existing rollout transition path with a deterministic decision-derived idempotency key; no second state writer was added | PASS |
| Stale/race safety | Expected revision is checked before and inside the CAS; manual halt, concurrent health halt, and two-instance PostgreSQL races converge without two rollout revisions | PASS |
| Future eligibility only | Halted revisions return false from existing `RolloutEligibility`; runtime admission, high-water, signing, artifacts, and AOT fallback code were not changed | PASS |
| Idempotency | Same key replays the immutable application record; changed request bodies return `HEALTH_HALT_CONFLICT`; a different key for an already-applied decision records `ALREADY_APPLIED` without another transition | PASS |
| Tenant and scope isolation | Auth requires `health:evaluate`, `rollout:read`, and `rollout:halt`; foreign rollout/decision reads are non-revealing; restricted credentials fail closed | PASS |
| Malformed evidence | Corrupt persisted decisions and mismatched digests produce stable evidence rejection and cannot reach the transition | PASS |
| Audit coverage | Requested, applied, replayed, stale, conflict, cross-tenant, evidence-rejected, rejected, and already-applied paths use the existing redacted audit chain | PASS |
| Persistence recovery | If transition commit precedes the separate linkage write, the deterministic health-transition reason and revision are detected on retry and recorded as `ALREADY_APPLIED` | PASS, with cross-store durability risk retained |
| PostgreSQL multi-instance behavior | Two services sharing PostgreSQL control/P3E stores converged on one applied and one already-applied result | PASS |

## Implemented boundary

The narrow endpoint is:

```text
POST /v1/rollouts/{rolloutId}/health/decisions/{decisionId}/apply
```

The request contains only preconditions and an operator reason:

```text
expected_rollout_revision
target_binding_digest
evaluation_input_digest
aggregate_input_digest
aggregate_digest
operator_reason
```

The `Idempotency-Key` header is required. The service verifies the supplied
digests against the persisted P3E evidence and the trusted current rollout
target. The response is the immutable `HealthHaltApplication` record with one
of `APPLIED`, `ALREADY_APPLIED`, `STALE`, `REJECTED`, `CONFLICT`, or
`EVIDENCE_REJECTED`.

The transition linkage uses the deterministic key
`health-halt:{decisionId}` in the existing `rollout-transition` CAS. The
application evidence uses a separate deterministic ID derived from tenant,
decision, and caller idempotency key, so every attempt is append-only while
the rollout transition remains single-shot.

## Trust and failure behavior

P3E-4 is advisory control-plane evidence plus a rollout eligibility mutation.
It is not a runtime trust root. It cannot change Patch Format v1, capability
v1, exact release/function/capability binding, state-v4 high-water, customer
signing, artifact immutability, signed rollback, AOT fallback, or installed
patch state. A failed evidence read, digest mismatch, unsupported decision,
stale revision, missing capability, or malformed body fails closed before a
transition. A transition that has already committed remains authoritative;
retry recovery links it without replaying a second state change.

The P3E evidence store and control-plane CAS are separate persistence
boundaries. They are made recoverable with deterministic IDs and history
markers, but this task does not claim a distributed transaction or eliminate
the need for operator reconciliation after a storage outage.

## Executed evidence

The P3E-4 tests are in
`packages/control_plane/test/p3e_manual_api_test.dart` and cover:

- File application, future eligibility suppression, same-key replay, and
  different-key `ALREADY_APPLIED`;
- concurrent equal-key requests converging on one immutable application
  outcome;
- changed-body conflict, malformed persisted decision, digest mismatch,
  non-HALT/`HOLD` rejection, missing mutation scope, and HTTP route behavior;
- manual-halt versus health-halt and expansion versus health-halt races with
  exactly one rollout revision in each case; and
- two independent PostgreSQL-backed services converging on one halt revision
  and two immutable attempt records.

The migration contract is tested in
`packages/control_plane/test/migration_test.dart`. The P3E persistence suite
also exercises PostgreSQL restart, tenant isolation, immutable writes, and
concurrent startup against schema version 4.

## Validation evidence

- `cd packages/control_plane && dart analyze --fatal-infos .` — passed;
- focused P3E-4 tests without PostgreSQL — 14 passed; two PostgreSQL tests
  skipped because the environment variable is absent;
- focused P3E-4 tests with the configured local PostgreSQL test container via
  `HYFENS_TEST_POSTGRES_URL` — 16 passed, including the two-instance halt
  race;
- full control-plane suite with the configured PostgreSQL test container — 102
  passed, one MinIO integration skipped because `HYFENS_TEST_S3_*` was not
  configured; and
- no Android/iOS/runtime code was changed, so no physical-device rerun was
  authorized or claimed for this control-plane slice.

## Risks and unknowns

- File P3E storage remains single-node; PostgreSQL is the tested multi-instance
  adapter, not a provider availability or disaster-recovery claim.
- Cross-store transition/linkage recovery is deterministic but not atomic
  across the two stores; reconciliation and operator handling remain needed.
- No production health thresholds, scheduler cadence, automatic halt policy,
  expansion policy, alerting, beta, production, App Store, Google Play, or
  legal-compliance claim follows from these tests.
- Existing P1D, provider-production, beta, production, store, and legal gates
  remain open and are not relabelled by P3E-4.

## Recommendation

`AUTHORIZE P3E5 SCHEDULED-EVALUATION DESIGN WITH CONDITIONS`

Conditions:

1. Keep P3E-4 as the only conservative halt mutation boundary; do not add
   automatic evaluation or scheduling until its separate design is reviewed.
2. Preserve all frozen runtime, signing, high-water, Patch Format, capability,
   artifact, P3A, P3D, P3E-1, P3E-2, and P3E-3 invariants.
3. Do not map `HOLD` to pause, add automatic expansion, invoke runtime
   rollback, or introduce dashboard/worker/mobile/provider work in the design
   slice.
4. Keep all readiness and policy gates listed above open. This recommendation
   authorizes design/review work only, not P3E-5 implementation.

Stop at the P3E-4 maintainer-review gate.
