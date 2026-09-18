# Cloudflare R2 recovery acceptance research

**Research date:** 2026-09-18
**Status:** Source-backed decision input; not legal, privacy, security, or
provider-contract approval.

This note closes the evidence gap between the managed disposable recovery
rehearsal and the external decisions needed before launch. It uses Cloudflare's
first-party R2 documentation and the sanitized Task 284 result. It contains no
credentials, bucket secrets, or customer data.

## Decision summary

R2 remains a reasonable off-host destination for the current recovery design
if Hyfens explicitly accepts provider-managed encryption and the
provider dependency. The repository must not describe the R2 design target as
a Hyfens guarantee, or describe a bucket lock as a backup schedule, a failover
system, or a legal retention decision.

The remaining recovery decisions are:

1. confirm the actual destination bucket's jurisdiction and the applicable
   Cloudflare account terms/SLA;
2. decide whether Cloudflare-managed encryption keys satisfy the security
   requirement, or whether customer-provided/client-side encryption is needed;
3. approve the backup cadence, retention, RPO, RTO, restore owner, and
   maintenance/recovery window; and
4. obtain privacy/legal/accounting approval for residency, deletion exceptions,
   legal holds, and customer-facing backup wording.

## Evidence already proven by Hyfens

Task 284's managed-host run restored backup `20260918T061844Z` into a unique
disposable PostgreSQL/object-store pair. The sanitized result recorded:

- manifest and checksum validation passed;
- restored object count: `2`;
- coupled managed restore passed;
- artifact reconciliation passed with `orphan_object_count=2`, and the
  restored bytes were preserved rather than deleted;
- deletion-tombstone replay passed;
- deleted tenant records and customer memberships: `0`;
- source, restored, and shared artifact digests matched;
- disposable recovery containers, volumes, and network were removed; and
- live services remained running and unchanged.

This proves the current Hyfens restore and deletion-reconciliation procedure
against that selected backup. It does not prove provider durability, automatic
failover, customer-controlled key custody, a statutory retention period, or an
approved RPO/RTO.

## Read-only live configuration observation

On 2026-09-18, the managed host's sanitized preflight returned:

```text
managed_public_backup_preflight=PASS
source_bucket_scope=PASS
destination_bucket_scope=PASS
```

The protected configuration was inspected for bucket and endpoint names only;
credential values were not read. It currently wires:

```text
source:      hyfens-dev
destination: hyfens-cloud-backups
endpoint:    https://<same-account>.r2.cloudflarestorage.com
```

Therefore the source and destination are distinct buckets and the suspected
same-bucket wiring blocker is closed. They are, however, in the same Cloudflare
account, so an account-compromise or account-lockout isolation decision remains
open.

The read-only Cloudflare dashboard observation for that account showed:

- `hyfens-cloud-backups`: 21 objects / 694.87 kB; UI location Asia-Pacific
  (APAC); `operational/` lifecycle delete after 30 days enabled; matching
  `operational/` bucket lock for 30 days enabled; Data Access Logs disabled;
  public development URL and custom domain disabled.
- `hyfens-dev`: 2 objects / 2.19 kB; UI location APAC; no bucket lock or
  retention lifecycle beyond the default multipart-abort rule.
- `hyfens-prod`: 0 objects; UI location APAC; no bucket lock or retention
  lifecycle beyond the default multipart-abort rule.

The dashboard paths use the default R2 endpoint and do not show an explicit
jurisdiction restriction. The displayed APAC location is not evidence of a
legal residency guarantee. The exact account, bucket, and configuration
snapshot should be attached to the launch record through the approved
redacted-evidence process.

## First-party R2 facts and the Hyfens boundary

