# Task 69 — P3E5-5A reconciliation domain and taxonomy

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Implement the bounded, deterministic P3E5-5A reconciliation domain foundation:
typed invocations, findings, repair attempts, taxonomy metadata, policy bounds,
cursor/fairness state, a narrow exact-scope reconciliation principal, canonical
serialization, idempotency identities, precondition digests, tenant isolation,
malformed-input rejection, resource safety, and audit-safe metadata.

## Scope and Non-goals

Scope: pure control-plane domain types and validation with focused unit tests,
public export, and factual implementation addenda.

Non-goals: startup or manual scanning, projection repair execution, persistence
or migrations, metrics/readiness/diagnostics, dashboards, operator tooling,
runtime/mobile/compiler changes, patch/capability changes, rollout mutation,
P3E-4 changes, P3E5-5B/5C/5D/5E, P3F, and P3G.

## Owner

Coordinator. No commit is authorized.

## Dependencies

- Maintainer authorization in
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK69_P3E5_5A_RECONCILIATION_DOMAIN_TAXONOMY.md`;
- accepted Task 68 design and ADR 0013;
- existing canonical encoding, credential, audit, schedule/work, and P3E-4
  authority contracts.

## Assumptions

- P3E-4 remains the sole health-halt application path and P3A remains the sole
  rollout-mutation authority.
- Immutable P3E/P3A/audit/schedule evidence is report-only when divergent.
- P3E5-5A introduces no production numeric policy defaults; test bounds are
  explicitly marked `TEST VECTOR ONLY — NOT PRODUCTION POLICY`.
- The reconciliation principal is exact-scope, expiring/revocable, and has no
  signing, artifact, credential, rollout mutation, or runtime authority.

## Work Items

- [x] Reserve the Task 69 scope and preserve frozen invariants.
- [x] Implement immutable typed invocation, finding, repair-attempt, policy,
  cursor/fairness, and principal records.
- [x] Implement stable taxonomy, severity, repairability, action, lifecycle,
  and repair-result vocabularies with metadata and validation.
- [x] Implement deterministic canonical identities, precondition digests,
  tenant/application/environment scope checks, and audit-safe redaction.
- [x] Add focused tests for valid and malformed values, canonical ordering,
  idempotency/conflicts, bounds, authority, isolation, and resource limits.
- [x] Add factual P3E5-5A review/design/threat/context documentation without
  rewriting Task 68 history.
- [x] Run scoped and required validation, review the task-owned diff, and stop
  at the P3E5-5A maintainer-review gate.

## Validation

Completed: `dart format` on changed Dart files; `dart analyze --fatal-infos`
and focused tests for `packages/control_plane`; full control-plane and root
tests because the public package contract is extended; Markdown/link,
whitespace, secret, and prohibited-scope scans. MinIO, S3, and PostgreSQL
remain explicit skips when their existing environments are unavailable.

Evidence: focused domain suite 11/11 PASS; full control-plane suite 182 PASS
with 21 existing PostgreSQL/MinIO/S3 environment skips; root analyze PASS; root
test 1/1 PASS; Markdownlint, local-link, whitespace, secret, and domain-scope
scans PASS.

## Next Action

Request maintainer review using
`docs/P3E5_5A_RECONCILIATION_DOMAIN_REVIEW.md`. Do not begin P3E5-5B
automatically.

## Blockers

None currently. Existing provider, production, beta, store, legal, privacy,
and readiness gates remain open and are not addressed by this task.

## Outcome

P3E5-5A is complete for its domain-only scope. The recommended next decision
is `AUTHORIZE P3E5-5B FILE/POSTGRESQL BOUNDED RECONCILIATION WITH CONDITIONS`.
P3E5-5B remains unstarted and requires a separate maintainer gate.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK69_P3E5_5A_RECONCILIATION_DOMAIN_TAXONOMY.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- `/Volumes/970EvoPlus/Downloads/0013-bounded-reconciliation-and-observability.md`;
- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- `docs/adr/0013-bounded-reconciliation-and-observability.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.
- `docs/P3E5_5A_RECONCILIATION_DOMAIN_REVIEW.md`.

## History

- 2026-08-24: Reserved after maintainer authorization of P3E5-5A only. P3E5-5B
  and later slices remain unauthorized.
- 2026-08-24: Implemented and tested the pure P3E5-5A domain/taxonomy module,
  added factual review/security/design/context addenda, and stopped before
  persistence or reconciliation execution.
