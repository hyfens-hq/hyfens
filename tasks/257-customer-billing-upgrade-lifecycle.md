# Task 257 — Customer billing upgrade lifecycle

Status: [x] Completed — BILLING_STATE_VERIFIED

## Goal

Make Free → Starter → Team a verifiable customer-owned upgrade path that
preserves the existing organization and data, and make Enterprise contact and
paid cancellation behavior explicit.

## Scope and Non-goals

Scope:

- provide a customer-authorized current-plan, usage, and upgrade contract;
- connect Starter and Team checkout intents to verified Razorpay callbacks and
  the existing organization-scoped subscription state;
- preserve Free access through cancelled, failed, delayed, duplicate, or
  incomplete payments;
- verify Starter → Team on the same organization;
- define and implement the approved cancellation/downgrade transition and
  over-limit behavior; and
- provide a credible, durable Enterprise contact path.

Non-goals:

- new plans, prices, quotas, or metering;
- replacing the existing billing provider;
- an Enterprise contracts engine; and
- a second workspace or data migration during upgrade.

## Owner

Codex

## Dependencies

- Tasks 248–254 and Task 255.
- Existing organization-scoped `BillingService`, Cloud billing API, and human
  customer authorization.
- Razorpay plan IDs, amounts, and webhook secret are deployment configuration;
  no provider credentials are stored in the repository.
- The current repository contains the control-plane/dashboard boundary, not
  the separate private Cloud web checkout UI.

## Assumptions

- Provider webhooks remain authoritative for paid transitions; checkout
  creation and browser redirects never activate entitlements.
- Free must never require a paid provider subscription merely to use Cloud.
- A signed provider-event fixture is the strongest available acceptance seam in
  this environment because Razorpay credentials and the private Cloud web
  repository are not available here.

## Work Items

- [x] Add customer-authorized billing read, checkout-intent, incomplete-
  checkout-cancellation, and end-of-cycle-cancellation routes without
  granting operator billing or CMS administration capabilities.
- [x] Verify Free → Starter and Starter → Team transitions on one organization,
  with provider-event idempotency and data preservation.
- [x] Exercise checkout cancellation, payment failure, delayed activation,
  duplicate callbacks, out-of-order callbacks, and provider-unavailable Free
  behavior.
- [x] Implement non-destructive scheduled cancellation and effective downgrade
  to the existing Free assignment, including over-limit admission behavior and
  re-upgrade safety.
- [x] Add a verified Enterprise inquiry route backed by a durable,
  platform-owned inbox.
- [x] Add focused authorization, provider-event, cancellation, isolation, and
  audit-idempotency tests.
- [x] Review the combined task diff and record the provider/UI boundary.

## Validation

Completed:

- `dart format lib/src/billing.dart lib/src/http.dart lib/src/service.dart
  lib/src/domain.dart lib/src/human_auth.dart lib/src/config.dart
  test/customer_billing_test.dart` — passed.
- `dart analyze lib test/customer_billing_test.dart` from
  `packages/control_plane` — passed.
- Focused control-plane/auth/billing tests (`customer_billing_test.dart`,
  `cloud_plan_test.dart`, `customer_onboarding_test.dart`, `config_test.dart`,
  `human_auth_test.dart`, and `human_auth_http_test.dart`) — 38 passed.
- `git diff --check` — passed.

Not run:

- Razorpay test-mode or live checkout: no provider credentials/configuration
  are available in this environment.
- Cloud web typecheck/lint/build or browser billing acceptance: the separate
  `hyfens-cloud-web` project is not present in this repository checkout and
  the current dashboard exposes only the platform entitlement projection.

## Next Action

Wire the private Cloud web checkout/customer billing surface to these routes,
add the outbound Razorpay checkout/cancellation adapter, and verify them with
Razorpay test mode. Task 259 remains responsible for production provider,
email, policy, tax, refund, and operational verification. Task 256B remains
responsible for any customer-workspace production cutover.

## Blockers

No blocker remains for the backend/provider-event verification completed here.
Live Razorpay credentials, outbound provider API wiring, and the private Cloud
web billing UI are external follow-ups required before a test-mode or
production billing verdict.

## Outcome

Completed at `BILLING_STATE_VERIFIED` level. The control plane now exposes an
organization-scoped customer billing contract and keeps operator billing
mutation separate from customer lifecycle actions. Customer owners can read
their own billing state and create/cancel checkout intents; paid entitlements
activate only after a signature-checked, server-mapped provider event.

The signed provider-event fixture verified the same customer-owned
organization moving Free → Starter → Team with unchanged organization,
application, environment, and history records. Failed/cancelled checkout
attempts preserve Free, duplicate and concurrent event delivery is idempotent,
older events cannot regress state, and a late activation cannot revive a
cancelled/failed checkout. Scheduled cancellation retains paid access until a
terminal event, then resolves to the existing Free assignment without deleting
resources; over-limit growth is blocked and preserved resources remain
re-upgradeable. The same customer boundary also rejects foreign-organization
billing access and operator-only subscription mutation.

Enterprise inquiries now have a real public intake route and durable
platform-owned destination. No automatic refund, tax calculation, invoice,
annual billing, outbound Razorpay API call, or private Cloud web UI was
invented.

## References

- `packages/control_plane/lib/src/billing.dart`
- `packages/control_plane/lib/src/http.dart`
- `packages/control_plane/lib/src/domain.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/test/customer_billing_test.dart`
- `docs/architecture/cloud-billing-lifecycle.md`
- `tasks/254-cloud-commercial-launch-readiness-audit.md`

## History

- 2026-09-07: Created from the Task 254 P1 billing and Enterprise-contact
  findings.
- 2026-09-08: Added the customer billing authorization boundary, durable
  checkout intents, signed Razorpay event transition path, cancellation and
  downgrade semantics, Enterprise inquiry inbox, and focused fixture tests.
  Completed at `BILLING_STATE_VERIFIED`; live/test-mode provider checkout and
  the separate Cloud web billing surface remain external follow-ups.
