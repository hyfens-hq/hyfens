# CLI distribution

The canonical executable is `hyfens`. The old `tool` executable is shipped as
a compatibility shim and prints a deprecation notice. The CLI is not a pub.dev
package because its release build currently uses repository path dependencies.

## GitHub Release workflow

The version source is `cli/pubspec.yaml`. The current public release is
`v0.1.1`; future releases follow the same tag-driven workflow:

1. Set `version` in `cli/pubspec.yaml`.
2. Run the CLI tests and a host-native build locally.
3. Create and push an annotated tag with the same version, for example
   `v0.1.1`.
4. `.github/workflows/release-cli.yml` builds and attaches six archives:
   macOS, Linux, and Windows on x64 and arm64.
6. The workflow extracts the same changelog section into non-empty GitHub
   Release notes and attaches `SHA256SUMS` and `artifact-inventory.json`.

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
GitHub repository, or accepts an explicit release such as `v0.1.1`:

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
below when a native release is unavailable.

After a compiled release installation, the CLI can update itself through the
same immutable archive and checksum contract:

```sh
hyfens upgrade
hyfens upgrade --check
hyfens upgrade --version 0.1.1
```

`hyfens upgrade` does not modify profiles, credentials, project files, or shell
startup files. It is intended for binaries installed from a release archive;
package-manager installations should continue to use their package manager's
upgrade command.

On Windows PowerShell, download the matching archive and checksum from the
[`v0.1.1` GitHub Release](https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.1):

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

## Package-manager channels

The public `v0.1.1` release is the immutable source for package-manager
metadata. Homebrew is available through the Hyfens tap and Scoop is available
through the Hyfens bucket; use their normal package-manager commands rather
than installing a formula or manifest from this repository directly. WinGet
remains an external publication gate and is not advertised as live here.

For a new version, use `artifact-inventory.json` and `SHA256SUMS` from the
corresponding GitHub Release for the exact archive names and SHA-256 values.
Construct each URL as
`https://github.com/hyfens-hq/hyfens/releases/download/v<version>/<archive>`.
The templates under `packaging/cli/` are update inputs, not proof that a
package-manager channel has been published.

## Source-checkout fallback

For contributors or environments where a native release is unavailable, use
the source workflow described in
[`docs/getting-started.md`](getting-started.md). It requires Dart `3.13.x` and
the repository's path dependencies. The source installer remains useful for
local development; it is not a network installer or a package-manager
publication.
