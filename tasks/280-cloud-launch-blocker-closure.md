# Task 280 — Cloud launch blocker closure

Status: [-] Blocked

Reason: remaining launch gates require external authority or managed access.

## Goal

Reconcile the recovered Hyfens Cloud launch blockers, close every
repository-controlled blocker that can be safely completed, and leave a
launch-ready evidence trail with explicit external gates for anything that
requires maintainer, accounting, legal, provider, or deployment action.

## Scope and Non-goals

Scope:

- managed backup, restore, data-scope, and deletion-tombstone recovery
  readiness across the public control plane and private Cloud deployment;
- personal-account deletion and ownership-resolution safety that is
  implementable in the current product boundary;
- Enterprise TEST readiness and the bounded acceptance procedure where the
  private Cloud repository can provide it;
- private provider-dashboard, production-attestation, legal/tax, and
  ledger-backed LIVE prerequisites;
- operational launch evidence, decision checklists, and focused regression
  coverage; and
- consolidated review and validation of the affected Cloud surfaces.

Non-goals:

- live payment activation, live refunds, or production customer data actions;
- changing `app.hyfens.com` or performing the separately authorized 256B
  customer-workspace cutover;
- inventing tax treatment, legal policy text, statutory retention periods,
  RPO/RTO commitments, or compliance certifications;
- creating a second provider, email, backup, or deployment platform; and
- pushing or creating a private Cloud remote without an explicit destination
  and authorization.

## Owner

Codex coordinator

## Dependencies

- Tasks 259, 260, 265–271, and 274–287 across the public and private Cloud
  workspaces.
- Current `packages/control_plane` source and `deploy/p2` deployment
  manifests.
- Existing protected managed-host deployment and provider configuration in the
  public and private Cloud workspaces.
- Maintainer, accounting, legal, and provider decisions for external gates.

## Assumptions

- The current checkout is clean and work begins from `main` on the task
  branch `launch/cloud-blocker-closure`.
- Existing user changes, public contracts, protected secrets, and the
  `app.hyfens.com` target remain untouched.
- Managed-host evidence can be recorded only when the required access and
  disposable acceptance data are available; no secret values will be stored.
- Enterprise remains a launch-scope question until explicitly confirmed;
  source and runbook readiness can be improved without activating LIVE
  payments.

## Work Items

- [x] Reconstruct the current launch blockers from task history and source
  evidence.
- [x] Inspect the backup/restore, deletion, Enterprise, provider, metering,
  policy, and operational gates and assign disjoint implementation/review
  packages.
- [x] Fix the demonstrated same-organization duplicate-artifact reference
  deletion bug and protect it with a focused regression test.
- [x] Harden the legacy transactional-email fallback so environment sender
  configuration cannot bypass the centralized sender policy, with a regression
  test.
- [-] Close repository-controlled backup/restore and tombstone-replay gaps;
  the remaining managed destination, key, policy, and replay evidence is
  external.
- [-] Close repository-controlled personal-deletion/ownership gaps; the
  current sole-owner stop is safe, while the ownership policy remains
  unresolved.
- [x] Close repository-controlled Enterprise documentation gaps and document
  the managed TEST acceptance boundary in the private Cloud workspace.
- [x] Publish the consolidated launch gate matrix and external decision list.
- [x] Review the combined task-owned diff and run the affected validation
  checks.
- [x] Record outcome, evidence, remaining blockers, and next action.

## Validation

Planned scoped validation:

- backup/restore and deployment-manifest tests;
- focused control-plane deletion, ownership, Enterprise, billing, and auth
  tests;
- `dart analyze` for affected Dart packages;
- relevant shell, Compose, web, and documentation checks;
- secret and diff checks; and
- managed disposable acceptance only where existing protected access permits
  it, with no LIVE provider, provider-dashboard mutation, or
  customer-workspace cutover.

The public repository changes from this reconciliation are limited to the
same-organization duplicate-artifact retention fix and the legacy email sender
allowlist. Current private source/test evidence is recorded in Tasks 277–286
and the Enterprise runbook in the private Cloud workspace.

