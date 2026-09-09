# Task 250 — Cloud usage metering and settlement

Status: [x] Completed

## Goal

Build the minimum reliable Cloud usage-accounting foundation for artifact
storage and artifact delivery without activating quotas, overages, billing, or
provider settlement.

## Scope and Non-goals

Scope:

- immutable, idempotent usage facts;
- logical ready-artifact storage accounting;
- control-plane-origin artifact delivery bytes;
- UTC operational usage periods;
- read-only storage reconciliation; and
- additive Cloud billing usage projection and workspace display.

Non-goals:

- changing the Cloud versus Self-hosted model;
- changing the fixed Free/Starter/Team/Enterprise matrix;
- weakening release integrity;
- inventing MAU billing; and
- deleting historical security or audit records without approved policy.

## Owner

Codex

## Dependencies

- Task 249 countable Cloud plan boundaries.
- Existing organization-owned artifact records and object-store seam.
- Existing Cloud billing projection and workspace bridge.

## Assumptions

- Logical ready-artifact bytes are the authoritative current customer-visible
  storage gauge.
- Current artifact delivery is observable at the control-plane origin; CDN,
  proxy-cache, direct-object, and patch-install traffic remain unmeasured.
- Self-hosted deployments remain outside Cloud usage and quota accounting.

## Work Items

- [x] Define immutable usage event contracts, trusted sources, integer byte
  units, and Cloud-only behavior.
- [x] Define UTC calendar-month delivery periods, occurrence versus recording
  timestamps, and durable idempotency.
- [x] Add logical storage projection and read-only event/state reconciliation.
- [x] Add origin delivery-byte accounting to the verified HTTP delivery path.
- [x] Expose measured usage additively through Cloud billing and the workspace
  without publishing quotas.
- [x] Add focused tests and architecture documentation.
- [x] Explicitly defer plan quotas, overages, billing settlement, retention
  deletion, physical-capacity accounting, CDN ingestion, and install receipts.

## Validation

`dart format`, scoped `dart analyze`, focused control-plane tests, Cloud web
lint/typecheck/build, and `git diff --check` are required after the batch is
complete. Completed validation:

- `dart analyze .` from `packages/control_plane` — passed.
- Focused metering and Cloud plan tests — passed.
- Affected control-plane, HTTP, closure, release, bundle, and artifact tests —
  passed.
- Cloud web `npm run typecheck`, `npm run lint`, and `npm run build` — passed.
- `git diff --check` in both repositories — passed.

Existing unrelated reconciliation/P3E failures were not changed or used as a
reason to expand this task.

## Next Action

Use the measured evidence to make a later commercial quota decision. Do not
activate byte quotas or overages from this foundation alone. A future edge
delivery integration should be completed before treating CDN or direct object
store egress as authoritative.

## Blockers

None for the measurement foundation. Commercial quota, retention, edge-egress,
and install-receipt decisions remain deferred follow-up work.

## Outcome

Implemented and validated. The control plane now persists immutable,
organization-scoped `cloud_usage_events` with deterministic event IDs and
durable retry comparison. Logical current artifact storage is derived from
ready artifact records; storage transition facts support reconciliation.
Artifact delivery records the exact bytes accepted by the current control
plane origin over an explicit UTC calendar month. Cloud billing exposes these
measured fields and the Cloud workspace displays raw bytes without quotas or
progress bars. Self-hosted deployments do not emit or require Cloud usage
facts.

No pricing, plan matrix, quota, overage, invoice, tax, retention deletion,
patch-install, or provider settlement behavior was added.

## References

- `tasks/249-cloud-plan-boundaries.md`
- `docs/architecture/cloud-plan-entitlements.md`
- `docs/architecture/cloud-usage-metering.md`
- Preserved private catalog reference: `feat/cloud-commercial-platform-web`

## History

- 2026-09-07: Created as the explicit follow-up for storage, bandwidth,
  retention, and trusted patch-install accounting deferred from Task 249.
- 2026-09-07: Implemented the first evidence layer for logical artifact
  storage and control-plane-origin delivery bytes. Quotas, overages, and
  provider settlement remain deferred.
- 2026-09-07: Completed focused Dart and Cloud web validation; closed the
  task with quotas, edge egress, retention, install receipts, and settlement
  explicitly deferred.
