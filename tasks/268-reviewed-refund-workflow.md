# Task 268 — Reviewed refund workflow

Status: [x] Completed — TEST_MODE_VERIFIED; production refund execution remains unauthorized

## Goal

Add a first-class, provider-backed refund process for legitimate billing
exceptions without coupling refunds to cancellation or entitlement changes.

## Scope and Non-goals

In scope:

- captured-payment refund request and decision records;
- authorized operator approval/rejection for full or partial refunds;
- Razorpay refund initiation and status reconciliation;
- captured-balance validation, idempotency, audit events, and retryable failure;
- customer request/status projection if it fits the existing billing workspace.

Out of scope:

- automatic refunds for ordinary cancellation or downgrade;
- tax, accounting, invoices, chargebacks, disputes, coupons, or a finance
  ledger;
- changing the published prices or refund policy without legal/maintainer
  review.

## Owner

Codex, with billing operator and maintainer/legal review.

## Dependencies

- Task 267 lifecycle policy matrix;
- existing Razorpay provider adapter and `billing:provider` service boundary;
- captured payment/provider mapping and immutable audit infrastructure;
- Task 259 policy and production-provider gates.

## Assumptions

- voluntary cancellation/downgrade has no automatic current-period refund;
- only captured payments are refundable;
- partial refunds cannot exceed the remaining captured balance;
- a refund does not implicitly cancel a valid subscription.

## Work Items

- [x] Model request, decision, provider refund, and bounded statuses.
- [x] Add customer request and narrow operator approval/execution surfaces.
- [x] Add idempotent Razorpay refund execution and provider reconciliation.
- [x] Add cross-organization, balance, retry, and entitlement-separation tests.
- [x] Reconcile customer copy with the approved Refund Policy without changing
  legal/CMS text.

## Validation

- `dart format lib/src/billing.dart test/refund_workflow_test.dart`;
- targeted `dart analyze` for billing, HTTP, auth, persistence, service, and
  refund-test files;
- focused control-plane tests: refund workflow, provider bridge, customer
  billing, and Enterprise billing (all passed);
- Cloud web `npm run lint`, `npm run typecheck`, and `npm run build` (all
  passed);
- `git diff --check` in both repositories;
- browser-bundle secret-name scan (clear);
- managed Razorpay TEST acceptance on 2026-09-09: a disposable customer made a
  captured USD 49.00 payment, requested a USD 1.00 partial refund, and an
  authorized platform operator approved it through the Hyfens review route;
  the deployed route returned HTTP 200 with `refunded`;
- Razorpay read-only evidence confirmed one processed USD 1.00 refund against
  that captured payment, and the refreshed customer billing projection showed
  a USD 48.00 refundable balance while Starter remained active;
- read-only live checks: Terms, Privacy, and Pricing returned 200; live
  `/refund-policy` and `/pricing.md` returned 404 and were not changed here.

## Next Action

Keep production refunds disabled until Task 259's production policy,
operational ownership, and live-provider authorization gates are approved.

## Blockers

Production refund execution, public policy deployment, tax, and payment
operations remain Task 259 dependencies. No live refund or live key was used.

## Outcome

Implemented. Customer requests are organization-scoped and limited to
captured payments. Operators with `platform:billing_refunds:manage` approve or
reject exact full/partial amounts. The billing provider service prepares a
server-derived Razorpay attempt and records pending/processed/failed results;
provider failures remain retryable and unresolved attempts reuse the same
idempotency key. Refunds do not cancel subscriptions or alter entitlement
state.

The customer billing workspace includes a request-only flow and the platform
billing workspace includes a narrow review/execution surface. The live
production `https://hyfens.com/refund-policy` check returned HTTP 404 on
2026-09-08; the live `/pricing.md` check also returned HTTP 404. Both are
recorded for Task 259 rather than silently rewriting deployed policy/content.

Post-completion correction (2026-09-09): the managed Razorpay TEST refund
workflow was executed successfully. The initial managed failure was caused by
the Cloud web server module importing `recordValue` from a `use client` auth
module; the helper is now local to the server billing module. This correction
does not change the refund domain or entitlement/refund separation.

## References

- `tasks/267-commercial-lifecycle-refund-retention-deletion.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `docs/research/task-267-razorpay-lifecycle.md`
- `docs/research/task-268-razorpay-refunds.md`
- https://razorpay.com/docs/payments/refunds/issue/
- https://razorpay.com/docs/api/refunds/
- https://razorpay.com/docs/api/refunds/normal-refunds-idempotent/
- https://razorpay.com/docs/webhooks/refunds/

## History

- 2026-09-08 — Reserved from Task 267 audit; current repository has provider
  subscription state but no reviewed refund workflow.
- 2026-09-08 — Implemented captured-payment refund requests, narrow operator
  review, provider execution/reconciliation, customer/operator projections,
  transaction-locked balance reservation, and focused security/idempotency
  coverage. Final verdict is CODE_VERIFIED pending real Razorpay TEST refund
  execution.
- 2026-09-08 — Consolidated backend and Cloud web validation passed; live
  policy/catalog checks exposed the existing production 404 discrepancy.
- 2026-09-08 — Final review preserved unresolved provider attempts on
  transport/ambiguous Razorpay failures, moved idempotent request replay ahead
  of balance recalculation, and added full-refund plus provider-ID-conflict
  coverage. Final focused validation passed.
- 2026-09-09 — Managed TEST acceptance completed for a reviewed partial refund;
  Razorpay reported the refund as processed and the customer projection
  reconciled the reduced refundable balance. Status advanced to
  `TEST_MODE_VERIFIED`; production refunds remain out of scope.
