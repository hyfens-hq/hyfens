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
control plane, and client dashboard under `dashboard/`. It is intentionally
limited to the local and self-hosted product surface; deployment-specific
services, credentials, operator procedures, and commercial implementation
remain outside this tree.

The documentation under `docs/` is the source of truth for the public command
surface and its security boundaries.

## License and editions

The Hyfens OSS software is licensed under the [Apache License 2.0](LICENSE)
(SPDX: `Apache-2.0`). It is self-hostable and includes the complete baseline
CLI, runtime, protocol, control-plane, dashboard, and single-node deployment
path. Third-party components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[docs/ASSET_PROVENANCE.md](docs/ASSET_PROVENANCE.md).

Hosted services and other commercial editions are separate products and are
not part of this source distribution. The OSS edition remains self-hostable;
Hyfens names and brand assets are governed separately by
[TRADEMARKS.md](TRADEMARKS.md).

## Dashboard surfaces

The authenticated web product provides one tenant-scoped workspace over the
same authentication, API transport, and UI system:

- **Workspace** — the tenant-scoped developer workspace for an organization’s
  applications, environments, delivery records, audit, credentials, and
  settings.

The dashboard uses the selected instance origin. DNS and production routing
remain deployment configuration, not a requirement for the shared static
bundle. The organization selector contains only organizations the signed-in
user belongs to.

## Quick start

The CLI package is not published to pub.dev because it uses repository path
dependencies. For normal installation use the [CLI distribution guide](docs/cli-distribution.md).
For contributors or environments without a native release, use a source
checkout:

```bash
export HYFENS_CHECKOUT=/absolute/path/to/hyfens
cd "$HYFENS_CHECKOUT/cli"
dart pub get

# Keep the canonical public name while running the source checkout.
hyfens() {
  dart run "$HYFENS_CHECKOUT/cli/bin/hyfens.dart" "$@"
}
```

Run the function from the Flutter project you want to operate on. The source
entry file is named `tool.dart` only for compatibility with the existing
checkout; `hyfens` is the documented command name. Tagged releases build
native macOS, Linux, and Windows archives with SHA-256 checksums. Installed
release binaries can update themselves with `hyfens upgrade`; source-checkout
invocations should use the documented installer for upgrades. See
[CLI distribution](docs/cli-distribution.md) for the release workflow and
[Getting started](docs/getting-started.md) for the complete local flow.

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

For flavor-based Flutter apps, select the native flavor and its Dart
entrypoint explicitly (or configure the mapping in `tool.yaml`):

```bash
hyfens release android --flavor local --entrypoint lib/src/flavors/local.dart
hyfens patch android --flavor local
```

The CLI requires `flutter pub get` before release discovery and records the
selected entrypoint in the release baseline. See the [CLI reference](docs/cli.md)
for target/flavor mappings and the safe `hyfens detach` command, which removes
only Hyfens project metadata and local evidence after explicit confirmation.

The currently tested toolchain family is Flutter `3.47.x` with Dart `3.13.x`.
Other versions are outside the declared evidence boundary until separately
validated.

## Self-hosted control planes

`hyfens login` uses the local development endpoint when no host is supplied.
For a deployed instance, select the endpoint explicitly and keep it in a named
profile.

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

For an installed CLI, check for and install the latest stable release with:

```bash
hyfens upgrade
```

Use `hyfens upgrade --check` to check without changing the installed binary.
The command verifies the release archive checksum before activation and does
not modify profiles or project files. `hyfens mcp` starts the local stdio MCP
server for compatible AI coding agents; its startup message is written to
stderr so protocol output remains valid.

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
for the local transport, profile isolation, tool catalog, and troubleshooting.

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
application ports to loopback by default and does not claim high availability
or backup automation.

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

The following are intentionally not claimed by the public workflow:

- browser-PKCE or device-code auth as a generally deployed service feature;
- AWS/provider acceptance, public ingress hardening, durable object retention,
  production key recovery/rotation, or HA/DR;
- independent customer-application and physical-device acceptance beyond the
  recorded fixtures;
- App Store/Google Play, legal, or compliance approval;
- arbitrary Dart/native/dependency patching;
- WinGet publication, code signing, or a global registry installer. GitHub
  Release archives, the curl installer, Homebrew, and Scoop are documented in
  the [CLI distribution guide](docs/cli-distribution.md).

The public `v0.1.1` distribution publishes direct GitHub Release archives and
supports the documented curl, Homebrew, and Scoop channels. The source
checkout remains the contributor fallback.

See [CLI reference](docs/cli.md), [Getting started](docs/getting-started.md),
the [self-hosted deployment guide](deploy/self-hosted/README.md), and the
[support matrix](docs/dart-support-matrix.md) for public usage and limitations.
