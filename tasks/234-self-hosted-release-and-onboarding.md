# Self-hosted release and onboarding package

Status: [x] Completed

## Goal

Turn the current local-only Compose reference into an explicit, reproducible single-node self-hosted installation path using versioned release images and clear operator steps.

## Scope and Non-goals

Scope:

- Define the supported self-hosted topology and first-run configuration.
- Add a release-oriented Compose shape that consumes versioned OCI images rather than source builds.
- Make dashboard-to-control-plane routing configurable without baking a loopback-only endpoint into a published image.
- Document how an account connects a Flutter project to a managed or self-hosted control plane.

Non-goals:

- No HA, Kubernetes, billing, hosted entitlements, external identity provider, or production SLA claim.
- No automatic TLS certificate issuance or provider-specific infrastructure provisioning.
- No deletion, archive, rename, or recreation of GitHub repositories.

## Owner

Coordinator / self-hosting and deployment integration

## Dependencies

- Existing control-plane configuration and P2 Compose services.
- Existing dependency-free dashboard and `hyfens.yaml` project binding.
- CLI release image names and tags from task 235.

## Assumptions

- A customer-managed reverse proxy terminates HTTPS and routes the dashboard and control plane according to the documented topology.
- GHCR is the initial OCI registry for public release images; the exact repository owner/name is verified before publishing.
- PostgreSQL and S3-compatible object storage remain customer-operated stateful dependencies.

## Work Items

- [x] Audit current self-hosted, dashboard, and local Compose boundaries.
- [x] Add versioned image configuration and a bounded self-host Compose reference.
- [x] Add runtime-configurable dashboard API routing or an equivalent same-origin deployment shape.
- [x] Document first-owner bootstrap, dashboard login, CLI login, project binding, and upgrade/backup responsibilities.
- [x] Add targeted Compose/configuration checks and validate a clean local deployment.

## Validation

- `docker compose --env-file deploy/self-hosted/.env.example -f deploy/self-hosted/docker-compose.yml config --quiet` — passed.
- Dashboard image build, immutable-container runtime-config smoke test, and local `127.0.0.1:18083` health check — passed.
- Isolated self-host Compose rehearsal with temporary images and ports — passed health, readiness, discovery, scope bootstrap, and first-owner bootstrap; validation stack and volumes were removed afterward.
- `python3 -m unittest dashboard.test_serve` — 29 tests passed.

## Next Action

Verify the destination repository and publish a matching version tag before
using the release images in a customer installation.

## Blockers

External registry owner/repository naming and publication permissions must be verified before pushing images.

## Outcome

The self-hosted release package is implemented and validated locally. It uses
versioned GHCR image references, runtime dashboard API configuration, loopback
bindings, explicit TLS reverse-proxy guidance, protected first-owner
bootstrap, and account-to-project onboarding documentation.

## References

- `docs/self-hosted.md`
- `deploy/p2/docker-compose.yml`
- `deploy/p2/docker-compose.dashboard.yml`
- `dashboard/Dockerfile`
- `dashboard/nginx.conf`
- `dashboard/docker-entrypoint.sh`
- `dashboard/runtime-config.js`
- `deploy/self-hosted/docker-compose.yml`
- `deploy/self-hosted/.env.example`
- `deploy/self-hosted/nginx.conf.example`
- `deploy/self-hosted/README.md`
- `cli/lib/src/cli_runner.dart`
- `cli/lib/src/configuration.dart`

## History

- 2026-09-02: Reserved task 234 after confirming that self-hosted packaging is documented as backlog and the current dashboard image is loopback-baked.
- 2026-09-02: Added versioned single-node Compose packaging, runtime dashboard routing, GHCR image-release integration, and operator onboarding documentation; local image and Compose rehearsal passed.
