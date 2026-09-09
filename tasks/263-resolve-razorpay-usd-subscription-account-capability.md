# Task 263 — Resolve Razorpay USD Subscription Account Capability

Status: [x] Completed — PROVIDER_CURRENCY_ENABLED

## Goal

Determine the account-level Razorpay enablement required for Hyfens Cloud to
create and charge the approved monthly USD Starter and Team Subscription
Plans. Preserve the existing Hyfens billing implementation and commercial
model.

## Scope and Non-goals

Scope:

- capture and classify the real Razorpay TEST API rejection;
- inspect merchant activation, website review, product, and webhook state;
- verify current official Razorpay guidance for international Subscriptions;
- audit Hyfens public-site prerequisites for provider review; and
- prepare the exact account-owner enablement action and truthful support text.

Non-goals:

- changing Hyfens prices, currency, plan limits, or billing architecture;
- creating INR plans or applying exchange-rate conversion;
- submitting an account-activation/support request without explicit account-owner
  authorization;
- adding another payment provider or a payment-link workaround;
- configuring production credentials, subscriptions, webhooks, or DNS; and
- running Task 262/261B before provider capability is enabled.

## Owner

Codex, with the Razorpay merchant/account owner responsible for provider
activation.

## Dependencies

- Task 262's supplied Razorpay TEST credentials and protected deployment plan.
- Razorpay merchant-owner access to submit website/app details and request
  International Payments/Subscription enablement.
- A verified public Contact Us destination if Razorpay requires one during
  website review.

## Assumptions

- Hyfens pricing remains Starter USD `$49/month` and Team USD `$199/month`.
- Razorpay's documented international Subscription path is card-based; UPI
  and eMandate restrictions remain provider rules, not Hyfens plan changes.
- Provider settlement currency does not change the customer-facing Hyfens
  currency.

## Work Items

- [x] Inspect Task 262, the Hyfens billing adapter, public-site requirements,
  and current Razorpay account/dashboard state.
- [x] Re-run one safe TEST MODE `POST /v1/plans` diagnostic using the supplied
  local CSV credentials without printing credentials.
- [x] Capture safe provider error metadata and classify the rejection.
- [x] Verify official Razorpay documentation for international Subscription
  currencies, payment methods, settlement, and website review.
- [x] Inspect TEST MODE activation, website/app details, Plan, Subscription,
  and webhook surfaces without submitting account changes.
- [x] Verify live Hyfens product, pricing, policy, and contact/support routes.
- [x] Prepare the provider enablement checklist and support-request text.
- [x] Confirm merchant website/account review and International Payments
  enablement — the merchant reported the capability enabled and the real TEST
  API subsequently accepted the approved USD plan requests.
- [x] Recreate/validate USD TEST Plans after account enablement.
- [x] Hand off protected deployment configuration and Task 261B acceptance to
  Task 262; no billing implementation changes are required here.

## Findings

### API rejection

Using the supplied local TEST credential CSV in memory, the diagnostic request
was:

```text
POST https://api.razorpay.com/v1/plans
period=monthly
interval=1
item.currency=USD
item.amount=4900
```

Razorpay returned only the following safe metadata to the audit output:

```text
HTTP status: 400
error code: BAD_REQUEST_ERROR
description: Currency provided is not supported
field: currency
```

The preceding Plan read returned HTTP 200 with zero Plans. A final read after
the rejected request also returned HTTP 200 with zero Plans. No provider Plan
was created, and Team creation was not attempted.

### Post-enable result

After the merchant reported International Payments enabled, the supplied TEST
credentials authenticated successfully and the real Razorpay API created and
read back exactly two monthly USD Plans: Starter at `4900` minor units and Team
at `19900` minor units. This confirms the provider/account capability required
by Hyfens. No subscription or payment was created.

### Merchant capability

The open Razorpay Dashboard was visibly in TEST MODE. Activation details show
`Account Access Limited`: only Payment Links and Invoices are available until
the merchant provides a website/app link for access to APIs and products such
as Subscriptions.

The Website/App page shows no submitted website/app and provides an `Add
website/app` review path with a stated 24–48 hour verification period. The
Subscriptions page shows zero Subscriptions and the Plans page shows zero
Plans. The Plan form presents INR as the currency. No Dashboard form was
submitted.

### Official provider support

Current official Razorpay documentation says:

- Subscription payments can use supported international currencies;
- USD is listed as a supported international currency;
- only cards support international currencies for Subscriptions;
- UPI and eMandate are INR-only for this Subscription configuration; and
- settlements for international payments to an Indian Razorpay account are in
  INR.

