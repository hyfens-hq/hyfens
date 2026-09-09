# Transactional notifications

Status: CODE VERIFIED — 2026-09-09; managed provider configuration and
mailbox acceptance remain deployment-owned

## Current-state audit

The control plane previously exposed only an injected
`HumanAuthMessageDelivery`/`HumanDeletionMessageDelivery` seam. The managed
implementation called Keplars synchronously from authentication and Enterprise
inquiry code. Billing and Razorpay webhook processing already had durable
provider-event, payment, refund, subscription, audit, and idempotency records,
but no normalized notification event or delivery record. The existing stores
are the File control-plane store and the PostgreSQL JSON-record store; there is
no second queue or audit framework.

The Cloud web uses the same control-plane API and keeps customer billing,
operator billing, Enterprise, and privacy surfaces separate. The sign-in card
used by the customer billing route was rendered without its existing centered
auth-page wrapper; the wrapper is now applied to both customer and platform
sign-in variants.

## Domain boundary

Hyfens owns notification meaning and customer copy. A payment provider can
produce evidence, but it never chooses a Hyfens subject, template, recipient,
plan name, entitlement, or customer-facing state.

```text
authoritative domain mutation
  -> durable Hyfens notification event
  -> recipient/policy resolution
  -> durable per-recipient delivery
  -> notification worker
  -> renderer
  -> provider adapter
  -> normalized delivery state + audit record
```

Razorpay webhooks verify the raw signature, deduplicate and apply billing state
first. Only the normalized `BillingProviderEventResult` is mapped to a
notification key. The webhook does not call an email provider. A validated
provider retry with a duplicate billing event can repair a notification enqueue
that failed after the billing mutation because the notification ID is
deterministic and duplicate billing results are enqueue-eligible.

## Durable records

`notification_events` is the provider-neutral outbox record. Its identity is
derived from the Hyfens key, semantic version, and stable domain consequence.
It stores correlation/causation/provider references and non-sensitive
variables. Authentication and deletion tokens are encrypted with AES-GCM using
the protected 256-bit `HYFENS_NOTIFICATION_PAYLOAD_KEY`; raw tokens are never
stored in the event, audit, log, or provider metadata.

`notification_deliveries` is one record per event/normalized recipient. It
tracks pending, processing, accepted, delivered, failed, bounced, and
complained states, attempt count, retry time, provider message ID, and a
recipient digest. The deterministic delivery ID is sent as the provider
`Idempotency-Key`, so a worker retry does not intentionally create a second
message.

The current dispatcher is a bounded one-shot worker invoked with
`--process-notifications`. It uses exponential backoff, a hard attempt bound,
and a processing lease. The File store serializes claims within one process;
the PostgreSQL store claims due deliveries with a row lock and guarded
compare-and-set update. An expired lease can be reclaimed, while a stale worker
cannot overwrite a newer attempt. Stores that do not implement the claim
contract must run a single worker rather than pretending generic JSON
replacement is a cross-process claim.

## Notification catalogue

All entries are versioned at `v1`, mandatory by default, and use Hyfens keys
rather than Razorpay event names.

| Key | Category | Template | Recipient/purpose |
| --- | --- | --- | --- |
| `auth.registration.completed` | authentication | welcome | verified customer who completed onboarding |
| `auth.email.verification_requested` | authentication | verification code | registering address |
| `auth.password.recovery_requested` | authentication | recovery code | requested account address |
| `auth.password.changed` | security | security notice | account whose password changed |
| `security.new_device_detected` | security | security notice | affected account |
| `organization.member.invited` | organization | invitation | invited member |
| `organization.owner_changed` | security | security notice | affected workspace members |
| `billing.checkout.initiated` | billing | billing summary | verified members with billing visibility |
| `billing.plan_change.requested` | billing | plan change | verified workspace members |
| `billing.plan_change.cancelled` | billing | plan change | verified workspace members |
| `billing.refund.requested` | billing | refund | requesting workspace members |
| `billing.subscription.activated` | billing | billing summary | verified workspace members |
| `billing.subscription.renewed` | billing | billing summary | verified workspace members |
| `billing.payment.succeeded` | billing | billing summary | verified workspace members |
| `billing.payment.failed` | billing | billing warning | verified workspace members |
| `billing.payment.action_required` | billing | billing warning | verified workspace members |
| `billing.subscription.upcoming_renewal` | billing | billing summary | verified workspace members |
| `billing.subscription.upgrade_applied` | billing | plan change | verified workspace members |
| `billing.subscription.downgrade_scheduled` | billing | plan change | verified workspace members |
| `billing.subscription.downgrade_applied` | billing | plan change | verified workspace members |
| `billing.subscription.cancellation_scheduled` | billing | cancellation | verified workspace members |
| `billing.subscription.cancelled` | billing | cancellation | verified workspace members |
| `billing.subscription.reactivated` | billing | billing summary | verified workspace members |
| `billing.refund.initiated` | billing | refund | verified workspace members |
| `billing.refund.completed` | billing | refund | verified workspace members |
| `billing.refund.failed` | billing | billing warning | verified workspace members |
| `account.deletion.requested` | account | destructive notice | verified account owner/address |
| `account.deletion.cancelled` | account | security notice | affected account |
| `account.deleted` | account | destructive notice | affected account/owner |
| `organization.deletion.requested` | account | destructive notice | verified organization owner |
| `organization.deletion.cancelled` | account | security notice | affected organization owner |
| `organization.deleted` | account | destructive notice | affected organization owner |
| `ops.enterprise.inquiry_received` | operational | Enterprise inquiry | configured platform commercial recipients |

