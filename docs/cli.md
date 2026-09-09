# Hyfens CLI

Status: bounded local/self-hosted developer workflow with explicit external
gates. The canonical executable name is `hyfens`.

The CLI builds releases from ordinary Flutter/Dart source, creates signed
bounded patches, verifies them, and deploys them through a selected control
plane. The runtime remains the final authority for patch bytes, exact release
binding, capabilities, sequence/high-water, health, rollback, and fallback.

## Source checkout invocation

The package manifest deliberately has `publish_to: none` and uses repository
path dependencies, so pub.dev is not the distribution channel. Tagged GitHub
Releases build native archives for macOS, Linux, and Windows. Use the
[CLI distribution guide](cli-distribution.md) for normal binary installation;
use a checkout when contributing or when a native release is unavailable:

```bash
export HYFENS_CHECKOUT=/absolute/path/to/hyfens
cd "$HYFENS_CHECKOUT/cli"
dart pub get
```

From the Flutter project being operated on, give the source runner its
canonical shell name:

```bash
hyfens() {
  dart run "$HYFENS_CHECKOUT/cli/bin/hyfens.dart" "$@"
}
```

`cli/bin/hyfens.dart` is the canonical source entry point. `cli/bin/tool.dart`
is retained only as the deprecated compatibility shim; it is not a second
public CLI. Release archives include both executables, checksums, and a
machine-readable inventory. Homebrew, Scoop, and WinGet publication is separate
from the GitHub Release and must point at a real published archive; use each
package manager's own upgrade command for package-managed installations.

## Public command surface

```text
hyfens --help | -h | help
hyfens --version | -v | version
hyfens upgrade [--check] [--version VERSION]
hyfens login [--host URL] [--profile NAME] [--device]
hyfens logout
hyfens status
hyfens doctor
hyfens profile list|show|use|remove|current|bind
hyfens auth login|status|logout
hyfens init
hyfens analyze
hyfens release android|ios
hyfens patch android|ios
hyfens rollback
hyfens cleanup
hyfens detach
hyfens inspect
hyfens verify <patch-file>
hyfens keys generate|inspect
hyfens serve
hyfens deploy
hyfens rollout create|inspect|transition
hyfens bundle export|verify|import|admit
hyfens mcp [--profile NAME] [--debug]
```

`hyfens --help`, `hyfens -h`, and `hyfens help` show the same root usage.
Every listed command and subcommand accepts `--help`; use
`hyfens <command> --help` (or `hyfens help <command>`) for its options. The
deprecated `tool` executable delegates to this same help and command surface
after printing its migration notice.

## Endpoint and profile selection

With no host override, `hyfens login` selects the built-in Hyfens Cloud
profile. Its managed service endpoint is intentionally not shown in public
CLI help, examples, or profile display output. This keeps an implementation
route from becoming part of the user-facing configuration contract.

Choose a self-hosted control plane explicitly:

```bash
hyfens login \
  --host https://hyfens.example.com \
  --profile acme
```

The CLI normalizes the host/API base, performs compatibility discovery, stores
the selected endpoint in the profile, and reuses it for normal commands. The
profile maps one endpoint to an authenticated session and an
organization/application/environment scope. A conceptual profile contains
metadata like this:

```toml
active_profile = "acme"

[profiles.acme]
endpoint = "https://hyfens.example.com/"
managed = false
organization = "org_..."
application = "app_..."
environment = "env_..."
```

The exact file format may follow the platform implementation, but profile
semantics do not change: no password, session secret, JWT, bearer token,
signing key, or private key is stored in profile/configuration metadata. A
credential is keyed to the normalized endpoint origin and API base path, so it
cannot silently cross hosts.

The managed profile's exact endpoint is stored internally for host-bound
credential lookup. It is represented as `Hyfens Cloud (managed)` in CLI and
MCP output. Self-hosted endpoint URLs remain visible so operators can confirm
which server they selected.

