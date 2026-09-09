# Task 273 — Transactional Email and Notification System

Status: [x] Completed

## Goal

Provide Hyfens-branded, provider-neutral transactional notifications with a
durable delivery record, normalized Razorpay event mapping, shared HTML/plain
text rendering, idempotency, and audit traceability. Correct the customer
sign-in layout that currently renders its capped card flush left.

## Scope and Non-goals

Scope is the control-plane notification contract, catalogue, renderer,
Keplars adapter, durable notification event/delivery records, billing webhook
integration, safe authentication-message queue seam, focused tests and
operational documentation. The web change is limited to centering the shared
sign-in card.

This task does not replace the billing state machine, change Razorpay plans or
pricing, add marketing automation, introduce a second queue/audit system, or
perform live provider configuration.

## Owner

Codex, with maintainer review before deployment.

## Dependencies

- Existing `ControlPlaneStore` JSON persistence and audit chain.
- Existing `HumanAuthService`, billing webhook processing, and Keplars API
  configuration.
- Razorpay webhook signature validation remains authoritative.
- Cloud web repository at `hyfens-cloud-web/site`.

## Assumptions

- The deployed email provider is Keplars and accepts the existing raw-email
  request shape.
- Email-provider delivery callbacks are optional; an accepted provider request
  is not treated as final delivery without callback evidence.
- Sensitive authentication tokens may be queued only when encrypted with the
  protected notification payload key; legacy direct delivery remains available
  for self-hosted deployments that have not enabled the queue key.

## Work Items

- [x] Audit current auth, billing, webhook, persistence, audit, email and web
  layout seams.
- [x] Add notification catalogue, sender policy, shared renderer, provider
  abstraction, outbox records, dispatcher and auth queue seam.
- [x] Integrate normalized provider events and customer lifecycle events.
- [x] Add focused security/idempotency/provider/rendering tests.
- [x] Document catalogue, Razorpay ownership, operations and configuration.
- [x] Run consolidated validation and self-review.
- [x] Commit/push the task branches and open reviewable pull requests.

## Validation

Validation completed:

- `dart format` and `dart analyze .` pass for `packages/control_plane`.
- Changed-scope notification, onboarding, billing, refund and deletion tests
  pass, including claim leases, concurrency and provider callback ordering.
- Cloud web typecheck, lint and production build pass.
- `git diff --check` passes.
- The complete Dart suite was attempted; 27 unrelated pre-existing tests fail
  in credential-scope, reconciliation, observation and platform test areas,
  while 34 PostgreSQL/process tests are skipped because their external test
  fixtures are not configured. No changed-scope test fails.
- Static secret review found no live keys, private keys, tokens or card data in
  the task diff.

Managed email/provider acceptance is external to this repository change and
must use the protected TEST environment; no live payment or secret is used.

## Next Action

Maintainer review and merge the task PRs. Configure the protected Keplars
credentials/webhook and run managed mailbox/provider acceptance separately;
this repository task does not claim live delivery or payment evidence.

## Blockers

None at task start. Managed provider delivery and production DNS/provider
configuration remain deployment-owned follow-up gates.

## Outcome

CODE VERIFIED. Hyfens now has a provider-neutral notification catalogue and
renderer, encrypted sensitive-message queueing, durable per-recipient
delivery records, storage-aware claim/lease dispatch, normalized Razorpay
event mapping, authenticated Keplars delivery callbacks, centralized sender
policy, auth/billing/deletion/Enterprise integration, provider-free previews,
documentation, and the shared centered sign-in layout fix. No production
provider configuration, mailbox acceptance, live payment, or live secret was
used.

## References

- `packages/control_plane/lib/src/email_delivery.dart`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/billing.dart`
- `packages/control_plane/lib/src/persistence.dart`
- `packages/control_plane/lib/src/notifications.dart`
- `packages/control_plane/test/notifications_test.dart`
- `docs/architecture/transactional-notifications.md`
- `docs/research/transactional-email-notification-research.md`
- `packages/control_plane/lib/src/http.dart`
- `docs/architecture/cloud-billing-lifecycle.md`
- `https://razorpay.com/docs/api/payments/subscriptions/update-subscription/`
- `https://razorpay.com/docs/webhooks/subscriptions/`
- `https://razorpay.com/docs/payments/subscriptions/notifications/`

## History

- 2026-09-09: Task reserved on `codex/task-273-transactional-notifications`
  and `codex/task-273-billing-ui` after the repository audit. UI root cause
  confirmed as a missing horizontal auto margin.
- 2026-09-09: Completed implementation and changed-scope validation. Full
  suite failures were isolated to pre-existing unrelated tests; managed
  provider/mailbox acceptance remains an external deployment gate.
- 2026-09-09: Hyfens PR opened at
  https://github.com/hyfens-hq/hyfens/pull/3. Companion Cloud-web PR opened at
  https://github.com/hyfens-hq/hyfens-cloud-web/pull/3.
- 2026-09-09: Managed acceptance found that the public control-plane Compose
  service omitted the callback/payload-key variables and the host had no
  notification timer. Added the missing environment mapping and the bounded
  systemd notification worker/timer to the existing deployment package as a
  post-completion correction; managed acceptance remains separate from
  repository code verification.
- 2026-09-09: Runtime acceptance delivered real Hyfens verification, welcome,
  checkout-ready, and recovery messages to the approved TEST mailbox. Keplars
  accepted the sends and reported callback delivery to the deployed endpoint;
  a signed provider-shaped callback for a known Hyfens message reconciled to
  `delivered` and created `notification.provider_status_updated` audit
  evidence. Real Keplars callbacks did not correlate to the send response
  identifier, so final provider callback reconciliation remains blocked on the
  provider identifier contract; no live payment was used.
