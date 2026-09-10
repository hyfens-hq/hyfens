# P3E5-5A reconciliation domain review

<!-- markdownlint-disable MD013 -->

Status: implementation complete; maintainer review required

Date: 2026-08-24

## Decision boundary

Task 69 authorized only the P3E5-5A domain/taxonomy foundation. This review
covers the implementation of typed reconciliation records and validation. It
does not authorize startup scanning, manual reconciliation, projection repair,
persistence, metrics, readiness, diagnostics, dashboards, P3F, P3G, runtime
changes, mobile changes, rollout mutation, or production enablement.

## Implemented scope

`packages/control_plane/lib/src/reconciliation_domain.dart` now provides:

- `ReconciliationScope` with organization/application/environment binding;
- explicit versioned `ReconciliationPolicy` bounds with no operational
  defaults;
- resumable `ReconciliationCursor` fairness state;
- deterministic `ReconciliationInvocation` identity and canonical codec;
- immutable `ReconciliationFinding` identity over scope, taxonomy, entity, and
  source evidence (not observation timestamps);
- immutable `ReconciliationPrecondition` and SHA-256 currentness digest;
- deterministic `ReconciliationRepairAttempt` IDs and replay/conflict
  comparison;
- the three repairability classes, five severity values, six finding states,
  six repair results, and the eight typed repair actions;
- all 19 required divergence codes with typed severity, repairability,
  automatic action, operator action, and audit behavior metadata;
- explicit immutable-source and projection-target vocabularies;
- an exact-scope, expiring/revocable/rotatable reconciliation principal with
  only `health:reconcile`, `health:read`, and `rollout:read`;
- bounded safe audit event metadata for domain/admin actions.

The module is exported from `packages/control_plane/lib/control_plane.dart`.
It has no storage, HTTP, scheduler, rollout writer, P3E-4 application, runtime,
mobile, compiler, or patch-format dependency.

## Verified invariants

The domain rejects unknown schema/policy/fairness versions, unknown taxonomy or
action values, invalid severity/repairability combinations, invalid digests,
non-UTC or reversed timestamps, inconsistent bounds, cross-scope cursors,
foreign principal scopes, stale precondition evidence, changed repair bodies,
oversized bounded fields, unknown JSON fields, and noncanonical JSON input.

Finding and repair identities include tenant scope. A principal must use its
exact application/environment scope and cannot authorize any rollout, release,
artifact, credential, observation, runtime, signing, or halt scope. The action
policy has no rollout mutation path. Immutable source records are represented
as report-only evidence; no mutation API was introduced for them.

Safe detail/error codes, digests, opaque IDs, bounded counts, and typed enum
values are the only audit fields. Credentials, lease tokens, patch bytes,
private keys, observations, user data, stack traces, and arbitrary exception
text have no representation in the audit record.

## Tests

`packages/control_plane/test/reconciliation_domain_test.dart` verifies:

- canonical round trips and deterministic policy/cursor/invocation identity;
- complete taxonomy coverage and immutable-source classification;
- action/repairability rejection and rollout-authority exclusion;
- finding identity stability across observation timestamps and sensitivity to
  source-digest changes;
- repair idempotent replay versus changed-body conflict;
- unknown taxonomy, malformed digest, unknown fields, noncanonical JSON, and
  oversized safe-code rejection;
- principal expiry, revocation, rotation, exact scope, and forbidden scope;
- audit-field redaction and canonical round trips.

## Validation evidence

- `dart format packages/control_plane/lib/src/reconciliation_domain.dart
  packages/control_plane/test/reconciliation_domain_test.dart` — PASS;
- `dart analyze . --fatal-infos` in `packages/control_plane` — PASS;
- focused `dart test test/reconciliation_domain_test.dart` in
  `packages/control_plane` — 11/11 PASS;
- full `dart test` in `packages/control_plane` — 182 PASS, 21 existing
  environment skips (PostgreSQL/MinIO/S3 fixtures not configured);
- root `dart analyze --fatal-infos` — PASS;
- root `dart test` — 1/1 PASS;
- Markdownlint, local-link, trailing-whitespace, high-confidence secret, and
  domain prohibited-scope scans — PASS.

## Explicitly not implemented

The following remain not started by P3E5-5A:

- File/PostgreSQL findings or repair-attempt persistence;
- startup or explicit administrator scan execution;
- projection CAS repair or operational-state transitions;
- metrics, readiness, diagnostics, alerting, or dashboard endpoints;
- repair queues, workers, heartbeats, Redis, or distributed transactions;
- any P3A rollout mutation or P3E-4 halt application;
- runtime, Android, iOS, compiler, patch, capability, signing, or mobile
  behavior changes.

## Open readiness gates

P1D-01 true power loss, P1D-03 iOS diagnostics limitations, P1D-04 broad iOS
performance, P1D-07 independent real-application validation, P1D-09
interpreter attribution, P1D-18 Apple/Google/legal review, provider-production
readiness, beta readiness, production readiness, App Store readiness, Google
Play readiness, and legal/privacy readiness remain open. P3E5-5A is not
production-readiness evidence.

## Recommendation

### AUTHORIZE P3E5-5B FILE/POSTGRESQL BOUNDED RECONCILIATION WITH CONDITIONS

Conditions for the next slice:

1. Keep the domain types, taxonomy wire values, immutable-source boundary,
   exact principal scopes, and canonical identity rules frozen.
2. Persist findings and repair attempts append-only with tenant-scoped keys,
   canonical-body idempotency, restart durability, and no overwrite on conflict.
3. Implement only bounded startup/manual candidate discovery and existing
   projection/operational CAS contracts; do not add a worker, queue, rollout
   writer, or direct P3A/P3E-4 mutation.
4. Add malformed-persistence, concurrent File/PostgreSQL, and foreign-scope
   tests before any repair execution is considered.
5. Stop again for maintainer review before metrics/readiness/diagnostics or
   later P3E5 slices.

No P3E5-5B code is started by this task.

## P3E5-5B final-closure factual addendum (2026-08-24)

The later Task 70/71 implementation preserved the 5A taxonomy wire values and
made its action binding explicit. `LINK_EXISTING_DECISION` is proven
`MODEL_UNREACHABLE` under the atomic evaluation/decision link invariant;
`COMPLETE_WORK_FROM_EXISTING_APPLICATION` is covered by the existing fenced
completion operation; and `REBUILD_DERIVED_PROJECTION` is
`NOT_APPLICABLE`/report-only because no authorized projection owner exists in
the bounded scope. Non-executable dispositions fail closed without a mutation
path. These are implementation addenda to the frozen 5A model, not changes to
the taxonomy or a new authority.
