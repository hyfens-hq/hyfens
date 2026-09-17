# Task 283 — Platform-managed backup administration

Status: [x] Completed

## Goal

Allow the private Hyfens Platform Console to administer the public managed
control-plane backup through a narrowly scoped host boundary, while preserving
least privilege, fail-closed R2 validation, protected configuration, and
append-only audit evidence.

## Scope and Non-goals

Scope:

- add a safe public-backup preflight/configuration contract for the managed
  host wrapper;
- validate source and destination R2 credentials against their intended
  buckets before activation;
- preserve the root-owned protected environment and existing backup timers;
- expose only redacted operational results to the private Cloud API; and
- document the cross-repository deployment contract.

Non-goals:

- changing customer backup policy, legal retention, RPO/RTO, or pricing;
- accepting arbitrary endpoints, commands, bucket paths, or restore targets;
- placing R2 credentials in PostgreSQL, audit records, browser code, or logs;
- changing the existing public customer API or artifact authority; and
- claiming managed restore or deletion-tombstone acceptance by itself.

## Owner

Platform operations.

## Dependencies

- Current public managed backup wrapper and Compose deployment.
- Private Cloud host broker and Platform Console package in Task 295.
- Existing root-owned `/etc/hyfens/public-control-plane-dev.env`.

## Assumptions

- The public source bucket and managed destination remain the approved
  Cloudflare R2 account/bucket pair.
- The host broker is the only component allowed to write protected files or
  invoke root backup operations.
- The public wrapper remains the authoritative backup implementation.

## Work Items

- [x] Add the allowlisted public-backup preflight/configuration operation.
- [x] Add tests for correct-pair validation, reversed-pair rejection, safe
  redaction, and protected-file invariants.
- [x] Update deployment documentation and the Task 295 integration contract.
- [x] Review the task-owned diff and run scoped shell/Compose validation.

## Validation

Completed:

- shell syntax and executable-bit checks;
- `node --test deploy/p2/managed-backup-contract.test.mjs` (3 passed);
- public capability catalogue test and focused human-auth/demo/staff tests
  (all passed);
- the broader public package suite was also run and reported 27 unrelated
  pre-existing failures in closure/reconciliation coverage; no affected
  managed-backup capability or wrapper test failed;
- broker protocol tests cover public freshness/preflight markers, duplicate
  source/destination rejection, and safe output boundaries;
- `sh -n` on the public backup wrapper;
- `git diff --check` and secret-pattern scans (passed); and
- Compose model validation was skipped because `/usr/bin/docker` is not
  installed on the development workstation.

## Next Action

Review and merge public PR #20 together with private Task 295 PR #39; then
install the broker/wrapper package on the managed host and rerun the live
preflight/freshness acceptance checks.

## Blockers

None currently.

## Outcome

Implemented the public preflight contract, fixed public freshness marker
coverage, registered the managed-backup capability catalogue, and preserved
the root-owned wrapper as the only public backup authority. No credentials or
arbitrary bucket/endpoint/command controls were added.

## References

- `deploy/p2/hyfens-public-control-plane-dev-backup`
- `deploy/p2/managed-backup-contract.test.mjs`
- `deploy/p2/docker-compose.public-control-plane-dev.yml`
- `tasks/282-public-managed-backup-runner.md`
- Private Cloud Task 295: platform-managed backup administration.

## History

- 2026-09-18: Reserved as the public deployment package for console-managed
  backup configuration and preflight validation.
- 2026-09-18: Completed wrapper preflight, capability registration, contract
  tests, documentation, and scoped validation; linked to private Task 295 for
  the broker/API/Console integration.
- 2026-09-18: Opened public review PR #20; private companion review is #39.