| Area | First-party fact | Hyfens implication | Evidence/decision still needed |
| --- | --- | --- | --- |
| Encryption at rest | R2 encrypts objects and metadata at rest automatically with AES-256; Cloudflare manages the encryption keys. | Provider-managed encryption is technically present. It is not customer-controlled key custody. | Security owner accepts provider-managed keys, or selects SSE-C/client-side encryption and defines key backup, rotation, recovery, and loss handling. |
| Encryption in transit | R2 client traffic is protected with TLS. | The managed wrapper must continue using the HTTPS S3 endpoint and protected host credentials. | Record endpoint and secret-store configuration without exposing secrets. |
| Durability | Cloudflare says R2 is designed for 99.999999999% annual durability through redundancy and synchronous persistence. Cloudflare separately publishes a 99.9% monthly R2 availability service level. | This is provider design/SLA evidence, not a Hyfens data-loss guarantee, application availability target, or recovery-time commitment. | Confirm the account's applicable terms/plan and retain a dated provider-contract reference. Do not convert the figures into Hyfens marketing or RTO claims. |
| Location and residency | Automatic placement is based on the create request; location hints are best effort. Jurisdiction restrictions guarantee storage/processing within the selected jurisdiction, and a bucket's jurisdiction cannot be changed after creation. | The current endpoint/name alone does not prove residency. | Record the actual bucket jurisdiction. If a legal requirement needs a restricted jurisdiction and the current bucket is not one, create a separately approved destination and perform a controlled migration. |
| Bucket lock | Lock rules apply to new and existing objects and take precedence over lifecycle rules. | The existing 30-day `operational/` policy is an anti-early-deletion control. It is not the backup cadence, full recovery-unit coverage, or a legal hold. | Legal/security approve retention and hold behavior; operations exports the actual lock/lifecycle configuration. |
| Lifecycle deletion | Lifecycle deletion is asynchronous and can take time after an object becomes eligible. | A 30-day policy is not a precise deletion timestamp. | Use the application audit/tombstone record as the authoritative deletion evidence; retain provider configuration as supporting evidence. |
| Access audit | R2 request logging is useful operational telemetry but is asynchronous/best effort. | R2 logs cannot replace Hyfens' append-only administrative audit trail. | Keep actor, reason, target, result, and correlation data in the Hyfens audit system; never place credentials in it. |
| API authority | Bucket-scoped R2 tokens can limit object access to the intended bucket. | Separate source/destination credentials and correct-pair preflight reduce blast radius. | Confirm the live token scopes and rotate/revoke through the approved owner workflow. The same-account placement still needs a security isolation decision. |

The R2 availability SLA is an availability commitment with service-credit
remedies, not a promise of automatic failover or restoration of Hyfens data.
The R2 durability page itself distinguishes durability from availability and
notes that durability does not prevent intentional or accidental deletion.

## Encryption and key-custody decision

The current implementation relies on R2's built-in at-rest encryption. That is
appropriate only if the security owner accepts Cloudflare-managed keys for this
recovery class.

Cloudflare documents SSE-C (customer-provided keys) for R2. SSE-C changes the
operational contract: the key must be supplied for every applicable read/write
operation, and Cloudflare cannot recover objects if Hyfens loses the key. It is
therefore not a free security upgrade by itself; it creates a second recovery
asset that must be protected, rotated, escrowed, tested, and included in the
same recovery acceptance. Client-side envelope encryption would create a
similar key-management obligation and is not implemented by this task.

Until the security owner chooses one of these postures, the launch wording must
say **encrypted by the provider with provider-managed keys**, not
**customer-controlled encrypted backup**.

## RPO/RTO acceptance method

No RPO or RTO value is selected in code by this task.

### RPO

Define RPO as the maximum accepted data interval between the incident boundary
and the last backup that is confirmed complete and readable. For each accepted
run, retain:

- backup ID and source consistency-point timestamp;
- backup start and successful-completion timestamps;
- database and object manifest/checksum identifiers;
- measured backup age at the incident boundary; and
- any writes intentionally excluded by the quiesce/consistency procedure.

