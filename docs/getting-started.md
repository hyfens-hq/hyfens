# Getting started

This guide runs the bounded Hyfens developer workflow against either the
managed default or a self-hosted control plane. The current Hyfens release
provides native CLI archives through GitHub Releases; the source checkout
remains the contributor fallback. The CLI uses repository path dependencies
rather than pub.dev.

The tested toolchain family is Flutter `3.47.x` with Dart `3.13.x`.

## 1. Install the CLI

On macOS or Linux, install the latest release without Dart or Flutter:

```bash
curl -fsSL https://raw.githubusercontent.com/hyfens-hq/hyfens/main/scripts/install-hyfens.sh | bash
```

The installer detects x64/arm64, verifies the downloaded archive against
`SHA256SUMS`, and prints PATH guidance. Pin a published release with
`--version v0.1.0`. Direct Windows archives and PowerShell verification are
documented in [CLI distribution](cli-distribution.md).

Package-manager installs are:

```bash
brew install hyfens-hq/tap/hyfens
```

```powershell
scoop bucket add hyfens https://github.com/hyfens-hq/scoop-bucket
scoop install hyfens
```

WinGet remains an external Microsoft submission gate. For contributors who
need a source checkout:

```bash
export HYFENS_CHECKOUT=/absolute/path/to/hyfens
cd "$HYFENS_CHECKOUT/cli"
flutter pub get
hyfens() {
  dart run "$HYFENS_CHECKOUT/cli/bin/hyfens.dart" "$@"
}
```

The `tool.dart` source filename is a compatibility detail. New scripts and
documentation use `hyfens`; there is no second implementation. Do not copy a
session file, token, or private signing key into the checkout.

## 2. Select an endpoint and authenticate

The managed default is the canonical Cloud API base:

```text
https://api.hyfens.com/
```

Existing profiles using `https://api.hyfens.com/p2/` continue to work and are
adopted to the canonical root when the CLI reads their session. `/p2/` is a
legacy deployment alias, not an API version.

Use the default profile for managed work:

```bash
hyfens login
hyfens profile current
```

For self-hosting, provide the HTTPS API base or host once and name the profile:

```bash
hyfens login \
  --host https://hyfens.example.com \
  --profile acme
hyfens profile show acme
```

For the local Docker fixture, loopback HTTP is the one development exception
to the HTTPS rule:

```bash
hyfens login --host http://127.0.0.1:18082 --profile local
```

That command requires human authentication to be enabled in the fixture. The
Compose startup and one-time owner bootstrap are documented in the
[self-hosted release guide](../deploy/self-hosted/README.md). Remote non-loopback
credential-bearing flows must use HTTPS.

The first self-hosted owner is created only through the server-local
`--bootstrap-owner --password-stdin` seam. Supply the password through a
protected secret/stdin mechanism, never as a command argument, committed
configuration, or profile value.

Profiles are non-secret selections for an endpoint and its
organization/application/environment scope. Credentials are stored separately
and are bound to the normalized endpoint origin and API base path, so a
session from one host cannot be sent to another.

Human login uses a short-lived 15-minute (`15m`) access JWT backed by a
revocable 30-day (`30d`) server session. The CLI prefers the native OS
credential store. Its portable fallback is `~/.hyfens/` with mode `0700` and
credential files with mode `0600`. Profile/configuration metadata contains no
password, JWT, bearer token, session secret, signing key, or private key.
`hyfens logout` revokes the server session and removes local session material.

Browser Authorization Code + PKCE and device-code login use the static
approval pages under `dashboard/cli/authorize/` and `dashboard/device/` when
the selected deployment advertises their URLs. Use them only when
`GET /.well-known/hyfens` on the selected API base advertises the method. The
discovery response is the compatibility check, not the hostname.

## 3. Check and bind the Flutter project

Run the read-only checks first:

```bash
hyfens doctor
hyfens status
```

`doctor` checks the local Flutter/Dart and project prerequisites. `status`
reports a bounded local projection of the toolchain and Hyfens-owned release
and patch metadata; it does not introspect a running application.

Initialize the project binding:

