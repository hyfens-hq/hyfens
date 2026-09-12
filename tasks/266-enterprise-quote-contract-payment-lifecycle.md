# Task 266 — Enterprise quote, contract, custom entitlements and payment lifecycle

Status: [-] Blocked — Enterprise quote/contract implementation and local validation are complete; managed Razorpay TEST acceptance has not yet run

## Goal

Add a bounded Enterprise commercial workflow that preserves the existing
inquiry funnel and separates immutable quote versions, accepted contract
snapshots, provider mappings, and effective custom entitlements.

## Scope and Non-goals

In scope:

- Enterprise quote and immutable quote-version records;
- narrow operator quote management and authenticated customer quote review;
- explicit quote acceptance and pending-payment contract creation;
- contract-specific Cloud entitlement overrides;
- Razorpay custom-plan/subscription provisioning seams and signed provider
  activation handling;
- cancellation/amendment state boundaries, audit evidence, isolation tests, and
  architecture documentation;
- minimal customer billing and operator workspace integration.

Out of scope:

- changes to Free, Starter, Team, or public Enterprise pricing;
- generic CRM/CPQ, invoicing, tax, discount, or accounting systems;
- offline/invoice settlement, electronic signatures, multi-provider billing,
  production Enterprise payment acceptance, or `app.hyfens.com` cutover;
- runtime patch, rollback, delivery metering, or Self-hosted commercial
  behavior changes.

## Owner

Codex, with maintainer review for protected deployment and Enterprise
commercial policy.

## Dependencies

- existing `enterprise_inquiries` intake;
- Cloud plan/entitlement and organization authorization model;
- Task 265 `billing:provider` service principal;
- existing Razorpay adapter/webhook verification;
- private Cloud web repository at `../hyfens-cloud-web`;
- protected Razorpay TEST configuration for provider acceptance.

## Assumptions

- Initial Enterprise checkout is monthly and provider-confirmed; offline/manual
  activation remains deferred.
- An Enterprise quote is currently associated with an existing organization;
  prospect-to-organization conversion remains a follow-up workflow.
- Enterprise termination falls back to the existing internal Free assignment
  without deleting resources.
- Custom overrides are limited to existing Cloud countable dimensions and do
  not invent Enterprise-only capabilities.

## Work Items

- [x] Inspect existing inquiry, billing, entitlement, authorization, Razorpay,
  audit, and customer/operator workspace seams.
- [x] Add immutable Enterprise quote/version and contract domain state.
- [x] Add operator quote management and customer quote review/acceptance APIs.
- [x] Add contract-backed entitlement resolution and provider lifecycle seams.
- [x] Add customer billing and operator quote workspace integration.
- [x] Add focused authorization, versioning, concurrency, provider-mismatch,
  entitlement, and cancellation tests.
- [x] Update architecture, billing, and task documentation.
- [-] Run real Razorpay TEST Enterprise acceptance in the protected managed
  environment; the acceptance remains unexecuted.

## Validation

Completed affected-scope validation:

- `dart format` on the changed control-plane files;
- `dart test test/enterprise_billing_test.dart
  test/billing_provider_bridge_test.dart test/customer_billing_test.dart`;
- `dart analyze` for `packages/control_plane`;
- Cloud web `npm run typecheck`, `npm run lint`, and `npm run build`;
- static Cloud web bundle scan for server-only provider configuration names;
- `git diff --check` in both repositories.

All local checks pass. The Enterprise suite covers immutable quote versions,
foreign-organization quote isolation, concurrent acceptance, provider-plan and
subscription mapping, custom entitlements, provider mismatch, cancellation,
history, and Self-hosted separation. The existing provider-bridge and customer
billing regressions also pass.

Real Razorpay TEST acceptance will be reported separately from code/provider
fixture evidence. Protected deployment access is now available, but no real
Enterprise TEST payment has been executed or claimed.

## Next Action

Run the real Enterprise acceptance in the existing protected Razorpay TEST
environment: inquiry-linked quote → issue → customer acceptance → custom TEST
Plan/Subscription → signed provider activation. Do not use live credentials or
perform production customer-workspace cutover.

## Blockers

The protected managed Cloud Razorpay TEST environment and webhook are
available, but the real Enterprise checkout/webhook acceptance has not been
run. This blocks closing the managed acceptance item but does not block the
completed local domain/API implementation and automated validation. No
provider or database state was fabricated.

## Outcome

Code-verified. The Enterprise domain, control-plane routes, private Cloud web
customer/operator surfaces, focused tests, and architecture documentation are
complete. Real Razorpay TEST acceptance remains externally blocked.

The implementation remains code-verified while managed Enterprise TEST
acceptance is pending.

## References

- `tasks/257-customer-billing-upgrade-lifecycle.md`;
- `tasks/261-razorpay-checkout-customer-billing-acceptance.md`;
- `tasks/265-multi-tenant-billing-bridge.md`;
- `packages/control_plane/lib/src/public_onboarding.dart`;
- `packages/control_plane/lib/src/billing.dart`;
- `packages/control_plane/lib/src/human_auth.dart`;
- `packages/control_plane/lib/src/enterprise_billing.dart`;
- `packages/control_plane/test/enterprise_billing_test.dart`;
- `hyfens-cloud-web/site/src/lib/billing-server.ts`;
- `hyfens-cloud-web/site/src/app/api/customer-billing/route.ts`;
- `hyfens-cloud-web/site/src/app/api/enterprise-quotes/route.ts`;
- `hyfens-cloud-web/site/src/components/customer/CustomerBillingWorkspace.tsx`;
- `hyfens-cloud-web/site/src/components/platform/EnterpriseQuoteWorkspace.tsx`.

## History

- 2026-09-08 — Reserved as the next monotonic task file and began the
  Enterprise domain/API implementation.
- 2026-09-08 — Completed the Enterprise quote/version, contract snapshot,
  custom entitlement, provider-plan/subscription, customer/operator API and
  workspace implementation. Added mapping-bound provider checks, explicit
  contract-created audit evidence, and focused isolation/lifecycle tests.
- 2026-09-08 — Consolidated validation passed. Real Razorpay TEST acceptance is
  blocked only by protected managed deployment/provider configuration.
- 2026-09-12 — Protected TEST deployment and bridge configuration became
  available, and public Starter/Team/refund acceptance passed in Tasks 261–262.
  The Enterprise task remains blocked solely because its inquiry → quote →
  custom TEST payment → signed activation acceptance has not been executed.
