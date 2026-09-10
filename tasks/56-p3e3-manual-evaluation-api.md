# Task 56 — P3E-3 manual evaluation API

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — bounded manual evaluation implementation; maintainer review required

## Goal

Allow an authorized operator to evaluate one exact immutable P3E-2 aggregate
revision under one explicit, versioned, caller-supplied test policy; persist
deterministic immutable `HealthEvaluation` and `RolloutDecision` evidence; and
expose only the narrow manual evaluation API without mutating rollout state or
runtime trust.

## Scope and Non-goals

Scope: explicit policy/value validation; deterministic evaluation precedence;
aggregate/revision/digest/version/scope revalidation; evaluation-input digest;
File and PostgreSQL evidence reuse; immutable evaluation and decision evidence;
tenant-scoped authorization; idempotent manual POST and read/list routes;
stable bounded errors; audit references; malformed, stale, privacy, quality,
concurrency, and cross-tenant tests; factual P3E/threat-model documentation
addenda.

Non-goals: P3E-4 halt/hold rollout mutation, P3E-5 scheduler/worker, automatic
halt or expansion, dashboard/charts/alerts, broad operator tooling, production
threshold defaults, raw observations or installation identity, runtime/mobile,
Patch Format/capability/high-water/signing changes, hosted key custody,
provider deployment, React Native, billing, enterprise features, store/legal
claims, or closing existing readiness gates.

## Owner

Coordinator. No commit is authorized. Stop at the P3E-3 maintainer-review gate.

## Dependencies

- supplied `/Volumes/970EvoPlus/Downloads/CODEX_TASK56_P3E3_MANUAL_EVALUATION_API.md`;
- `docs/P3E2_IMMUTABLE_PERSISTENCE_REVIEW.md`;
- `tasks/55-p3e2-immutable-persistence.md`;
- `packages/control_plane/lib/src/aggregation.dart`;
- `packages/control_plane/lib/src/p3e_persistence.dart`;
- existing control-plane authorization, audit, HTTP, and rollout read seams.

## Assumptions

- Task 56 authorization is limited to explicit/manual evaluation over already
  persisted immutable P3E-2 aggregate revisions.
- Caller policy values are test vectors or deployment-owned inputs and are
  never selected as production defaults by the implementation.
- Evaluation and decision records remain advisory evidence; `HALT_NEW_OFFERS`
  cannot invoke a rollout transition in this task.
- File persistence is single-node only; PostgreSQL is the multi-instance test
  adapter when the configured environment is available.
- Existing P3E-2 entity/version/digest/tenant bindings remain frozen.

## Work Items

- [x] Preserve P3E-1/P3E-2 semantics and frozen runtime/rollout trust
  invariants.
- [x] Add explicit versioned manual-evaluation policy and deterministic pure
  evaluator with conservative decision precedence.
- [x] Bind evaluation inputs to one persisted aggregate revision, exact scope,
  window, policy versions, quality/privacy state, and deterministic digest.
- [x] Persist immutable `HealthEvaluation` and `RolloutDecision` evidence with
  same-body acknowledgement and changed-body conflict behavior.
- [x] Add narrow authorized POST/GET/list evaluation routes with bounded
  pagination, stable errors, idempotency, and no rollout mutation.
- [x] Integrate redacted audit references for requested/created/replayed,
  cross-tenant, stale/corrupt, and mutation-attempt outcomes.
- [x] Add unit, File, PostgreSQL (when configured), API authorization,
  cross-tenant, stale, malformed, privacy/quality, idempotency, and concurrency
  tests.
- [x] Update P3E design and threat model with factual P3E-3 addenda.
- [x] Run consolidated validation, complete the review, and stop before P3E-4.

## Validation

Completed validation:

- `dart format` over the changed control-plane source and tests — passed;
- `cd packages/control_plane && dart analyze --fatal-infos .` — passed;
- focused evaluator/API tests without PostgreSQL — 11 passed, one
  environment-gated PostgreSQL test skipped;
- focused evaluator/API tests with
  `HYFENS_TEST_POSTGRES_URL='postgresql://hyfens:hyfens-p2-db@127.0.0.1:55433/hyfens?sslmode=disable'`
  — 12 passed, including two-service concurrency;
- the same configured PostgreSQL URL with the full control-plane suite — 91
  passed, one MinIO integration skipped because `HYFENS_TEST_S3_*` was not
  configured;
- `cd packages/control_plane && dart test test/migration_test.dart` — 1 test
  passed;
- `dart analyze .` at repository root — passed;
- `dart test` at repository root — 1 test passed;
- Markdown lint for the Task 56-owned documents and factual addenda — passed;
- local Markdown-link, trailing-whitespace, secret/private-material, and
  prohibited-implementation boundary scans — passed.

No physical Android/iOS rerun is authorized: P3E-3 must not modify runtime or
mobile code.

## Next Action

Maintainer review of `docs/P3E3_MANUAL_EVALUATION_REVIEW.md` and its
recommendation `AUTHORIZE P3E-4 WITH CONDITIONS`. Do not begin P3E-4
automatically.

## Blockers

None known. Existing P1D, provider, beta, production, store, and legal gates
remain open and are not relabeled by this task.

## Outcome

P3E-3 is complete for its authorized bounded scope: an explicit versioned pure
evaluator, immutable aggregate-only evidence binding, File/PostgreSQL-backed
evaluation and decision evidence, tenant-scoped manual POST/GET/list routes,
audit integration, deterministic idempotency, fail-closed stale/corrupt/
privacy/quality behavior, and environment-gated two-instance concurrency
evidence. No rollout mutation, automatic halt, scheduler, dashboard,
production threshold, provider deployment, mobile/runtime change, or readiness
claim was added. Stop at maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK56_P3E3_MANUAL_EVALUATION_API.md`;
- `/Volumes/970EvoPlus/Downloads/P3E2_IMMUTABLE_PERSISTENCE_REVIEW.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `docs/P3_ROLLOUT_OBSERVABILITY_DESIGN.md`.

## History

- 2026-08-24: Reserved Task 56 after explicit maintainer authorization of
  P3E-3 manual evaluation only. P3E-4/P3E-5/P3F/P3G remain unauthorized.
- 2026-08-24: Implemented and reviewed the bounded evaluator/API; added focused
  File/API and PostgreSQL concurrency evidence plus factual design/threat/review
  documentation. Consolidated validation passed; P3E-4 remains a separate
  maintainer decision.
