# Task 282 — Public managed backup runner

Status: [*] In Progress

## Goal

Add a bounded, root-owned backup path for the public control plane that writes
the PostgreSQL and R2 artifact-store pair to the verified `operational/`
backup policy and proves upload integrity without exposing credentials or
performing a restore.

## Scope and Non-goals

Scope:

- a pinned one-shot AWS CLI container isolated from the long-running control
  plane;
- a host wrapper that snapshots PostgreSQL and all non-backup R2 objects,
  writes a versioned manifest, uploads the pair below
  `operational/public-control-plane/`, and verifies read-back checksums;
- a daily backup timer and a separate freshness timer with bounded age
  validation; and
- protected configuration, deployment installation, contract tests, and
  operator documentation.

Non-goals:

- no production restore, deletion request, deletion-tombstone replay, or
  customer-data mutation;
- no claim that a scheduled upload proves an approved RPO/RTO, encryption/key
  custody, provider durability, or legal retention;
- no reuse of the backup destination as the application artifact endpoint;
- no credentials, object contents, or raw provider output in tracked files or
  logs; and
- no change to public launch flags, billing, or the separately authorized
  `app.hyfens.com` cutover.

## Owner

Public control-plane engineering.

## Dependencies

- the existing R2-backed public control-plane deployment;
- a separate source read credential for the public artifact bucket and a
  destination read/write credential for `hyfens-cloud-backups`;
- the verified `operational/` 30-day R2 policy; and
- an operator-approved backup owner, encryption/key procedure, RPO/RTO, and
  isolated restore window for later acceptance.

## Assumptions

- the protected public deployment environment remains root-owned with mode
  `600`;
- the public artifact store uses digest-addressed keys and excludes the
  reserved `operational/` prefix from the source snapshot;
- the deployment owner will quiesce or otherwise approve the consistency
  window before using the runner as managed launch evidence; and
- the public control-plane service is already healthy when the backup timer
  runs.

## Work Items

- [x] Reserve this cohesive package and define the public recovery boundary.
- [x] Implement the isolated backup client, manifest, checksum verification,
  and freshness wrapper.
- [x] Install the systemd units and protected configuration contract.
- [x] Add focused contract validation and operator documentation.
- [x] Review the combined diff and run the affected validation checks.
- [*] Open one substantive PR for maintainer review and merge.

## Validation

Completed scoped validation:

- `sh -n deploy/p2/hyfens-public-control-plane-dev-backup
  deploy/p2/install-public-control-plane-dev-backup.sh` — passed.
- Embedded Python manifest blocks — five blocks compiled successfully.
- `node --test deploy/p2/managed-backup-contract.test.mjs` — passed, three
  tests.
- Docker Compose model validation with synthetic non-secret values and the
  `managed-backup` profile — passed.
- `git diff --check` — passed.
- No live R2 write, production restore, deletion, or customer mutation was
  performed.

The requested broader Dart validation was attempted once. It remains
non-green for pre-existing workspace/toolchain reasons: the default Puro
Flutter/Dart launcher cannot execute on this arm64 host, the root workspace
analyzer package configuration lacks the package dependencies required by the
monorepo, and the direct-Dart package loop reaches existing analyzer-cache and
control-plane integration failures. None of those paths are affected by this
shell/YAML/Node deployment package.

## Next Action

Complete the implementation and open one substantive PR. After merge, the
operator must install the protected source/destination credentials and run a
controlled first backup before the managed restore/tombstone exercise.

## Blockers

Managed recovery acceptance remains externally blocked until the operator
provides the protected R2 credentials, approves the consistency window and
RPO/RTO, and runs the isolated restore plus deletion-tombstone replay.

## Outcome

Implementation and scoped validation are complete. The remaining review gate
is one substantive PR; managed acceptance still requires protected credentials
and the external isolated restore/tombstone exercise.

## References

- `deploy/p2/docker-compose.public-control-plane-dev.yml`
- `deploy/p2/README.md`
- `scripts/p2-dr-rehearsal.sh`
- `tasks/281-public-dr-tombstone-rehearsal.md`

## History

- 2026-09-17: Reserved after the disposable public coupled restore and
  tombstone rehearsal passed. The next repository-controlled gap is a managed
  off-host public database/object backup path; restore and tombstone replay
  remain a separate protected acceptance action.
- 2026-09-17: Implemented the root-owned backup runner, profile-gated pinned
  AWS CLI client, protected timers, paired manifest/read-back verification,
  focused contract tests, and operator runbook. Final review added the
  managed-backup Compose profile and mode-600 short-lived credential env file;
  all scoped checks passed. Broader Dart validation remains non-green only for
  pre-existing Puro, package-configuration, analyzer-cache, and integration
  environment failures.
