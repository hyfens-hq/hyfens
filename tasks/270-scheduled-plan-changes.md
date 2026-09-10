# Task 270 — Scheduled plan changes and provider transition semantics

Status: [x] Completed — TEST_MODE_VERIFIED; production activation remains unauthorized

## Goal

Complete the customer plan-transition lifecycle with immediate trusted
upgrades and end-of-cycle downgrades/cancellation, while preserving provider
and resource history.

## Scope and Non-goals

In scope:

- customer-visible scheduled downgrade state and effective timestamps;
- Team → Starter/Free and Starter → Free end-of-cycle transitions;
- cancellation of a pending downgrade where provider semantics support it;
- immediate Starter → Team and Enterprise amendment activation after trusted
  payment evidence;
- provider update/proration mapping, concurrency/idempotency, and transition
  audit events;
- customer billing UX for current and scheduled plan state.

Out of scope:

- new prices, limits, quotas, taxes, refunds, or provider replacement;
- immediate downgrade with an implicit refund/credit;
- runtime, rollback, or artifact-retention redesign.

## Owner

Codex, with billing/provider and maintainer review.

## Dependencies

- Task 267 transition matrix;
- Task 257 billing state machine and Task 266 Enterprise contracts;
- Razorpay subscription update/cancellation semantics and TEST MODE
  acceptance;
- existing `billing:manage`, `billing:provider`, audit, and entitlement
  resolver boundaries.

## Assumptions

- upgrades take effect after trusted provider confirmation;
- customer downgrades/cancellation take effect at the current paid cycle end;
- ordinary downgrade/cancellation does not refund the current paid period;
- existing over-limit resources remain and only future constrained growth is
  blocked.

## Work Items

- [x] Add a server-authoritative desired/scheduled plan transition model.
- [x] Implement customer downgrade scheduling and safe cancellation of a
  pending downgrade.
- [x] Map provider update or supersession behavior without two effective paid
  plans.
- [x] Add transition, provider-ordering, concurrency, and over-limit tests.
- [x] Update billing snapshot, UI, audit projection, and lifecycle docs.

## Validation

- `dart analyze` from `packages/control_plane` — passed with no issues.
- `dart test test/billing_provider_bridge_test.dart test/cloud_plan_test.dart
  test/enterprise_billing_test.dart test/customer_billing_test.dart` from
  `packages/control_plane` — 27 tests passed.
- `npm run typecheck`, `npm run lint`, and `npm run build` from
  `hyfens-cloud-web/site` — all passed.
- Built-browser server-only configuration scan — passed; no provider secret,
  webhook secret, billing bridge token, or private API configuration appeared
  in `.next/static`.
- `git diff --check` — passed.
- Real Razorpay TEST MODE evidence — Team → Starter cycle-end scheduling was
  accepted by the provider; the customer remained on Team, “Keep Team”
  cancelled the pending provider update, and no refund was created. A separate
  cycle-end cancellation was accepted while paid access remained active.

## Next Action

Keep LIVE provider activation disabled. Production plan changes remain behind
Task 259 and Task 256B authorization; the managed TEST provider acceptance for
this task is complete.

## Blockers

Production LIVE activation, final policy approval, tax treatment, and customer
workspace cutover remain external dependencies; no pricing change is
authorized.

## Outcome

`CODE_VERIFIED`. Hyfens now has a durable `billing_plan_changes` projection
that distinguishes the current effective plan from a future target and the
provider subscription state. Customer owners can schedule Team → Starter at
the paid-cycle boundary and cancel that pending change; cancellation to Free
uses the same projection while retaining Razorpay's cycle-end cancellation
semantics. The control plane records provider schedule confirmation without
reducing current entitlements, accepts the boundary event only for the still
authoritative mapping, updates the provider mapping after the target becomes
active, and prevents stale scheduled/cancellation state from surviving a new
paid subscription. Existing resources and refund state are untouched.

The customer billing surface now displays current and scheduled state,
effective timing, and the reversible Team → Starter action. Provider failures
remain retryable, repeated requests are idempotent, superseded/late events
cannot reactivate an old target, and lower-plan transitions preserve
over-limit resources while blocking only new constrained growth.

Post-completion correction (2026-09-09): the protected managed Razorpay TEST
environment accepted a real Team → Starter scheduled update and its
provider-supported cancellation. The current Team entitlement remained active
throughout; no ordinary refund was created. Status advanced to
`TEST_MODE_VERIFIED`.

## References

- `tasks/267-commercial-lifecycle-refund-retention-deletion.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `docs/research/task-267-razorpay-lifecycle.md`
- `packages/control_plane/lib/src/billing.dart`
- `hyfens-cloud-web/site/src/components/customer/CustomerBillingWorkspace.tsx`

## History

- 2026-09-08 — Reserved from Task 267 audit; existing cancellation is
  cycle-end, but no customer downgrade operation is exposed.
- 2026-09-08 — Implemented and validated the scheduled-plan projection,
  Razorpay cycle-end update/cancel mapping, customer UI, provider-ordering
  guards, supersession behavior, and focused billing tests. Marked
  `CODE_VERIFIED`; real Razorpay TEST acceptance remains external.
- 2026-09-09 — Managed TEST provider acceptance completed for Team → Starter
  scheduling, Keep Team cancellation, and cycle-end cancellation evidence.
  Status advanced to `TEST_MODE_VERIFIED`; LIVE activation remains
  unauthorized.
