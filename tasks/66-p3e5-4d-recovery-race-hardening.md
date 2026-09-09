# Task 66 — P3E5-4D recovery and race hardening

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Harden the P3E5-4 automatic-halt path after lease expiry, lost responses,
process restart, and competing recovery callers without adding a rollout
mutation route or weakening P3E4/P3A authority.

## Scope and Non-goals

Scope: auto-halt-specific recovery/reclaim, evidence-first idempotency,
lease/work-version fencing, File and PostgreSQL race/restart evidence,
malformed-linkage fail-closed behavior, bounded recovery limits, tenant and
principal isolation, regression tests, and factual Task 66 documentation.

Non-goals: P3E5-4E, generic scheduler redesign, heartbeat, rollout action or
policy behavior changes, expansion/pause/retire/rollback/resume/unhalt
implementation, runtime/mobile changes, production defaults or enablement,
provider HA claims, dashboard/telemetry, or any direct rollout write outside
the existing P3E4/P3A path.

## Owner

Coordinator. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK66_P3E5_4D_RECOVERY_RACE_HARDENING.md`;
- completed Task 65/P3E5-4C application path;
- existing P3E5 schedule/work leases and File/PostgreSQL persistence;
- existing P3E-4 evidence/application and P3A expected-revision CAS;
- Auto-Halt Principal authorization and exact release/rollout binding.

## Assumptions

- P3E-4 remains the only rollout mutation authority and P3A remains the only
  rollout state transition authority.
- Recovery is evidence-first: an exact immutable application and P3A linkage
  are verified before any retry with the same deterministic idempotency key.
- A recovered work item never inherits a successor rollout revision and never
  guesses or repairs malformed linkage.
- File mode is single-process/single-writer/single-host-clock; PostgreSQL
  tests demonstrate transactional fixture convergence, not provider HA.
- Recovery limits are explicit test inputs, not production defaults or
  enablement.

## Work Items

- [x] Reserve the public recovery/reclaim seams and ensure generic scheduled
  evaluation cannot mutate `HALT_APPLYING` work.
- [x] Add red tests for lease expiry, evidence-first recovery, old-token
  rejection, lost responses, restart, competing PostgreSQL claimants, and
  malformed/stale/foreign linkage.
- [x] Implement bounded auto-halt reclaim/recovery that reuses the Task 65
  application service and exact P3E-4/P3A path.
- [x] Add File/PostgreSQL recovery limits, failure seams, tenant isolation,
  principal/policy/rollout race handling, and audit-divergence fail-closed
  boundary behavior; record unexecuted provider/audit outage evidence as
  review conditions.
- [x] Review the cohesive diff for direct-rollout-write/P3A-bypass risk,
  idempotency/downgrade risk, token leakage, and unbounded retry/resource use.
- [x] Update only factual Task 66 addenda in the approved design, threat-model,
  ADR, schedule-design, and context documents.
- [x] Run the consolidated validation matrix and stop at the Task 66
  maintainer-review gate before P3E5-4E.

## Validation

Completed after the cohesive implementation and self-review:

- scoped format and `dart analyze --fatal-infos`: PASS;
- focused File and PostgreSQL recovery/race tests: PASS, 34 tests;
- full control-plane regression suite: PASS, 187 tests and 1 unchanged MinIO
  skip because `HYFENS_TEST_S3_*` was not configured;
- root `dart analyze --fatal-infos` and `dart test`: PASS;
- Markdownlint, trailing-whitespace, changed-scope secret, and
  prohibited-boundary scans: PASS;
- provider-disconnect, audit-outage, heartbeat/lease-sufficiency,
  resource-envelope, and production evidence are explicitly reported in the
  review.

## Next Action

Request maintainer review using
`docs/P3E5_4D_RECOVERY_RACE_HARDENING_REVIEW.md`. Do not begin P3E5-4E.

## Blockers

The bounded engineering slice has no implementation blocker. Provider
disconnect/reconnect, injected audit divergence, heartbeat/lease sufficiency,
resource-storm capacity, provider HA, and production/beta/store/legal evidence
remain conditions before any production claim. Any need for direct rollout
writes, P3A bypass, generic scheduler mutation of auto-halt work, runtime
changes, production enablement, or unapproved P3E5-4E behavior is a stop
trigger.

## Outcome

Implemented and validated for the bounded Task 66 scope. Recovery is
evidence-first, auto-halt-specific, fenced, bounded, and reuses P3E-4/P3A.
The review recommendation is
`AUTHORIZE P3E5-4E INTEGRATION EVIDENCE WITH CONDITIONS`; this does not
authorize 4E implementation or production readiness.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK66_P3E5_4D_RECOVERY_RACE_HARDENING.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_4C_P3E4_APPLICATION_REVIEW.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Task 66 reserved after maintainer authorization of the bounded
  P3E5-4D recovery/race-hardening slice. P3E5-4E and later work remain
  unauthorized.
- 2026-08-24: Implemented evidence-first recovery, auto-halt-only reclaim,
  terminal stale fencing, generic-claim exclusion, File/PostgreSQL race and
  restart coverage, and bounded outcome handling. Final scoped and full-suite
  validation passed; stopped at the Task 66 maintainer-review gate.
