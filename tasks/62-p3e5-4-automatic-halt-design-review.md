# Task 62 — P3E5-4 automatic halt design/review

<!-- markdownlint-disable MD013 -->

Status: [x] Completed

## Goal

Define the exact, versioned, auditable, least-privilege safety gate through
which immutable scheduled `HALT_NEW_OFFERS` evidence may later invoke the
existing P3E-4/P3A halt path, while keeping implementation unauthorized.

## Scope and Non-goals

Scope: eligible scheduled evidence, split principal/authorization model,
automatic-halt policy identity and freshness, work-state fencing, P3E-4/P3A
reuse, idempotency, retry/recovery, races, tenant/resource bounds, audit and
metric vocabulary, threats, simulation vectors, implementation entry criteria,
ADR, glossary, and factual design cross-references.

Non-goals: Dart/source/test/SQL changes, automatic mutation, timers, queues,
heartbeats, automatic expansion, HOLD-to-pause, runtime rollback, dashboards,
provider infrastructure, production thresholds/defaults, P3E5-5, P3F/P3G,
runtime/mobile work, or readiness/compliance claims.

## Owner

Coordinator. No commit is authorized. Stop at the P3E5-4 design maintainer
review gate.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK62_P3E5_4_AUTOMATIC_HALT_DESIGN_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/61-p3e5-3-explicit-window-ready-executor.md`;
- `/Volumes/970EvoPlus/Downloads/P3E5_3_EXPLICIT_EXECUTOR_REVIEW.md`;
- `tasks/57-p3e4-conservative-halt-integration.md`;
- `tasks/61-p3e5-3-explicit-window-ready-executor.md`;
- existing P3E-4 evidence validation and P3A expected-revision CAS.

## Assumptions

- A future implementation may add versioned automatic-halt policy bindings and
  a narrower service-principal profile without changing historical work meaning.
- Automatic halt remains delivery eligibility only; runtime trust is unchanged.
- All numeric freshness/resource values remain required deployment policy
  inputs and are intentionally unset by this design.
- Existing worktree content is maintainer-owned baseline and must be preserved.

## Work Items

- [x] Inspect Task 62 authorization and verify P3E5-3, P3E-4, P3A,
  authorization, idempotency, and state-machine facts against source.
- [x] Define eligible evidence, versioned policy/freshness, currentness, and
  scheduled-only decision provenance.
- [x] Select the principal split and exact two-authority work/mutation boundary.
- [x] Define fenced state transitions, P3E-4 reuse, retry, crash recovery,
  reconciliation, races, terminal behavior, and resource limits.
- [x] Define audit/metrics, poisoning and tenant controls, production approval,
  OSS/provider boundaries, simulation vectors, and implementation sequencing.
- [x] Record the hard-to-reverse mutation-routing decision in ADR 0012 and
  update factual design, threat-model, and glossary references.
- [x] Review required-section completeness and run documentation-only
  validation, then stop before implementation.

## Validation

Completed after the documentation batch and self-review:

- `markdownlint` passed on all eight Task 62 task/design/ADR/index/glossary/
  cross-reference/threat-model documents;
- the numbered-section check reported `41/41`, and all local link targets
  resolved;
- trailing-whitespace and private-key/token-pattern scans passed;
- invariant, recommendation, readiness-gate, and prohibited-boundary scans
  found the required fail-closed language;
- file-newer-than-task scans found no changed Dart, SQL, package, fixture,
  experiment, CLI, script, or test file.

No Dart implementation or physical-device validation is authorized or needed.

## Next Action

Maintainer review of the recommendation. Do not create an implementation task
or begin P3E5-4A without explicit authorization.

## Blockers

None. Discovery that safe application requires a direct rollout write,
runtime-trust change, automatic rollback/expansion, or implementation code is
an immediate stop trigger.

## Outcome

The design selects scheduled-only, `SEALED`, `PATCH_SAFETY` evidence; a
separate exact-scope Auto-Halt Principal combined with the current fenced work
lease; a newly versioned automatic-halt policy/work meaning; and the existing
P3E-4/P3A CAS path as the sole mutation authority. Historical logical-key v1
work is ineligible. Automatic expansion, pause, rollback, unhalt, direct
rollout writes, and runtime-trust changes remain prohibited.

Recommendation: `AUTHORIZE P3E5-4 IMPLEMENTATION WITH CONDITIONS`. This is a
design recommendation, not implementation authorization. Production policy
approval, production enablement, and all existing readiness gates remain open.

## References

- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Reserved Task 62 after maintainer approval of P3E5-3 and explicit
  authorization of P3E5-4 design/review only. Implementation remains
  unauthorized.
- 2026-08-24: Completed the 41-section design, ADR 0012, glossary and factual
  cross-references, threat review, self-review, and documentation-only
  validation. Stopped before implementation as required.
