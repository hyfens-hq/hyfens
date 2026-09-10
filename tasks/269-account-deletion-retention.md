# Task 269 — Account deletion and retention lifecycle

Status: CODE_VERIFIED

## Goal

Implement a verified, resumable Cloud account/organization deletion lifecycle
that is separate from subscription cancellation and preserves required
security, billing, and audit evidence.

## Scope and Non-goals

In scope:

- authenticated deletion request with strong confirmation;
- neutral no-login email initiation using a purpose-bound, hashed, single-use,
  expiring token;
- ownership-transfer/sole-owner handling;
- explicit account versus organization deletion scope;
- approved grace-period state, cancellation/reconciliation, resumable deletion
  job, and observable retryable failures;
- erase/anonymize/retain/temporary-retain classification for database,
  artifact, audit, billing, and backup records;
- shared content-addressed object safety and Self-hosted separation.

Out of scope:

- a general privacy/GDPR/DPDP management suite;
- universal export, tax, refunds, or legal drafting;
- remote deletion of Self-hosted deployment data;
- destructive retention periods invented without policy approval.

## Owner

Codex, with maintainer/security/legal review.

## Dependencies

- Task 267 retention/deletion audit;
- existing human auth, recovery delivery, artifact retention, object-store, and
  audit primitives;
- Task 259 Privacy/Terms and production communications gates.

## Assumptions

- cancellation stops renewal and retains customer data;
- deletion alone does not create a refund;
- the organization cannot be orphaned by deleting its sole owner;
- backups may require retention until normal rotation unless infrastructure
  proves immediate erasure.

## Work Items

- [-] Obtain and record the approved deletion grace period and backup wording;
  the architecture is configurable, but the approved legal/operational values
  remain a Task 259 decision.
- [x] Add purpose-bound deletion request/token and authenticated confirmation.
- [x] Add ownership-safe account/organization state transitions.
- [x] Implement idempotent, resumable data/object deletion with shared-object
  protection and reconciliation.
- [x] Add data-classification, enumeration, token, race, partial-failure, and
  Self-hosted tests.
- [-] Update approved Privacy/Terms copy through the existing policy process;
  local/customer copy and architecture documentation are updated, while final
  production legal publication remains Task 259.

## Validation

- `dart analyze lib test/deletion_test.dart` — passed.
- `dart test test/deletion_test.dart` — passed, including neutral no-login
  initiation, purpose-bound single-use/expiry, ownership blocking, staged
  account/org processing, shared/exclusive artifact handling, retry batches,
  tombstoning, and unconfigured-policy blocking.
- `dart analyze` (control-plane package) — passed with no issues.
- Dart formatting check for task-touched files — passed with no changes.
- Focused deletion/auth/onboarding/billing set (26 tests) — passed:
  `deletion_test.dart`, `human_auth_test.dart`, `human_auth_http_test.dart`,
  `customer_onboarding_test.dart`, and `customer_billing_test.dart`.
- Full control-plane `dart test` — not clean because 27 unrelated existing
  observation/reconciliation/credential suites fail; deletion tests remain
  green. Database/object-store cases that require unavailable external test
  services remain skipped.
- Cloud web `npm run typecheck` — passed.
- Cloud web `npm run lint` — passed.
- Cloud web `npm run build` — passed; `/account-deletion`,
  `/dashboard/privacy`, and the proxy route build successfully.
- `git diff --check` — passed for tracked changes.
- Final affected-scope validation after formatting — passed: control-plane
  analyzer and the 26 focused tests are green; Cloud web typecheck/lint/build
  are green.

## Next Action

Task 259 must supply the approved grace-period, backup/evidence-retention, and
production deletion-mail/policy-publication decisions. Configure
`HYFENS_DELETION_GRACE_PERIOD` before enabling the deletion worker in a managed
deployment. Then run a managed disposable organization deletion acceptance.

## Blockers

- `POLICY_DECISION_REQUIRED: deletion_grace_period` until the reviewed value is
  configured.
- Backup rotation and deletion wording are infrastructure/policy inputs; the
  current store cannot erase individual records from immutable backups.
- Financial/billing, security/audit, and Enterprise commercial evidence
  retention durations require policy/legal authority.
- Production deletion-email delivery and final Privacy/Terms publication
  remain Task 259 dependencies.
- A managed production-like deletion run was not claimed in this task.

## Outcome

CODE_VERIFIED. Added a separate account-deletion and organization-deletion
domain with neutral no-login initiation, hashed purpose-bound deletion tokens,
strong authenticated confirmation, sole-owner protection, explicit Cloud
organization tombstones, billing-domain future-renewal stopping, credential and
session revocation, bounded resumable processing, content-addressed shared
object protection, anonymized evidence, and customer privacy/status surfaces.
No synchronous cascade, automatic refund, ownership transfer, Self-hosted
deletion, or arbitrary legal retention duration was introduced. Managed
acceptance and final policy/operational decisions remain external.

## References

- `tasks/267-commercial-lifecycle-refund-retention-deletion.md`
- `tasks/259-cloud-launch-operations-and-policy-gates.md`
- `docs/architecture/cloud-billing-lifecycle.md`
- `packages/control_plane/lib/src/human_auth.dart`
- `packages/control_plane/lib/src/artifact_retention.dart`

## History

- 2026-09-08 — Reserved from Task 267 audit; cancellation and artifact cleanup
  exist, but account/privacy deletion is not implemented.
- 2026-09-09 — Implemented and locally verified the deletion lifecycle. Added
  the public and authenticated privacy surfaces, durable deletion records,
  protected token consumption, ownership/billing safeguards, staged artifact
  cleanup, retention classification, and retryable worker behavior. Marked
  CODE_VERIFIED; retained policy, backup, production-mail, and managed-run
  gates as blockers/follow-up decisions.
- 2026-09-09 — Final affected-scope validation passed. Full package analysis
  passed; the focused deletion/auth/onboarding/billing tests and Cloud web
  typecheck/lint/build passed. The broader package test command still reports
  unrelated pre-existing observation/reconciliation/credential failures, so
  no broader-suite success is claimed.
