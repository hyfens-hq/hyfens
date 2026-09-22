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
   The checksum file covers all six archives and the inventory. Assembly
   rejects missing, empty, noncanonical, or extra files and symlinks.

The separate `release-images.yml` workflow publishes matching multi-architecture
`hyfens-control-plane` and `hyfens-dashboard` images to GHCR. Both workflows
fail if the tag does not match `cli/pubspec.yaml`.

Both use `release-checks.yml` before building or publishing: it scans the
checked-out source with checksum-pinned Gitleaks and validates a canonical
`vMAJOR.MINOR.PATCH` tag, optionally with a SemVer prerelease. Build metadata
(`+...`) is rejected because Docker tags cannot represent it. Prereleases do
not move the image `latest` tags and are marked prerelease on GitHub.

The scan uses the scanner's default rules, redacts findings, and disables
inline bypass comments. `.gitleaks.toml` contains only an exact Dart-type false
positive exception in four files and one exact invalid-token test fixture.
It scans release source, not full Git history
or compiled binary contents; it is not a guarantee that every secret is
detectable. Never expand an exception to an entire fixture or source directory.

Actions are pinned to reviewed commits. Native CLI build and assembly jobs use
the pinned Flutter `3.47.1` stable toolchain (and its bundled Dart 3.13.x)
because the checked-in lockfile includes Flutter SDK dependencies. Checkout
does not persist credentials. Build and assembly jobs have read-only repository
tokens; only the final CLI publishing job has release/attestation/OIDC write
scopes, and only the image publishing job has package write permission.
Dependency resolution and repository scripts do not run in the CLI publishing
job.

The workflows do not contain signing keys, package-manager tokens, or user
credentials. CLI assets receive GitHub OIDC-backed provenance attestations,
which require no stored signing key. OS code signing and package-manager publication are separate release
controls that must be added only after their credentials and ownership are
approved.

## Verify provenance and integrity

For releases produced by the hardened workflow, use GitHub CLI to authenticate
the downloaded archive and checksum file before extraction:

```sh
gh attestation verify "$archive" --repo hyfens-hq/hyfens \
  --signer-workflow hyfens-hq/hyfens/.github/workflows/release-cli.yml \
  --source-ref "refs/tags/v${version}"
gh attestation verify SHA256SUMS --repo hyfens-hq/hyfens \
  --signer-workflow hyfens-hq/hyfens/.github/workflows/release-cli.yml \
  --source-ref "refs/tags/v${version}"
```

Set `archive` and `version` as in the installation example below. Stop if either
verification fails. Older releases may lack attestations: their checksums
detect corrupted downloads but cannot independently authenticate the publisher.
An attestation binds the asset to this workflow/repository/tag; it is not an
independent code audit or a claim of reproducible builds. See GitHub's
[attestation verification guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations).

Container builds publish BuildKit `mode=min` provenance with repository,
revision, platform, and build-material metadata; build-argument values are not
included. Each pushed digest also receives a GitHub OIDC/Sigstore
workflow-bound attestation in the registry. The workflow summary and its
`image-digests` artifact record immutable image references (artifact retained
for 90 days). Copy the desired reference from the trusted release run, verify
its attestation, then inspect and pull by digest:

```sh
image='ghcr.io/hyfens-hq/hyfens-dashboard@sha256:<digest-from-release-run>'
gh attestation verify "oci://$image" -R hyfens-hq/hyfens
docker buildx imagetools inspect "$image" --format '{{ json .Provenance.SLSA }}'
docker pull "$image"
```

Use GitHub's container attestation verification tooling to confirm that the
digest is bound to the expected repository workflow and tag before promotion.
The attestation is signed with short-lived identity; no repository signing key
is stored in Actions.

Compare the recorded source revision with the reviewed release commit. Tags,
including version tags, can move; retain the digest for repeatable deployment.
See Docker's [provenance reference](https://docs.docker.com/build/metadata/attestations/slsa-provenance/).

The public control-plane image is built by
`deploy/self-hosted/control-plane.Dockerfile`. It compiles
only the checked-in control-plane and patch-format packages, then runs from a
distroless non-root image with no shell or package manager. Self-hosted Compose
also runs the service read-only with `no-new-privileges` and all Linux
capabilities dropped; PostgreSQL and object storage remain external services.
Owners should protect release tags and workflow changes using repository rules;
no repository settings are changed here.

The CLI lockfile includes Flutter SDK dependencies. Native release jobs install
the pinned Flutter 3.47.1 stable toolchain, which supplies the compatible Dart
SDK on each runner; the shared tag-validation gate intentionally does not
resolve CLI dependencies. Local packaging tests can run with `FLUTTER_ROOT`
pointing to an installed compatible Flutter SDK.

## Install a GitHub Release directly

Use the archive for the host operating system and architecture. Keep the
archive's `bin/` and `lib/` directories together because Dart build hooks may
ship native libraries beside the executable.

On macOS or Linux:

```sh
set -eu
version=0.1.0
platform=macos
architecture=arm64
base="https://github.com/hyfens-hq/hyfens/releases/download/v${version}"
archive="hyfens-${version}-${platform}-${architecture}.tar.gz"
mkdir -p "$HOME/.local/opt/hyfens-${version}"
curl --fail --location --remote-name "$base/$archive"
curl --fail --location --remote-name "$base/SHA256SUMS"

# Verify provenance as described above before continuing on hardened releases.
awk -v name="$archive" '$2 == name { print }' SHA256SUMS > "$archive.sha256"
test "$(wc -l < "$archive.sha256" | tr -d ' ')" = 1
if [ "$platform" = macos ]; then
  shasum -a 256 -c "$archive.sha256"
else
  sha256sum -c "$archive.sha256"
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
$checksumLines = @(Get-Content "$root\SHA256SUMS" | Where-Object {
  $_ -cmatch ('^[0-9a-f]{64}  ' + [regex]::Escape($archive) + '$')
})
if ($checksumLines.Count -ne 1) { throw "Expected exactly one checksum for $archive" }
$expected = $checksumLines[0].Substring(0, 64)
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