```bash
hyfens init
hyfens keys generate
```

`init` detects the Flutter project and platform application identity, resolves
the active profile, and writes a minimal committed `hyfens.yaml` binding. It
must contain safe organization/application/environment identifiers only. It
does not write credentials or signing material and must report an application
identity mismatch rather than weakening the check.

## 4. Create a release, patch ordinary code, and deploy

Create a platform-specific release baseline:

```bash
hyfens release android
# or: hyfens release ios
```

Edit supported ordinary Dart/Flutter code, then create a signed patch for the
same platform:

```bash
hyfens patch android
# or: hyfens patch ios
```

Verify the exact artifact produced by the patch command before deployment:

```bash
hyfens verify <patch-file>
hyfens deploy
```

Normal commands use the active profile and do not need a repeated endpoint.
Deployment registers immutable release/patch metadata, uploads exact signed
bytes, and promotes only with the control plane's authorization and
preconditions. The runtime independently checks the application, release,
capabilities, sequence, digest, and signature; the server is not the runtime
trust root.

Use the exact release/platform when more than one baseline exists. A change to
native code, manifests, permissions, entitlements, dependencies, or an
unsupported Dart/Flutter construct requires a normal store release or separate
review. This workflow is not arbitrary-Dart OTA patching.

## 5. CI authentication

CI must use a scoped, expirable, revocable service/API key supplied through the
public `HYFENS_TOKEN` environment variable:

```yaml
steps:
  - name: Deploy Hyfens patch
    env:
      HYFENS_TOKEN: ${{ secrets.HYFENS_TOKEN }}
    run: hyfens deploy
```

Inject the secret through the CI provider; do not write its value to a
repository, `hyfens.yaml`, profile metadata, logs, or a command argument.
Human browser/device sessions are not the CI contract. SSH is not a developer
authentication mechanism.

## 6. Run the self-hosted Docker package

For a single-node installation from versioned release images, follow the
[self-hosted release guide](../deploy/self-hosted/README.md). It covers
PostgreSQL, MinIO, the control plane, the dashboard, host-level HTTPS, first
owner bootstrap, and account-to-project connection. The package is a bounded
reference deployment, not an HA or production backup solution.

The Compose package binds its application ports to loopback by default. Check
the local upstreams after starting it:

```bash
curl --fail http://127.0.0.1:18082/healthz
curl --fail http://127.0.0.1:18082/readyz
curl --fail http://127.0.0.1:18083/healthz
```

Use the Compose package's documented `down` command to stop it. Use `down -v`
only for an intentionally disposable run because it deletes the named
PostgreSQL and object-store volumes.

## 7. Migration from `tool`

`tool` is deprecated compatibility nomenclature. Migrate deliberately:

1. Replace command invocations in new scripts with `hyfens`.
2. Run `hyfens doctor` and `hyfens status` and preserve any existing evidence.
3. Run `hyfens init`; review the generated `hyfens.yaml` before committing it.
4. Keep legacy `tool.yaml` and `.tool/` evidence until the new binding and a
   fresh release have been verified. Do not manually rename or copy them.
5. Keep existing release/patch artifacts and private signing material in their
   protected locations. Never move session credentials into project metadata.
6. Log in separately for each endpoint and confirm the selected profile with
   `hyfens profile current`.

Do not manually rename configuration or credential files to force a migration.
The compatibility runner must delegate to the same command implementation and
may emit `tool is deprecated; use hyfens`. Published migration tooling is not
promised until the CLI packaging work is complete.

## Current gates

The local workflow is the supported boundary. These remain explicit external
gates or backlog:

- generally deployed browser-PKCE/device-code auth;
- AWS/provider acceptance, public ingress, object durability, signing-key
  recovery/rotation, HA/DR, and production operations;
- independent customer applications and physical-device acceptance beyond the
  recorded fixtures;
- App Store/Google Play, legal, and compliance review;
- pub.dev publication, package-manager publication, code signing, or a global
  installer.

See the [CLI reference](cli.md) and the
[developer platform contract](HYFENS_DEVELOPER_PLATFORM_CONTRACT.md) for the
full surface and invariants.
