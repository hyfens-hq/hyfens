# Account deletion and retention

Status: CODE VERIFIED — 2026-09-09; grace-period, backup, and production-mail
policy inputs remain external decisions

## Separate lifecycle actions

Hyfens treats these as independent transitions:

| Action | Effect |
| --- | --- |
| Cancel subscription | Stops future renewal; preserves current paid access and data |
| Downgrade plan | Schedules lower entitlements at the paid-cycle boundary |
| Request refund | Starts a reviewed payment-remediation workflow |
| Delete account | Removes/deidentifies one human identity after ownership resolution |
| Delete organization | Deletes that Cloud tenant's customer-owned data in stages |

Neither cancellation, downgrade, nor deletion automatically creates a refund.
An already-paid period remains governed by the commercial policy and the
reviewed refund workflow.

## Request and verification model

The public `/account-deletion` page accepts an email and always returns a
neutral acknowledgement. If an active verified Cloud customer exists, the
control plane sends a deletion-purpose token through the injected
`HumanDeletionMessageDelivery` seam. The token is random, stored only as a
hash, purpose-bound to `account_deletion`, time bounded by the existing
recovery-token policy, and atomically single-use. It cannot be used for login,
password recovery, or email verification. Unknown addresses produce the same
response and no observable token.

The verified link creates a durable account deletion request but does not
delete an organization. A signed-in customer can request the same operation
from `/dashboard/privacy` after current-password verification and typing
`DELETE`. The organization surface is owner-only and requires the same strong
confirmation. Customer-facing routes disclose only the request projection,
never tokens, provider secrets, payment credentials, internal notes, or
foreign organizations.

## Ownership and billing

One human may belong to multiple organizations. A personal deletion request
is blocked with `ownership_resolution_required` for each organization where
the user is the sole active customer owner. The implementation never silently
transfers ownership or orphans a tenant. Non-owner memberships can be removed
when personal deletion completes; other owners and their organizations remain.

Verified organization deletion first calls the existing billing seam to stop
future renewal and cancels pending checkout intents. The Cloud web performs
the provider-side Razorpay cycle-end cancellation before committing the
control-plane deletion request, using the existing customer authorization and
server-only provider adapter. The control plane then records the billing stop,
revokes organization credentials, marks the organization
`deletion_requested`, and starts the configured grace boundary. A provider
failure leaves the request retryable and does not mark the tenant deleted.

While deletion is pending, new paid checkout and plan-change operations are
rejected. Existing paid access and existing tenant reads remain available
during the configured grace period so the customer can resolve ownership or
cancel a pending request. A pending deletion can be cancelled for a Free
organization after strong owner confirmation. Once a paid provider renewal has
been stopped, cancellation is fail-closed until a provider-supported
reversal/reconciliation is available; the system never restores local state
while Razorpay remains cancelled.

## Staged worker

Deletion requests are the durable queue. `processPendingDeletions` selects
due, failed, and previously processing requests; `processDeletion` processes a
bounded batch and may be called again after a crash. The request records track
status, stage, attempt, grace boundary, progress, and safe error codes. The
worker is idempotent: terminal requests are returned unchanged, evidence IDs
are deterministic, artifact cleanup has durable item records, and retries do
not re-run an already completed identity transition.

Organization deletion removes only customer operational records from the
explicit collection allow-list, removes memberships, and tombstones the
organization as `deleted`. Billing, refund, audit, Enterprise, and required
security evidence are outside that erase allow-list. Completed tenants fail
ordinary customer authorization with `ORGANIZATION_DELETED`; this does not
delete or alter Self-hosted deployment data.

Artifact bytes are content addressed. Before an exclusive digest is purged,
the worker records a cleanup item and an anonymized digest/evidence record.
If another tenant still references the digest, only the deleting tenant's
logical artifact record is removed and the shared bytes remain. An exclusive
object is purged through the existing `ArtifactDeletion` seam. A failed object
delete leaves the request retryable and the cleanup item observable.

## Retention classification

The current implementation publishes the following classification through
`deletionRetentionClassification`:

| Data class | Classification |
| --- | --- |
| User profile, email, authentication credentials, sessions | ERASE |
| Memberships, applications, environments, usage events | ERASE |
| Verification/recovery/deletion tokens | TEMPORARY_RETAIN |
| Organization operational content | ERASE |
| Artifact bytes | TEMPORARY_RETAIN |
| Release/patch and deployment/rollback security metadata | ANONYMIZE |
| Immutable audit chain | RETAIN |
| Billing and refund evidence | RETAIN |
| Enterprise commercial evidence | RETAIN |
| Security and abuse events | RETAIN |
| Backups and snapshots | TEMPORARY_RETAIN |

The retained evidence stores a digest of the removed record and bounded
identity such as organization/request/source IDs; it does not copy raw
passwords, tokens, payment credentials, card data, or provider secrets.
Accepted quotes/contracts remain reproducible while contact PII can be
minimized according to the final policy. Payment/refund/provider references
remain available for settlement, reconciliation, disputes, and fraud review.

The repository's artifact policy keeps READY bytes because release and
rollback retention is not yet time-bounded. Organization deletion is the
stronger lifecycle boundary, so its staged worker can purge eligible bytes
only after tenant reference checks and evidence creation. Shared objects are
never purged solely because one tenant was deleted.

## Managed Cloud launch policy

The managed Cloud launch default is a seven-day deletion grace period, set by
the protected deployment value `HYFENS_DELETION_GRACE_PERIOD=7d`. This is a
product/recovery default and does not replace legal/privacy approval of the
customer-facing retention wording. Self-hosted deployments remain explicit:
they may leave the setting unset because Cloud deletion is not exposed there.

## Policy and infrastructure decisions still required

No arbitrary legal duration is embedded in code. A managed deployment must set
`HYFENS_DELETION_GRACE_PERIOD` to the reviewed launch value before requests
can process. The following remain Task 259/legal/infrastructure inputs:

- approved deletion grace period and whether login/undo remains available
  during it;
- billing/financial, security/audit, and Enterprise commercial evidence
  durations;
- backup rotation and when deleted data disappears from immutable snapshots;
- production deletion-mail delivery and notification ownership;
- final Privacy/Terms wording and production publication.

The worker reports failed object cleanup as retryable rather than claiming
completion. Backup systems that do not support per-record erasure must be
described as retained until normal rotation; the product must not promise
instant removal from every historical backup.

## Self-hosted boundary

Cloud privacy requests operate only on the Cloud control-plane tenant and
identity. They never issue remote deletion commands to Self-hosted databases,
artifact stores, credentials, or operator infrastructure. A new signup after
completed personal deletion is a new identity and does not resurrect the old
organization.
