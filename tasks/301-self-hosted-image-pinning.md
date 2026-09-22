# Task 301 — Self-hosted image pinning

Status: [x] Completed

## Goal

Make the bundled self-hosted infrastructure resolve immutable, reviewed image
references by default so an unplanned upstream tag change cannot alter a
deployment.

## Scope and Non-goals

Scope:

- PostgreSQL, MinIO, and MinIO client defaults in the self-hosted Compose
  package; and
- operator documentation and validation for those defaults.

Non-goals:

- no production deployment or registry mutation;
- no change to the operator-supplied Hyfens release image contract; and
- no change to data, credentials, or volume layout.

## Owner

Coordinator: Hyfens engineering.

## Dependencies

- verified multi-architecture image manifest digests;
- the existing self-hosted Compose contract; and
- operator review before upgrading a pinned image.

## Assumptions

- operators may deliberately override image variables for a reviewed upgrade;
- digest references are supported by Docker Compose v2; and
- the self-hosted package remains a single-node starting point.

## Work Items

- [x] Reserve the task and inspect the current image references.
- [x] Pin the mutable infrastructure defaults and document the upgrade path.
- [x] Review the combined diff and run Compose/configuration validation.

## Validation

Completed on 2026-09-19:

- `docker compose config --quiet` with a safe fixture environment passed;
- rendered Compose inspection confirmed the PostgreSQL, MinIO, and MinIO
  client defaults resolve to immutable manifest digests;
- the MinIO defaults now use the reachable Quay registry references rather than
  the previous mutable Docker Hub tags; and
- `git diff --check` passed.

## Next Action

Owner review remains before release. Upgrade these images only by changing the
reviewed digest and testing backup/restore as one data set.

## Blockers

None known.

## Outcome

The self-hosted infrastructure defaults are now digest-pinned without changing
the operator override variables or data layout. No deployment was performed.

## References

- `deploy/self-hosted/docker-compose.yml`
- `deploy/self-hosted/.env.example`
- `deploy/self-hosted/README.md`

## History

- 2026-09-19: Reserved after the security review found mutable PostgreSQL,
  MinIO, and MinIO client defaults.
- 2026-09-19: Pinned the verified multi-architecture manifests, documented
  deliberate digest upgrades, and passed Compose/diff validation.
