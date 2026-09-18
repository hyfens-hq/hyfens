# Task 67 — P3E5-4E integration evidence

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Execute and document bounded integration evidence for the completed P3E5-4
automatic-halt path under provider-like PostgreSQL faults, audit-store
failure/divergence, measured lease timing, bounded contention, process
restart, cross-store partial success, tenant isolation, and two-instance
operation without changing product semantics.

## Scope and Non-goals

Scope: evidence-only integration tests, fault-injection seams already present
or narrowly added for evidence, lease/resource measurements, deterministic
evidence artifacts and manifest, and factual design/security documentation.

Non-goals: new rollout semantics, new mutation authority, heartbeat,
production defaults or enablement, provider HA claims, runtime/mobile changes,
P3E5-5, P3F, P3G, dashboard, telemetry, or broad reconciliation services.

## Owner

Coordinator. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK67_P3E5_4E_INTEGRATION_EVIDENCE.md`;
- completed Task 66/P3E5-4D recovery/race hardening;
- existing P3E5-3 executor, P3E5-4B applicability, P3E5-4C P3E-4/P3A
  application, and P3E5-4D recovery paths;
- local PostgreSQL fixture when configured by `HYFENS_TEST_POSTGRES_URL`.

## Assumptions

- P3E-4 remains the only health-halt application path and P3A remains the
  only rollout mutation authority.
- Integration fixtures use `TEST VECTOR ONLY — NOT PRODUCTION POLICY` and do
  not change repository production defaults.
- Local/container fault injection is provider-like evidence only, not provider
  HA or production-capacity evidence.
- Existing audit append behavior is measured as part of the current contract;
  no new audit authority or distributed transaction is introduced.

## Work Items

- [x] Reserve the Task 67 evidence/review seams and preserve frozen invariants.
- [x] Execute the provider-like PostgreSQL disconnect/reconnect matrix,
  including exact pre/post claim and pre/post P3A response-fault boundaries.
- [x] Add integration evidence for audit outage/divergence outcomes.
- [x] Measure lease sufficiency and record the heartbeat decision without
  implementing heartbeat.
- [x] Execute bounded resource/race-storm, two-instance PostgreSQL,
  cross-instance handoff, File restart, and cross-store partial-success
  campaigns.
- [x] Reconfirm manual/stale races, generic scheduler exclusion, tenant
  isolation, and security/redaction boundaries.
- [x] Rehearse one bounded P3E5-3 → P3E5-4 call with separate evaluation and
  Auto-Halt principals across all five evaluator decision classes.
- [x] Create deterministic evidence artifacts and a SHA-256 manifest without
  secrets or host-specific payloads.
- [x] Update only factual design, ADR, threat-model, and context addenda.
- [x] Run the consolidated validation matrix and stop at the Task 67
  maintainer-review gate before P3E5-5.

## Validation

Completed for the bounded local File/PostgreSQL campaign. Exact boundary and
single-call rows are now independently executed and pass.

- focused automatic-halt suite with local PostgreSQL: 44/44 PASS;
- serialized full control-plane suite with local PostgreSQL: 197 PASS, one
  unchanged MinIO/S3 skip because `HYFENS_TEST_S3_*` was not configured;
- package `dart analyze . --fatal-infos`: PASS;
- root `dart analyze --fatal-infos` and `dart test`: PASS;
- Markdownlint, evidence/source-scope whitespace, secret, absolute-path,
  prohibited-debug, and evidence-manifest SHA-256 checks: PASS.

A parallel full-suite attempt exposed one environment-contended timing
assertion; the focused and serialized timing vectors passed without changing
the threshold.

## Next Action

Request maintainer review using
`docs/P3E5_4E_INTEGRATION_EVIDENCE_REVIEW.md`. The recommended next design is
P3E5-5, but it is not authorized or started by this task.

## Blockers

No blocker remains for the authorized bounded engineering evidence. Provider
HA, production capacity, beta/store/legal readiness, and any P3E5-5 work remain
separate gates and are not closed by this task.

## Outcome

Executed evidence is complete for the bounded File/local-PostgreSQL campaign.
The exact transaction-boundary rows and single-call authority rehearsal pass;
the review recommendation is `CLOSE P3E5-4 IMPLEMENTATION — PROCEED TO P3E5-5
DESIGN`, subject to a separate maintainer authorization before any P3E5-5
implementation.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK67_P3E5_4E_INTEGRATION_EVIDENCE.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK67_CONTINUATION_EXACT_BOUNDARY_CLOSURE.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_4D_RECOVERY_RACE_HARDENING_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/66-p3e5-4d-recovery-race-hardening.md`;
- `docs/P3E5_4D_RECOVERY_RACE_HARDENING_REVIEW.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Task 67 reserved after maintainer authorization of bounded
  P3E5-4E integration evidence. P3E5-5 and later work remain unauthorized.
- 2026-08-24: Added audit fault/divergence, lease timing, File contention,
  PostgreSQL close/reopen, and eight-caller recovery evidence. Focused suite
  passed 38/38 with PostgreSQL. Stopped at the Task 67 maintainer-review gate;
  exact PostgreSQL claim/P3A boundary rows remained explicitly open.
- 2026-08-24: Added bounded PostgreSQL pre/post claim and pre/post P3A
  response-fault seams, fixed committed-halt recovery after post-P3A response
  loss, and added the two-authority single-call rehearsal. Focused suite passed
  44/44; serialized full control-plane suite passed 197 with one unchanged
  MinIO/S3 skip. Task 67 exact closure rows pass; stop for maintainer review.
