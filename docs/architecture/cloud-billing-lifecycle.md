# Cloud billing lifecycle

Status: IMPLEMENTED — 2026-09-08; provider settlement remains an external
deployment dependency

This document describes the organization-scoped Cloud billing state machine
implemented in the control plane. It does not change Cloud prices or the
Free, Starter, or Team resource boundaries.

## Ownership and separation

An `Organization` owns the Cloud subscription state. `free`, `starter`,
`team`, and `enterprise` are Cloud plan identities. `self_hosted` is a
deployment model and never enters the Cloud subscription hierarchy.

Free is an internal subscription assignment with
`billingStatus: not_required`. It does not create a Razorpay customer,
subscription, checkout, invoice, or payment requirement. The existing
organization, applications, environments, artifacts, release history, and
audit history are retained through every plan transition.

## Customer authorization

Customer owners receive the separate `billing:manage` capability in addition
to the existing customer read/control surface. They do not receive the
operator-only `billing:write` or CMS administration capabilities.

The customer routes are:

| Route | Purpose |
| --- | --- |
| `GET /v1/organizations/{organizationId}/billing` | Own-organization plan, subscription, checkout, cancellation, usage, limits, and actions |
| `POST /v1/organizations/{organizationId}/billing/checkout` | Create an idempotent server-owned Starter/Team checkout intent |
| `POST /v1/organizations/{organizationId}/billing/checkouts/{checkoutId}/cancel` | Cancel an incomplete checkout without changing the plan |
| `POST /v1/organizations/{organizationId}/billing/plan-change` | Request a supported lower-plan change for the next paid-cycle boundary |
| `POST /v1/organizations/{organizationId}/billing/plan-change/cancel` | Cancel a pending Team → Starter scheduled change |
| `POST /v1/organizations/{organizationId}/billing/cancel` | Request end-of-cycle cancellation for the active paid subscription |
| `POST /v1/billing/webhooks/razorpay` | Apply a signed provider event; this is not a customer-authenticated route |

Tenant authorization is resolved from the authenticated customer membership.
An identifier for another organization is not sufficient to read or mutate
its billing state.

## Paid activation

`POST .../billing/checkout` creates a durable checkout intent using deployment
configuration for the Razorpay plan ID, amount, and currency. It never grants
paid entitlements. A signed Razorpay event must match the server-owned
checkout/subscription mapping, provider plan, amount, and currency before an
active paid subscription is persisted.

The control plane requires an explicit `HYFENS_RAZORPAY_CURRENCY`; it does not
invent a provider currency. The private Cloud web service requires the same
approved `HYFENS_PUBLIC_BILLING_CURRENCY` and currently validates the public
USD catalog prices (`$49` Starter and `$199` Team) before opening checkout. No
INR conversion or browser-selected amount is supported.

The private Cloud web service creates the provider subscription with the
server-owned checkout ID in its notes, then registers the provider ID against
that checkout intent through a dedicated billing-provider service bridge.
Customer owners use `billing:manage`; provider processing uses a separate
deployment principal with `billing:provider`, no organization membership, and
no Platform/CMS capabilities. The bridge accepts a checkout ID only as a
lookup key and the control plane derives the organization, requested plan,
amount, and currency from its own records. It never trusts an organization or
plan selected by the browser or Razorpay payload. Free never contacts
Razorpay.

The provider bridge routes are intentionally separate from customer routes:

| Route | Authority | Purpose |
| --- | --- | --- |
| `POST /v1/billing/provider/checkouts/{checkoutId}/subscription` | `billing:provider` service credential | Link a server-created provider subscription to an existing checkout |
| `POST /v1/billing/provider/subscriptions/{providerSubscriptionId}` | `billing:provider` service credential | Refresh provider metadata for an already-linked subscription |
| `POST /v1/billing/provider/subscriptions/{providerSubscriptionId}/scheduled-change` | `billing:provider` service credential | Record a validated Razorpay cycle-end Plan update without changing current entitlements |
| `POST /v1/billing/provider/webhook` | `billing:provider` service credential plus Razorpay HMAC | Re-verify and apply a signed provider event |