The catalogue deliberately does not invent templates for unsupported MFA,
device-management, team-invitation, trial, pause/resume, dispute, or tax
features. If those capabilities are added, they receive new domain events and
catalogue entries rather than reusing a misleading billing key.

## Razorpay mapping

| Razorpay event | Hyfens consequence | Notification |
| --- | --- | --- |
| `subscription.activated` | Provider-confirmed activation | `billing.subscription.activated` |
| `subscription.charged` | Recurring charge captured | `billing.subscription.renewed` |
| `payment.captured` | Captured checkout payment | `billing.payment.succeeded` |
| `payment.failed` / `subscription.payment_failed` | Payment failure recorded | `billing.payment.failed` |
| `subscription.halted` | Provider requires attention | `billing.payment.action_required` |
| `subscription.updated` with a scheduled mapping | Scheduled plan projection updated | `billing.subscription.downgrade_scheduled` |
| `subscription.updated` without a scheduled mapping | Immediate plan update applied | `billing.subscription.upgrade_applied` |
| `subscription.cancelled` / `subscription.completed` / `subscription.expired` | Provider termination recorded | `billing.subscription.cancelled` |
| `refund.created` | Provider refund initiated | `billing.refund.initiated` |
| `refund.processed` | Provider refund processed | `billing.refund.completed` |
| `refund.failed` / `refund.reversed` | Provider refund requires recovery | `billing.refund.failed` |

`payment.authorized` is not treated as a receipt: authorization is not the
same as a captured payment. Unknown provider events remain auditable through
the existing provider-event record but do not create customer email.

The Cloud Razorpay adapter sets `customer_notify: false` when it creates a
Hyfens-managed subscription or confirms a cycle-end plan update. Checkout still
owns the browser authorization surface; the resulting signed provider event is
then normalized into the Hyfens notification catalogue. This prevents a
provider-branded duplicate for covered lifecycle events. New provider flows
must keep provider notifications enabled until their Hyfens event and delivery
path is implemented.

## Sender policy

Sender selection is centralized in `HyfensSenderPolicy`:

| Purpose | From | Reply-To |
| --- | --- | --- |
| automated transactional | `no-reply@hyfens.com` | none |
| support-sensitive billing/account messages | `no-reply@hyfens.com` | `support@hyfens.com` |
| security | `no-reply@hyfens.com` | none |
| human/product relationship | `team@hyfens.com` | none |

Display names are `Hyfens`, `Hyfens Support`, `Hyfens Security`, and
`Hyfens Team`. Transactional or security messages are mandatory and do not
use marketing consent or unsubscribe semantics.

## Email design system

`NotificationRenderer` provides one table-based shell and reusable pieces:

- Hyfens wordmark/text mark and Cloud eyebrow;
- preheader and semantic heading;
- dark primary CTA with a visible fallback URL;
- status/warning/destructive panels;
- billing and plan-change summary tables;
- security metadata block;
- responsive spacing and typography with inline fallbacks;
- plain-text output for every rendered message.

The design is intentionally restrained: warm paper background, white message
panel, near-black type, thin neutral rules, and a single Hyfens orange mark.
The shell uses the canonical Hyfens SVG-derived `brand-mark.png` email asset
with an accessible text fallback; it does not redraw the logo. There are no
image-only calls to action, gradients, or marketing decoration. The renderer
escapes dynamic values, requires HTTPS actions, and permits actions only on the
configured dashboard or marketing origins. Customer-facing dates are rendered
through the shared formatter; canonical UTC storage is shown as a readable UTC
date/time because no reliable workspace timezone is currently available.

