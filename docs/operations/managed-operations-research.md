# Managed operations research

Status: source-backed decision input; not legal, tax, or provider-contract
approval.

This note records the external practices reviewed for the Task 259 managed
operations gate. It separates observed provider/platform behavior from Hyfens
recommendations and decisions that still require the maintainer, security,
finance, or legal owner.

## Findings

| Area | Observed facts | Hyfens recommendation | Decision owner |
| --- | --- | --- | --- |
| Email delivery callbacks | Keplars documents stable `email_id` correlation, an optional `reference_id` echoed in callbacks, delivery/bounce/failure events, and HMAC signatures. | Send a Hyfens delivery/reference identifier when the deployed Keplars contract supports it; retain exact-ID-only matching and quarantine unmatched events. Never correlate by recipient, subject, timestamp, or order. | Platform owner and Keplars support |
| Backup/restore and deletion | Keplars describes automated backup/recovery but does not publish Hyfens-relevant RPO/RTO or deletion-tombstone semantics. AWS recommends encrypted, automated backups and periodic isolated recovery tests. | Treat database, object storage, configuration, and deletion/tombstone records as one recovery unit; restore into isolation, replay tombstones before re-exposure, verify ownership/status/digests, and record measured RPO/RTO. | Platform/infra owner; legal/security for exceptions and wording |
| Evidence retention | Provider and SaaS audit systems expose finite/configurable windows; long-lived evidence therefore needs an application-owned export/retention decision. | Retain minimized invoice/refund/chargeback records, provider references/statuses, security events, deletion decisions, and Enterprise/commercial snapshots; use legal holds only when approved. | Accountant for financial/commercial; security for audit; legal for minimization/holds |
| Tax and invoice boundary | Payment gateways automate parts of collection and calculation, but merchant terms and tax authorities keep the merchant responsible for the product invoice, refunds, reconciliation, and tax treatment. | Hyfens must decide GST/IGST, export-of-services, USD pricing, invoice/credit-note responsibility, and tax-inclusive/exclusive wording before LIVE paid launch. Do not treat a gateway receipt or gateway-fee invoice as Hyfens' tax invoice. | Accountant/tax advisor and legal |
| Operational ownership | AWS recommends named resource/process/activity owners, discoverable runbooks, escalation, and tested recovery. Google recommends explicit incident roles and reviewed incident procedures. | Maintain a small platform ownership registry with a role, mailbox, status, and reasoned, audited changes. Link each role to a runbook/signal rather than adding a new incident platform. | Maintainer approves RACI; assigned platform/security/finance roles operate it |

## Current Hyfens decision

Until a different owner is explicitly assigned, the six Task 259 operational
roles are owned by `admin@hyfens.com`:

- `email_delivery`
- `payments_webhooks`
- `refunds`
- `enterprise_inquiries`
- `deletion_object_cleanup`
- `backup_restore`

Changing an owner is a platform operation, not a customer-tenant mutation.
The authenticated platform operator must provide a non-empty reason. The
registry records the actor, role, old and new values, reason, correlation and
causation references, and timestamp through the existing audit system.

## Sources

- [Keplars webhooks](https://docs.keplars.com/docs/getting-started/webhooks)
- [Keplars send emails](https://docs.keplars.com/docs/getting-started/send-emails)
- [Keplars API keys](https://docs.keplars.com/docs/getting-started/setup-api-keys)
- [AWS resources have identified owners](https://docs.aws.amazon.com/wellarchitected/latest/framework/ops_ops_model_def_resource_owners.html)
- [AWS processes and procedures have identified owners](https://docs.aws.amazon.com/wellarchitected/2024-06-27/framework/ops_ops_model_def_proc_owners.html)
- [AWS activities have identified owners](https://docs.aws.amazon.com/wellarchitected/latest/framework/ops_ops_model_def_activity_owners.html)
- [AWS back up data](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/back-up-data.html)
- [AWS periodic recovery testing](https://docs.aws.amazon.com/wellarchitected/2023-10-03/framework/rel_backing_up_data_periodic_recovery_testing_data.html)
- [Stripe customer emails](https://docs.stripe.com/invoicing/send-email?locale=en-GB)
- [Postmark delivery webhooks](https://postmarkapp.com/developer/webhooks/delivery-webhook)
- [Postmark bounce webhooks](https://postmarkapp.com/developer/webhooks/bounce-webhook)
- [Razorpay terms](https://razorpay.com/terms/)
- [CBIC GST invoice rules](https://cbic-gst.gov.in/gst-invoice-rules.html)
- [CBIC account and record rules](https://cbic-gst.gov.in/accnt-record-rules.html)

## Interpretation boundary

These sources support the operational shape and the need for explicit
ownership. They do not approve Hyfens' statutory retention durations, tax
treatment, RPO/RTO, legal wording, or Razorpay production configuration.