The deployment bearer remains only in the private web environment as
`HYFENS_BILLING_CONTROL_TOKEN`; the control plane stores its lowercase SHA-256
digest in `HYFENS_BILLING_PROVIDER_TOKEN_HASH`. The service principal is not a
`CredentialRecord`, is not tenant-bound, and cannot satisfy ordinary customer,
operator, Platform, or CMS authorization. The provider mapping is durable and
keyed by provider subscription, so retries are idempotent and a provider ID
cannot be attached to another checkout or organization.

The callback path stores only bounded event metadata and a payload digest; it
does not retain the raw webhook body or signature. Provider event IDs are
durable idempotency keys. Concurrent or repeated delivery of the same event
produces one state transition and one provider-event audit record.

An older event is recorded as evidence but cannot regress a newer subscription
state. A late activation for a checkout already cancelled or failed is
ignored and cannot revive the organization into a paid plan.

The repository now contains the bounded outbound adapter and customer billing
surface, but provider credentials, matching plan configuration, webhook
reachability, and settlement-currency approval remain deployment inputs. A
browser callback only starts a refresh; it is not evidence of payment.

### Test-environment provisioning boundary

For managed TEST MODE acceptance, the control plane requires these protected
provider inputs in its own deployment environment:

```text
HYFENS_RAZORPAY_STARTER_PLAN_ID
HYFENS_RAZORPAY_TEAM_PLAN_ID
HYFENS_RAZORPAY_WEBHOOK_SECRET
HYFENS_RAZORPAY_CURRENCY=USD
HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR=4900
HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR=19900
```

The private Cloud web service separately requires its server-only Razorpay
key pair, webhook secret, bridge bearer, and
`HYFENS_PUBLIC_BILLING_CURRENCY=USD`. The bridge bearer is installed only as
`HYFENS_BILLING_CONTROL_TOKEN` in the private web environment; the control
plane receives only its lowercase SHA-256 digest as
`HYFENS_BILLING_PROVIDER_TOKEN_HASH`. The current external webhook boundary is
the private route `https://<cloud-web-origin>/api/billing/webhook`; a direct
control-plane webhook route, if used by the deployment topology, must retain
its own raw-body verification configuration. Provider plan IDs and secrets are
deployment values, not source or browser configuration. The web deployment
wrapper protects its environment at `/etc/hyfens/platform-web.env` with
`root:root` ownership and mode `0600`; the managed control-plane secret-store
location is deployment-owned and is not represented by a repository-local
file.

Before Task 261B, the provider account owner must verify TEST MODE, monthly USD
plan metadata, webhook reachability, bridge connectivity, and web/control-plane
configuration consistency. A connectivity ping is not payment evidence. If
the provider account cannot create the approved USD plans, checkout remains
disabled with `PROVIDER_CURRENCY_BLOCKED`; no INR substitute is permitted.

The initial 2026-09-08 Task 262 check authenticated successfully with the
supplied Razorpay TEST key pair, but the account returned HTTP 400 for the
approved USD Starter plan request. After the merchant enabled International
Payments, the same TEST account created and validated the approved monthly USD
Starter and Team Plans (`4900` and `19900` minor units). No subscription or
Hyfens billing state was created. Task 262 now remains blocked only on the
protected managed-web/control-plane configuration, webhook setup, bridge
installation, and the real Task 261B browser acceptance. The code-level
multi-tenant bridge is tracked in Task 265 because repository task number 264
is already reserved for the public control-plane development naming task.

## Cancellation and downgrade

Customer cancellation is represented as a scheduled cancellation. The active
paid subscription remains effective until a trusted terminal provider event
arrives. The terminal event marks the cancellation effective; effective plan
resolution then falls back to the existing internal Free assignment.

