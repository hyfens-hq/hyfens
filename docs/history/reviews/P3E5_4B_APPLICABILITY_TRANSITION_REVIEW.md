# P3E5-4B applicability transition review

<!-- markdownlint-disable MD013 -->

Status: `IMPLEMENTED AND VALIDATED — READY FOR MAINTAINER REVIEW`

Date: 2026-08-24

Task: `tasks/64-p3e5-4b-applicability-transition.md`

## Decision boundary

Task 64 implements applicability and durable intent only:

```text
current v2 scheduled EVALUATED work
  + exact current immutable evidence
  + approved and explicitly enabled test state
  + current fenced lease
  + exact Auto-Halt Principal
  -> HALT_APPLYING + canonical AutomaticHaltIntent
```

It does not invoke P3E-4 or P3A and does not change a rollout.

## Implemented result

`P3e5AutomaticHaltApplicabilityService` reloads and validates the exact work,
schedule/revision/generation, policy/environment-state generation and digest,
application/environment scope, rollout/revision/state/target, aggregate and
revision lineage, evaluation, decision, successor records, versions, digests,
scheduled idempotency, readiness, reason class, and authoritative freshness.

Eligibility is v2 only and exactly scheduled `HALT_NEW_OFFERS` with
`PATCH_SAFETY` and `SEALED` evidence. Initial eligible rollout states are
`INTERNAL`, `CANARY`, and `EXPANDING`. Policy approval and production
enablement must both be explicit; the repository still contains no approval,
production-enablement workflow, or production numeric defaults. Every enabled
fixture is labelled `TEST VECTOR ONLY — NOT PRODUCTION POLICY`.

The two-authority boundary is enforced twice: the request carries the exact
lease plus a current exact-scope Auto-Halt Principal, then the persistence
operation checks authoritative time, state, owner, token digest, work version,
expiry, scope, and principal again immediately before the final currentness
reload and commit. Scheduler, control, delivery, observation, bootstrap, and
signing identities cannot substitute through this API.

## Intent and persistence

`AutomaticHaltIntent` contains:

```text
workId / attemptId / evaluationId / decisionId
scheduleRevisionId
automaticHaltPolicyVersion / automaticHaltPolicyDigest
expectedRolloutRevision / targetBindingDigest
authorizedPrincipalId / authorizedAt / intentDigest
```

It excludes raw credentials and lease tokens. Authorization time is retained
as evidence but excluded from semantic identity; equivalent attempts therefore
share one digest, while changed work, decision, policy, target, or principal
changes semantic identity.

The intent is embedded in the new work version. File mode performs one atomic
replacement. PostgreSQL locks the exact work row and performs one work-version
update transaction. No schema migration was needed because the existing
canonical work body is the authoritative projection. `HALT_APPLYING` is now
invalid without a fully bound intent, and the generic executor advance rejects
that state so only the narrow operation can enter it.

Equal retries report the persisted intent. Changed intent conflicts. A failure
before commit leaves `EVALUATED` with no intent; a lost response after commit
leaves discoverable `HALT_APPLYING` evidence. File and PostgreSQL restart reads
preserve the same digest. Two PostgreSQL store instances racing on the same
lease converge on one changed work version and one idempotent replay.

## Security and failure evidence

Tests cover default-off state, unsuitable decision/reason/rollout state,
freshness expiry, successor decisions, revoked principal, expired lease, wrong
token, generic-transition rejection, pre-commit failure, a rollout change at
the final revalidation seam, lost response, restart, audit redaction, and
two-instance PostgreSQL convergence. The prior v1/v2, unsupported-version,
policy-digest, cross-scope, scheduler-principal, malformed persistence, and
credential-kind regression tests also pass in the full suite.

Audit actions implemented are:

```text
health.auto_halt_intent_created
health.auto_halt_intent_replayed
health.auto_halt_ineligible
health.auto_halt_stale
health.auto_halt_security_rejected
```

No `health.auto_halt_applied` event exists. Audit assertions exclude raw lease
and credential material.

## Validation evidence

- Control-plane `dart format`: PASS, 55 files checked and no final changes.
- Control-plane `dart analyze --fatal-infos`: PASS, no issues.
- Focused P3E5-4B suite with live PostgreSQL 17: PASS, 12 tests.
- Full control-plane suite with the live PostgreSQL fixture: PASS, 165 tests;
  the unchanged MinIO test was the only skip because `HYFENS_TEST_S3_*` was
  not configured.
- Root `dart analyze --fatal-infos`: PASS, no issues.
- Root `dart test`: PASS, 1 test.
- Markdown lint for every Task 64 document: PASS.
- Trailing-whitespace and high-confidence secret-pattern scans: PASS.
- Prohibited-boundary scan: the applicability service contains no
  `applyHealthHalt`, `transitionRollout`, `RolloutAction.halt`, P3A CAS,
  rollout transition commit, or `HealthHaltApplication` reference.
- No migration was added; PostgreSQL schema remains v7.
- Runtime, compiler, patch-format, fixture, and mobile code were unchanged.

## Completion matrix

| Requirement | Status |
| --- | --- |
| V2-only eligibility and v1 permanent ineligibility | PASS |
| Scheduled-only provenance | PASS |
| HALT_NEW_OFFERS / PATCH_SAFETY / SEALED only | PASS |
| Current policy/state/schedule binding | PASS |
| Explicit approval and default-off production state | PASS |
| Authoritative freshness | PASS |
| Exact rollout/target/evidence/version/digest binding | PASS |
| Unsuperseded decision/revision | PASS |
| Current fenced lease plus exact Auto-Halt Principal | PASS |
| Scheduler/other principal and principal-alone insufficiency | PASS |
| Tenant isolation and old-token/expiry/revocation rejection | PASS |
| Fenced `EVALUATED -> HALT_APPLYING` | PASS |
| Canonical immutable intent and idempotency | PASS |
| File atomicity, restart, crash, and lost-response recovery | PASS |
| PostgreSQL work-version CAS, restart, and two-instance convergence | PASS |
| Audit/redaction | PASS |
| P3E-4 invocation | NOT STARTED |
| P3A CAS or rollout mutation | NOT STARTED |
| `HALT_APPLYING -> COMPLETED` | NOT STARTED |
| P3E5-4C/4D/4E and P3E5-5/P3F/P3G | NOT STARTED |
| Runtime/security invariants | UNCHANGED |

## Residual risks and open gates

The schedule, health-evidence, and rollout repositories are not one global
transaction. Task 64 performs the final external-currentness reload inside the
fenced work transaction and proves injected stale changes are rejected, but a
different store can change after that reload. This is safe in 4B because the
result is non-authoritative intent only; any future P3E5-4C implementation must
reload all evidence and let existing P3E-4/P3A currentness and CAS decide the
race before mutating delivery eligibility.

File mode remains single-process/single-writer/single-host-clock. PostgreSQL
tests prove local transactional behavior, not provider HA. P1D-01, P1D-03,
P1D-04, P1D-07, P1D-09, P1D-18, provider-production, beta, production, and
store-readiness gates remain open and unchanged.

## Recommendation

`AUTHORIZE P3E5-4C P3E-4 APPLICATION WITH CONDITIONS`

Conditions: P3E5-4C must use the existing P3E-4 evidence/application core and
P3A expected-revision CAS; independently reload every current binding; use
`scheduled-halt:<workId>`; never write rollout state directly; preserve the
two-authority boundary and runtime invariants; add no production defaults or
enablement; and stop at its own maintainer-review gate. Task 64 does not itself
authorize or begin P3E5-4C.
