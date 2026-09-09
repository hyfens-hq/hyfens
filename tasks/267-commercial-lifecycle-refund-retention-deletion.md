# Task 267 — Commercial lifecycle, refund policy, plan changes, retention and account deletion

Status: [x] Completed — lifecycle audit reconciled, bounded corrections validated, and follow-up work handed off

## Goal

Audit and, where small and unambiguous, complete the coherent Cloud customer
lifecycle for upgrades, downgrades, cancellation, refunds, retention, account
deletion, organization deletion, Enterprise amendments, and related policy
copy. Preserve the existing plan, billing, provider-bridge, entitlement,
artifact, and Self-hosted architectures.

## Scope and Non-goals

In scope:

- independent audits of billing transitions, refunds, retention/deletion,
  deletion security, policy consistency, and edge cases;
- one reconciled lifecycle and refund policy matrix;
- small evidence-backed fixes to existing customer/operator flows;
- first-class deletion/refund work only where the current architecture already
  provides the required safe primitives;
- focused tests and documentation updates.

Out of scope:

- changes to public prices, plan limits, metering, runtime/rollback, or
  Cloud/Self-hosted separation;
- tax, accounting, invoicing, chargebacks, generic CRM, multi-provider billing,
  universal export, or a broad privacy-management platform;
- guessed legal policy, unsupported refund promises, or production provider
  activation.

## Owner

Codex, with maintainer/legal review for policy decisions and production
provider/deployment actions.

## Dependencies

- Tasks 257, 259, 261, 265, and 266;
- existing billing, Enterprise, artifact lifecycle, audit, authentication,
  recovery, and protected deployment mechanisms;
- current official Razorpay documentation for subscription updates,
  cancellation, and refunds.

## Assumptions

- ordinary paid cancellation and downgrade stop future renewal at cycle end;
  they do not refund the already-paid period;
- upgrades become effective after trusted provider confirmation;
- existing data remains preserved after cancellation/downgrade;
- unresolved legal, tax, retention-duration, or deletion-grace choices are
  surfaced rather than invented.

## Work Items

- [x] Run six independent lifecycle/policy audit workstreams and reconcile the
  findings. Six GPT-5.6 Luna Max/Fast read-only scans were dispatched for
  billing transitions, refunds, retention/deletion, deletion security, public
  policy, and edge cases. They were stopped after the bounded wait window
  without usable reports; the primary audit reconciled the authoritative
  repository evidence directly and recorded this limitation.
- [x] Verify official Razorpay lifecycle behavior and record primary-source
  evidence in `docs/research/task-267-razorpay-lifecycle.md`.
- [x] Audit current implementation and public/CMS policy consistency.
- [x] Implement only small, evidence-backed lifecycle fixes within scope:
  customer cancellation copy now states end-of-cycle access, no ordinary
  current-period refund, and no data deletion; public pricing FAQ now
  distinguishes cancellation from unsupported scheduled downgrades.
- [x] Add focused regression/security tests for changed behavior. Existing
  backend cancellation, provider-ordering, preservation, Enterprise, and
  artifact-isolation tests cover the implemented behavior; no new behavior
  test was warranted for static copy-only changes. The new direct
  `RazorpayBillingConfig` constructor guard is covered by `config_test.dart`.
- [x] Update lifecycle/refund/retention/deletion documentation, including the
  transition matrix, refund boundary, retention boundary, and deletion
  boundary in `docs/architecture/cloud-billing-lifecycle.md`.
- [x] Create prioritized follow-up tasks for substantial gaps: Tasks 268
  (reviewed refunds), 269 (account deletion/retention), and 270 (scheduled
  plan changes).

## Validation

The consolidated affected-scope validation passed:

- `dart format lib/src/billing.dart test/config_test.dart
  test/customer_billing_test.dart test/billing_provider_bridge_test.dart
  test/enterprise_billing_test.dart` — passed;
- `dart test test/config_test.dart test/customer_billing_test.dart
  test/billing_provider_bridge_test.dart test/enterprise_billing_test.dart
  test/artifact_lifecycle_test.dart` — 32 tests passed;
- `dart analyze lib test/config_test.dart test/customer_billing_test.dart
  test/billing_provider_bridge_test.dart test/enterprise_billing_test.dart` —
  no issues;
- Cloud web `npm run typecheck` — passed;
- Cloud web `npm run lint` — passed;
- Cloud web `npm run build` — passed, including the generated
  `/pricing.md`, `/terms`, `/privacy`, and `/refund-policy` routes;
- `git diff --check` — passed in both repositories.

Read-only live checks also recorded the production-policy/deployment mismatch
for Task 259: `/terms` and `/privacy` returned 200, `/refund-policy` returned
404, and live pricing did not match the current repository catalog. No
production mutation was performed.

## Reconciled decision matrix

