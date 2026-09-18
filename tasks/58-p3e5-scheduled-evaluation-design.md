# Task 58 — P3E-5 scheduled-evaluation design

<!-- markdownlint-disable MD013 -->

Status: [x] Completed — design only; maintainer review required

## Goal

Define a bounded, duplicate-safe, stale-safe, failure-tolerant orchestration
model for scheduling exact P3E-3 evaluations and, only when separately enabled,
routing a current `HALT_NEW_OFFERS` decision through P3E-4 and the existing P3A
compare-and-set boundary. Stop before any scheduler implementation.

## Scope and Non-goals

Scope: scheduler-ownership comparison and recommendation; domain terminology;
immutable schedule/work identity; work states and transitions; server-time
window readiness; claim/lease/retry/fairness/resource-bound semantics;
authorization and service-principal design; cancellation, restart, and
reconciliation behavior; audit/metrics concepts; File/PostgreSQL deployment
boundaries; threat analysis; future simulation vectors and staged entry
criteria; factual design addenda and a proposed ADR.

Non-goals: scheduler, worker, timer, cron, queue, work table, migration, API,
automatic evaluator, automatic halt loop, automatic expansion, HOLD-to-pause,
runtime rollback, rollout-state mutation, dashboard, alerts integration,
provider deployment, production cadence/SLO defaults, P3F/P3G, mobile/runtime
changes, beta/production/store/legal claims, or physical-device validation.

## Owner

Coordinator. No commit is authorized. Stop at the P3E-5 design
maintainer-review gate.

## Dependencies

- supplied
  `/Volumes/970EvoPlus/Downloads/CODEX_TASK58_P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- supplied `/Volumes/970EvoPlus/Downloads/P3E4_CONSERVATIVE_HALT_REVIEW.md`;
- `tasks/53-p3e-aggregation-and-conservative-halt-design.md`;
- `tasks/56-p3e3-manual-evaluation-api.md`;
- `tasks/57-p3e4-conservative-halt-integration.md`;
- existing P3A rollout CAS, P3E server-time windows, P3E-3 idempotent manual
  evaluation, and P3E-4 idempotent halt application boundaries.

## Assumptions

- At-least-once work execution plus existing downstream idempotency is the
  safety model; exactly-once execution is not required.
- PostgreSQL is the multi-instance scheduling authority candidate; File mode
  remains explicitly single-process and single-writer.
- The scheduler clock is authoritative server/database time. Client event
  timestamps never make work ready.
- Schedule configuration and logical work bindings are immutable revisions;
  operational claim status may be a CAS-protected projection.
- Existing control credentials are organization-scoped and do not yet support
  the required application/environment-scoped scheduler principal or the new
  `health:schedule` scope. This is an implementation prerequisite, not a fact
  to conceal in design.

## Work Items

- [x] Confirm the maintainer authorization, frozen invariants, current code
  vocabulary, and design-only boundary.
- [x] Compare ownership models and recommend one initial scheduling boundary.
- [x] Define schedule, schedule-revision, work, attempt, logical-key, and
  deterministic downstream idempotency semantics.
- [x] Define the work state machine, claim/lease lifecycle, retries,
  cancellation, staleness, terminal behavior, and reconciliation.
- [x] Define initial triggers, window readiness/late-data rules, automatic-halt
  enablement, authorization, fairness, resource bounds, audit, and metrics.
- [x] Define File/PostgreSQL deployment behavior, failure recovery, threat
  mitigations, simulation vectors, implementation sequence, and entry gates.
- [x] Create the P3E-5 design, proposed ADR, domain glossary, and factual
  P3E/threat-model addenda without implementation code.
- [x] Run the design-only validation matrix and stop for maintainer review.

## Validation

Completed validation scope:

- `markdownlint` passed for the seven Task 58-owned or updated Markdown files;
- repository-local Markdown link and referenced-path checks passed;
- required recommendation cardinality, ten work states, and 26 future
  simulation vectors were verified;
- trailing-whitespace and credential/secret-material scans passed;
- the terminology, transition, frozen-invariant, authorization, and deployment
  boundaries were reviewed as a combined design; and
- the implementation-boundary scan found no newer files under source, CLI,
  deployment, script, experiment, fixture, benchmark, or test roots.

No Dart compilation, control-plane tests, or physical Android/iOS rerun was
performed because Task 58 changed no source, schema, API, runtime, or mobile
code and explicitly prohibited implementation.

## Next Action

Maintainers review `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md` and decide whether
to authorize its staged implementation recommendation. Do not begin P3E-5,
P3F, or P3G implementation without a new explicit authorization.

## Blockers

None for design. The absent application/environment-scoped scheduler principal
and `health:schedule` scope are explicit future implementation prerequisites.
Existing P1D, provider, beta, production, store, and legal gates remain open.

## Outcome

The design recommends database-backed cooperative scheduling with PostgreSQL
as the multi-instance authority and File mode restricted to one process and
one writer. It specifies immutable schedule revisions, deterministic logical
work identity, leases and fenced CAS transitions, bounded at-least-once
execution, downstream idempotency, stale-safe reconciliation, and separately
disabled-by-default scheduled evaluation and automatic halt controls. Only an
eligible sealed `HALT_NEW_OFFERS` decision may reach the unchanged P3E-4/P3A
CAS boundary. The missing scoped scheduler principal and authorization scopes
remain implementation entry prerequisites. No implementation was started.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_TASK58_P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `/Volumes/970EvoPlus/Downloads/P3E4_CONSERVATIVE_HALT_REVIEW.md`;
- `docs/P3E_AGGREGATION_HALT_DESIGN.md`;
- `docs/P3E4_CONSERVATIVE_HALT_REVIEW.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/security/productization-threat-model.md`;
- `docs/adr/0011-database-backed-cooperative-scheduling.md`;
- `CONTEXT.md`.

## History

- 2026-08-24: Reserved Task 58 after explicit maintainer approval of P3E-4
  and authorization of P3E-5 scheduled-evaluation design only. P3E-5
  implementation and P3F/P3G remain unauthorized.
- 2026-08-24: Completed the scheduled-evaluation domain, state-machine,
  ownership, failure, authorization, deployment, security, and implementation
  entry-gate design. Added the proposed ADR and glossary plus factual P3E and
  threat-model addenda.
- 2026-08-24: Passed the scoped design-document validation matrix, recorded 26
  future simulation vectors, confirmed that no implementation files changed,
  and stopped at the required maintainer-review gate.
