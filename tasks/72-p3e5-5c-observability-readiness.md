# Task 72 — P3E5-5C observability and readiness

Status: [x] Completed

## Goal

Add bounded, non-authoritative reconciliation metrics, liveness, readiness,
and exact-scope read-only diagnostics around the closed P3E5-5B core.

## Scope and Non-goals

In scope: low-cardinality process-local reconciliation metrics, `/livez`,
bounded `/readyz` dependency checks, exact-scope diagnostic list/detail reads,
redaction, action-disposition visibility, malformed-state fail-closed
reporting, File/PostgreSQL parity, PostgreSQL outage/recovery evidence, and
factual documentation.

Out of scope: reconciliation workers, schedulers, queues, Redis, alerts,
dashboards, new rollout behavior or writers, P3A/P3E-4 mutation calls,
P3E5-5D/5E, P3F/P3G, provider deployment, runtime/mobile/compiler changes,
and production/store/legal claims.

## Owner

Repository maintainer / Codex

## Dependencies

- Task 70/P3E5-5B bounded reconciliation persistence and HTTP boundary.
- Task 71 final action-disposition and PostgreSQL disconnect evidence.
- Maintainer authorization in `CODEX_P3E5_5C_OBSERVABILITY_READINESS.md`.

## Assumptions

- P3E5-5B remains the only reconciliation execution and mutation authority.
- The existing `ControlPlaneHttpServer` is the only HTTP routing layer.
- Diagnostics authorization is supplied by an exact-scope host callback; the
  observability adapter never invents or broadens credentials.
- Readiness checks never initialize migrations or run reconciliation.

## Work Items

- [x] Reserve Task 72 and define the bounded observability boundary.
- [x] Add low-cardinality reconciliation metrics and run-result observation.
- [x] Add `/livez`, reconciliation-aware `/readyz`, and diagnostics routes to
  the existing HTTP server.
- [x] Add exact-scope authorization, bounded pagination/filtering, redaction,
  action-disposition, report-only, cursor, repair, and audit summaries.
- [x] Add File/PostgreSQL readiness, outage/recovery, malformed, parity, and
  non-mutation tests.
- [x] Update the P3E5-5 design, ADR 0013, and create the final review.
- [x] Run consolidated package/root/migration/documentation validation and
  stop at maintainer review.

## Validation

Completed validation:

- focused File/PostgreSQL/HTTP observability suite — 11 passed;
- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- full control-plane suite with local PostgreSQL — 248 passed, one explicit
  MinIO/S3 environment skip;
- root `dart analyze --fatal-infos` — PASS;
- root `dart test` — 1 passed;
- `dart test test/migration_test.dart` — 1 passed;
- Markdownlint, local links, trailing whitespace, high-confidence secret, and
  changed-scope prohibited-boundary scans — PASS.

## Next Action

Stop at the maintainer-review gate. Do not begin P3E5-5D or any prohibited
infrastructure or product work without a new explicit authorization.

## Blockers

None known at task start.

## Outcome

Task 72 is complete for its bounded engineering scope. The implementation is
non-authoritative: metrics are process-local, readiness is read/verify-only,
and diagnostics are exact-scope/read-only. The review recommendation is
`PROCEED TO P3E5-5D WITH CONDITIONS`; this is not authorization for P3E5-5D.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_P3E5_5C_OBSERVABILITY_READINESS.md`
- `docs/P3E5_5B_BOUNDED_RECONCILIATION_REVIEW.md`
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`
- `docs/adr/0013-bounded-reconciliation-and-observability.md`

## History

- 2026-08-24 — Task 72 reserved under explicit maintainer authorization for
  P3E5-5C only. Implementation started; P3E5-5D and prohibited work remain
  unauthorized.
- 2026-08-24 — Implemented bounded metrics, `/livez`, `/readyz`, exact-scope
  diagnostics, malformed fail-closed handling, File/PostgreSQL readiness and
  parity tests, and documentation. Consolidated validation passed; stopped at
  maintainer review with `PROCEED TO P3E5-5D WITH CONDITIONS`.