Razorpay's international-payments guidance says enablement is requested from
Razorpay Support or a dedicated sales point of contact. Its website/app review
guidance requires a live, functional site and identifies Terms and Conditions,
Privacy Policy, Shipping Policy, Contact Us, and Cancellation and Refunds as
pages to have available for review.

References: [Subscription FAQs](https://razorpay.com/docs/payments/subscriptions/faqs/?preferred-country=IN),
[International Payments FAQ](https://razorpay.com/docs/payments/international-payments/faqs/?preferred-country=IN),
[International Payments](https://razorpay.com/docs/payments/international-payments/?preferred-country=IN),
[Business Website Details](https://razorpay.com/docs/payments/dashboard/account-settings/business-website-details/?preferred-country=IN),
and [Create Plan API](https://razorpay.com/docs/api/payments/subscriptions/create-plan/?preferred-country=IN).

### Hyfens public-site readiness

Read-only HTTPS checks returned 200 for `/`, `/product`, `/pricing`,
`/terms`, `/privacy`, `/refund-policy`, and `/self-hosted`. The live surfaces
contain the current Hyfens product description, USD Cloud pricing, separate
Self-hosted positioning, Flutter support messaging, and policy pages.

`/contact` and `/support` currently return 404. The repository also has no
verified public Contact Us destination. This is recorded as a provider-review
prerequisite gap; no unrelated public-site change was made in this task.
Shipping is not applicable to Hyfens' software-only SaaS offering, but the
merchant owner should follow Razorpay's review form if it requires an explicit
not-applicable selection or page.

## Payment-method implications

Once enabled, the approved USD recurring path should be presented through
Razorpay's international card flow. UPI and eMandate should not be advertised
for these USD Subscription Plans because Razorpay documents those methods as
INR-only. Razorpay may settle an Indian merchant's international receipts in
INR, but that does not authorize Hyfens to change its USD customer price or
send a converted amount.

No checkout change was made before account enablement is confirmed.

## Enablement Checklist

The Razorpay merchant/account owner must:

1. In TEST MODE, open `Account & Settings → Business website detail → Add
   website/app` and submit the live Hyfens website/app details for review.
2. Resolve or explicitly explain the missing Contact Us destination during
   that review. Do not claim a support route that does not exist.
3. After website/account review, ask Razorpay Support or the dedicated sales
   contact to enable International Payments for Razorpay Subscriptions and
   USD card-based recurring payments for this merchant account.
4. Confirm the account can create monthly USD Plans at 4900 and 19900 minor
   units. Then rerun Task 262; do not change Hyfens pricing or create INR
   Plans.

The Dashboard's current account status indicates that website/app review is
the first concrete gate. The support request should also ask Razorpay to
confirm any KYC/compliance or product-activation requirements rather than
assuming that approval is automatic.

## Prepared Support Request

This text is prepared only; it was not submitted:

> Subject: Enable International Payments for USD Razorpay Subscriptions
>
> Hello Razorpay Support,
>
> Please review our merchant account for International Payments and USD
> recurring Razorpay Subscriptions. Hyfens is a developer platform for
> securely delivering verified Flutter application patches and managing mobile
> release workflows. Hyfens Cloud is a recurring SaaS service for software
> developers and engineering teams; no physical goods or financial services
> are provided.
>
> Our approved monthly Cloud plans are Starter at USD $49/month and Team at
> USD $199/month. We need to create the corresponding Razorpay Subscription
> Plans in USD and accept international card payments. The TEST API currently
> rejects a monthly USD Plan request with `BAD_REQUEST_ERROR` and
> `currency: Currency provided is not supported`; the TEST Dashboard also
> shows limited account access and an INR plan form.
>
> Website: https://hyfens.com
> Pricing: https://hyfens.com/pricing
> Terms: https://hyfens.com/terms
> Privacy: https://hyfens.com/privacy
> Refund/cancellation information: https://hyfens.com/refund-policy
>
> Please confirm the required KYC, website review, international-payment,
> Subscription, payment-method, and settlement prerequisites for this account,
> and advise how to enable USD recurring card payments in TEST MODE before
> production activation.

The merchant owner must replace any provider-form placeholders with the legal
business name and approved contact details. No revenue, volume, customer
count, certification, or country claims were invented. The provider enablement
request is now superseded by the successful TEST USD Plan creation; protected
deployment configuration remains tracked by Task 262.

## Validation

- Supplied CSV read safely: one row, both fields present, TEST key prefix
  validated; no credential value printed or persisted.
- Razorpay TEST API authentication: payment, Plan-list, and Subscription-list
  reads returned HTTP 200.
- One approved USD Starter Plan diagnostic: HTTP 400 with safe
  `BAD_REQUEST_ERROR` / unsupported `currency` metadata.
- Final Plan read: HTTP 200, zero Plans, no Starter or Team match.
- Razorpay Dashboard inspection: TEST MODE, account access limited, no
  website/app submitted, zero Plans/Subscriptions, INR Plan form, no form
  submission.
- Post-enable Razorpay TEST API check: exact monthly USD Starter and Team Plans
  created and read back with amounts `4900` and `19900` minor units.
- Live Hyfens HTTPS checks: product/pricing/policy/self-hosted routes 200;
  contact/support routes 404.
- No account setting, provider Plan, Subscription, webhook, Hyfens billing
  state, production credential, DNS, or `app.hyfens.com` change was made.

## Next Action

The provider capability is now enabled and the two approved USD TEST Plans are
validated. Continue with Task 262 to configure protected Hyfens values and
then run Task 261B. Do not submit credentials through chat.

## Blockers

- Task 262 still needs protected Hyfens deployment configuration, webhook
  registration/secret, bridge authorization, and browser acceptance.

## Outcome

Razorpay's USD recurring-Plan capability is now enabled for the TEST account:
the approved Starter and Team Plans were created and validated through the
real provider API. No Hyfens pricing or currency workaround was used. Task 262
continues for protected deployment configuration and Task 261B acceptance.

## References

- `tasks/262-provision-razorpay-test-environment.md`
- `tasks/261-razorpay-checkout-customer-billing-acceptance.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `hyfens-cloud-web/docs/HYFENS_CLOUD_BILLING_V1.md`
- `hyfens-cloud-web/deploy/web/README.md`
- [Razorpay Subscription FAQs](https://razorpay.com/docs/payments/subscriptions/faqs/?preferred-country=IN)
- [Razorpay International Payments](https://razorpay.com/docs/payments/international-payments/?preferred-country=IN)
- [Razorpay Business Website Details](https://razorpay.com/docs/payments/dashboard/account-settings/business-website-details/?preferred-country=IN)

## History

- 2026-09-08: Created from Task 262's `PROVIDER_CURRENCY_BLOCKED` result.
- 2026-09-08: Captured the real TEST API rejection, inspected Dashboard
  activation/website/Plan/Subscription/webhook state, checked official
  provider guidance, and verified Hyfens public routes. No provider-account
  request or workaround was submitted.
- 2026-09-08: Provisioned one disposable customer-owner reviewer fixture with
  the generic `test-review` profile and stored its credential record outside
  the repository under protected permissions. The real public P2 login was
  verified successfully. No second reviewer account, provider state, or
  Razorpay submission was created.
- 2026-09-08: Rotated the disposable reviewer password to an exactly 12
  character value at the account owner's request and reverified the live P2
  customer login successfully. The password value remains only in the
  protected external credential file.
- 2026-09-08: Removed provider-specific naming from the disposable remote
  scope: the organization is now `Hyfens Test Review` and the runtime
  application identity is `com.hyfens.test.review`; stable record IDs were
  preserved and a remote search found no remaining provider-specific fixture
  label.
- 2026-09-08: Rotated the existing platform `super-admin` and
  `content-admin` password hashes to exactly 12 character values and stored
  their credential record outside the repository under protected permissions.
  The content-admin customer login succeeds; the super-admin platform login
  is rejected by the deployment's separate platform-email allowlist, not by
  the password hash. No platform privilege was broadened.
- 2026-09-08: After the merchant reported that the website was verified, one
  bounded real TEST API recheck still rejected the approved USD Starter plan
  with HTTP 400 `BAD_REQUEST_ERROR` (`currency: Currency provided is not
  supported`). No plan was created and Team was not attempted. This narrows the
  remaining provider action to International Payments/USD recurring-
  Subscriptions enablement; no pricing workaround or account mutation was
  submitted.
- 2026-09-08: The merchant reported International Payments enabled. A real
  TEST API run using the supplied local key CSV created and read back exactly
  two monthly USD Plans with the approved amounts (`4900` and `19900` minor
  units). Task 263 is complete at `PROVIDER_CURRENCY_ENABLED`; protected
  deployment and browser acceptance continue under Task 262/261B.
