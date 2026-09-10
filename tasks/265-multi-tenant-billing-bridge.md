# Task 265 — Multi-tenant billing bridge and Razorpay TEST environment completion

Status: [-] Blocked — BRIDGE_VERIFIED; protected deployment unavailable

## Goal

Provide a narrow, non-tenant-bound billing-service authorization boundary for
Razorpay provider processing, preserve customer billing isolation, and prepare
the protected TEST deployment for the real Task 261B browser acceptance.

This repository uses task number 265 because task 264 is already reserved by
the existing public control-plane development naming task.

## Scope and Non-goals

In scope:

- explicit billing-provider service authentication;
- dedicated provider subscription-link, provider sync, and webhook routes;
- server-side organization resolution from checkout/provider mappings;
- provider bridge isolation, idempotency, and audit identity tests;
- private-web forwarding changes required by the bridge;
- protected TEST configuration/preflight assessment.

Out of scope:

- pricing, currency, plan limits, or provider selection;
- runtime patching or rollback;
- customer billing UI redesign;
- production Razorpay activation;
- `app.hyfens.com` cutover;
- Task 261B browser payment acceptance when protected deployment access is unavailable.

## Owner

Codex, with maintainer review for protected deployment and service-secret
installation.

## Dependencies

- Task 257 billing lifecycle and existing Razorpay webhook validation;
- Task 261 provider adapter and customer billing surface;
- Task 262/263 TEST plans and protected deployment configuration;
- existing control-plane credential and audit infrastructure;
- private Cloud web repository at `../hyfens-cloud-web`.

## Assumptions

- customer credentials remain organization-bound and continue to authorize
  customer billing routes;
- Razorpay signatures remain authoritative for provider lifecycle transitions;
- the control plane is the authority for checkout, subscription, plan, and
  organization mappings;
- root-owned deployment environment files cannot be changed by the current
  shell user without the documented privileged wrapper.

## Work Items

- [x] Inspect the existing credential, billing, webhook, deployment, and audit
  boundaries.
- [x] Add the explicit billing-provider service principal configuration and
  capability.
- [x] Add dedicated provider bridge routes and server-derived tenant mapping.
- [x] Update private-web provider linking, cancellation sync, and webhook
  forwarding without exposing tenant selection to provider payloads.
- [x] Add focused cross-tenant, scope, idempotency, and self-hosted tests.
- [x] Update billing architecture/runbook and preserve Task 262/261 status
  accurately.
- [-] Validate protected TEST configuration and, only if ready, run Task 261B;
  root-managed deployment configuration is not available to this user.

## Validation

Completed checks:

- focused Dart control-plane billing/auth/http tests;
- focused customer billing, HTTP, Cloud plan, and public onboarding tests;
- `dart analyze` for `packages/control_plane`;
- Cloud web typecheck, lint, and production build;
- static browser bundle secret-safety scan;
- Compose configuration rendering with non-secret placeholders;
- `git diff --check` in both repositories; and
- read-only protected deployment checks without printing secrets.

## Next Action

Install the protected bridge bearer/hash, Razorpay TEST settings, webhook
secret, and provider plan IDs through the root-managed deployment path; restart
the managed Cloud web/control-plane services; then run the Task 262 preflight
and Task 261B acceptance.

## Blockers

The bridge is implemented and locally verified, but protected deployment
changes and real Razorpay TEST browser acceptance require the root-managed
environment installation and deployed managed target. The current SSH user
cannot update `/etc/hyfens/platform-web.env` or the managed control-plane
secret store (`sudo -n` is unavailable), so Task 262 remains
`EXTERNAL_CONFIGURATION_BLOCKED` and Task 261 remains
`BILLING_STATE_VERIFIED`.

## Outcome

`BRIDGE_VERIFIED`. No provider plans, subscriptions, webhook events, database
billing state, production DNS, or `app.hyfens.com` customer-workspace routing
were changed by this task.

## References

- `tasks/257-customer-billing-upgrade-lifecycle.md`;
- `tasks/261-razorpay-checkout-customer-billing-acceptance.md`;
- `tasks/262-provision-razorpay-test-environment.md`;
- `docs/architecture/cloud-billing-lifecycle.md`;
- `packages/control_plane/lib/src/auth.dart`;
- `packages/control_plane/lib/src/billing.dart`;
- `packages/control_plane/lib/src/http.dart`;
- `hyfens-cloud-web/site/src/lib/billing-server.ts`.

## History

- 2026-09-08 — Created as the next available monotonic task number because
  repository task 264 is already reserved for an unrelated naming task.
- 2026-09-08 — Implemented the non-tenant billing-provider principal, hashed
  deployment credential, dedicated provider link/sync/webhook routes,
  server-derived checkout/provider tenant mapping, immutable service audit
  identity, private-web forwarding, deployment-source configuration, and
  architecture/runbook updates. Focused Dart tests, analyzer, Cloud web
  typecheck/lint/build, bundle secret scan, Compose validation, and diff checks
  passed. Protected TEST deployment and Task 261B remain blocked because the
  current deployment user cannot install root-managed environment/configuration.
- 2026-09-08 — Corrected optional deployment parsing so empty billing variables
  keep the default self-hosted Compose deployment disabled rather than making it
  fail at startup. Cloud provider configuration still fails closed unless the
  approved USD currency and `4900`/`19900` minor-unit amounts are supplied.