The current 30-hour `HYFENS_PUBLIC_BACKUP_MAX_AGE_SECONDS` freshness threshold
is an operational alarm threshold, not an approved RPO. An owner must select a
cadence and maximum tolerated backup age based on the product's business impact.

### RTO

Define RTO as the elapsed time from incident declaration to an approved
recovered service being ready for traffic, including restore, readiness,
reconciliation, deletion-tombstone replay, audit verification, and traffic
reopen. The measured `managed_pair_restore=10872ms` result is a restore-component
timing only; it is not the end-to-end RTO.

The recommended acceptance run is:

1. declare the failure boundary and start the timer;
2. restore the database/object pair into an approved disposable target;
3. verify readiness, manifests, artifact digests, ownership/status, and
   tombstone replay;
4. record the recovery owner decision to reopen traffic; and
5. repeat under the same approved deployment shape enough times to establish a
   representative p95, then have the owner approve the target and exclusions.

This is an operational recommendation, not a statutory or Cloudflare
requirement. It must be rerun if the destination, encryption posture, backup
cadence, deployment shape, or recovery procedure changes materially.

## External closure checklist

The following items require human/provider action and must remain open until
evidence is attached to the launch record:

- [ ] Record the destination bucket's actual jurisdiction, endpoint form,
  account/plan, and dated applicable R2 terms/SLA.
- [ ] Record the source and destination bucket identities in a redacted form,
  confirm they are distinct approved targets, and confirm token scope/rotation
  ownership. The current host preflight passes for `hyfens-dev` to
  `hyfens-cloud-backups`; decide whether same-account placement is sufficient.
- [ ] Security owner accepts provider-managed R2 keys, or approves a separate
  SSE-C/client-side encryption design with a tested key-recovery procedure.
- [ ] Operations owner selects backup cadence, retention, legal-hold behavior,
  freshness alert threshold, RPO, RTO, recovery owner, and maintenance window.
- [ ] Run the approved RPO/RTO rehearsal and retain sanitized timings,
  manifests, reconciliation, tombstone, audit, and cleanup evidence.
- [ ] Privacy/legal/accounting owners approve residency, deletion exceptions,
  evidence retention, and customer-facing backup language.
- [ ] Monitoring owner proves mailbox/alert coverage and runs the bounded
  backup-restore incident drill.

## What is safe to say now

The product may say that Hyfens has a managed, encrypted-at-rest R2 backup
destination and a tested disposable restore/tombstone-replay procedure, with
the caveat that provider durability, availability, and legal policy approvals
remain external gates.

It must not yet say that Hyfens has:

- customer-controlled encryption keys;
- automatic provider failover;
- an approved RPO or RTO;
- a jurisdiction-specific residency guarantee for the existing bucket; or
- a universal 30-day statutory retention rule.

## Primary sources

- [Cloudflare R2 data security](https://developers.cloudflare.com/r2/reference/data-security/)
- [Cloudflare R2 durability](https://developers.cloudflare.com/r2/reference/durability/)
- [Cloudflare R2 Service Level Agreement](https://www.cloudflare.com/r2-service-level-agreement/)
- [Cloudflare R2 data location](https://developers.cloudflare.com/r2/reference/data-location/)
- [Cloudflare R2 bucket locks](https://developers.cloudflare.com/r2/buckets/bucket-locks/)
- [Cloudflare R2 object lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)
- [Cloudflare R2 SSE-C](https://developers.cloudflare.com/r2/examples/ssec/)
- [Cloudflare R2 data access logs](https://developers.cloudflare.com/r2/buckets/data-access-logs/)
- [Task 284 — Managed public recovery rehearsal](../../tasks/284-managed-public-recovery-rehearsal.md)

## Interpretation boundary

These sources support the technical distinctions and the evidence checklist.
They do not choose Hyfens' legal retention periods, tax treatment, data
residency, security classification, provider contract, RPO, RTO, or launch
wording.
