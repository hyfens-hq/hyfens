# Task 297: Public control-plane image

Status: [x] Completed

## Goal

Provide the public, reproducible control-plane image recipe required by the
release workflow without importing private Cloud deployment code or secrets.

## Scope and Non-goals

Scope is the checked-in Docker build recipe, its runtime hardening, and the
release documentation/workflow contract. This does not change application
authorization, database migrations, private Cloud deployment, or registry
settings.

## Owner

Coordinator

## Dependencies

- The public `packages/control_plane` package and its `packages/patch_format`
  path dependency.
- The existing release-image workflow and self-hosted Compose contract.

## Assumptions

- Production Compose supplies PostgreSQL and object-store configuration, so the
  control-plane process can run with a read-only root filesystem and a tmpfs
  for transient files.
- The release workflow remains responsible for exact image digest capture and
  OIDC/Sigstore attestation.

## Work Items

- [x] Add a minimal multi-stage control-plane image recipe.
- [x] Apply read-only/non-root runtime settings to the self-hosted Compose
  service.
- [x] Validate the recipe and update release documentation.

## Validation

- `docker build --file deploy/self-hosted/control-plane.Dockerfile .` when a
  Docker daemon and network
  are available.
- `docker compose config` for the self-hosted deployment.
- `git diff --check` and the existing release workflow/actionlint checks.

## Next Action

Keep the base-image digests and release attestations under the normal release
review process.

## Blockers

None currently.

## Outcome

The missing public control-plane Dockerfile is now present. It builds a
minimal distroless non-root image and the self-hosted Compose service has
read-only runtime hardening. Release documentation no longer describes the
recipe as missing.

## References

- `.github/workflows/release-images.yml`
- `deploy/self-hosted/docker-compose.yml`

## History

- 2026-09-19: Reserved to remove the missing public control-plane image recipe
  blocker found during the release security review.
- 2026-09-19: Added the multi-stage image and Compose hardening; local Docker
  build and Compose config validation passed. The recipe lives under the
  public self-hosted deployment path; the OSS boundary checker continues to
  reject reserved hosted/operator-only paths.
- 2026-09-19: Post-completion review found the distroless image could not run
  the shell/curl Compose healthcheck; Task 299 corrected it to use the
  compiled image-native health-check executable.
