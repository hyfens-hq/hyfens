# ADR 0013 — Bounded reconciliation and non-authoritative observability

Status: Proposed for P3E5-5 maintainer review

Date: 2026-08-24

## Context

Task 67 closes the declared P3E5-4 bounded File/local-PostgreSQL evidence
scope. The repository already has an immutable P3E persistence reconciler and
an artifact inventory reconciler. P3E5 schedule/work projections span separate
File/PostgreSQL, P3E evidence, control-plane rollout, and audit boundaries, so
crashes can leave operational links incomplete without making immutable source
evidence safe to rewrite.

P3E5-5 needs visibility and narrowly safe projection repair while preserving
P3E-4 as the only health-halt application path and P3A as the only rollout
mutation authority.

## Decision proposed

1. Use a hybrid ownership model: bounded reconciliation runs during startup
   and through an explicit tenant-scoped administrator invocation. Do not add a
   periodic reconciliation worker, queue, or heartbeat in the design gate.
2. Classify findings as repairable projection, recoverable operational state,
   or report-only immutable divergence.
3. Permit only typed, idempotent CAS repairs with exact immutable evidence and
   fresh currentness checks. There is no arbitrary force-state operation.
4. Use a narrow future `health:reconcile` plus `health:read` and
   `rollout:read` principal. It has no `rollout:halt`, promotion, signing,
   artifact, credential, or release authority.
5. Reuse P3E5-4 evidence-first recovery and `scheduled-halt:<workId>` when a
   HALT_APPLYING work item requires the existing automatic-halt path. The
   reconciler never writes rollout state directly.
6. Expose bounded low-cardinality metrics, `/livez`, `/readyz`, `/metrics`, and
   read-only diagnostics. Observability cannot trigger rollout actions.
7. Keep immutable source evidence, audit history, and P3A transition history
   report-only when they conflict. No distributed two-phase commit is added.

## Consequences

Startup catches crash divergence without a permanent worker. Explicit repair
requests provide operator control and bounded replay. PostgreSQL instances may
race safely through row CAS/`SKIP LOCKED`; File remains one writer. Some
findings remain unresolved until a maintainer or operator repairs the source
system, and provider durability/HA is not implied.

## Alternatives rejected

- **Explicit admin only:** smallest implementation, but a clean restart would
  not automatically surface crash divergence.
- **Startup only:** detects divergence but provides no targeted operator retry
  or bounded repair request.
- **Periodic worker:** adds a scheduler lifecycle, overlap, backpressure, and
  deployment problem before P3E5-5 correctness is proven.
- **Managed queue or Redis:** unnecessary for the File/PostgreSQL bounded
  model and expands the infrastructure boundary.
- **Direct rollout repair:** rejected because it bypasses P3A CAS and the
  existing P3E-4 authority.

## Non-decisions

This ADR authorizes no code, SQL, migration, endpoint, metric exporter,
production default, provider deployment, dashboard, alert integration, P3F,
P3G, or P3E5-5 implementation. It does not close provider, beta, store,
legal, privacy, or production-readiness gates.

## References

- `docs/P3E5_5_RECONCILIATION_OBSERVABILITY_DESIGN.md`;
- `docs/P3E5_SCHEDULED_EVALUATION_DESIGN.md`;
- `docs/P3E5_4_AUTOMATIC_HALT_DESIGN.md`;
- `docs/adr/0012-gated-automatic-halt-through-existing-p3e4-cas.md`.

## P3E5-5A factual implementation addendum (2026-08-24)

Task 69 implemented only the pure reconciliation domain and taxonomy
foundation described by this ADR: strict typed records, bounded policy/cursor
values, deterministic canonical identities, immutable-source/report-only
classification, typed future action vocabulary, exact-scope non-control
principal rules, and audit-safe metadata. No persistence, scan execution,
projection mutation, observability endpoint, rollout writer, P3E-4 call,
runtime/mobile change, or production default was added. The ADR remains
proposed for the approved P3E5-5 implementation sequence; P3E5-5B requires its
own review gate.

## P3E5-5B factual implementation addendum (2026-08-24)

Task 70 added the bounded File/PostgreSQL persistence and orchestration core.
Immutable findings and repair attempts use canonical idempotent bodies;
lifecycle and cursor projections use CAS; File remains one-process/one-writer;
PostgreSQL migration 008 is advisory-lock protected; and startup/manual runs
are explicitly bounded and exact-scope. Audit-before-repair, fresh
precondition reload, adapter postcondition verification, report-only immutable
divergence, and deterministic replay are implemented and tested.

The implementation intentionally stops at injected authoritative detectors and
existing projection-CAS adapters. It does not claim that schedule/P3E source
discovery or real work projection repair is wired yet. P3E5-5C metrics,
readiness, diagnostics, workers, queues, rollout mutation, P3E-4, runtime,
mobile, and production enablement remain out of scope.

## P3E5-5B final-closure factual addendum (2026-08-24)

Task 71 completed the bounded reconciliation evidence gate without changing
the proposed authority model. The frozen action vocabulary now has a total
typed disposition map: existing evaluation/stale/retry CAS paths are bound;
the atomic work model makes standalone decision linking unreachable; existing
halt completion covers the separate completion action; and derived-projection
rebuild remains not applicable/report-only until a future authorized owner
exists. Persisted non-executable actions fail closed.

