# Task 261 — Razorpay checkout and customer billing acceptance

Status: [x] Completed — BILLING_STATE_VERIFIED

## Goal

Connect the private Hyfens Cloud customer workspace to the existing
organization-scoped billing lifecycle and Razorpay adapter so a normal
customer can initiate and confirm Starter/Team checkout, request cancellation,
and submit an Enterprise inquiry without platform or CMS privileges.

## Scope and Non-goals

Scope:

- add a customer-only billing API boundary around the existing control-plane
  customer billing routes;
- connect server-owned checkout intents to outbound Razorpay subscriptions and
  existing signed webhook activation;
- connect end-of-cycle cancellation to Razorpay;
- provide the minimum private customer billing UI and authoritative pending
  payment refresh behavior;
- connect the public Enterprise inquiry UI to the durable intake route; and
- document provider configuration, currency safety, and test/live boundaries.

Non-goals:

- changing prices, plan limits, metering, quotas, runtime delivery, rollback,
  self-hosted semantics, or app.hyfens.com routing;
- replacing the Task 257 billing state machine;
- automatic refunds, tax calculation, invoices, annual billing, or Enterprise
  contracts; and
- claiming Razorpay test-mode or production acceptance without provider
  evidence.

## Owner

Codex

## Dependencies

- Tasks 255–260 and the existing `BillingService` customer billing contract.
- Main control-plane repository and private `hyfens-cloud-web` repository.
- Razorpay plan IDs, API credentials, webhook secret, and an explicitly
  approved settlement currency supplied through deployment configuration.

## Assumptions

- Provider webhooks remain authoritative for paid entitlements; browser
  callbacks only start confirmation polling.
- `billing:manage` is the customer boundary; `billing:write` remains an
  operator/platform capability.
- The public catalog currently represents Starter/Team as USD prices while the
  control-plane default provider currency is INR. The adapter must fail closed
  until deployment configuration explicitly resolves that mismatch.

## Work Items

- [x] Inspect the current billing state machine, provider adapter, customer
  session, private web route, and deployment configuration.
- [x] Add customer-scoped checkout, cancellation, and provider reconciliation
  operations with idempotent checkout/provider linkage.
- [x] Add the private customer billing workspace and preserve the platform
  billing setup surface separately.
- [x] Connect Enterprise inquiry form submission to the durable control-plane
  intake route.
- [x] Update provider configuration/runbook and billing lifecycle documentation.
- [x] Run focused control-plane and Cloud web validation, then attempt the
  strongest available Razorpay acceptance without fabricating provider state.

## Validation

Completed:

- focused Dart billing/configuration tests;
- Cloud web typecheck, lint, production build, and `git diff --check`;
- provider-adapter contract checks through the control-plane fixture and
  browser-safe static bundle scan; and
- Razorpay test-mode browser acceptance was attempted but could not run because
  this environment has no Razorpay credentials, provider plan IDs, webhook
  secret, control-plane bridge token, or approved deployment configuration.

## Next Action

Provision the protected Razorpay test-mode configuration and matching USD
provider plans, then run the manual customer browser acceptance against a
reachable HTTPS webhook. Do not promote the current result beyond
`BILLING_STATE_VERIFIED` without that evidence.

## Blockers

Razorpay test-mode credentials, provider plan IDs, webhook reachability,
control-plane bridge authorization, and protected `HYFENS_PUBLIC_BILLING_CURRENCY=USD`
are not present in this environment. They must be supplied through deployment
configuration; no provider state was fabricated.

## Outcome

Implemented. The private customer surface now uses a customer-only billing
route, creates server-owned Razorpay subscriptions from the organization
checkout intent, registers the provider identity through the protected control
plane bridge, polls only authoritative billing state after browser checkout,
and calls Razorpay for end-of-cycle cancellation. The provider callback and
webhook paths remain server-authoritative. Customer billing responses expose
only the browser-safe key, provider subscription ID, plan summary, mode, and
status projection; bridge tokens and provider secrets remain server-only.

The current result is intentionally `BILLING_STATE_VERIFIED`, not
`TEST_MODE_VERIFIED`: compilation and fixture evidence passed, but a real
Razorpay test-mode payment could not be attempted without deployment
credentials and webhook configuration.

## References

- `tasks/257-customer-billing-upgrade-lifecycle.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `packages/control_plane/lib/src/billing.dart`
- `hyfens-cloud-web/site/src/lib/billing-server.ts`
- `hyfens-cloud-web/site/src/app/api/billing/route.ts`
- `hyfens-cloud-web/site/src/app/api/customer-billing/route.ts`
- `hyfens-cloud-web/site/src/components/customer/CustomerBillingWorkspace.tsx`
- Razorpay subscription API and webhook documentation.

## History

- 2026-09-08: Reserved for the provider adapter, customer billing UI, and
  Razorpay test-mode acceptance gap identified by Task 257.
- 2026-09-08: Implemented the provider/customer boundary, explicit USD
  configuration guard, retry-safe checkout linkage, customer billing UI,
  Enterprise inquiry intake, runbook updates, and focused validation. Provider
  acceptance remains pending protected Razorpay test-mode configuration.
- 2026-09-08: Continued the external-acceptance preflight. Razorpay mode and
  credentials, provider plan mapping, webhook secret/reachability, control-plane
  bridge authorization, and approved USD deployment configuration were all
  missing from the protected environment. No provider or billing state was
  mutated. Re-ran the focused analyzer/tests and Cloud web lint, typecheck, and
  production build successfully; the result remains
  `BILLING_STATE_VERIFIED` until real Razorpay TEST MODE configuration is
  provisioned.