Lower-plan changes are represented by `billing_plan_changes`. The projection
retains the current plan, target plan, provider subscription, target provider
Plan, requested actor, revision, provider schedule, and effective timestamp.
Its bounded states are `pending_provider`, `scheduled`, `cancelled`,
`superseded`, `effective`, and `failed`. Only one pending/scheduled target is
authoritative for an organization; a replacement or cancellation leaves the
previous row intact for history. Until the provider confirms the cycle-end
transition, the effective-entitlement resolver continues to return the current
higher plan.

Abandoned, cancelled, failed, expired, or provider-unavailable checkout
attempts leave the current Free organization usable. A provider outage does
not remove an already persisted active paid state and does not prevent Free
billing reads.

Downgrade never deletes resources. Applications, environments, members,
artifacts, release history, deployment history, rollback state, and audit
evidence remain. The existing entitlement admission checks block only future
creation that exceeds the effective plan's finite limit. Re-upgrading the same
organization makes preserved resources usable again without migration.

## Commercial lifecycle policy matrix

The product policy distinguishes entitlement timing from provider operations
and from refunds:

| Event | Entitlement timing | Billing timing | Refund |
| --- | --- | --- | --- |
| Free → Starter/Team | Immediately after a trusted provider activation event | New provider subscription/charge | No automatic refund |
| Starter → Team | Immediately after a trusted provider activation event | Current implementation provisions the higher provider subscription; provider proration/update semantics remain an acceptance and follow-up concern | No automatic refund |
| Team → Starter | End of the current paid cycle, after Razorpay confirms a cycle-end Plan update | Provider subscription is updated at `cycle_end`; no current-period adjustment | No normal refund |
| Team/Starter → Free | End of the current paid cycle, after the cancellation reaches its trusted terminal state | Renewal is cancelled at cycle end; internal Free assignment becomes effective | No normal refund |
| Paid cancellation | Current paid entitlement remains until the provider-confirmed cycle end | Renewal is cancelled at cycle end | No normal refund |
| Enterprise amendment | Higher accepted contract terms after trusted payment; lower terms at the contract/cycle boundary | Defined by the accepted contract and provider operation | No automatic current-period refund |
| Payment error | Existing valid entitlement remains; a failed new activation does not grant the target plan | Reconcile or retry the provider state | Eligible for separate review where a captured charge cannot be fulfilled |
| Account/organization deletion | Separate privacy lifecycle; it is not cancellation | Stop future renewal as part of the deletion workflow | No automatic refund |

The control plane implements the upgrade, scheduled-downgrade, cancellation,
payment-error, non-destructive-preservation, and reviewed-refund rows. A
scheduled downgrade is a durable projection, not an early entitlement change:
the current paid plan remains effective while the change is pending or
scheduled. Customer cancellation to Free uses the same projection for
observability, but continues to use Razorpay's cycle-end cancellation
operation.

