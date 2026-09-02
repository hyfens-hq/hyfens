# Hyfens

Hyfens is an open-source Flutter live-update foundation for signed over-the-air
patches to supported ordinary Dart and Flutter code. The current OSS boundary
is a local and single-node self-hosted developer workflow. It is not a
production SaaS, high-availability service, or store-policy approval.

The public command name is `hyfens`:

```text
hyfens login → profile → hyfens init → release → patch → deploy
```

## Repository boundary

This public OSS repository contains the reusable runtime, CLI, self-hosted
control plane, and client dashboard under `dashboard/`. Managed marketing,
editorial, and hosted operations are outside this source tree and its release
archives. See the
[OSS/Cloud source boundary](docs/OSS_CLOUD_SOURCE_BOUNDARY.md) for the
deployment topology and the
[Cloud commercial boundary](docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md) for the
managed-service model.

The [developer platform contract](docs/HYFENS_DEVELOPER_PLATFORM_CONTRACT.md)
is the source of truth for this command surface and its security boundaries.

## License and editions

The Hyfens OSS software is licensed under the [Apache License 2.0](LICENSE)
(SPDX: `Apache-2.0`). It is self-hostable and includes the complete baseline
CLI, runtime, protocol, control-plane, dashboard, and single-node deployment
path. Third-party components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[docs/ASSET_PROVENANCE.md](docs/ASSET_PROVENANCE.md).

[Hyfens Cloud](docs/HYFENS_CLOUD_COMMERCIAL_BOUNDARY.md) is the managed
commercial service. Its value is hosted infrastructure, upgrades, monitoring,
backups, availability, security maintenance, team collaboration, advanced
rollout controls, enterprise governance, and support. The OSS and Cloud
products use the same CLI and core protocol; Cloud does not hide baseline
self-host functionality. Hyfens names and brand assets are governed separately
by [TRADEMARKS.md](TRADEMARKS.md).

## Install the CLI

The canonical executable is `hyfens`. The packaged `tool` executable is
only a deprecated compatibility shim.

### macOS / Linux

Install the latest published release without Dart or Flutter:

```bash
curl -fsSL https://raw.githubusercontent.com/hyfens-hq/hyfens/main/scripts/install-hyfens.sh | bash
```

Pin an explicit release with `--version v<version>`. The installer detects
macOS/Linux and x64/arm64, verifies `SHA256SUMS` before extraction, and
prints PATH guidance without modifying project files or `~/.hyfens`.

### Homebrew

The published Homebrew tap provides the same release archives:

```bash
brew tap hyfens-hq/tap
brew install hyfens
```

### Windows

The published Scoop bucket provides the same release archives:

```powershell
scoop bucket add hyfens https://github.com/hyfens-hq/scoop-bucket
scoop install hyfens
```

WinGet publication is an external Microsoft submission gate. Until it is
available, use the direct Windows archive from the GitHub Release.

### Direct release archive

Download the matching archive and verify its `SHA256SUMS` entry before
running `bin/hyfens`. See [CLI distribution](docs/cli-distribution.md) for
archive names, Windows PowerShell instructions, upgrade, and uninstall
guidance.

## Quick start

After installation, run these commands from the Flutter project you want to
operate on. See [Getting started](docs/getting-started.md) for the complete
local and self-hosted flow.

```bash
hyfens doctor
hyfens init
hyfens keys generate
hyfens status
hyfens release android

# Edit supported ordinary Dart/Flutter code, then:
hyfens patch android
hyfens deploy
```

The currently tested toolchain family is Flutter `3.47.x` with Dart `3.13.x`.
Other versions are outside the declared evidence boundary until separately
validated.

## Managed and self-hosted control planes

With no host override, the managed profile uses the currently proven Cloud API
base:

```text
https://api.hyfens.com/p2/
```

That URL is a versioned API base and health/readiness evidence, not a promise
of public signup, production availability, or a hosted release download.

For a self-hosted instance, select the endpoint once at login and keep it in a
named profile:

```bash
hyfens login --host https://hyfens.example.com --profile acme
hyfens profile current
hyfens profile use acme
```

Profiles contain endpoint and organization/application/environment metadata,
never passwords, JWTs, session secrets, bearer tokens, signing keys, or other
private material. Credentials are bound to the normalized endpoint origin and
API base path; a session from one host is not sent to another. Remote
credential-bearing requests require HTTPS. HTTP is permitted only for an
explicit loopback development endpoint such as `127.0.0.1`.

## Authentication and CI

