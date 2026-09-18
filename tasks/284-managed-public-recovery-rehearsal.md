# Task 284 — Managed public recovery rehearsal

Status: [*] In Progress

## Goal

Extend the existing opt-in public DR rehearsal so an operator can restore one explicitly selected managed backup into a disposable Compose project and exercise the real deletion/tombstone path without touching production.

## Scope and Non-goals

Scope:

- consume an explicit `HYFENS_DR_MANAGED_BACKUP_ID` from the protected public backup destination;
- verify the downloaded database/object manifests and checksums;
- restore the pair into unique disposable PostgreSQL and object-store volumes;
- reuse the existing fixture, artifact, deletion-worker, and tombstone assertions;
- document one operator command for the approved managed-host rehearsal; and
- preserve fail-closed target naming, restore opt-in, cleanup, and sanitized evidence.

Non-goals:

- no production restore, production deletion, or live customer mutation;
- no change to the recurring public backup runner or its no-restore boundary;
- no claim of provider durability, encryption/key custody, RPO/RTO, or legal acceptance from the rehearsal alone; and
- no credential values in output, source, or tracked evidence.

## Owner

Public control-plane engineering and platform operations.

## Dependencies

- Public PR #20 and the installed managed backup runner.
- A fresh managed backup ID and the root-owned `/etc/hyfens/public-control-plane-dev.env` destination credential.
- Docker access to the managed host and the current public control-plane image.
- An approved disposable recovery target and maintenance window for live acceptance.

## Assumptions

- The managed backup contains a consistent PostgreSQL/object pair as declared by its manifest.
- The managed host has the pinned AWS CLI image and PostgreSQL/MinIO images available or pullable.
- The existing local rehearsal's generated fixture credentials remain isolated to the temporary project.

## Work Items

- [x] Add an explicit managed-backup restore branch to the disposable DR rehearsal.
- [x] Validate the managed branch and fail-closed target/credential boundaries.
- [ ] Run the selected managed backup restore and tombstone rehearsal.
- [ ] Record sanitized evidence and close the external recovery gate.

## Validation

Expected:

- `bash -n scripts/p2-dr-rehearsal.sh`.
- `node --test deploy/p2/managed-backup-contract.test.mjs` (3 passed).
- Disposable Compose configuration validation with synthetic local values.
- Local extended disposable rehearsal (passed): coupled restore, deletion
  tombstone replay, denied deleted-tenant access, zero retained tenant
  records/memberships, shared-object preservation, and project cleanup.
- Dart package tests were not rerun because the local Dart launcher exits with
  `Bad CPU type in executable`; the existing Task 281 run remains the focused
  Dart evidence for unchanged control-plane code.
- Managed run output proves manifest/checksum validation, readiness, restored artifact fetch, tombstone state, denied access, zero deleted tenant records/memberships, and preserved shared bytes.
- Cleanup proves the exact disposable Compose project, volumes, and network are removed.

## Next Action

Review and merge the implementation PR, deploy the reviewed script to the
managed host, then run it with backup `20260918T061844Z`.

## Blockers

Provider durability, encryption/key evidence, approved RPO/RTO, and legal/launch acceptance remain separate decisions even after the technical rehearsal passes.

## Outcome

Implementation and local validation are complete; managed execution is pending.

## References

- `scripts/p2-dr-rehearsal.sh`
- `deploy/p2/hyfens-public-control-plane-dev-backup`
- `deploy/p2/README.md`
- `tasks/281-public-dr-tombstone-rehearsal.md`
- Private runbook `docs/operations/managed-launch-acceptance.md`

## History

- 2026-09-18: Reserved as the single implementation package for the managed public coupled recovery blocker.
- 2026-09-18: Added the fail-closed managed restore branch, manifest/object
  checksum verification, protected temporary credential env files, disposable
  Compose image selection, operator command, and local coupled tombstone
  regression evidence.
- 2026-09-18: The first managed-host attempt stopped before container creation
  because Docker Compose rejects uppercase `T`/`Z` in project names; the
  derived disposable project slug is now lowercase while the R2 backup ID
  remains unchanged for object paths and manifest identity.
- 2026-09-18: Managed restore and object verification passed on the host, but
  the existing organization-scoped reconciliation also reported two
  pre-existing restored bucket objects as `orphan_object`. The managed branch
  now requires the disposable fixture to be verified and fetchable while
  preserving those restored bytes; the local rehearsal keeps its stricter
  zero-orphan `deliverable` assertion.