Razorpay supports cycle-end cancellation and scheduled subscription updates;
its update operation accepts `schedule_change_at=cycle_end`, and a pending
scheduled change can be cancelled through the provider's dedicated cancel-
scheduled-changes operation. Hyfens uses that path for Team → Starter and
keeps immediate upgrades separate from end-of-cycle downgrades. The provider's
pending schedule is reconciled into the Hyfens projection, while a later
provider event must match the still-active server-owned change before it can
change effective state. See the [Razorpay cancel subscription
API](https://razorpay.com/docs/api/payments/subscriptions/cancel-subscription/),
[subscription update API](https://razorpay.com/docs/api/payments/subscriptions/update-subscription/),
[fetch pending update details](https://razorpay.com/docs/api/payments/subscriptions/fetch-pending-update-details/),
[cancel scheduled update](https://razorpay.com/docs/api/payments/subscriptions/cancel-update/),
and [subscription update behavior](https://razorpay.com/docs/payments/subscriptions/update/?preferred-country=IN).

## Reviewed refund workflow

Refunds are independent of entitlement, cancellation, downgrade, and account
deletion. A normal cancellation or downgrade stops future renewal at the
appropriate cycle boundary and does not refund the already-paid period. An
account deletion request also does not create a refund.

Only a server-recorded captured Razorpay payment can enter the refund workflow.
The control plane derives the organization, provider payment, captured amount,
currency, previous refunds, and remaining refundable balance from its own
records. A customer with `billing:manage` can submit a request with a bounded
reason and explanation; that request does not approve or execute a refund.

The current bounded state model is:

```text
requested → approved → provider_pending → refunded
     └────→ rejected
provider_pending → failed → provider_pending (retry)
```

Customer and provider/operator surfaces are intentionally separate:

| Surface | Authority | Purpose |
| --- | --- | --- |
| `POST /v1/organizations/{organizationId}/billing/refund-requests` | Customer `billing:manage` | Request review for an own captured payment |
| `GET /v1/platform/billing/refund-requests` | `platform:billing_refunds:read` | Review safe payment/request facts across organizations |
| `POST /v1/platform/billing/refund-requests/{id}/approve` | `platform:billing_refunds:manage` | Approve one exact full or partial amount |
| `POST /v1/platform/billing/refund-requests/{id}/reject` | `platform:billing_refunds:manage` | Reject with an operator reason |
| `POST /v1/billing/provider/refunds/{id}/prepare` | `billing:provider` | Claim a server-derived provider attempt |
| `POST /v1/billing/provider/refunds/{id}/result` | `billing:provider` | Record provider status and evidence |
| `POST /v1/billing/webhooks/razorpay` | Razorpay HMAC | Reconcile signed payment/refund events |

Approval is an operator decision; the billing provider service is only an
execution/reconciliation principal. It cannot choose another organization,
payment, amount, or currency. The transaction lock reserves approved amounts,
so concurrent approvals cannot exceed a payment's captured balance. Provider
attempts carry a deterministic Razorpay `X-Refund-Idempotency` key. An
unresolved attempt reuses that key rather than creating a second refund; a
provider failure remains retryable.

Razorpay supports full and partial refunds only for captured payments, allows
multiple partial refunds while their total remains within the captured amount,
and reports refund processing asynchronously. Hyfens records the provider
refund as pending, processed, or failed and keeps the subscription/entitlement
state unchanged. See the [Razorpay issue a refund API](https://razorpay.com/docs/payments/refunds/issue/?preferred-country=IN),
[refund API reference](https://razorpay.com/docs/api/refunds/),
[idempotent refund requests](https://razorpay.com/docs/api/refunds/normal-refunds-idempotent/?preferred-country=IN),
and [refund webhooks](https://razorpay.com/docs/webhooks/refunds/).

The customer billing workspace exposes “Request refund” only for captured
payments with remaining balance. The platform billing workspace exposes the
narrow review surface only to identities carrying the explicit refund-review
capabilities; it is not general Platform/CMS administration. Payment and
refund webhook projections preserve signed event evidence without storing raw
provider secrets, signatures, or card data.

The domain, HTTP authorization, local transaction/idempotency behavior, and
provider-contract tests are code-verified. A real Razorpay TEST refund was not
executed in this repository validation because the protected managed provider
environment remains an external deployment dependency.

As of 2026-09-08, the production `https://hyfens.com/refund-policy` check
returned HTTP 404 in the audit environment. This is a Task 259 production
policy/deployment discrepancy, not a reason to promise automatic refunds in
the product.

## Retention and deletion boundary

Cancellation and downgrade retain the organization, membership, applications,
environments, releases, patches, artifacts, deployment/rollback history,
billing evidence, Enterprise records, usage evidence, and immutable audit
history. Only future constrained growth is blocked by the effective plan.
READY artifacts have no time-based expiry in the current product, and the
existing quarantine cleanup preserves metadata while protecting shared
content-addressed objects.

Task 269 adds separate account and organization deletion requests. The public
no-login entry point returns a neutral response and sends only a hashed,
purpose-bound, single-use deletion token through the injected deletion-mail
seam. Authenticated requests require the existing customer session, current
password, and an explicit `DELETE` confirmation. A sole owner cannot delete a
personal account until every solely owned organization has another owner or a
separate organization-deletion request.

Organization deletion is owner-only and first stops future renewal through the
billing domain. A deletion request is stored as a durable, bounded worker
record; it is not a synchronous cascade. During the configured grace period,
customer data remains available for recovery and no refund is created. After
the boundary, the worker revokes organization credentials, removes customer
operational records in retryable batches, removes memberships, schedules
content-addressed artifact cleanup with shared-digest protection, and leaves
minimized evidence for audit, billing/refund reconciliation, security, and
Enterprise commercial history. A deleted organization is tombstoned and
ordinary tenant authorization returns `ORGANIZATION_DELETED`.

`HYFENS_DELETION_GRACE_PERIOD` is intentionally required for processing. When
it is absent, verified requests remain `policy_decision_required`; the product
does not invent a 7/14/30-day legal duration. Backup rotation, financial and
security evidence retention, Enterprise record retention, and final policy
wording remain deployment/legal decisions. The deletion taxonomy is:

| Class | Treatment |
| --- | --- |
| User profile, email, credentials, sessions, memberships, usage events | Erase |
| Verification/recovery/deletion tokens, artifact bytes, backups | Temporary retain until expiry/reconciliation |
| Release/patch security metadata | Anonymize |
| Audit chain, billing/refund evidence, Enterprise commercial evidence, security/abuse events | Retain |
| Organization operational content | Erase in staged processing |

The account and organization privacy surfaces are separate from billing. A
customer can request account deletion at `/account-deletion` without a
session, or use `/dashboard/privacy` after signing in. The Cloud web
organization-deletion path authorizes the owner first, stops Razorpay renewal
through the existing provider adapter, then commits the control-plane request.
The control plane never trusts a browser-selected tenant for deletion and
does not let a pending deletion start a new paid checkout or plan change.

Self-hosted deployments do not expose Cloud organization deletion or billing;
deleting a Cloud identity never remotely deletes Self-hosted data. See
`docs/architecture/account-deletion-retention.md` for the full lifecycle and
retention boundary.

Account deletion must remain visibly separate from subscription cancellation in
customer copy and product design. A cancellation stops future renewal; it does
not erase customer data. A deletion request must be verified and must not
orphan an organization or silently transfer its ownership.

## Upgrade and provider event ordering

The supported Cloud progression is:

```text
Free → Starter → Team → Enterprise/contact
```

An active provider subscription takes precedence over the internal Free row.
When a higher paid subscription becomes active, the prior active Razorpay row
is marked `superseded`; the organization and all customer-owned resource IDs
remain unchanged. Self-hosted is not a downgrade target or provider SKU.

## Audit and Enterprise contact

Customer checkout and cancellation actions use the immutable audit chain.
Verified provider transitions record event ID, plan/subscription status, and
provider identity without payment secrets. Enterprise inquiries are accepted
through `POST /v1/public/enterprise-inquiries` into the durable,
platform-owned `enterprise_inquiries` inbox and are readable only through the
platform account projection. This is a real owned destination, not a fake
calendar or response-time promise; outbound email/CRM delivery is deferred.

Tax calculation, invoices, annual billing, and customer-facing provider
management remain policy/operations work. The reviewed refund workflow is
implemented and code-verified; real Razorpay refund settlement remains an
external protected-environment acceptance step. No unsupported tax claim is
made by the control plane.

## Enterprise quote and contract lifecycle

Enterprise keeps the single public Cloud plan key `enterprise` and the public
pricing label `Custom`; it is not a fixed catalog SKU. The existing
`enterprise_inquiries` collection is the sales-funnel entry point. For the
initial workflow, an authorized commercial operator associates an inquiry with
an existing Cloud organization and creates a quote.

The commercial records are deliberately separate:

| Record | Authority and purpose |
| --- | --- |
| Enterprise quote | Stable commercial proposal identity and current version pointer |
| Quote version | Immutable issued/accepted terms: currency, integer minor-unit amount, monthly interval, term/cycle count, optional upfront amount, customer notes, and typed current entitlement limits |
| Enterprise contract | Accepted quote-version snapshot, contract status, provider mapping, and effective custom entitlement snapshot |
| Razorpay Plan/Subscription | Provider execution and payment evidence only; never the source of Hyfens terms |

Quote versions use draft, issued/viewed, accepted, rejected, expired,
withdrawn, and superseded states. Issued terms are never edited in place.
Revising an issued quote creates a new draft version; revising an accepted
quote leaves the accepted version attached to its existing contract and starts
an amendment draft. Acceptance is bound to the current version and uses
server time, so an expired or superseded version cannot be accepted. Customer
projections omit internal notes and provider identifiers.

The control-plane surfaces are separated by authority:

| Surface | Authority | Purpose |
| --- | --- | --- |
| `/v1/platform/enterprise-quotes` | `platform:enterprise_quotes:read/manage` | Operator list, create, issue, revise, and withdraw |
| `/v1/organizations/{organizationId}/billing/enterprise-quotes/{quoteId}` | Customer `billing:read`/`billing:manage` | Own-organization quote review, acceptance, or rejection |
| `/v1/billing/provider/enterprise-contracts/*` | `billing:provider` | Link a server-created provider Plan/Subscription and sync provider state |

An accepted quote creates a `pending_payment` contract. The customer cannot
choose its amount, currency, interval, term, provider Plan, or entitlement
limits. The private Cloud web adapter resolves the immutable contract,
creates a dedicated monthly Razorpay Plan only after acceptance, creates a
Subscription against that Plan, and links the provider identifiers through
the billing-provider bridge. The bridge derives organization and commercial
terms from the contract; it does not trust organization IDs or prices from a
browser or provider payload.

The initial accepted currency is USD, represented in integer minor units, and
the initial interval is monthly. An optional upfront/setup amount is kept
separate from the recurring amount and is sent as a Razorpay subscription
add-on when the provider path is enabled. Annual billing, invoice/PO or other
offline settlement, tax calculation, electronic signatures, and complex sales
approvals are deferred.

Only a validated signed Razorpay event can move a contract to `active` and
make `effective_plan = enterprise`. Entitlement resolution uses the Enterprise
base plan plus the contract's typed overrides for the existing application,
environment, and member dimensions. Pending payment never grants those
limits. A later active amendment supersedes the prior active contract without
changing customer resource IDs or historical records.

Cancellation is represented as requested/scheduled first; paid access remains
effective until a trusted terminal provider state. Initial termination falls
back to the internal Cloud Free assignment, preserving applications,
environments, artifacts, release/deployment history, rollback state, and
audit evidence. Provider outage or abandoned payment preserves the accepted
quote/contract for retry and does not grant Enterprise prematurely.

Enterprise audit records distinguish commercial operator/customer actions
from billing-service provider processing, including quote creation/issue/
revision/withdrawal, customer acceptance/rejection, contract creation and
activation, and cancellation transitions. Cross-organization quote reads,
acceptance, provider-plan/subscription mismatches, and customer access to
operator/provider surfaces are rejected by the existing authorization and
server-owned mapping checks.

The domain/API and local provider-contract tests are code-verified. Real
Razorpay Enterprise checkout/webhook acceptance remains a protected managed
TEST-environment activity and is not claimed by this repository change.