Human sessions are separate from project configuration. The preferred storage
is the native OS credential store. The portable fallback is a `~/.hyfens/`
directory with mode `0700` and credential files with mode `0600`. Logout
revokes the server session and removes local session material. Access JWTs are
short-lived at the proven 15-minute (`15m`) value; server sessions are
revocable and last 30 days (`30d`) by default. Authentication signing material
is separate from Patch Format signing material.

The contract defines browser Authorization Code + PKCE and device-code login
interfaces. The static approval pages live under `dashboard/cli/authorize/`
and `dashboard/device/`; a deployment must advertise their URLs and allow the
dashboard origin explicitly. Use them only when the instance's
`/.well-known/hyfens` discovery response advertises the method. The
[self-hosted deployment guide](deploy/self-hosted/README.md) documents the
operator authentication seam.

For responsible vulnerability disclosure, see the
[security policy](SECURITY.md).

CI must use a scoped, expirable, revocable service/API key through
`HYFENS_TOKEN`; do not put a human session or a token value in source control:

```yaml
steps:
  - name: Deploy Hyfens patch
    env:
      HYFENS_TOKEN: ${{ secrets.HYFENS_TOKEN }}
    run: hyfens deploy
```

SSH is an infrastructure/operator mechanism, never a developer
authentication path.

## AI agents / MCP

The v0.1.1 CLI can serve the bounded Hyfens workflow to compatible coding
agents over local MCP stdio. Authenticate outside the client, then launch the
server:

```bash
hyfens login
hyfens mcp
```

The server reuses the selected Hyfens profile/session and exposes structured
project, release, patch, verification, deploy, rollback, and profile tools; it
does not pass raw credentials to the agent. The generic client process mapping
is `command: hyfens` with `args: [mcp]`. See the [MCP documentation](docs/mcp.md)
for self-hosted profiles, isolation details, the exact tool catalog, and
troubleshooting.

## What the workflow proves

Within the declared local evidence boundary, Hyfens can build an exact release
baseline, classify changes, create and verify a signed bounded patch, register
and promote it through a local/single-node control plane, and retain the
runtime's release/signature/sequence checks and base rollback behavior. The
runtime remains the authority for downloaded bytes; a server or object store
cannot make an invalid patch valid.

The supported patch subset is bounded. Native code, manifests, permissions,
entitlements, dependency changes, and unsupported Dart/Flutter semantics
require a normal store release or separate review. Hyfens makes no claim of
arbitrary-Dart patching, zero risk, App Store or Google Play approval, or
compliance certification.

## Self-hosted release

For a single-node installation from published versioned images, use the
[self-hosted release package](deploy/self-hosted/README.md). It includes
PostgreSQL, MinIO, the control plane, the dashboard, first-owner bootstrap
steps, and the required host-level TLS reverse-proxy boundary. It binds the
application ports to loopback by default and does not claim HA or managed
backups.

## Migration from `tool`

`tool` is a deprecated compatibility name, not a second CLI. For an existing
checkout:

1. Replace new command examples and scripts with `hyfens`.
2. Run `hyfens doctor` and `hyfens status` before changing project metadata.
3. Run `hyfens init` and review the generated `hyfens.yaml` binding. It must
   contain only safe organization/application/environment identifiers.
4. Keep any legacy `tool.yaml` and `.tool/` evidence until the new binding and
   a fresh release have been checked. Do not manually rename or copy these
   files to force a migration.
5. Keep signing keys and existing local release/patch evidence in their
   protected locations. Never copy session material into project files or
   profiles.
6. Re-authenticate per host and verify `hyfens profile current`; do not
   manually move credentials between endpoints.

Do not maintain independent `tool` and `hyfens` workflows. A checkout that
still exposes the compatibility entry point may emit a deprecation notice;
follow that notice and use the canonical name for new automation.

## External gates and backlog

The following remain explicit external gates or limitations:

- browser-PKCE or device-code auth as a generally deployed service feature;
- AWS/provider acceptance, public ingress hardening, durable object retention,
  production key recovery/rotation, or HA/DR;
- independent customer-application and physical-device acceptance beyond the
  recorded fixtures;
- App Store/Google Play, legal, or compliance approval;
- arbitrary Dart/native/dependency patching;
- WinGet submission, platform code signing/notarization, and any additional
  package-manager channels while their external repositories are being
  provisioned.

The CLI distribution workflow publishes direct GitHub Release archives. A
source checkout remains available for contributors and environments where a
native archive is not yet available.

See [CLI reference](docs/cli.md), [Getting started](docs/getting-started.md),
the [self-hosted deployment guide](deploy/self-hosted/README.md), and the
[support matrix](docs/dart-support-matrix.md) for public usage and limitations.
