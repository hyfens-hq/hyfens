# ADR 0011 — Own scheduled evaluation through durable cooperative work claims

Status: Proposed — P3E-5 design only; implementation not authorized

Date: 2026-08-24

## Context

P3E-3 can idempotently evaluate one exact aggregate/rollout revision, and
P3E-4 can conservatively apply an eligible `HALT_NEW_OFFERS` decision through
the P3A expected-revision CAS. P3E-5 needs orchestration that survives duplicate
workers, crashes, restarts, and stale rollout changes without creating a new
evaluator, rollout state machine, queue dependency, or runtime trust root.

Process-local timers make ownership ambiguous under replication. An external
scheduler can wake a service but cannot by itself preserve immutable logical
identity, work attempts, leases, staleness, or cross-store reconciliation. A
separate PostgreSQL worker is a useful deployment shape, but it still needs a
shared ownership model.

## Decision proposed

Scheduled-evaluation ownership belongs to a durable work store using
at-least-once cooperative claims:

1. PostgreSQL is the multi-instance authority for deterministic work identity,
   due-state selection, database-time leases, token/work-version CAS, bounded
   retry state, and append-only attempts.
2. File mode implements the same domain state machine for one process and one
   writer only; it makes no multi-process lease or HA claim.
3. Executors may run as one explicit scheduler process initially and as
   separate replicated workers later without changing the ownership contract.
4. External cron/timer systems may wake executors but never define work or
   bypass durable claims.
5. Duplicate execution is accepted. P3E-3 idempotency, P3E-4 idempotency, and
   P3A expected-revision CAS prevent duplicate semantic evaluation/halt
   effects.
6. Work state is an orchestration projection. Immutable P3E-3/P3E-4/P3A
   evidence remains authoritative, with deterministic reconciliation after
   interruption instead of two-phase commit.

## Consequences

This keeps the initial open-source/self-host implementation independent of
Redis and managed queues, gives single-node and replicated deployments one
domain model, and lets worker process placement change later. It requires a
future PostgreSQL claim/lease implementation, a strict File single-writer
guard, application/environment-scoped scheduler credentials, resource/fairness
limits, and failure-injection tests. It provides at-least-once rather than
exactly-once execution and retains a cross-store reconciliation obligation.

No scheduler, worker, schema, lease, or automatic halt is implemented by this
ADR.

## Alternatives considered

- **Process-local timer ownership:** rejected because replication and restart
  recovery would require a second hidden ownership mechanism.
- **External scheduler as authority:** rejected because provider retries do not
  supply tenant-scoped logical identity, work history, stale checks, or
  downstream reconciliation.
- **Queue-first ownership:** deferred because a queue adds operations and does
  not remove the need for authoritative work state and idempotency.
- **Distributed exactly-once execution:** rejected as unnecessary complexity;
  downstream immutable/idempotent boundaries already provide semantic safety.

## Reference

See [P3E-5 scheduled-evaluation design](../history/reviews/P3E5_SCHEDULED_EVALUATION_DESIGN.md).
