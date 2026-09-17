# Hyfens Cloud launch gate matrix

Status: NOT READY — reconciled 2026-09-17

This is the current coordinator view of the Cloud launch blockers recovered
from Tasks 259, 266, 269, and 271 and checked against the live public edge. It
does not authorize a production payment, a destructive customer action, or the
`app.hyfens.com` customer-workspace cutover.

## Current verdict

The repository and public edge are operationally healthy enough for continued
TEST work, but the product is not ready for a public paid launch. The missing
items are managed evidence and human/provider decisions, not a justification
for bypassing the existing fail-closed gates.

## Gate matrix

<!-- markdownlint-disable MD013 -->

| Gate | Current evidence | State | Closure owner/action |
| --- | --- | --- | --- |
| Deployment, TLS, health, readiness, and rollback | Current protected deployment is healthy; `/healthz` and `/readyz` return 200; rollback rehearsal is recorded | CODE/MANAGED VERIFIED | Keep the protected wrapper and previous-release evidence current |
| Public policy and pricing routes | `/`, `/pricing`, `/pricing.md`, `/terms`, `/privacy`, `/refund-policy`, `/account-deletion`, and `/api/pricing` return 200 | ROUTE VERIFIED | Maintainer/legal owner must approve the exact catalog and policy references before paid activation |
| Paid billing and webhook | Public catalog reports live paid checkout and overage collection disabled; private Cloud standard TEST capture/refund and signed callback acceptance passed; provider dashboard still rejects edits and six dispute subscriptions remain unsaved | FAIL-CLOSED / NOT LAUNCH-CLOSED | Provider owner must repair dashboard configuration and complete managed dispute delivery; approved LIVE smoke follows legal/tax approval |
| Transactional email | Hyfens-owned verification, recovery, and deletion paths are code-verified; managed mailbox/provider evidence is partial | MANAGED PARTIAL | Prove recovery/deletion completion and monitored owned-mailbox response |
| Enterprise payment | Private contract-bound order/payment safeguards are code-verified; standard managed TEST passed, but Enterprise browser quote-to-activation evidence is not recorded | OPEN IF IN SCOPE | Run the private Cloud Enterprise TEST acceptance runbook, or explicitly defer Enterprise from launch copy/scope |
| Personal and organization deletion | Organization grace/cancellation/staged completion is partially managed-verified; duplicate artifact references are now source-safe; personal deletion is blocked for sole owners pending ownership resolution | MANAGED PARTIAL | Resolve sole-owner product policy, run final personal/no-login acceptance, and prove object/tombstone behavior |
| Backup and restore | Private Cloud Platform Console now controls and verifies a private R2 bucket-lock/lifecycle policy for `operational/` objects at 30 days; no managed scheduled/off-host encrypted recovery, full backend/configuration scope, approved rotation/RPO/RTO, or tombstone replay proof | POLICY VERIFIED / RECOVERY OPEN | Provision the approved destination and schedule, exercise isolated restore, replay deletion tombstones, and record evidence |
| Artifact retention and reconciliation | Managed timer is active and fail-closed smoke passed with no eligible rows | TRIGGER VERIFIED / PHYSICAL PURGE OPEN | Exercise disposable exclusive/shared object rows and reconcile results |
| Operational ownership | Six roles are assigned to `admin@hyfens.com` in the registry | ASSIGNED / MONITORING UNPROVEN | Prove mailbox/alert monitoring and run bounded incident-response drills |
| Tax and evidence retention | Tax treatment and financial/security/Enterprise/backup retention durations are intentionally not selected in code | EXTERNAL POLICY BLOCKER | Accountant/legal/security owners approve jurisdiction, records, durations, and legal holds |
| Production runtime metering | Source safeguards and test vectors pass; production device attestation is not recorded | EXTERNAL ACCEPTANCE BLOCKER | Complete approved Android Play Integrity/iOS App Attest evidence before enabling trusted metering or live overage |
| Customer-workspace cutover | `app.hyfens.com` remains on the legacy OSS dashboard; the current surface still contains stale/unavailable onboarding markers | NOT AUTHORIZED | Obtain separate 256B authorization and cutover plan; do not change this route in task 280 |