The PostgreSQL stores have a null-by-default test-only disconnect injector. It
closes the actual pool at named pre/post-commit, audit, projection, lifecycle,
cursor, and postcondition boundaries; recovery is explicit store recreation,
with no hidden retry loop. Local PostgreSQL evidence proves one-mutation CAS
convergence, append-only replay, audit-before-repair, exact principal scope,
tenant isolation, and bounded startup outage behavior. This closes Task 70 for
its bounded scope only. P3E5-5C implementation still requires a separate
maintainer authorization, and provider, beta, production, store, and legal
readiness remain unresolved.

## P3E5-5C factual implementation addendum (2026-08-24)

Task 72 added only non-authoritative observability around the closed bounded
reconciliation core. The existing `dart:io` HTTP adapter now exposes `/livez`,
reconciliation-aware `/readyz`, bounded process-local reconciliation metrics,
and exact-scope read-only diagnostics routes. Readiness probes persistence and
schema compatibility without running migrations or reconciliation; optional
audit verification is read-only and fail-closed. PostgreSQL disconnect and
explicit recreation evidence is covered alongside File behavior.

Diagnostics require a host-supplied exact organization/application/environment
authorization callback. Their lists and filters are bounded; responses expose
only safe digests, typed status/action dispositions, repair summaries, cursor
metadata, and audit validity. The metrics observer is process-local and
non-durable; it cannot invoke repair, advance a cursor, mutate lifecycle,
write rollout state, or call P3A/P3E-4. Route operation labels are normalized
to fixed templates and contain no tenant/resource identifiers.

Task 72 introduced no worker, scheduler, queue, Redis, alert, dashboard,
rollout writer, runtime/mobile/compiler, provider, store-submission, or legal
behavior. P3E5-5D/5E and all readiness gates outside this bounded engineering
slice remain unauthorized and unresolved.

Task 72 validation passed the focused observability suite (11 tests), the full
control-plane suite against the local PostgreSQL fixture (248 tests passed and
one explicit MinIO/S3 environment skip), root analysis/tests, migration
regression, Markdownlint, local-link, whitespace, secret, and prohibited-scope
scans. The implementation stops at maintainer review with the recommendation
`PROCEED TO P3E5-5D WITH CONDITIONS`; that recommendation is not authorization
for the next slice.

## P3E5-5D factual implementation addendum (2026-08-24)

Task 73 implements the separately authorized periodic orchestration boundary
without changing this ADR's authority model. The runner is disabled by
default, invokes only the existing bounded reconciliation service, rejects
local overlap, applies bounded startup delay/jitter and failure backoff, and
waits only a bounded shutdown budget. It does not contain detector, repair,
CAS, audit, cursor, rollout, or halt logic, and it does not replay missed
timer firings.

PostgreSQL uses a session-scoped advisory lock for one global periodic pass;
the lock is coordination only and is held on a dedicated pool so the bounded
callback can use the persistence pool even when that pool has one connection.
File remains single-process/single-writer. Existing startup and administrator
entry points remain available and retain their service-local execution gate,
fairness, cursor, exact-scope, audit-before-repair, postcondition, CAS, and
report-only semantics.

Periodic metrics and runner status are fixed-key, process-local, read-only
observability. They are exposed through the existing metrics/diagnostic
surfaces only when the host wires the same runner instance; no runner-control
HTTP endpoint, queue, Redis, provider scheduler, rollout writer, P3A/P3E-4
call, runtime/mobile change, or production default was added. Task 73's
implementation/review and remaining external readiness gates are recorded in
`docs/P3E5_5D_PERIODIC_RUNNER_REVIEW.md`; P3E5-5E still requires a new
maintainer decision.

## P3E5-5E factual implementation addendum (2026-08-24)

Task 74 added only disposable crash/lock-loss evidence around the existing
Task 73 runner and Task 70/71 reconciliation seams. A child-process harness
uses direct OS `SIGKILL` at idle, ownership-before-callback, pre-CAS,
post-CAS, audit, and callback-completion markers; restart reads the same
durable File state. A local PostgreSQL harness targets the dedicated advisory
ownership session with `pg_terminate_backend` and separately proves direct
process-kill handoff to a second process. Existing disconnect injection is
reused for persistence-session boundaries.

The evidence proves one semantic projection mutation, deterministic repair
identity, lifecycle/cursor convergence, audit ordering/tamper fail-closed
behavior, File restart, tenant isolation/fairness, and process-local metrics/
diagnostic reset within the bounded local scope. The implementation fixed
idempotent replay of an earlier File audit event and reconstructs lifecycle
from an already committed immutable repair attempt without re-entering the
executor.

Task 74 adds no provider HA, power-loss, queue, Redis, persistent scheduler
table, alert, dashboard, rollout writer, P3E-4 mutation, runtime/mobile/
compiler work, production default, or beta/store/privacy/legal behavior. Its
review stops at maintainer review with
`PROCEED TO NEXT P3E5 PHASE WITH CONDITIONS`; the next phase is not started.

## P3E5-5F factual addendum (2026-08-25)

Task 75 exercised the existing authority seams in a disposable two-instance
Compose topology. Both directions of instance loss, passive reverse-proxy
retry, direct/proxied readiness, separate PostgreSQL and object-store outages,
exact artifact recovery, audit verification, and a bounded local capacity
sample passed. No new repair path, queue, provider SDK, scheduler table,
rollout writer, or runtime/mobile behavior was introduced.

The result is provider-neutral local evidence only. The proxy has no active
readiness-aware backend removal; the HTTP host does not wire the optional
diagnostics adapter or periodic runner; provider failover, edge TLS, rolling
upgrade, soak, power loss, production supply-chain evidence, and beta/
production/store/privacy/legal gates remain open. See Task 75 and
`docs/P3E5_5F_PROVIDER_RESILIENCE_READINESS_REVIEW.md`.
