# Task 63 — P3E5-4A automatic-halt policy and principal

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Implement the approved P3E5-4A policy, identity, authorization, enablement, and
historical-work foundation so that only newly created, explicitly bound
scheduled work can ever become an automatic-halt candidate.

## Scope and Non-goals

Scope: strict immutable `AutomaticHaltPolicy`, canonical digest and validation,
separate approval and environment enablement state, a dedicated exact-scope
Auto-Halt Principal, two-authority representation, logical work meaning v2,
historical v1 ineligibility, scheduled/SEALED/PATCH_SAFETY bindings, File and
PostgreSQL persistence, audit/redaction, tests, and factual documentation.

Non-goals: `EVALUATED -> HALT_APPLYING`, automatic candidate scanning, P3E-4
or P3A invocation, rollout mutation, halt recovery/reconciliation, heartbeat,
expansion, HOLD-to-pause, rollback, resume/unhalt, production policy values,
runtime/mobile changes, P3E5-5, P3F, P3G, or readiness claims.

## Owner

Coordinator. Implementation is limited to P3E5-4A and stops at maintainer
review. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK63_P3E5_4_IMPLEMENTATION_WITH_CONDITIONS.md`;
- accepted Task 62 design and ADR 0012;
- P3E5-1 schedule/work identity and authorization;
- P3E5-2 fencing and P3E5-3 explicit executor;
- existing File/PostgreSQL persistence and migration locking.

## Assumptions

- Existing public service/repository seams can carry this foundation without a
  new rollout mutation path.
- Test freshness/resource durations are explicit test vectors and are never
  production defaults.
- Existing worktree content is maintainer-owned baseline and must be preserved.
- MinIO remains out of scope because object-store behavior is unchanged.

## Work Items

- [x] Map current domain, authorization, persistence, migration, audit, and test
  seams and confirm prohibited boundaries.
- [x] Add failing public-seam tests for policy identity, validation, digest,
  default-off state, and historical-v1 behavior.
- [x] Implement the strict policy and enablement domain foundation.
- [x] Add failing public-seam tests for the dedicated Auto-Halt Principal,
  exact scopes, expiry/revocation, tenant isolation, and authority separation.
- [x] Implement principal issuance/authorization and bounded audit evidence.
- [x] Add failing persistence tests for logical-key v2, File restart,
  PostgreSQL restart/races/migration, conflicts, and malformed records.
- [x] Implement the smallest File/PostgreSQL persistence and migration changes.
- [x] Review the cohesive diff for frozen invariants, security, compatibility,
  resource bounds, and absence of P3E-4/P3A application behavior.
- [x] Update the required factual review/design/ADR/threat/glossary documents.
- [x] Run the required validation matrix, record evidence, and stop before
  P3E5-4B.

## Validation

Completed after implementation and self-review:

- changed Dart scope formatted; package and root `dart analyze --fatal-infos`
  passed with no issues;
- full control-plane suite passed 153 tests against PostgreSQL 17; only the
  unchanged MinIO test skipped because `HYFENS_TEST_S3_*` was unavailable;
- root test passed 1 test;
- migration 007 upgraded the live v6 schema to v7, and an isolated empty
  database passed concurrent initialization plus the two-instance immutable
  race (15 tests) before that temporary database was removed;
- focused policy, principal, v1/v2, File restart/malformed, PostgreSQL,
  tenancy, expiry/revocation, audit, schedule, claim, and executor coverage
  passed within those suites;
- Markdown lint, local-reference, whitespace, secret, prohibited-call, and
  runtime/mobile unchanged scans passed.

## Next Action

Maintainer review of the recommendation. Do not create or begin P3E5-4B
without explicit authorization.

## Blockers

None. Any need for a runtime trust change, rollout write, P3E-4/P3A call,
`HALT_APPLYING`, production default, or prohibited later-phase behavior is an
immediate stop trigger.

## Outcome

P3E5-4A is implemented and validated. The repository now has a strict
automatic-halt policy and digest, immutable default-off approval/production
state, exact-scope Auto-Halt Principal, two-authority representation, v2 work
meaning, permanent v1 ineligibility, policy-current schedule binding, and
File/PostgreSQL schema-v7 persistence. No automatic halt is applied.

Recommendation:
`AUTHORIZE P3E5-4B APPLICABILITY TRANSITION WITH CONDITIONS`.
P3E5-4B and every later slice remain unauthorized pending maintainer review.

## References

- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Maintainer approved Task 62 and authorized P3E5-4A only. Task 63
  reserved before implementation; P3E5-4B through P3G remain unauthorized.
- 2026-08-24: Completed test-first policy/principal/work-v2/File/PostgreSQL
  implementation, review documentation, full validation, and the P3E5-4A
  review gate. Stopped before P3E5-4B as required.
