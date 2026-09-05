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

Or use Homebrew:

~~~bash
brew install hyfens-hq/tap/hyfens
~~~

On Windows with Scoop:

~~~powershell
scoop bucket add hyfens https://github.com/hyfens-hq/scoop-bucket
scoop install hyfens
~~~

## Check the installation

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

Use ios instead of android for an iOS patch. The patch command prints the
artifact path to verify. Deployment uses the active Hyfens profile.

## Flavors and monorepos

Automatic discovery is the normal path:

~~~bash
cd my_flutter_app
hyfens init
hyfens release android
~~~

If a project has several apps or flavors, Hyfens shows the candidates and
persists your choice. It never silently chooses a production flavor.

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

Pure Dart packages, Flutter plugins, and shared packages are not release
targets. You can also run Hyfens from the selected app directory.

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

## Hyfens Cloud and self-hosted

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

| Change | Patch |
| --- | :---: |
| Dart business logic | Verified subset |
| Flutter widgets, state and async code | Real-app CLI acceptance not yet proven |
| Changed, added or removed assets/fonts | New base release |
| New tree-shaken icon glyph | New base release |
| Native code, plugins or configuration | New base release |
| Flutter engine change | New base release |

Patches currently carry code, not asset or font bundles. Referencing an asset
already in the base is different from changing its bytes. See the
[support matrix](docs/dart-support-matrix.md) for exact boundaries and device
evidence. Broader real-application acceptance is still in progress.

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
- [Self-hosted deployment](deploy/self-hosted/README.md)
- [Architecture](docs/architecture/dashboard-separation.md)

## Contributing

Read the [contributing guide](CONTRIBUTING.md), [security policy](SECURITY.md),
and [developer documentation](docs/README.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
