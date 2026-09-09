# Task 65 — P3E5-4C P3E-4 application

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Apply one exact, current `HALT_APPLYING` automatic-halt work item through the
existing P3E-4 evidence/application path and P3A expected-revision CAS, then
complete the work only after the immutable halt application and resulting
`HALTED` revision are verified.

## Scope and Non-goals

Scope: independent currentness reload, v2 scheduled/SEALED/PATCH_SAFETY
eligibility, exact rollout/evidence binding, fenced lease plus Auto-Halt
Principal, deterministic `scheduled-halt:<workId>` idempotency, existing P3E-4
and P3A reuse, bounded application linkage, fenced `HALT_APPLYING ->
COMPLETED`, File/PostgreSQL recovery and race evidence, audit/redaction, tests,
and factual documentation.

Non-goals: direct rollout writes, a scheduler-specific rollout writer, 2PC,
automatic expansion/pause/rollback/resume/unhalt, production policy approval or
enablement, P3E5-4D/4E, P3E5-5/P3F/P3G, provider deployment, runtime/mobile
changes, or readiness/store-compliance claims.

## Owner

Coordinator. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK65_P3E5_4C_P3E4_APPLICATION.md`;
- completed Task 64/P3E5-4B applicability and intent transition;
- existing P3E-4 evidence validation/application and P3A expected-revision CAS;
- P3E5 schedule/work persistence, lease fencing, and Auto-Halt Principal
  authority;
- File and PostgreSQL fixtures used by the control-plane test suite.

## Assumptions

- The existing P3E-4 method remains the single rollout mutation authority;
  automatic application may supply a validated Auto-Halt Principal as its
  in-memory actor but does not receive a direct rollout writer.
- Work, schedule/policy, P3E evidence, and rollout stores are not one global
  transaction. Fresh reload, P3E-4 validation, P3A CAS, deterministic
  idempotency, and reconciliation provide the bounded safety boundary.
- Repository automatic-halt policy and enablement remain explicitly disabled
  for production; enabled values in tests are labelled test vectors only.
- File mode remains single-process/single-writer/single-host-clock. PostgreSQL
  tests demonstrate fixture-local transactional convergence, not provider HA.

## Work Items

- [x] Map and reserve the public application/completion seams without changing
  frozen Architecture B, P3A, runtime trust, or policy defaults.
- [x] Add public-seam regression tests for exact currentness gates, Auto-Halt
  Principal/lease authority, deterministic idempotency, P3E-4/P3A linkage,
  and fenced completion.
- [x] Add File/PostgreSQL regression tests for crash/lost-response recovery,
  stale/manual races, principal/policy changes, tenant isolation, and
  two-instance convergence.
- [x] Implement the smallest shared-core automatic application adapter and
  narrow schedule-store completion command.
- [x] Review the cohesive diff for direct-rollout-write/P3A-bypass risk,
  credential/lease redaction, malformed evidence handling, and resource
  bounds.
- [x] Update only factual Task 65 review/design/ADR/threat/context addenda.
- [x] Run the consolidated validation matrix and stop at the Task 65
  maintainer-review gate before P3E5-4D/4E.

## Validation

Completed after the cohesive implementation and self-review:

- scoped `dart format`: PASS;
- `dart analyze --fatal-infos` in `packages/control_plane`: PASS;
- focused automatic application suite with live PostgreSQL: PASS, 20 tests;
- full control-plane suite with live PostgreSQL: PASS, 173 tests and 1
  unchanged MinIO skip because `HYFENS_TEST_S3_*` was not configured;
- root `dart analyze --fatal-infos`: PASS; root `dart test`: PASS, 1 test;
- Markdownlint, trailing-whitespace, high-confidence secret, and
  prohibited-boundary scans: PASS;
- File crash/restart/lost-response evidence and two-instance PostgreSQL
  application convergence: PASS;
- unchanged runtime/mobile and frozen P3A/P3E-4 regression tests: PASS through
  the full control-plane suite.

## Next Action

Task 65 is complete for its bounded scope. Request maintainer review using
`docs/P3E5_4C_P3E4_APPLICATION_REVIEW.md`; do not begin P3E5-4D/4E
automatically.

## Blockers

None currently for the bounded Task 65 scope. Any need for direct rollout
writes, a P3A bypass, production enablement/defaults, runtime trust changes,
or later-phase behavior is an immediate stop trigger.

## Outcome

Implemented and validated. The exact P3E5-4C chain now reuses P3E-4/P3A,
persists one verified application, fences completion, and converges File and
PostgreSQL retries. The review recommendation is
`AUTHORIZE P3E5-4D RECOVERY/RACE HARDENING WITH CONDITIONS`. Production
approval/enablement, provider HA, beta, store readiness, and all later P3
slices remain open or unauthorized.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK65_P3E5_4C_P3E4_APPLICATION.md`;
- `docs/P3E5_4B_APPLICABILITY_TRANSITION_REVIEW.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Task 65 reserved after maintainer authorization of only the
  P3E5-4C P3E-4 application slice. P3E5-4D/4E and later work remain
  unauthorized.
- 2026-08-24: Implemented the shared P3E-4/P3A application adapter, deterministic
  scheduled-halt idempotency, verified completion proof, File/PostgreSQL
  recovery seams, and focused/whole-suite evidence. Stopped at the Task 65
  maintainer-review gate.
