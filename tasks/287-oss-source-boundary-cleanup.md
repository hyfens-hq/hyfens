# Task 287 — OSS source-boundary cleanup

Status: [*] In Progress

## Goal

Keep the public repository limited to the reusable local/self-hosted product
surface. Remove hosted implementation, operator evidence, deployment details,
real environment identifiers, and private-product references from the current
tree, then assess whether public history needs coordinated treatment.

## Scope and Non-goals

Scope:

- inventory the public tree and its publication history;
- retain the reusable runtime, CLI, control-plane, dashboard, and self-hosted
  reference components;
- remove hosted-only source, deployment material, operator evidence, stale
  task records, and real environment identifiers; and
- record the history decision and validation evidence.

Non-goals:

- no changes to the sibling commercial product;
- no customer-account provisioning implementation in this repository;
- no credential rotation without evidence of an exposed credential; and
- no remote history replacement without an explicit reviewed recovery plan.

## Owner

Coordinator: Hyfens engineering; boundary implementation was delegated to the
assigned repository-cleanup worker and reviewed by the coordinator.

## Dependencies

- the public repository publication baseline;
- the local self-hosted reference contract; and
- coordinator review before any history replacement or force-push.

## Assumptions

- the public edition remains useful without hosted operations;
- deployment-specific credentials, provider configuration, operator workflows,
  and commercial policy are maintained outside this repository; and
- a normal follow-up commit cannot erase already-published history.

## Work Items

- [x] Inventory the public tree, remotes, publication baseline, and history.
- [x] Classify hosted implementation/evidence versus reusable OSS surface.
- [x] Remove hosted source modules, deployment material, operational docs,
  stale task records, private references, and real identifiers from the tree.
- [x] Restore affected public runtime, CLI, dashboard, and control-plane areas
  to the self-hosted OSS baseline before applying neutral changes.
- [x] Add a reviewed repository-boundary guard for future contributions.
- [x] Complete the history-replacement assessment and coordinator decision.
- [x] Review the combined diff and prepare the cleanup pull request.

## Validation

Planned and performed as applicable:

- current-tree scans for private hosts, provider credentials, real mailboxes,
  company-specific environment identifiers, and hosted-only paths;
- public/private visibility and remote verification;
- scoped CLI, dashboard, and control-plane tests;
- `git diff --check`; and
- explicit review before any public history replacement.

Validation completed on 2026-09-19:

- `scripts/check-oss-boundary.sh` passed;
- tracked-tree scans found no private host, provider, mailbox, or signing-team
  markers;
- CLI analysis passed, and the changed CLI/MCP/profile tests passed;
- control-plane analysis passed, and the affected configuration,
  authentication, onboarding, HTTP, ingress, and object-store tests passed;
- dashboard HTTP tests passed (`30` tests);
- shell syntax, Python syntax, and `git diff --check` passed.

The full control-plane suite still has date-sensitive reconciliation failures
and skips external PostgreSQL/S3 integration without their environment. The
full CLI suite also has unrelated release/toolchain tests that require the
machine's normal Flutter launcher and current fixture assumptions; these are
recorded as follow-up validation work, not boundary findings.

## Next Action

Hand the single cleanup pull request to the maintainer. The published history
assessment requires the separate Task 288 recovery plan before any remote
history replacement. Keep private customer-account provisioning blocked until
the current-tree boundary is approved and the history decision is accepted.

## Blockers

The current tree is clean, but published history contains earlier private
deployment markers. A normal pull request cannot erase them; Task 288 is the
separate recovery package for an isolated sanitized-history rewrite and
downstream-clone coordination.

## Outcome

Current-tree cleanup is complete and ready for review. Published history
replacement remains a separate, coordinator-gated operation.

## References

- `README.md`
- `CONTRIBUTING.md`
- `deploy/self-hosted/README.md`
- `scripts/check-oss-boundary.sh`
- public publication baseline and reachable-ref scan

## History

- 2026-09-19: Reserved after the coordinator found hosted implementation,
  operational evidence, private-product references, and real environment
  identifiers mixed into the public tree. Customer-account work is gated on
  this boundary review.
- 2026-09-19: Restored the reusable self-hosted baseline, removed hosted
  implementation/evidence, added a boundary guard, and completed scoped
  validation. Reachable history still requires the separate Task 288 plan.