After a verified Cloud account is created, `hyfens login` uses the customer
audience and stores the organization scope returned by the control plane. Bind
the first application and environment as they are created:

```bash
hyfens profile bind \
  --organization-id org_... \
  --application-id app_... \
  --environment-id env_...
```

The values are identifiers only; bearer tokens and session secrets remain in
the credential store. Use `hyfens profile current` to inspect the active
non-secret context, or `hyfens profile use NAME` when working with more than
one organization or control plane.

## Upgrade an installed CLI

Run the following from a compiled Hyfens release installation:

```bash
hyfens upgrade
```

The command resolves the latest stable GitHub Release, verifies its
`SHA256SUMS` entry, and activates the new binary without changing Hyfens
profiles, credentials, or project files. Use `hyfens upgrade --check` to check
without installing, or `hyfens upgrade --version 0.1.1` to request a specific
release. A source checkout invoked through `dart run` cannot replace the Dart
process; use the public installer or a release archive instead.

## AI agents / MCP

The installed CLI includes a local stdio MCP server:

```bash
hyfens mcp
```

It reuses the active authenticated profile and exposes structured Hyfens
operations to compatible coding agents. Use `--profile NAME` for a named
self-hosted profile and `--debug` for diagnostics on stderr. The server's
stdout is reserved for MCP protocol messages.

Remote credential-bearing requests require HTTPS. HTTP is allowed only for
explicit loopback development, for example:

```bash
hyfens login --host http://127.0.0.1:18082 --profile local
```

Every compatible control plane advertises its versioned, non-secret contract
at `GET /.well-known/hyfens` relative to its configured API base. The CLI
rejects an unsupported response with a compatibility diagnostic; compatibility
is determined by the discovery response, not by the hostname.

## Local Auvana demo

For the repository's local Auvana demo, start the disposable Compose fixture
and use its protected credential file:

```bash
sh scripts/local-dashboard.sh demo
sh scripts/local-dashboard.sh demo-credentials
hyfens login --host http://127.0.0.1:18082 --profile auvana-demo
```

The seeded owner can test the normal `doctor`, `init`, `release`, `patch`, and
`deploy` flow against a real Flutter project. When the configured platform
profile is selected in the dashboard, its `Platform` page provides read-only
aggregate metrics rather than cross-tenant records.

## Authentication and session storage

The preferred human login is Authorization Code + PKCE:

```text
CLI → browser authorization → loopback callback → one-time code exchange
    → revocable server session → short-lived access JWT
```

The browser interface requires random state, S256 PKCE, exact redirect
validation, a short-lived single-use code, and no session secret in a URL.
Headless login is exposed by the target device interface:

```bash
hyfens login --device
```

Browser-PKCE uses the static `/cli/authorize/` page and device-code auth uses
the static `/device/` page when the deployment advertises those URLs. Use
them only when discovery advertises the method. The bounded human-auth seam
and one-time owner bootstrap are described in the
[self-hosted deployment guide](../deploy/self-hosted/README.md).

Self-hosted first-owner bootstrap accepts a password only through the
server-local `--bootstrap-owner --password-stdin` seam. Do not pass that
password as an argument or place it in a profile, project file, image, or log.

Access JWTs use the currently proven 15-minute (`15m`) lifetime. Server-side
sessions are revocable and use the currently proven 30-day (`30d`) lifetime.
Authentication JWT keys and Patch Format signing keys are separate trust
boundaries.

The CLI prefers the native OS credential store (macOS Keychain, Windows
Credential Manager, or Linux Secret Service). The portable fallback is:

```text
~/.hyfens/       mode 0700
credentials     mode 0600
```

The fallback stores only the session material needed by the implementation and
is excluded from the repository. `hyfens status` and profile commands display
metadata, not secrets. `hyfens logout` revokes the server session and removes
local session material.

## Project commands

### `hyfens doctor`

Checks the Flutter/Dart toolchain and project prerequisites. The currently
tested family is Flutter `3.47.x` with Dart `3.13.x`; other versions should be
treated as not tested until evidence is added.

