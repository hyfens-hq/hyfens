<p align="center">
  <img src="dashboard/brand-mark.svg" alt="Hyfens logo" width="96">
</p>

<h1 align="center">Hyfens</h1>

<p align="center">
  Ship supported Dart fixes to your Flutter app without rebuilding and
  reinstalling the whole app.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache License 2.0"></a>
  <a href="https://github.com/hyfens-hq/hyfens/releases"><img src="https://img.shields.io/github/v/release/hyfens-hq/hyfens" alt="Latest release"></a>
</p>

## What is Hyfens?

Hyfens lets a Flutter team create a native release once, then deliver signed
updates to supported Dart and Flutter code.

The public project includes the Hyfens CLI, runtime, MCP server, control plane,
and Customer/Instance Workspace for self-hosted installations. The private
Hyfens Cloud Platform Console is not part of the public dashboard image.

## Install

On macOS or Linux, install the latest native CLI:

~~~bash
curl -fsSL https://raw.githubusercontent.com/hyfens-hq/hyfens/main/scripts/install-hyfens.sh | bash
~~~

## Dashboard surfaces

The authenticated web product has two explicit surfaces over the same
authentication, API transport, and UI system:

- **Customer Workspace** — the tenant-scoped developer workspace for an
  organization’s applications, environments, delivery records, audit, team,
  credentials, and settings.
- **Platform Console** — the privileged Hyfens operator surface for platform
  metrics, the bounded organization directory, organization inspection, and
  platform-audience audit/operations views.

The intended managed hosts are `app.hyfens.com` for the Customer Workspace and
`platform.hyfens.com` for the Platform Console. Local development exposes the
same split as `/` and `/platform`; a self-hosted instance exposes the Customer
Workspace on its own instance origin. DNS and production routing remain
deployment configuration, not a requirement for the shared static bundle.

The customer organization selector contains only organizations the signed-in
user belongs to. It is not a platform-wide directory. Platform routes use an
explicit platform audience and server-side capability checks. See the
[dashboard separation architecture](docs/architecture/dashboard-separation.md)
for the route and authorization contract.

## Quick start

The CLI package is not published to pub.dev because it uses repository path
dependencies. For normal installation use the [CLI distribution guide](docs/cli-distribution.md).
For contributors or environments without a native release, use a source
checkout:

On Windows with Scoop:

~~~powershell
scoop bucket add hyfens https://github.com/hyfens-hq/scoop-bucket
scoop install hyfens
~~~

Run the function from the Flutter project you want to operate on. The source
entry file is named `tool.dart` only for compatibility with the existing
checkout; `hyfens` is the documented command name. Tagged releases build
native macOS, Linux, and Windows archives with SHA-256 checksums. Installed
release binaries can update themselves with `hyfens upgrade`; source-checkout
invocations should use the documented installer for upgrades. See
[CLI distribution](docs/cli-distribution.md) for the release workflow and
[Getting started](docs/getting-started.md) for the complete local flow.

~~~bash
hyfens --version
hyfens doctor
~~~

## Your first Hyfens project

Sign in, then run Hyfens from your Flutter project:

~~~bash
hyfens login

cd my_flutter_app
hyfens doctor
hyfens init
hyfens keys generate
~~~

Hyfens reads the project automatically. It can find normal Flutter apps,
flavors, custom Dart entrypoints, Melos workspaces, Pub Workspaces, and
multiple apps. It asks only when it cannot choose safely. The saved
hyfens.yaml file contains project and release selection metadata, not
credentials or signing keys.

## Create your first release

A release is the native application baseline that can later receive patches.

~~~bash
hyfens release android
~~~

For iOS, run:

~~~bash
hyfens release ios
~~~

## Ship your first patch

Change supported Dart or Flutter code, then create and verify a signed patch:

~~~bash
hyfens patch android
hyfens verify <patch-file>
hyfens deploy
~~~

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

## Flavors and monorepos

With no host override, `hyfens login` uses the built-in Hyfens Cloud profile.
The managed service endpoint is intentionally kept out of public CLI examples
and display output; it is an implementation detail of that profile. Use the
self-hosted form below when selecting an explicit server.

For a Melos or Pub Workspace, run from the workspace root:

~~~text
my_workspace/
  apps/
    mobile/
  packages/
    design_system/
    api/
~~~

~~~bash
cd my_workspace
hyfens init
hyfens release android
~~~

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

### Advanced overrides

Use overrides for CI, temporary alternate builds, or an ambiguous repository:

~~~bash
hyfens init --project apps/mobile
hyfens release android --flavor dev
hyfens patch android --flavor dev
hyfens release android --entrypoint lib/src/flavors/dev.dart
~~~

The project selector is relative to the repository. The flavor and entrypoint
must describe the same application configuration used by the release.

Read the complete [project discovery guide](docs/cli/project-discovery.md) for
workspace selection, CI behavior, toolchain managers, and diagnostics.

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

Hyfens Cloud is the managed service:

~~~bash
hyfens login
~~~

For a self-hosted control plane, provide its HTTPS host:

~~~bash
hyfens login --host https://your-hyfens.example.com
~~~

Self-hosted deployments include the Customer/Instance Workspace. See the
[self-hosting guide](deploy/self-hosted/README.md).

## MCP and AI agents

Run the built-in MCP server for a compatible coding agent:

~~~bash
hyfens mcp
~~~

See the [MCP guide](docs/mcp.md) for setup and tool details.

## What can be patched?

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

## Common fixes

**Hyfens found multiple apps**

Run hyfens init and choose the app, or use
hyfens release android --project apps/mobile.

**Hyfens found multiple flavors**

Run hyfens init to save one, or pass --flavor explicitly for a temporary
build.

**No valid Dart entrypoint**

Check the project with hyfens doctor and pass --entrypoint only when the
entrypoint is a real executable Dart file.

**A native change was detected**

Create a new native release. Hyfens fails closed instead of producing an
unsafe patch.

**Not logged in**

Run hyfens login and check the selected profile with hyfens profile current.

## Learn more

- [Getting started](docs/getting-started.md)
- [CLI reference](docs/cli.md)
- [Project discovery](docs/cli/project-discovery.md)
- [Flutter support matrix](docs/dart-support-matrix.md)
- [Release process](docs/releases/releasing.md)
- [Changelog](CHANGELOG.md)
- [Self-hosted deployment](deploy/self-hosted/README.md)
- [Architecture](docs/architecture/dashboard-separation.md)

## Contributing

Read the [contributing guide](CONTRIBUTING.md), [security policy](SECURITY.md),
and [developer documentation](docs/README.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
