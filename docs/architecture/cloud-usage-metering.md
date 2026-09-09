# Cloud usage metering foundation

Status: IMPLEMENTED — 2026-09-07; delivery authority refined by Task 253

This document describes the evidence layer for Hyfens Cloud usage. It does
not define plan quotas, prices, overages, invoices, or payment-provider
settlement.

## Meter meanings

### Artifact storage

`artifact_storage_bytes_current` is the sum of `sizeBytes` on an
organization's `ArtifactRecord` rows whose state is `READY`.

This is a logical, customer-attributable gauge of currently retained,
deliverable artifacts. It includes patch artifacts uploaded through the normal
Cloud path and artifacts admitted from release bundles. It counts each ready
artifact record even when two logical records reference the same
content-addressed object, because the current product relation is the
authoritative customer ownership boundary.

It excludes:

- `UPLOADING` and `QUARANTINED` artifact records;
- temporary upload state, metadata, indexes, and failed operations; and
- orphan physical objects that have no ready artifact record.

Quarantined artifact bytes can be physically purged by the Task 252 cleanup
seam while artifact metadata remains. Physical residue after a quarantine is
therefore not silently treated as customer-visible storage usage. A future
physical-capacity meter can use the object inventory separately.

### Artifact delivery

`artifact_delivery_bytes_period` is the sum of non-negative artifact payload
bytes accepted by a trusted delivery observation during an explicit UTC
calendar month:

```text
[period_start, period_end)
```

The current route reads and digest-verifies the complete artifact before
writing the response. A single range response counts only the selected
payload bytes. A new request or retry with a new origin source identity is a
new origin transfer and is counted again. Failed authorization, missing,
corrupt, unsatisfiable-range, or zero-byte responses create no delivery fact.

The current delivery projection is explicitly `partial`: it covers the
control-plane origin but has no trusted CDN, proxy-cache, direct object-store,
or future-edge egress evidence. It must not be used as a bandwidth quota
source. See [cloud-delivery-accounting.md](cloud-delivery-accounting.md) for
the path inventory and future ingestion contract.

Patch installation is intentionally not inferred from artifact delivery.

## Evidence model

Usage facts are immutable JSON records in the `cloud_usage_events` collection.
Each fact contains:

- organization ownership;
- stable meter and operation identifiers;
- a non-negative integer quantity in bytes;
- `occurredAt` and `recordedAt` timestamps;
- a trusted source and source identifier; and
- safe source metadata, including server-resolved artifact identity for
  delivery observations.

Storage transitions use `artifact_state` as the source. Successful artifact
readiness creates an `add` fact and a transition out of `READY` creates a
`remove` fact. The current logical storage gauge remains derived from the
authoritative artifact records, so legacy artifacts without historical events
remain measurable while event gaps remain visible to reconciliation.

The current implementation uses the existing durable record seam for both the
filesystem and PostgreSQL stores. It does not introduce an event bus or a
second metrics database. A relational aggregate can be added later if event
volume requires it.

## Idempotency and corrections

Event IDs are deterministic hashes of organization, meter, operation, source,
and source identifier. Replaying a source operation reads the existing event
and compares its accounting identity. An equivalent retry is acknowledged
without creating a second fact. Reusing an event identity for different
quantity, ownership, or source metadata raises `USAGE_EVENT_CONFLICT`.

Historical events are not edited. If a future correction is required, it must
be represented by another auditable fact or an explicitly designed adjustment
operation.

## Reconciliation

`CloudUsageMeteringService.reconcileStorage` compares:

1. the state-derived sum of ready artifact sizes; and
2. the net sum of durable storage `add` and `remove` facts.

It returns a read-only report with expected bytes, accounted bytes, event
count, balance, and findings. It does not silently rewrite events or repair
customer state. A mismatch is evidence for an operator or a later repair
procedure.

The existing artifact reconciliation path also uses the storage removal seam
when it quarantines a previously ready artifact. Physical object inventory
remains a separate orphan-object check.

## Failure behavior

Artifact readiness is not acknowledged until its storage accounting fact has
been durably accepted. If that write is unavailable, the operation returns
`USAGE_ACCOUNTING_UNAVAILABLE` and can be retried with the same idempotency
key. The artifact state is not treated as a successful client operation.

For delivery, the server records the origin byte fact before writing the HTTP
response. A metering write failure returns `503` rather than acknowledging an
unaccounted delivery. This is an origin-transfer guarantee, not a claim about
bytes that may be lost after the server writes to a network socket.

Self-hosted deployments do not create Cloud usage facts, do not require the
usage collection, and do not fail because Cloud accounting is unavailable.

## Billing projection

Cloud billing responses retain the existing countable usage fields and now
additive measured fields:

```json
{
  "artifact_storage_bytes_current": 0,
  "artifact_delivery_bytes_period": 0,
  "artifact_delivery_period": {
    "type": "utc_calendar_month",
    "start": "2026-09-01T00:00:00.000Z",
    "end": "2026-10-01T00:00:00.000Z"
  },
  "artifact_delivery_authoritative": false,
  "artifact_delivery_authority": "partial",
  "artifact_delivery_quota_eligible": false,
  "artifact_delivery_source": "control_plane_origin",
  "artifact_delivery_covered_sources": ["control_plane_origin"],
  "artifact_delivery_uncovered_sources": ["cdn", "edge", "object_store"]
}
```

The Cloud workspace may display these raw measured values as **Measured origin
delivery** with partial-coverage wording. It does not render byte quotas or
progress bars because no storage or bandwidth allowance has been commercially
approved. Its compact display uses binary units (`KiB`, `MiB`, `GiB`, and
`TiB`) while the API and evidence records remain integer bytes.

## Deferred policy

The following remain separate decisions and are not implemented here:

- plan quotas and overage behavior;
- provider billing, invoices, taxes, and settlement;
- physical object capacity accounting;
- storage or delivery retention periods;
- monthly billing-cycle semantics;
- CDN/proxy/object-store edge ingestion and interrupted-socket receipts;
- trusted patch-install receipts; and
- usage aggregation, reconciliation repair, and Enterprise overrides beyond
  the current read-only foundation.