## Security and audit

Recipient resolution is server-side from verified active user records and
organization memberships. Browser values never choose a recipient, provider
ID, amount, or billing state. Sensitive auth payloads require the protected
payload key; self-hosted deployments without that key retain the pre-existing
direct delivery seam rather than persisting a raw token.

Each enqueue, provider acceptance, provider callback status, enqueue failure,
and provider event correlation is represented by an immutable audit event with
notification ID, version, recipient digest, provider message/event reference,
correlation ID, and delivery state. Audit records do not contain passwords,
tokens, card data, provider API keys, or full email bodies.

Keplars callbacks may be posted to the authenticated control-plane route
`POST /v1/notifications/webhooks/keplars` with an HMAC over the raw body in
`X-Webhook-Signature: sha256=<hex>`. The route is disabled unless
`KEPLARS_WEBHOOK_SECRET` is configured. Callback states are normalized to
`accepted`, `delivered`, `bounced`, `complained`, `hard_failed`, or
`cancelled` and are audited without allowing out-of-order callbacks to regress
a terminal state.

### Runtime correlation boundary

The Keplars documentation describes a send response identifier in
`data.id` and callback payloads containing `email_id`. The adapter accepts the
documented nested response shape as well as the top-level shape observed in
the existing managed deployment. It correlates callbacks only by the exact
provider message identifier stored on `notification_deliveries`.

Task 273 managed acceptance observed a live send response with a `msg_...`
identifier while the natural callback reported a different `email_id`; a
status lookup using the `msg_...` value returned not-found. The documented
contract currently exposes no metadata/client-reference echo or mapping
operation that safely bridges those identifiers. Until Keplars supplies such a
supported mapping, the delivery remains `accepted` rather than being promoted
to `delivered`. Recipient, subject, timestamp, and message-order heuristics
are explicitly prohibited.

## Provider/configuration contract

The managed process needs `KEPLARS_API_KEY`, and the protected configuration
should set `HYFENS_EMAIL_FROM` only to the approved sender address. Sensitive
queued auth messages additionally need a base64-encoded 32-byte
`HYFENS_NOTIFICATION_PAYLOAD_KEY`. The callback route needs
`KEPLARS_WEBHOOK_SECRET`. `HYFENS_WEB_ORIGINS` supplies HTTPS dashboard and
marketing origins; missing origins fail closed to the approved Hyfens defaults.

The worker command is:

```text
dart run bin/control_plane.dart --process-notifications
```

The command is a one-shot bounded invocation suitable for the existing host
scheduler. It does not replace billing/webhook processing and it never runs a
provider call in the Razorpay request path. The claim lease defaults to five
minutes and is renewed only by completing the guarded delivery update; a
restarted worker safely retries the same delivery ID.

## Safe local preview

The renderer can be exercised without a provider using deterministic fixture
events in `NotificationPreview`. A preview renders HTML and plain text only;
it never creates a delivery or opens an HTTP client. The preview fixture is
intended for local development and automated render tests, not production
customer data.

Provider schema/callback probes are acceptance infrastructure, not customer
notifications. The repository has no general raw-send probe path. Any managed
probe must be explicitly classified as an internal diagnostic, target only an
approved test mailbox, identify its environment and provider, and carry only a
short safe correlation reference. It must not participate in customer
recipient preferences or be used as evidence for customer delivery semantics.

## Operational checklist

Before enabling the managed worker, verify the Keplars sending domain and
SPF/DKIM/DMARC, configure a callback secret if delivery callbacks are enabled,
and run a mailbox acceptance test for verification, recovery, deletion, and a
billing message. Monitor pending/soft-failed/hard-failed/bounced/complained
counts and the provider callback route. Provider retries, webhook retries, and
worker retries must remain observable by their distinct audit/correlation IDs.

## References

- [Razorpay subscription update API](https://razorpay.com/docs/api/payments/subscriptions/update-subscription/)
- [Razorpay subscription notifications](https://razorpay.com/docs/payments/subscriptions/notifications/)
- [Razorpay subscription webhooks](https://razorpay.com/docs/webhooks/subscriptions/)
- [Razorpay payment webhooks](https://razorpay.com/docs/webhooks/payments/)
- [Razorpay refund API](https://razorpay.com/docs/api/refunds/)
- [Keplars skill/provider contract](../../.agents/skills/keplars/SKILL.md)
- [Keplars webhook documentation](https://docs.keplars.com/docs/getting-started/webhooks)
- [Keplars send-email documentation](https://docs.keplars.com/docs/getting-started/send-emails)