### `hyfens status`

Reports a bounded, read-only local projection of project configuration and
Hyfens-owned release/patch artifacts. It does not introspect a running app,
invent fleet telemetry, or report a remote runtime health state.

### `hyfens profile ...`

Lists, displays, selects, removes, or reports the current non-secret endpoint
scope. Removing a profile does not mean copying its credentials to another
host; authenticate again for the destination.

### `hyfens init`

Detects the Flutter project and platform application identities, resolves the
active profile, and writes a minimal committed `hyfens.yaml` binding. It must
contain only safe organization/application/environment identifiers. It does
not write credentials or signing material, and it reports an application
identity mismatch rather than weakening exact checks.

### `hyfens release android|ios`

Creates a target-specific release baseline from the normal Flutter build path.
Use a normal release build for compatibility evidence; metadata-only shortcuts,
if exposed by a local version, are test conveniences and not build evidence.

For a flavor-based application, select the native flavor and the Dart file that
declares that flavor's `main()` function:

```bash
hyfens release android \
  --flavor local \
  --entrypoint lib/src/flavors/local.dart
```

`--entrypoint` is project-relative and must point to a regular Dart file under
`lib/`. The CLI never guesses between multiple flavor files. To avoid
repeating the path, add a target/flavor map to `tool.yaml`:

```yaml
application_id: com.example.app

# Use these only when native flavors have distinct runtime application IDs.
application_ids:
  android:
    local: com.example.app.local
    prod: com.example.app

entrypoints:
  android:
    local: lib/src/flavors/local.dart
    staging: lib/src/flavors/staging.dart
    prod: lib/src/flavors/prod.dart
  ios:
    local: lib/src/flavors/local.dart
    staging: lib/src/flavors/staging.dart
    prod: lib/src/flavors/prod.dart
```

The special `default` mapping is used when no `--flavor` is supplied. A
flavor without a mapping must be paired with `--entrypoint`; this prevents the
common mistake of instrumenting `lib/main.dart` for the wrong native variant.
Run `flutter pub get` before `hyfens release` so
`.dart_tool/package_config.json` describes the current workspace. The selected
flavor and entrypoint become part of the immutable release identity and are
reused for later analysis and patch creation.

### `hyfens patch android|ios`

Analyzes the current source against the exact release, compiles the supported
change, signs the Patch Format artifact locally, and verifies it before it is
ready for deployment. Unsupported source constructs must fail with a
diagnostic; the CLI must not silently broaden the patchability boundary.

### `hyfens inspect` and `hyfens verify`

Inspect local artifact metadata and verify the exact patch bytes against the
selected release and trusted public key. Verification is required before
deployment.

### `hyfens deploy`

Registers immutable release/patch metadata, uploads the exact signed bytes, and
promotes them through the selected control plane with its authorization and
preconditions. Human commands use the active profile. CI uses the scoped
`HYFENS_TOKEN` service/API key; the token is injected by the CI secret store and
is never persisted by project configuration.

### `hyfens rollback`

Creates or requests the bounded signed rollback-to-base operation for the
selected release. Rollback does not make an older patch replayable and does not
lower the runtime's anti-replay high-water.

With a managed Cloud profile, use `hyfens rollback --cloud` to submit the
authenticated request for the profile's bound organization, application, and
environment. The runtime receives the signed control on its next Cloud poll;
an already-running process may need a relaunch before rendered UI reflects the
base release. Local and self-hosted profiles retain the existing local control
path and do not use the Cloud rollback endpoint.

### `hyfens detach`

Detaches the current Flutter checkout from Hyfens; it is intentionally separate
from runtime `rollback`. Runtime rollback records a signed return to the
trusted installed base. Detach removes local project integration metadata and
the Hyfens-owned `.tool` store; it does not change a deployed app, remote
control-plane records, Flutter source, Android/iOS files, `pubspec.yaml`, or
the CLI installation.

