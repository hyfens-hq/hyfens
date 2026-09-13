# Task 276 — Managed Artifact Retention Worker

Status: [x] Completed — CODE VERIFIED; managed acceptance remains external

## Goal

Provide a bounded, idempotent managed trigger for the existing Cloud artifact
retention cleanup service so deletion-related artifact purge work is scheduled
and observable on the managed development/TEST composition.

## Scope and Non-goals

Scope is limited to an operator/scheduler command, its systemd timer wiring,
deployment installation, and focused validation. Reuse
`ControlPlaneService.runArtifactRetentionCleanup()` and its existing
reference-safety/retention semantics.

This task does not define statutory retention periods, change the artifact
taxonomy, add a queue platform, alter customer authorization, implement
backup/restore or tombstone replay, or claim managed object-store acceptance.

## Owner

Platform operations.

## Dependencies

- Existing Cloud artifact retention cleanup service and tests.
- Existing public control-plane container and root-managed deployment
  installer.
- Task 259/269 managed operations and deletion evidence.

## Assumptions

- The existing cleanup method is the authoritative bounded implementation.
- A host timer with a lock is sufficient for the current single-node managed
  development/TEST composition.
- Failures must remain visible and retryable through the next timer run.

## Work Items

- [x] Add an operator-only control-plane mode for bounded artifact retention
  cleanup.
- [x] Add a locked managed worker/service/timer and installer wiring.
- [x] Add focused command/worker validation and update operations docs.
- [x] Record managed acceptance boundaries; do not overclaim object-store or
  backup readiness.

## Validation

- `dart test test/artifact_lifecycle_test.dart test/control_plane_command_test.dart`
  — passed.
- `dart analyze bin/control_plane.dart test/artifact_lifecycle_test.dart
  test/control_plane_command_test.dart` — passed.
- `dart format --output=none --set-exit-if-changed bin/control_plane.dart
  test/control_plane_command_test.dart` — passed.
- POSIX shell syntax, executable-bit, and systemd unit inspections — passed.
- Compose/deployment documentation diff checks — passed.
- Managed TEST worker smoke — not run; deployment was explicitly out of scope.

## Next Action

Maintainer review may stage and install the worker, then perform managed TEST
acceptance separately. This task does not authorize deployment.

## Blockers

Managed object-store topology and scheduled/off-host backup policy remain
outside this package.

## Outcome

CODE VERIFIED. Added the operator-only bounded cleanup command, a default
100-artifact scheduler batch with an optional validated limit, locked host
worker/service/timer wiring, installer activation, focused command/idempotency
coverage, and operational documentation. The command fails closed for
non-Cloud or non-deleting stores and returns a non-zero status for failed
items, while the existing deletion and notification modes remain unchanged.
No managed deployment, object-store acceptance, backup/restore evidence, or
production readiness is claimed.

## References

- `packages/control_plane/lib/src/service.dart`
- `packages/control_plane/test/artifact_lifecycle_test.dart`
- `packages/control_plane/test/control_plane_command_test.dart`
- `deploy/p2/hyfens-public-control-plane-dev-deletion-worker`
- `deploy/p2/hyfens-public-control-plane-dev-artifact-retention-worker`
- `tasks/259-cloud-launch-operations-and-policy-gates.md`
- `tasks/269-account-deletion-retention.md`

## History

- 2026-09-13: Reserved as a bounded operational correction after managed
  audit found no deployed trigger for the existing artifact cleanup seam.
- 2026-09-13: Implemented and locally verified the command, locked scheduler
  wiring, installer activation, and documentation. Managed installation and
  disposable TEST smoke were intentionally not run.
- 2026-09-13: Review tightened the command's explicit batch-limit validation to
  the service's supported range of 1 through 1000. The focused artifact and
  command tests passed again. The package-wide legacy suite still reports
  unrelated pre-existing closure/reconciliation failures and missing optional
  PostgreSQL integration configuration; those failures are outside this task's
changed scope.
- 2026-09-13: The reviewed commit was synchronized into the root-managed
  staging boundary and installed through the existing protected installer.
  The control plane was rebuilt and redeployed successfully; the artifact
  retention timer is enabled and active. The managed smoke returned zero with
  a Cloud/deletion-supported report and no eligible rows. No physical purge or
  backup/object-store acceptance is claimed.
