# Task 57 — P3E-4 conservative halt integration

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — bounded HALT_NEW_OFFERS application; maintainer review required

## Goal

Apply one previously persisted immutable P3E-3 `HALT_NEW_OFFERS` decision
through the existing P3A expected-revision compare-and-set transition boundary,
creating only a future-offer eligibility halt and immutable application
evidence. Stop before P3E-5.

## Scope and Non-goals

Scope: exact persisted evaluation/decision/aggregate/revision validation;
authenticated narrow halt-application service and route; existing P3A halt
transition reuse; immutable application-outcome evidence; stale, corruption,
tenant, authorization, idempotency, race, PostgreSQL, audit, and post-halt
lookup tests; factual P3E design/threat/review addenda.

Non-goals: HOLD-to-pause, automatic evaluation, scheduler/worker, automatic
expansion, runtime rollback, signed rollback invocation, high-water changes,
artifact/signature changes, mobile/runtime/compiler changes, dashboard,
operator console, production thresholds, provider deployment, beta,
production, store/legal claims, React Native, billing, or enterprise features.

## Owner

Coordinator. No commit is authorized. Stop at the P3E-4 maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK57_P3E4_CONSERVATIVE_HALT_INTEGRATION.md`;
- supplied P3E design and P3E-3 review;
- `tasks/56-p3e3-manual-evaluation-api.md`;
- existing P3E-3 evaluator/persistence and P3A rollout transition/CAS paths.

## Assumptions

- P3E-3 evidence is immutable, tenant-scoped, and runtime-advisory only.
- Only `HALT_NEW_OFFERS` may reach the P3A halt transition; `HOLD` never maps
  to pause in this task.
- The P3A transition service remains the only rollout-state writer.
- The File adapter remains single-node; PostgreSQL provides multi-instance CAS
  evidence when configured.
- Decision-to-transition linkage is append-only and recoverable after a
  cross-store failure; the original `RolloutDecision` body is never mutated.

## Work Items

- [x] Preserve P3E-1/P3E-2/P3E-3, runtime, signing, high-water, and artifact
  trust invariants.
- [x] Add typed immutable halt-application outcome evidence with strict
  decision/evaluation/revision bindings and File/PostgreSQL persistence.
- [x] Add explicit authenticated `HALT_NEW_OFFERS` application flow using the
  existing P3A CAS transition service and no HOLD/expansion behavior.
- [x] Add narrow POST halt-application route with stable bounded responses and
  scopes `health:evaluate`, `rollout:read`, and `rollout:halt`.
- [x] Add audit events for requested, applied, replay, stale, conflict,
  cross-tenant, evidence-rejected, and already-applied outcomes.
- [x] Add valid/non-halt/stale/corrupt/tenant/authorization/idempotency,
  lookup-eligibility, manual-halt race, expansion race, health-halt race, and
  PostgreSQL two-instance tests.
- [x] Update P3E design, threat model, and P3E-4 review with factual evidence.
- [x] Run consolidated validation and stop before P3E-5.

## Validation

Planned validation scope:

- `dart format` changed control-plane source/tests;
- `dart analyze --fatal-infos .` in `packages/control_plane`;
- focused halt-application, persistence, authorization, race, idempotency,
  stale, malformed, and lookup-eligibility tests;
- PostgreSQL migration/restart/two-instance CAS tests when configured;
- full control-plane suite, root tests, Markdown/path/whitespace/secret, and
  forbidden-boundary scans.

No physical Android/iOS rerun is authorized: P3E-4 must not modify runtime or
mobile code.

## Next Action

Maintainer review of `docs/P3E4_CONSERVATIVE_HALT_REVIEW.md`. Do not begin
P3E-5 implementation until a separate design decision authorizes it.

## Blockers

None known. Existing P1D, provider, beta, production, store, and legal gates
remain open and are not relabeled by this task.

## Outcome

Implemented the bounded P3E-4 conservative halt path. `HealthHaltApplication`
is strict, immutable, tenant-scoped, and persisted by both File and PostgreSQL
migration 004. The authenticated POST route validates exact P3E-3 evidence and
the complete rollout target, then uses the existing P3A expected-revision CAS
only for `HALT_NEW_OFFERS`. `HOLD` and all other decisions are rejected without
pause/expansion behavior. Idempotency, stale input, malformed evidence,
authorization, tenant isolation, manual/health races, PostgreSQL two-instance
convergence, eligibility suppression, restart persistence, and audit linkage
are covered by tests, including concurrent equal-key convergence. Runtime,
mobile, signing, high-water, artifact, and
rollback trust boundaries were not changed.

Validation completed:

- `dart format` on the eight changed Dart files — passed (the final run left
  the formatted test unchanged);
- `dart analyze --fatal-infos .` in `packages/control_plane` — passed;
- focused P3E-4 tests without PostgreSQL — 14 passed, 2 integration tests
  skipped because the environment variable was absent;
- focused P3E-4 tests with the configured PostgreSQL test container — 16
  passed;
- full control-plane suite with PostgreSQL — 102 passed, one MinIO test
  skipped because `HYFENS_TEST_S3_*` was not configured;
- root `dart analyze .` — passed; and
- root `dart test` — passed.

No physical-device rerun was performed or required because this task changes
only control-plane code. No P3E-5/P3F/P3G work was started.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK57_P3E4_CONSERVATIVE_HALT_INTEGRATION.md`;
- `/Volumes/970EvoPlus/Downloads/P3E_AGGREGATION_HALT_DESIGN.md`;
- `/Volumes/970EvoPlus/Downloads/P3E3_MANUAL_EVALUATION_REVIEW.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/P3E4_CONSERVATIVE_HALT_REVIEW.md`;
- `docs/P3E3_MANUAL_EVALUATION_REVIEW.md`;
- `docs/security/productization-threat-model.md`.

## History

- 2026-08-24: Reserved Task 57 after explicit authorization of P3E-4
  conservative HALT_NEW_OFFERS application through P3A CAS only. P3E-5/P3F/P3G
  remain unauthorized.
- 2026-08-24: Implemented immutable halt outcomes, File/PostgreSQL migration
  004, authenticated evidence validation, CAS application, audit/idempotency
  handling, route coverage, race/tenant/malformed-input tests, and factual
  design/threat/review addenda.
- 2026-08-24: Consolidated package and root validation passed; stopped at the
  P3E-4 maintainer-review gate as required.
- 2026-08-24: Added the separately requested expansion-versus-health-halt race
  vector after review found the earlier label covered only the manual-halt
  race; focused and full package validation remained green.
- 2026-08-24: Hardened concurrent equal-key outcome persistence so equal
  requests converge on the canonical immutable result while changed request
  bodies remain conflicts; reran focused, full package, root, and hygiene
  validation successfully.
