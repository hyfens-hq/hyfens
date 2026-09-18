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
   `v0.1.0`.
4. `.github/workflows/release-cli.yml` builds and attaches six archives:
   macOS, Linux, and Windows on x64 and arm64.
5. The workflow also attaches `SHA256SUMS` and `artifact-inventory.json`.

The separate `release-images.yml` workflow publishes matching multi-architecture
`hyfens-control-plane` and `hyfens-dashboard` images to GHCR. Both workflows
fail if the tag does not match `cli/pubspec.yaml`.

The workflows do not contain signing keys, package-manager tokens, or user
credentials. Code signing and package-manager publication are separate release
controls that must be added only after their credentials and ownership are
approved.

## Install a GitHub Release directly

Use the archive for the host operating system and architecture. Keep the
archive's `bin/` and `lib/` directories together because Dart build hooks may
ship native libraries beside the executable.

On macOS or Linux:

```sh
version=0.1.0
platform=macos
architecture=arm64
base="https://github.com/hyfens-hq/hyfens/releases/download/v${version}"
archive="hyfens-${version}-${platform}-${architecture}.tar.gz"
mkdir -p "$HOME/.local/opt/hyfens-${version}"
curl --fail --location --remote-name "$base/$archive"
curl --fail --location --remote-name "$base/SHA256SUMS"

if [ "$platform" = macos ]; then
  grep -F "  $archive" SHA256SUMS | shasum -a 256 -c -
else
  grep -F "  $archive" SHA256SUMS | sha256sum -c -
fi
tar -xzf "$archive" -C "$HOME/.local/opt/hyfens-${version}" --strip-components=1
mkdir -p "$HOME/.local/bin"
ln -sfn "$HOME/.local/opt/hyfens-${version}/bin/hyfens" "$HOME/.local/bin/hyfens"
ln -sfn "$HOME/.local/opt/hyfens-${version}/bin/tool" "$HOME/.local/bin/tool"
export PATH="$HOME/.local/bin:$PATH"
hyfens --version
```

The archive and checksum must be verified before extraction. Use the matching
`linux` or `macos` value and `x64` or `arm64` architecture for another host.

On Windows PowerShell:

```powershell
$version = "0.1.0"
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

The templates under `packaging/cli/` are intentionally not live manifests:

- Homebrew supports macOS and Linux formulas;
- Scoop provides a Windows manifest; and
- WinGet uses the two Windows YAML manifests.

After a GitHub Release exists, generate reviewed manifests from
`artifact-inventory.json`, replace every placeholder, and submit them through
the approved tap, bucket, or WinGet submission process. Do not commit a
release-specific checksum or URL until the destination repository and
publisher identity are verified.

## Source-checkout fallback

Before the first tagged release, use the source workflow described in
[`docs/getting-started.md`](getting-started.md). It requires Dart `3.13.x` and
the repository's path dependencies. The source installer remains useful for
local development; it is not a network installer or a package-manager
publication.
