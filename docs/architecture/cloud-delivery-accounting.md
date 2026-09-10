# Cloud artifact delivery accounting

Status: implemented as an authority-aware origin foundation — 2026-09-07

This document defines delivery evidence separately from artifact availability,
storage, patch installation, and commercial quota policy. It does not activate
bandwidth quotas, overages, invoices, or settlement.

## Delivery path inventory

| Delivery path | Exists today | Serves customer bytes | Origin observes it | Authority |
| --- | --- | --- | --- | --- |
| Authenticated control-plane artifact endpoint | Yes | Yes | Response payload length is observed before acknowledgement | Covered source; the overall meter remains `partial` until the wider delivery surface has trusted edge evidence |
| Host reverse proxy forwarding to the control plane | Deployment boundary only; no cache path is configured in this repository | It may forward origin bytes | The origin sees the response it produces, but not exact client socket egress after an interruption | Partial for client egress |
| CDN client egress | No adapter or deployment exists | Not currently | No | Unsupported/unmeasured |
| Direct signed object-store URL | No URL issuance path exists | Not currently | No | Unsupported/unmeasured |
| Future edge delivery | No | Not currently | No | Unsupported/unmeasured |

The S3-compatible and PostgreSQL artifact adapters are storage dependencies of
the control plane. They are not customer-facing delivery sources today.

## Canonical meter

`artifact_delivery_bytes_period` measures non-negative artifact payload bytes
accepted for a trusted delivery response during the UTC calendar period:

```text
[period_start, period_end)
```

The canonical commercial-neutral boundary is customer-facing artifact egress.
Traffic from a future CDN to its origin is infrastructure transfer and must not
be added to CDN client egress. A future source must emit one observation for
the bytes transferred toward the consuming client, not one observation for
every hop.

The current origin adapter records the payload length it is about to write.
This preserves Task 250's durable failure behavior: a metering failure returns
`503` rather than acknowledging an unaccounted origin response. The control
plane cannot prove how many bytes reached a client after a socket interruption;
that limitation is why the broader delivery meter is explicitly `partial`.

## Origin responses and ranges

- A complete response counts its actual response payload length.
- A single `Range: bytes=start-end` or suffix range returns `206` and counts
  only the selected bytes.
- Multiple ranges and unsatisfiable ranges return `416` and create no usage
  event.
- A zero-byte response creates no delivery event.
- Separate successful downloads count separately.
- The origin creates a fresh source identity for each response; only a retry
  of the same source identity is idempotent.
- Patch installation is not inferred from a delivery response.

The origin adapter still cannot turn a partially written socket into a precise
client-byte receipt. A future transport that can provide that evidence must
submit it as a trusted source rather than reusing the origin claim.

## Trusted observation contract

`TrustedArtifactDeliveryObservation` is the internal ingestion seam for the
origin and future edge adapters. It contains:

- server-resolved artifact identity;
- one stable source identifier supplied by the trusted adapter;
- a known source (`control_plane_origin`, `cdn`, `object_store`, or `edge`);
- integer payload bytes;
- `occurredAt`; and
- an optional artifact digest for identity verification.

The metering module resolves the artifact record itself and derives the
organization from `artifact → patch → organization` ownership. There is no
public customer usage-reporting endpoint, and an observation cannot choose an
arbitrary organization.

The durable usage event stores `occurredAt` separately from `recordedAt`, so a
late edge record for August 31 remains in the August period even if ingested on
September 1. Deterministic event IDs make an equivalent source retry a no-op;
different facts using the same identity fail closed with a conflict.

## Authority and quota guard

The current projection exposes:

- `artifact_delivery_authority`: `authoritative`, `partial`, or `unavailable`;
- covered and uncovered source lists; and
- `artifact_delivery_quota_eligible`.

The current value is `partial`, with `control_plane_origin` covered and CDN,
object-store, and edge sources uncovered. Quota eligibility is `false`. This is
an explicit evidence state, not an approval to bill. Future quota code must
require both an approved commercial policy and an authority state that is
complete for the configured delivery surface; it must never infer completeness
from a non-zero byte counter or the legacy boolean alone.

## Source precedence and double counting

When a future CDN is customer-facing, the intended precedence is:

```text
CDN → consuming client       commercial delivery evidence
CDN → origin                 infrastructure transfer only
```

The same rule applies to an object gateway or edge. A future adapter must not
submit both the customer-facing egress and the internal fetch for the same
transfer as commercial delivery. If a source cannot provide a stable transfer
identity, it remains unsupported rather than being deduplicated heuristically.

## Reconciliation and missing evidence

Storage can be reconciled against current artifact records. Delivery is an
append-only event stream and generally cannot be reconstructed perfectly from
artifact state after the fact. A future edge integration therefore needs its
own access-log or provider-summary reconciliation source, with findings for
missing, late, duplicate, unattributed, or invalid observations.

Until that exists, missing edge evidence lowers authority to `partial`; the
system does not estimate bytes from request counts, artifact size, signed URL
issuance, origin fetches, or patch-install observations.

## Self-hosted

Self-hosted services return no Cloud delivery usage and do not require the
Cloud usage collection. Operators may add local operational metrics, but those
metrics are not Cloud commercial evidence.

## Deferred

- CDN or edge deployment;
- provider-specific CDN/object-store log ingestion and authentication;
- exact interrupted-socket client-byte receipts;
- bandwidth quotas, overages, billing settlement, and invoice periods;
- physical storage accounting; and
- trusted patch-install or active-device receipts.
