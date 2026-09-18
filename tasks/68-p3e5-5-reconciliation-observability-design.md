# Task 68 — P3E5-5 reconciliation and observability design

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Design a bounded reconciliation and service-observability layer around the
existing immutable P3E evidence, P3E5 schedule/work projections, P3E-4/P3A
automatic-halt path, audit chain, and File/PostgreSQL storage boundaries.

## Scope and Non-goals

Scope: design-only ownership, divergence taxonomy, typed repair contracts,
authority, currentness, concurrency, resource bounds, metrics, readiness,
diagnostics, retention, failure behavior, threat model, implementation
sequencing, and evidence vectors.

Non-goals: Dart source, tests, SQL, migrations, runtime/mobile changes,
deployment infrastructure, scheduler loops, queues, dashboards, alert
providers, P3F, P3G, rollout actions, production defaults, provider HA, beta,
store, legal, or production-readiness claims.

## Owner

Coordinator. No implementation or commit is authorized by this task.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK68_P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- Task 67/P3E5-4E bounded closure;
- existing P3E immutable persistence/reconciliation report;
- existing P3E5 schedule/work, claim, recovery, audit, and P3A CAS contracts.

## Assumptions

- P3E-4 remains the sole health-halt application route.
- P3A remains the sole rollout-mutation authority.
- Reconciliation can repair only operational/projection state whose exact
  immutable source is present and current.
- File remains single-process/single-writer; PostgreSQL remains the
  multi-instance coordination boundary.
- Provider HA, production latency/capacity, beta, store, and legal gates stay
  open.

## Work Items

- [x] Inspect existing reconciliation, schedule/work, audit, auth, and
  readiness contracts.
- [x] Compare explicit-admin, startup, periodic-worker, and hybrid ownership.
- [x] Define immutable-source boundaries, repairability classes, taxonomy,
  severities, and typed repair actions.
- [x] Define currentness, idempotency, tenant, File, PostgreSQL, fairness, and
  resource-boundary contracts.
- [x] Define metrics, cardinality/privacy, readiness, diagnostics, alerts,
  retention, and failure semantics without implementing them.
- [x] Define required simulation vectors, threat model, OSS/commercial
  boundary, implementation sequence, and entry criteria.
- [x] Update only factual design references and add ADR 0013 for the bounded
  ownership/non-authority decision.
- [x] Run design-only validation and stop at the P3E5-5 maintainer-review
  gate.

## Validation

- Markdownlint over Task 68 documents and approved factual addenda — PASS.
- Local Markdown-link and required-section checks — PASS.
- Trailing-whitespace and high-confidence secret scans — PASS.
- Taxonomy/vector completeness and frozen-invariant scans — PASS.
- Design-only boundary scan confirms no Dart source, tests, SQL, runtime,
  mobile, or deployment files were changed by Task 68.

## Next Action

Request maintainer review of
`docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md` and ADR 0013. Do not
begin P3E5-5 implementation until a separate maintainer decision authorizes it.

## Blockers

No design blocker remains. P3E5-5 implementation is intentionally not
authorized by the supplied maintainer instruction. Existing provider,
production, beta, store, legal, and readiness gates remain open.

## Outcome

Task 68 design is complete. The recommended design is a hybrid of bounded
startup reconciliation and explicit tenant-scoped administrator invocation,
with no periodic worker or managed queue. Reconciliation may repair only
deterministic operational/projection state; immutable divergence is reported
and never rewritten. The design stops at maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/67-p3e5-4e-integration-evidence.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_4E_INTEGRATION_EVIDENCE_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK68_P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- `docs/adr/0013-bounded-reconciliation-and-observability.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Task 68 authorized for design only. P3E5-5 implementation,
  P3F, and P3G remain unauthorized.
- 2026-08-24: Completed bounded reconciliation/observability design, factual
  references, ADR 0013, and design-only validation. Stopped at maintainer
  review as instructed.