Validation evidence on 2026-09-15: scoped `markdownlint` passed for the matrix
and this task; untracked-file whitespace checks, local-reference checks, and
secret-pattern scans produced no findings; both repository statuses were
confirmed with the Command Line Tools Git binary. The previously recorded
non-mutating public health/route probes and private Tasks 277–286 validation
remain the source/test evidence for this documentation-only reconciliation.

Source-fix validation on 2026-09-15: `dart test test/deletion_test.dart` passed
all 17 tests, including the same-organization duplicate-artifact regression;
`dart analyze lib test/deletion_test.dart` reported no issues; and Dart format
validation passed after formatting the changed test. The compatible Dart
3.13.3 SDK was invoked directly because the default Puro wrapper is not
executable on this host.

Email-safety validation on 2026-09-15: `dart test
test/notifications_test.dart test/deletion_test.dart` passed 47 tests;
`dart analyze lib test/notifications_test.dart test/deletion_test.dart`
reported no issues; and Dart format validation passed for the changed email
source and notification test. The fallback now rejects unapproved sender
addresses before provider construction.

## Next Action

The repository-controlled review is complete. An authorized operator must
complete the external gates in the matrix before any paid-launch decision:
provider dashboard configuration, managed recovery and tombstone replay,
Enterprise browser TEST acceptance, policy/retention approval, production
device attestation, and any separately authorized LIVE or workspace cutover.

## Blockers

The product remains `NOT_READY` for a public paid launch. External blockers
include managed backup-destination and key provisioning, deletion-tombstone
replay, mailbox/role monitoring proof, tax/legal/accounting/security and
retention approval, Enterprise browser TEST acceptance, the provider dashboard
save failure and six dispute subscriptions, production device attestation,
ledger-backed LIVE activation, and any explicit authorization for the
`app.hyfens.com` cutover. These are not to be silently marked complete by code
changes.

## Outcome

Repository-controlled source gates remain fail-closed. The recovered blocker
list is consolidated in `docs/operations/cloud-launch-gate-matrix.md`; the
current private Cloud evidence is tracked by Tasks 277–287. The launch
recommendation remains `NOT_READY` until the external gates above are
completed. The same-organization duplicate-artifact deletion defect is closed
with a regression test.

## References

- `tasks/259-cloud-launch-operations-and-policy-gates.md`
- `tasks/271-recover-managed-cloud-deployment-and-operational-wiring.md`
- `docs/operations/cloud-launch-operations.md`
- `docs/operations/cloud-launch-gate-matrix.md`
- `deploy/p2/`
- `packages/control_plane/`

## History

- 2026-09-15: Created after reconstructing the persisted `NOT_READY` launch
  verdict following session termination. Reserved task number 280 and
  started bounded blocker closure on a task branch.
- 2026-09-15: Reconciled the clean private Cloud worktree on
  `feat/billing-launch-safeguards`. Tasks 277–286 show source-level TEST
  safeguards and a standard managed TEST capture/refund pass, but Enterprise
  browser acceptance, six provider dispute subscriptions, managed recovery,
  production attestation, LIVE integration, and policy approvals remain open.
- 2026-09-15: Added the cross-repository Enterprise TEST runbook and completed
  documentation/diff review. No source, provider, deployment, customer, or
  payment state changed; remaining launch blockers require external authority
  or managed access.
- 2026-09-15: The public recovery/deletion worker found and fixed the
  same-organization duplicate-artifact reference bug in `deletion.dart` and
  added a regression test. The Enterprise and provider workers found no safe
  source-level changes; their remaining gates are managed or external.
- 2026-09-15: Focused deletion tests (17) and scoped analysis passed with the
  compatible Dart 3.13.3 SDK. No provider, deployment, customer, or payment
  state changed.
- 2026-09-15: Found and fixed a production-path sender-policy bypass in the
  legacy Keplars human-delivery fallback. Added a regression test; source
  wiring is now verified, while managed provider delivery and mailbox
  monitoring remain external.
