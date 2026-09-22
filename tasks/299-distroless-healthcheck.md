# Task 299 — Distroless control-plane healthcheck

Status: [x] Completed

## Goal

Make the self-hosted control-plane healthcheck executable inside the hardened
distroless image.

## Scope and Non-goals

Scope:

- the control-plane Compose healthcheck command; and
- focused Compose/image contract validation.

Non-goals:

- changing the control-plane API or readiness semantics;
- weakening the distroless/non-root/read-only runtime; and
- changing private Cloud deployment files.

## Owner

Public self-hosted release maintainer.

## Dependencies

- `deploy/self-hosted/control-plane.Dockerfile` compiles
  `packages/control_plane/bin/health_check.dart`; and
- the Compose control-plane service runs with the image's non-root user.

## Assumptions

- the compiled health-check executable is present at the image path supplied by
  the Dockerfile and uses `HYFENS_PORT` to find `/readyz`.

## Work Items

- [x] Replace the shell/curl healthcheck with the image-native executable.
- [x] Validate Compose configuration and the image recipe.
- [x] Review the correction and record the handoff.

## Validation

Executed on 2026-09-19:

- `docker compose config` with safe fixture values: passed;
- `docker build --file deploy/self-hosted/control-plane.Dockerfile .`:
  passed, including the compiled health-check executable; and
- `git diff --check` plus the OSS boundary scan: passed.

## Next Action

The distroless readiness path is corrected. Hand off the change for review;
hosted deployment remains outside local validation.

## Blockers

None expected; local validation requires a Docker daemon.

## Outcome

Compose now invokes `/usr/local/bin/hyfens-health-check` directly, so the
non-root distroless control-plane image no longer depends on a missing shell or
`curl` binary.

## References

- `deploy/self-hosted/control-plane.Dockerfile`
- `deploy/self-hosted/docker-compose.yml`
- `packages/control_plane/bin/health_check.dart`
- Task 297 public control-plane image

## History

- 2026-09-19: Reserved after combined review found that a distroless image
  cannot execute the previous shell/curl healthcheck.
- 2026-09-19: Switched the healthcheck to the compiled image-native executable;
  Compose configuration, Docker build, boundary scan, and diff checks passed.