| Area | Classification | Evidence / next owner |
| --- | --- | --- |
| Paid cancellation | IMPLEMENTED | Control plane and customer web schedule end-of-cycle cancellation; current plan/data remain until trusted terminal provider state. |
| Trusted upgrades | IMPLEMENTED | Provider event ordering and same-organization preservation are covered by existing billing tests; provider financial/proration evidence remains external. |
| Scheduled downgrades | IMPLEMENT_NOW (follow-up) | No customer downgrade route or scheduled-plan projection exists; Task 270 owns the provider-compatible implementation. |
| Normal cancellation/downgrade refunds | IMPLEMENTED POLICY | No automatic current-period refund is represented; customer copy now states this. |
| Reviewed refunds | IMPLEMENT_NOW (follow-up) | No refund record, approval workflow, or provider refund execution exists; Task 268 owns it. |
| Enterprise amendments | IMPLEMENTED FOUNDATION | Immutable quote/contract revisions and custom entitlement snapshots exist; provider-backed amendment acceptance remains the Task 266/managed-provider boundary. |
| Cancellation/downgrade retention | IMPLEMENTED | Resources, READY artifacts, history, and audit evidence are preserved; finite future growth is the only enforced reduction. |
| Account/organization deletion | IMPLEMENT_NOW (follow-up) | No verified request/token/job/ownership-safe deletion flow exists; Task 269 owns it. |
| Retention duration/backups | POLICY_DECISION_REQUIRED / DEFERRED | No destructive duration or backup erasure promise is authorized; Task 259/legal review remains the owner. |
| Public/CMS policy | LEGAL/COMPLIANCE_REVIEW_REQUIRED | Fallback Terms/Privacy/Refund content is still draft/generic; live `/refund-policy` was observed as 404 and live pricing differed from repository truth. Task 259 owns production policy/deployment verification. |
| Self-hosted | IMPLEMENTED | No Cloud billing or retention transition is applied to Self-hosted. |

## Parallel audit coverage

The requested workstreams were assigned to six GPT-5.6 Luna Max/Fast scans:

- Billing transitions: upgrade, downgrade, cancellation, provider update, and
  Enterprise amendment behavior.
- Refunds: policy, provider refund capability, duplicate/incorrect charge, and
  activation-failure handling.
- Retention/deletion: persisted data classes, artifacts, evidence, backups, and
  organization deletion.
- Deletion security: authenticated/no-login request, verification, abuse,
  grace, and ownership handling.
- Policy/public copy: Terms, Privacy, Refund Policy, pricing, billing UI,
  quotes, and onboarding consistency.
- Tests/edge cases: races, duplicate events, provider failures, deletion races,
  over-limit downgrade, reactivation, and retention contradictions.

The scans did not return before the bounded execution window, so none is used
as evidence. Direct repository inspection and the primary-source research note
are authoritative for this task's conclusions.

## Next Action

Execute Tasks 268–270 in their bounded scopes and resolve the production
policy/deployment gates in Task 259. Task 256B remains separately authorized
and is not implied by this task.

## Blockers

None identified before the audit.

## Outcome

Completed at the audit/documentation boundary. The lifecycle policy is
reconciled; cancellation semantics, no-ordinary-refund behavior, data
preservation, and Self-hosted separation are documented and the customer copy
is aligned with current implementation. The direct Razorpay configuration guard
now rejects non-approved currency/amount combinations. Substantial missing
workflows are explicit follow-ups: reviewed refunds (268), verified account and
organization deletion/retention (269), and scheduled plan changes (270).
No unsupported legal, tax, backup-retention, refund, or deletion promise was
introduced.

## References

- `tasks/257-customer-billing-upgrade-lifecycle.md`;
- `tasks/259-cloud-launch-operations-and-policy-gates.md`;
- `tasks/266-enterprise-quote-contract-payment-lifecycle.md`;
- `docs/architecture/cloud-billing-lifecycle.md`;
- `docs/research/task-267-razorpay-lifecycle.md`;
- `hyfens-cloud-web/docs/HYFENS_CLOUD_BILLING_V1.md`.

## History

- 2026-09-08 — Reserved Task 267 and began the independent lifecycle audit.
- 2026-09-08 — Reconciled the lifecycle matrix, recorded official Razorpay
  behavior, clarified cancellation/no-refund/no-deletion customer copy, and
  reserved Tasks 268–270 for reviewed refunds, deletion/retention, and
  scheduled plan changes. Live `/refund-policy` and live pricing were checked
  separately; production policy/deployment reconciliation remains Task 259.
- 2026-09-08 — Completed targeted formatting, control-plane tests/analyzer,
  Cloud-web typecheck/lint/build, and repository diff checks. Marked the task
  complete at its audit/documentation boundary and recorded the remaining
  implementation work in Tasks 268–270.
