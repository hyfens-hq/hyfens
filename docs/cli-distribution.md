# CLI distribution

The canonical executable is `hyfens`. The old `tool` executable is shipped as
a compatibility shim and prints a deprecation notice. The CLI is not a pub.dev
package because its release build currently uses repository path dependencies.

## GitHub Release workflow

The version source is `cli/pubspec.yaml`. To publish a release after the
repository has been created and its Actions permissions are enabled:

1. Set `version` in `cli/pubspec.yaml`.
2. Run the CLI tests and a host-native build locally.
3. Create and push an annotated tag with the same version, for example
   `v<version>`.
4. `.github/workflows/release-cli.yml` builds and attaches six archives:
   macOS, Linux, and Windows on x64 and arm64.
5. The workflow also attaches `SHA256SUMS` and `artifact-inventory.json`.

The separate `release-images.yml` workflow publishes matching multi-architecture
`hyfens-control-plane` and `hyfens-dashboard` images to GHCR. The public
`hyfens-dashboard` image is the Customer/Instance Workspace only; the private
Cloud Platform Console is not published as an OSS image. Both workflows fail
if the tag does not match `cli/pubspec.yaml`.

The workflows do not contain signing keys, package-manager tokens, or user
credentials. Code signing and package-manager publication are separate release
controls that must be added only after their credentials and ownership are
approved.

## Install a GitHub Release directly

The bounded macOS/Linux installer resolves `latest` by querying the fixed
GitHub repository, or accepts an explicit published release such as `v0.1.1`:

```sh
# Install the latest published release.
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/hyfens-hq/hyfens/main/scripts/install-hyfens.sh \
  | bash

# Pin an explicit release instead.
curl --fail --silent --show-error --location \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/hyfens-hq/hyfens/main/scripts/install-hyfens.sh \
  | bash -s -- --version v0.1.1
```

The installer supports macOS and Linux on x64 and arm64. It downloads the
matching GitHub Release archive and `SHA256SUMS`, verifies the archive before
extracting or installing it, rejects unsafe archive paths and special files,
and keeps the archive's `bin/` and `lib/` directories together. It uses a
writable `/usr/local` prefix when available and otherwise falls back to
`~/.local`; `--prefix PATH` selects an explicit absolute prefix without using
`sudo`. Versions are kept under `PREFIX/opt/hyfens-VERSION`, with launchers in
`PREFIX/bin`.

It does not modify `~/.hyfens`, project files, shell startup files, or existing
non-symlink launchers. The command prints the required `PATH` export after a
successful install. It is release-only and fails closed when the requested
GitHub Release or checksum is unavailable; use the source-checkout fallback
below when a native release archive is unavailable.

On Windows PowerShell:

```powershell
$version = "0.1.1"
$architecture = "arm64"
$archive = "hyfens-$version-windows-$architecture.zip"
$base = "https://github.com/hyfens-hq/hyfens/releases/download/v$version"
$root = "$env:LOCALAPPDATA\Hyfens\$version"
New-Item -ItemType Directory -Force -Path $root | Out-Null
Invoke-WebRequest "$base/$archive" -OutFile "$root\$archive"
Invoke-WebRequest "$base/SHA256SUMS" -OutFile "$root\SHA256SUMS"
$checksumLine = Select-String -Path "$root\SHA256SUMS" -SimpleMatch $archive
if (-not $checksumLine) { throw "No checksum found for $archive" }
$expected = (($checksumLine.Line -replace '\s+.*$', '')).ToLowerInvariant()
$actual = (Get-FileHash "$root\$archive" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw "Checksum mismatch for $archive" }
Expand-Archive "$root\$archive" -DestinationPath $root -Force
$env:Path = "$root\hyfens-$version-windows-$architecture\bin;$env:Path"
hyfens.exe --version
```

The PowerShell example should compare the displayed hash with the
corresponding line in `SHA256SUMS` before using the extracted executable. Use
`windows-x64` or `windows-arm64` as appropriate for the host architecture.

## Package-manager metadata

The current `v0.1.1` release has live Homebrew and Scoop distribution:

- Homebrew: `hyfens-hq/homebrew-tap`, installed directly with
  `brew install hyfens-hq/tap/hyfens`. Homebrew automatically adds the tap
  and trusts only the requested formula;
- Scoop: `hyfens-hq/scoop-bucket`, installed with
  `scoop bucket add hyfens https://github.com/hyfens-hq/scoop-bucket` and
  `scoop install hyfens`; and
- WinGet remains an external Microsoft submission gate.

If the Homebrew tap was already added manually, trust only the formula once to
use the short name:

```sh
brew trust --formula hyfens-hq/tap/hyfens
brew install hyfens
```

Do not disable Homebrew tap trust globally.

The live package metadata points to immutable GitHub Release archives and the
release-generated SHA-256 values. For future releases, use
`artifact-inventory.json` to update the approved tap or bucket, and fill the
approved WinGet publisher identity separately. The templates under
`packaging/cli/` are not themselves publication channels.

## Source-checkout fallback

When a native archive is unavailable or for contributors, use the source
workflow described in [`docs/getting-started.md`](getting-started.md). It
requires Dart `3.13.x` and
the repository's path dependencies. The source installer remains useful for
local development; it is not a network installer or a package-manager
publication.
