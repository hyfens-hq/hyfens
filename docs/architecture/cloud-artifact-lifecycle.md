# Cloud artifact lifecycle and retention

Status: implemented for the current artifact state machine; commercial
retention periods remain deferred.

## Artifact inventory

| Artifact/object class | Owner | Delivery/rollback role | Current lifecycle policy |
| --- | --- | --- | --- |
| Registered patch artifact | `organization → patch → artifact` | Becomes deployable only after exact release binding, signature, digest, and size checks | `UPLOADING` is not available or counted; failed admission becomes `QUARANTINED`. |
| Ready release/patch artifact | Organization-owned patch record and content-addressed digest object | Required by update checks, controlled delivery, bundle export, and the current rollback-to-base path | `READY` remains available and counted. No automatic time-based expiry is active because deployment-history retention is not yet defined. |
| Quarantined artifact | Organization-owned artifact metadata and, for imports, `bundle_imports` provenance | Not deployable or downloadable; a quarantined bundle may still require bytes for explicit admission | Excluded from logical storage. Failed/untrusted bytes become purge-eligible; a pending quarantined bundle import protects its bytes. |
| Purged artifact metadata | Original artifact, patch, release, deployment, and audit records | Historical evidence only; bytes are no longer available | `PURGED` is terminal for the object bytes. Metadata is retained and records `purgedAt` and `purgeReason`. |
| Generated export | On-demand bundle response; no independent stored export record exists today | Temporary response around `exportBundle` | No separate export TTL is implemented. The source artifact follows the artifact policy. |
| Temporary/quarantined object residue | Content-addressed object store | Not customer-visible release state | Reconciliation reports unowned or unexpectedly retained objects. Cleanup is bounded and retryable. |

## State semantics

`READY` means that the artifact passed admission, may participate in update
checks, promotion/delivery, and bundle export, and contributes `sizeBytes` to
`artifact_storage_bytes_current`.

`QUARANTINED` means that the artifact is not available for delivery or
deployment. It does not count toward logical Cloud storage. Its metadata and
associated release/patch records remain. A quarantine transition records
`purgeEligibleAt`; pending bundle imports override that eligibility until they
are explicitly admitted.

`PURGED` means only that the content-addressed bytes were removed or were
already absent. The artifact record is retained with `purgedAt` and
`purgeReason`. It is not a new release-security capability and it cannot be
used by delivery, update checks, bundle export, or promotion.

Delivery returns `ARTIFACT_UNAVAILABLE` with HTTP 410 for non-ready artifacts
and `ARTIFACT_PURGED` with HTTP 410 for terminal PURGED metadata after tenant
authorization. Object-store details are not exposed to the client.

There is currently no plan-based expiry of `READY` release artifacts. A future
retention policy must first identify active deployments, rollback baselines,
and evidence requirements before introducing a READY expiry decision.

## Rollback and security protection

The current control plane does not store a complete deployment-history graph
that can prove an old READY artifact is no longer a rollback target. Therefore
all READY artifacts are conservatively protected from retention cleanup. The
existing exact release binding, digest verification, signature verification,
admission, and rollback-to-base behavior remain unchanged.

Quarantined bundle imports are also protected while their `bundle_imports`
record is not `ADMITTED`, because the artifact bytes are needed for explicit
destination admission. Failed uploads and invalid artifacts without a pending
bundle import may be purged by the internal cleanup seam.

## Logical storage interaction

Task 250 remains authoritative:

```text
artifact.state == READY → add sizeBytes to current logical storage
artifact.state != READY → do not count current logical storage
```

The READY → QUARANTINED transition records exactly one durable storage removal
fact when an add fact exists. QUARANTINED → PURGED does not record another
removal, because the bytes were already outside the logical READY gauge. A
reconciliation compares the READY-derived gauge with the net add/remove event
facts; cleanup never edits historical usage events.

## Physical purge and partial failure

`runArtifactRetentionCleanup` is an internal operator/scheduler seam. It uses
the configured deletion interface, processes a bounded batch, and resolves the
object digest from server-owned artifact metadata. Content-addressed bytes are
deleted only when no other non-PURGED artifact record references the digest.

The operation is idempotent:

- an absent object is a successful `purged_missing_object` outcome;
- a repeated run finds terminal `PURGED` metadata and does nothing;
- a deletion failure leaves the artifact QUARANTINED for retry; and
- a database failure after object deletion leaves an observable mismatch that
  the next cleanup/reconciliation can complete safely.

The file store, PostgreSQL inline store, and S3-compatible store implement the
deletion seam. Self-hosted services return a non-managed cleanup report and do
not apply Cloud commercial retention automatically.

## Reconciliation findings

Artifact reconciliation continues to verify READY object digest and size,
quarantines invalid READY records, inventories object keys where supported,
and reports orphan objects. It now also records:

- `purged_metadata` for retained evidence after byte removal; and
- `purged_object` when a PURGED record still has an unshared physical object.

No mismatch is silently repaired by reconciliation.

## Historical evidence

Physical bytes are not the historical record. Purging does not delete the
artifact metadata, patch/release identity, digest, size, signature key
reference, deployment/promotion records, bundle provenance, or immutable audit
records. A future policy may add explicit security/legal holds without changing
the purge boundary.

## Policy-content footer links

Terms, Privacy, and Refund Policy have stable public URLs. Their approved copy
can be stored as `ContentKind.policy` entries with slugs `terms`, `privacy`,
and `refund-policy` in the existing content workspace. Create, update, publish,
and archive operations already write the immutable `content.*` audit events;
the Cloud editor identifies that audit boundary. Static fallback copy remains
available until a published policy record exists or while the public API is
unavailable.

## Deferred decisions

- commercial retention periods by Cloud plan;
- security, legal, and investigation holds;
- customer-controlled deletion, if ever allowed;
- physical-capacity versus logical usage settlement;
- CDN/proxy/object-store cache retention and edge egress evidence;
- trusted patch-install receipts; and
- billing/overage behavior.