Preview first, then confirm the exact destructive operation:

```bash
hyfens detach --dry-run
hyfens detach --confirm DETACH
```

By default this removes `tool.yaml`, `hyfens.yaml`, `.tool/` (including local
release/patch evidence and signing keys), and nothing else. Because
`tool.yaml` is a generic filename, a lone `tool.yaml` without a Hyfens binding
or `.tool/` store is retained for manual review. Use `--keep-keys` when the
local signing key must be retained while releases and
patch artifacts are removed:

```bash
hyfens detach --confirm DETACH --keep-keys
```

Detach refuses to proceed if `.tool` contains unexpected entries, symbolic
links, special files, or malformed metadata. It makes no changes in that case;
inspect the store manually before retrying. It also refuses to delete a
metadata path that cannot be verified as a Hyfens v1 configuration.

## Self-hosted Docker validation

The public single-node Compose package is documented in the
[self-hosted deployment guide](../deploy/self-hosted/README.md). It binds the
application ports to loopback by default. Check both control-plane endpoints
and the dashboard health endpoint after starting the package:

```bash
curl --fail http://127.0.0.1:18082/healthz
curl --fail http://127.0.0.1:18082/readyz
curl --fail http://127.0.0.1:18083/healthz
```

`healthz` is process liveness; `readyz` includes the configured metadata and
artifact-store dependencies. The Compose stack is a bounded single-node
reference environment, not HA, internet-scale capacity, or a production
deployment. The deployment guide covers TLS, bootstrap, backup/restore, and
cleanup details.

## CI example

Only the service/API key belongs in a CI secret store. A human browser/device
session is not the CI contract:

```yaml
steps:
  - name: Deploy verified patch
    env:
      HYFENS_TOKEN: ${{ secrets.HYFENS_TOKEN }}
    run: hyfens deploy
```

Do not put `HYFENS_TOKEN` values in `hyfens.yaml`, profile files, command
arguments, logs, artifacts, or Docker images. SSH remains an operator
infrastructure mechanism, never developer authentication.

## Migration from `tool`

`tool` is a deprecated compatibility name. It may remain as a shim that
delegates to the same command runner and emits:

```text
tool is deprecated; use hyfens
```

For an existing checkout, replace new examples and scripts with `hyfens`, run
`hyfens doctor` and `hyfens status`, then run `hyfens init` and review the
generated `hyfens.yaml`. Keep legacy `tool.yaml` and `.tool/` evidence until a
new binding and fresh release have been verified; do not manually rename or
copy them. Preserve existing release/patch evidence and private signing
material in protected locations. Do not manually move session material or
rename files to bypass a migration boundary. Re-authenticate per host and
confirm the selected scope with `hyfens profile current`.

There must not be two independent workflows. Existing historical fixtures and
evidence may retain the compatibility name; new public documentation does not.

## Supported boundary and external gates

The current claims are limited to signed, exact-release, bounded Flutter
patches through the tested local/self-hosted path. They do not include:

- arbitrary Dart, native code, manifests, permissions, entitlements, or
  dependency changes as OTA patches;
- production availability, HA/DR, public-ingress hardening, compliance, or
  App Store/Google Play approval;
- AWS/provider acceptance, durable object-retention/recovery operations, or
  production signing-key custody/rotation;
- independent customer-application or physical-device acceptance beyond the
  recorded fixtures;
- a generally deployed browser-PKCE/device-code login;
- WinGet publication, code signing, or a global registry installer. GitHub
  Release archives, the curl installer, Homebrew, and Scoop are documented in
  the [CLI distribution guide](cli-distribution.md).

These are explicit external gates or backlog, not implicit guarantees. The
public `v0.1.1` release provides direct GitHub archives, curl installation,
Homebrew, and Scoop; WinGet remains a separate external setup step. The
[frozen contract](HYFENS_DEVELOPER_PLATFORM_CONTRACT.md) defines the shared
acceptance boundary.
