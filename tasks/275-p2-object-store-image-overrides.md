# Task 275 — P2 object-store image overrides

Status: [x] Completed — Compose override correction and targeted validation passed

## Goal

Make the disposable P2 DR and HA Compose manifests consume the existing
object-store and MinIO Client image overrides used by local deployment and DR
helpers, while preserving the current default image references.

## Scope and Non-goals

Scope:

- parameterize the `object-store` image in `deploy/p2/docker-compose.yml` and
  `deploy/p2/docker-compose.ha.yml` with `HYFENS_OBJECT_STORE_IMAGE`;
- parameterize the `object-bootstrap` image in both manifests with the
  existing `HYFENS_MC_IMAGE` override; and
- validate default and sentinel-override Compose interpolation.

Non-goals:

- changing the DR or HA scripts, backup/restore behavior, secrets, schemas,
  dependencies, or public APIs;
- claiming managed backup readiness or provider durability;
- inventing a backup schedule, retention policy, or tombstone architecture; or
- changing any unrelated worktree modification.

## Owner

Codex disposable DR/build-helper worker

## Dependencies

- Existing P2 Compose manifests and DR/HA rehearsal scripts.
- Existing `HYFENS_OBJECT_STORE_IMAGE` and `HYFENS_MC_IMAGE` override
  conventions.
- Docker Compose and `yq` for configuration-only validation.

## Assumptions

- The current default references `minio/minio:latest` and `minio/mc:latest`
  remain the fallback values.
- Placeholder values are sufficient for interpolation checks and are not
  persisted as deployment credentials.
- The managed backup/restore, off-host durability, schedule, retention, and
  deletion-tombstone gates remain unresolved outside this bounded correction.

## Work Items

- [x] Inspect the current DR/HA scripts and reproduce the hard-coded image
  failure with a configuration-only Compose check.
- [x] Parameterize both object-store image declarations and both
  object-bootstrap image declarations.
- [x] Validate both manifests with default and sentinel image values.
- [x] Review the task-owned diff, commit an atomic signed-off change, and
  record remaining DR blockers.

## Validation

Observed:

- `docker compose -f deploy/p2/docker-compose.yml config --quiet` and the
  equivalent HA command passed with placeholder credentials;
- sentinel override assertions passed for both image fields in both manifests:
  `registry.invalid/minio:override` and `registry.invalid/mc:override`;
- default fallback assertions passed for both image fields in both manifests:
  `minio/minio:latest` and `minio/mc:latest`;
- targeted static inspection confirmed only the four intended image fields
  changed; and
- `git diff --check` passed.

## Next Action

The bounded Compose image-field changes and targeted checks are complete.
Commit the isolated change and hand off the remaining DR blockers without
expanding scope.

## Blockers

None for the repository configuration correction. Managed backup readiness,
provider durability, backup scheduling, off-host rotation, restore ownership,
and deletion-tombstone replay remain DR blockers and are not addressed here.

## Outcome

Completed. Both P2 Compose manifests now honor the existing object-store and
MinIO Client image overrides while preserving their original defaults. No
secrets, scripts, backup behavior, schedules, retention policy, or tombstone
architecture changed.

## References

- `deploy/p2/docker-compose.yml`
- `deploy/p2/docker-compose.ha.yml`
- `deploy/self-hosted/docker-compose.yml`
- `scripts/p2-dr-rehearsal.sh`
- `scripts/p2-object-backup.sh`
- `scripts/p2-object-restore.sh`
- `tasks/259-cloud-launch-operations-and-policy-gates.md`

## History

- 2026-09-13 — Reserved after reproducing that both P2 manifests ignore
  `HYFENS_OBJECT_STORE_IMAGE` and `HYFENS_MC_IMAGE` sentinels and retain the
  hard-coded MinIO defaults.
- 2026-09-13 — Parameterized both manifests, verified default and sentinel
  image resolution with Docker Compose config, and passed `git diff --check`.
