# Task 64 — P3E5-4B applicability transition

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Prove that one exact current v2 scheduled `HALT_NEW_OFFERS` decision can be
classified under both independent authorities and atomically persist a fenced,
canonical `EVALUATED -> HALT_APPLYING` intent without invoking P3E-4 or P3A and
without mutating rollout state.

## Scope and Non-goals

Scope: v2/scheduled/provenance/readiness/reason/decision gates, current
policy/environment/schedule/rollout/evidence/freshness validation, current
fenced lease plus exact Auto-Halt Principal authority, bounded immutable intent
identity, File and PostgreSQL atomic persistence, idempotency/races,
crash/restart behavior, audit/redaction, tests, and factual documentation.

Non-goals: P3E-4 invocation, P3A CAS, rollout mutation or revision creation,
`HALT_APPLYING -> COMPLETED`, recovery through halt evidence, production
approval or enablement workflows/defaults, heartbeat, pause, expansion,
rollback, resume/unhalt, runtime/mobile changes, P3E5-4C through P3G, provider
deployment, or readiness claims.

## Owner

Coordinator. Implementation is limited to P3E5-4B and stops at maintainer
review. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK64_P3E5_4B_APPLICABILITY_TRANSITION.md`;
- completed Task 63/P3E5-4A policy, principal, and logical-work-v2 foundation;
- immutable P3E evidence, P3E5 fencing, File/PostgreSQL stores, and audit seams;
- frozen P3E-4/P3A behavior, which this task must not invoke.

## Assumptions

- Existing trusted repositories expose enough current records to validate the
  bounded applicability decision without introducing a rollout writer.
- Explicitly approved/enabled values and freshness durations exist only in
  fixtures labelled `TEST VECTOR ONLY — NOT PRODUCTION POLICY`.
- Authoritative time is injected or obtained from the persistence transaction;
  time-authority failure rejects the transition.
- Existing worktree content is maintainer-owned baseline and must be preserved.
- MinIO remains out of scope because object-store behavior is unchanged.

## Work Items

- [x] Map existing schedule, evidence, policy, lease, credential, audit,
  rollout-read, and persistence seams; confirm prohibited boundaries.
- [x] Add failing public-seam tests for exact applicability gates, both
  authorities, canonical intent identity, and safe rejection.
- [x] Add failing File/PostgreSQL tests for fencing, replay, restart, crash
  boundaries, stale races, and two-instance convergence.
- [x] Implement the smallest validator and atomic intent-store transition.
- [x] Review the cohesive diff for frozen invariants, authorization,
  currentness, transactionality, resource bounds, and prohibited behavior.
- [x] Update only the approved factual review/design/ADR/threat/context files.
- [x] Run the consolidated validation matrix, record evidence, and stop before
  P3E5-4C.

## Validation

Completed after the cohesive implementation and self-review:

- control-plane and root analysis passed with no issues;
- focused applicability tests passed 12 tests against the live PostgreSQL 17
  fixture;
- the full control-plane suite passed 165 tests; only the unchanged MinIO test
  skipped because `HYFENS_TEST_S3_*` was unavailable;
- root tests passed 1 test;
- File/PostgreSQL restart, crash/lost-response, stale revalidation, audit,
  fencing, and two-instance CAS evidence passed;
- no migration was required; schema remains v7;
- Markdown lint, whitespace, secret, and prohibited-boundary scans passed.

## Next Action

Maintainer review of the recommendation. Do not create or begin P3E5-4C
without explicit authorization.

## Blockers

None for the bounded Task 64 scope. Cross-store currentness is deliberately
revalidated again by future P3E-4/P3A because these repositories are not one
global transaction. Any need for a runtime trust change, direct rollout write,
production default/enablement, or prohibited later-phase behavior remains an
immediate stop trigger.

## Outcome

P3E5-4B is implemented and validated. Current v2 scheduled, sealed,
patch-safety halt evidence can enter one atomically persisted
`HALT_APPLYING` intent under both authorities. Equivalent retries converge;
stale, malformed, expired, revoked, cross-scope, and unsuitable inputs fail
closed. No automatic halt was applied and no rollout changed.

Recommendation:
`AUTHORIZE P3E5-4C P3E-4 APPLICATION WITH CONDITIONS`.
P3E5-4C and later slices remain unauthorized pending maintainer review.

## References

- `docs/P3E5_4B_APPLICABILITY_TRANSITION_REVIEW.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Maintainer approved P3E5-4A and authorized only the bounded
  P3E5-4B applicability/intent transition. Task 64 reserved before
  implementation; P3E5-4C and later work remain unauthorized.
- 2026-08-24: Completed test-first applicability, canonical intent,
  File/PostgreSQL fencing/restart/race evidence, factual documentation, full
  validation, and the P3E5-4B review gate. Stopped before P3E5-4C.
