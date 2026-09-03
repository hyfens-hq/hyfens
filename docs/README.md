# Hyfens documentation

Status: AUTHORITATIVE navigation for the current public repository.

Hyfens is an open-source Flutter live-update foundation. The documents below
describe the current bounded product and its self-hosted developer workflow.
Milestone reviews and historical evidence are kept separately under
[`history/`](history). Internal research notes and generated evidence remain
outside the public documentation tree.

## Get started

- [Getting started](getting-started.md) — install, authenticate, bind a
  Flutter project, and run the release/patch workflow.
- [CLI distribution](cli-distribution.md) — release binaries, installers, and
  package-manager status.
- [Self-hosted deployment](../deploy/self-hosted/README.md) — the single-node
  PostgreSQL, MinIO, control-plane, and dashboard package.
- [Dart/Flutter support matrix](dart-support-matrix.md) — supported toolchain
  boundary and known limitations.

## CLI

- [CLI reference](cli.md) — command surface, profiles, authentication, and
  project workflow.
- [MCP](mcp.md) — the built-in stdio server for compatible AI coding agents.
- [Diagnostics](diagnostics.md) — stable diagnostic codes and remediation.

## Product surfaces

- [Customer Workspace](product/customer-workspace.md) — the tenant-scoped
  developer workspace at `app.hyfens.com` or a self-hosted origin.
- [Platform Console](product/platform-console.md) — the privileged Hyfens
  operator surface at `admin.hyfens.com`.
- [Cloud and self-hosted boundary](HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md) — what
  is provided by the managed service versus the Apache-licensed foundation.

## Architecture

- [Architecture overview](architecture/dashboard-separation.md) — the two
  dashboard shells, shared infrastructure, routes, APIs, and authorization.
- [Control plane](architecture/control-plane.md)
- [Runtime](architecture/runtime.md)
- [Patch lifecycle](architecture/patch-lifecycle.md)
- [Patch format specification](spec/patch-format-v1.md)
- [Domain and tenancy](architecture/domain-tenancy.md)
- [Self-hosted operations](../deploy/self-hosted/README.md)

## Security and governance

- [Security reporting](../SECURITY.md)
- [Security architecture](architecture/security.md)
- [Asset provenance](ASSET_PROVENANCE.md)
- [Apache license](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md),
  and [trademarks](../TRADEMARKS.md)
- [Contributing](../CONTRIBUTING.md)

## Reference and history

- [Compatibility](dart-support-matrix.md)
- [Release and rollout reference](architecture/rollouts-observability.md)
- [Historical reviews](history/reviews/README.md)

Documents in the historical and research areas are evidence or decision
records. When they disagree with the current product guides, the current
guides and linked source contracts take precedence.