<!-- markdownlint-enable MD013 -->

## Live edge check

The non-mutating check used on 2026-09-15 was:

```text
api.hyfens.com/healthz       200 application/json
api.hyfens.com/readyz        200 application/json
hyfens.com/                  200 text/html
hyfens.com/pricing           200 text/html
hyfens.com/pricing.md        200 text/markdown
hyfens.com/terms             200 text/html
hyfens.com/privacy           200 text/html
hyfens.com/refund-policy     200 text/html
hyfens.com/account-deletion  200 text/html
hyfens.com/api/pricing       200 application/json
app.hyfens.com/              200 text/html
```

The public catalog currently reports `live_paid_checkout_enabled: false`,
`live_overage_collection_enabled: false`, and
`trusted_runtime_metering_accepted: false`. A 200 response is route evidence,
not legal approval or payment readiness. The current public payload does not
expose approval metadata, so the authorized reviewer must verify the governed
catalog projection in the Platform Console before changing any launch gate.

## Private Cloud reconciliation

The private Cloud worktree is clean on `feat/billing-launch-safeguards`. Tasks
277–286 record the current source and managed TEST boundary: standard TEST
checkout, capture, signed callbacks, one full refund, and refund reconciliation
passed; Enterprise browser acceptance remains unrecorded. LIVE checkout,
overage collection, and trusted production metering remain disabled.

The Razorpay TEST dashboard currently rejects webhook edits with a JSON decode
error, including a URL-only edit. The existing enabled TEST webhook is
preserved, but six `payment.dispute.*` subscriptions remain unsaved. This is a
provider-console blocker, not a safe reason to alter source gates.

The private operational runbook records only disposable DB/object recovery
evidence. The Platform Console's R2 policy control is deployed and verified
for the private `operational/` scope, but it has no managed backup job,
encryption-key reference, approved schedule/retention beyond that policy,
RPO/RTO owner, isolated restore target, or deletion-tombstone replay evidence.
The private Enterprise acceptance runbook now defines the required tenant-bound
contract, invoice, capture, callback, replay, refund, and negative-case
evidence without performing a mutation.

## External closure checklist

The following items cannot be closed by repository code alone:

1. Configure and evidence encrypted, off-host backup coverage for the complete
   recovery unit, including every data-bearing backend/configuration boundary;
   the verified R2 policy control is not backup-job or restore evidence.
2. Approve backup rotation, RPO/RTO, restore ownership, and the deletion
   tombstone replay procedure; run it against disposable managed data.
3. Decide how a sole owner resolves ownership before personal deletion. The
   current product correctly fails closed and does not invent silent transfer.
4. Complete Enterprise TEST acceptance if Enterprise remains public launch
   scope.
5. Repair the provider dashboard save failure and verify all six dispute
   subscriptions and their managed delivery.
6. Complete production device attestation and the ledger-backed prerequisites
   for any future LIVE paid activation.
7. Assign monitored operational ownership and run response drills for email,
   payments/webhooks, refunds, Enterprise inquiries, deletion/object cleanup,
   and backup/restore.
8. Obtain accountant/legal/security approval for tax treatment, policy text,
   financial/security/Enterprise evidence retention, and backup wording.
9. Separately authorize or defer the `app.hyfens.com` customer-workspace
   cutover.

## References

- [`Cloud launch operations`](cloud-launch-operations.md)
- [`P2 production-readiness runbook`](p2-production-readiness-runbook.md)
- [`Task 259`](../../tasks/259-cloud-launch-operations-and-policy-gates.md)
- [`Task 266`](../../tasks/266-enterprise-quote-contract-payment-lifecycle.md)
- [`Task 269`](../../tasks/269-account-deletion-retention.md)
- [`Task 271`](../../tasks/271-recover-managed-cloud-deployment-and-operational-wiring.md)
