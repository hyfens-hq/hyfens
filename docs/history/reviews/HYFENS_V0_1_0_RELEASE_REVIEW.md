# Hyfens v0.1.0 Release Review

Date: 2026-09-02

Final disposition: **HYFENS v0.1.0 — BLOCKED BY CLI RELEASE FAILURE**

The authorized `v0.1.0` tag and GitHub Release are public, but two concrete
CLI distribution defects were found in the immutable release output. The tag
was not moved or rewritten.

## Release identity

- Repository: <https://github.com/hyfens-hq/hyfens>
- Visibility: public
- Branch: `main`
- Release commit: `4982ab570c4fe76fa8233b25bff155414b774d77`
- Tag: `v0.1.0` (annotated and GPG-signed; tag object
  `2c7c7085742825654e0212a440f70d8939958e6d`)
- GitHub Release: <https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.0>
- CLI workflow: <https://github.com/hyfens-hq/hyfens/actions/runs/33626603207>
- Container workflow: <https://github.com/hyfens-hq/hyfens/actions/runs/33626603179>

## Published CLI artifacts

The GitHub Release contains six platform archives, `SHA256SUMS`, and
`artifact-inventory.json`. The release checksum file verified successfully:

| Archive | SHA-256 |
| --- | --- |
| `hyfens-0.1.0-linux-arm64.tar.gz` | `84db16a6667a0788e9c20613a37edb382a38d5fb0454509a9df43769939a6f01` |
| `hyfens-0.1.0-linux-x64.tar.gz` | `5a45d340d743187082a74d5b5714e603e76762025abe26ff37f7f75864176250` |
| `hyfens-0.1.0-macos-arm64.tar.gz` | `319529ad526b27819214e905ca64b12029db632ae37bf71696c9ba13c4ba89e1` |
| `hyfens-0.1.0-macos-x64.tar.gz` | `9fcbdf4494e337cd6e490ca42ffd56391ec8dad7047a264b239bd88ef6c17aa5` |
| `hyfens-0.1.0-windows-arm64.zip` | `3b1c303199daf40c5f8a2c10c9dc93820434497f3110bc4e213c96f3a53f45a9` |
| `hyfens-0.1.0-windows-x64.zip` | `557ad4e720ed8bbceb26c051214f6cb5728ef66200333c800068857f97c07f06` |

Each archive contains the canonical `hyfens` executable, the deprecated
`tool` shim, `LICENSE`, and `THIRD_PARTY_NOTICES.md`. No credentials,
environment files, keys, or temporary evidence were found in the archives.

## Installation validation

### Passed

- Direct macOS arm64 archive extraction and execution: `hyfens 0.1.0`.
- Explicit macOS arm64 curl installation with `--version v0.1.0` from a
  disposable environment; the installer contains the corresponding Linux
  branch.
- Curl checksum verification, safe extraction, install-path reporting, and
  preservation of `~/.hyfens`/project state.
- `hyfens --version`, `--help`, `login --help`, and `init --help`.
- `hyfens doctor` in a newly-created Flutter project: command completed with
  the documented warning result and exit code 0.
- Homebrew formula publication and real ARM macOS install/test/uninstall
  smoke. Published tap: <https://github.com/hyfens-hq/homebrew-tap>.
  Tap commit: `75a43def5c7d08d138c4d39ee80d69de2f784616`.
- Scoop manifest publication. Published bucket:
  <https://github.com/hyfens-hq/scoop-bucket>. Bucket commit:
  `15fe98a31d2b9c77c919f4b96de2bf816b2892d2`.
  Its `extract_dir` matches the actual shipped ZIP root.

### Release blockers

1. The default curl installer path (`latest`) fails to resolve the public
   GitHub Release because the installer parses the compact JSON response as if
   every field were on its own line. Explicit `--version v0.1.0` works, but
   the required latest-stable UX does not.

2. Both Windows ZIPs contain the root directory `hyfens-0.1` rather than
   the expected version/platform root. The archive filename and checksum are
   correct, and the executable is present, but the published PowerShell
   documentation and the source Scoop/WinGet templates expect the full root
   name. The published Scoop manifest was generated against the actual ZIP
   root, but this does not correct the tagged build script or Windows direct
   download documentation.

Per the release authorization, no source changes were made after the tag and
the tag was not recreated. These defects require a corrected source commit
and a separately authorized future release.

## Package-manager status

- Homebrew: LIVE at <https://github.com/hyfens-hq/homebrew-tap>; formula
  points to immutable `v0.1.0` URLs and canonical checksums. Homebrew 6.0.21
  required explicit trust of the third-party formula before installation.
- Scoop: LIVE at <https://github.com/hyfens-hq/scoop-bucket>; manifest points
  to immutable `v0.1.0` URLs and canonical checksums. A real Scoop/Windows
  installation was not available in this macOS environment.
- WinGet: EXTERNAL GATE. The repository templates are structurally present
  and ready to be generated from the release contract, but no Microsoft
  submission or public WinGet catalog installation was available.
- Direct Windows installation: BLOCKED by the shipped ZIP root/documentation
  mismatch described above.

## Container status

The image workflow completed successfully and produced these release digests:

- `ghcr.io/hyfens-hq/hyfens-control-plane:0.1.0`
  manifest digest `sha256:817e1ba72a5b551dbd11749bb024d923f862484fb7d7c0f42256692693e32704`
- `ghcr.io/hyfens-hq/hyfens-dashboard:0.1.0`
  manifest digest `sha256:0b4fead1e7ead707357c36b90198cfd973798261d1d66f3d642f97e1d818cf8f`

Anonymous GHCR token requests returned `401` for both packages in this
environment, so public image pulls and the self-hosted image path remain an
external package-visibility gate. The workflow itself passed, and the
self-hosted Compose files use the expected image names.

## Security, licensing, and repository hygiene

- Final focused secret scan: PASS. No private keys, tokens, credentials,
  real environment files, or acceptance artifacts were found. The only
  tracked environment file is the documented placeholder template.
- Apache-2.0 `LICENSE`, notices, trademark policy, and asset provenance from
  the reviewed public tree remain intact.
- Release workflows passed their reviewed CLI/image jobs. The only runner
  annotation was the GitHub Node.js 20 deprecation notice for pinned actions;
  it did not fail a job.
- `backend` remains private and was not targeted; its observed GitHub metadata
  remains unchanged. `frontend` remains private and was not targeted; its
  observed GitHub metadata remains unchanged.
- No `v0.1.1` tag was created.

## Release acceptance matrix

| Gate | Result | Evidence / classification |
| --- | --- | --- |
| Release commit verified | PASS | Tag resolves to the reviewed commit above. |
| Secret scan | PASS | Focused scan passed before and after publication. |
| `v0.1.0` tag | PASS | Public annotated signed tag; not rewritten. |
| GitHub Release | PASS | Public release with six archives, checksums, and inventory. |
| macOS CLI archive | PASS | Both assets/checksums present; arm64 executed. |
| Linux CLI archive | PASS | Both assets/checksums present and extractable; native execution is platform-gated here. |
| Windows CLI archive | RELEASE BLOCKER | ZIP root is `hyfens-0.1`, inconsistent with the documented/package path. |
| Checksums | PASS | All six release checksums verified. |
| Direct binary install | RELEASE BLOCKER | macOS path passes; Windows documented path does not match the archive. |
| curl installer | RELEASE BLOCKER | Explicit version passes; default latest resolution fails. |
| curl checksum verification | PASS | Installer verifies the release SHA-256 before extraction. |
| curl clean-machine smoke | PASS | Disposable HOME/prefix smoke passed with explicit `v0.1.0`. |
| Homebrew formula | PASS | Ruby syntax/style and real install test passed. |
| Homebrew publication | PASS | Public Hyfens tap published. |
| Homebrew install smoke | PASS | Install/test/uninstall passed after explicit tap trust. |
| Scoop manifest | PASS | Valid JSON, immutable URLs/hashes, actual archive root. |
| Scoop publication | PASS | Public Hyfens bucket published. |
| Scoop install smoke | EXTERNAL GATE | No Scoop/Windows runtime in the validation environment. |
| WinGet manifest | EXTERNAL GATE | Template is present; Microsoft publisher/submission path unavailable. |
| WinGet publication | EXTERNAL GATE | No Microsoft submission credentials/catalog path. |
| WinGet install smoke | EXTERNAL GATE | No Windows/WinGet runtime available. |
| `hyfens --version` | PASS | Reports `hyfens 0.1.0`. |
| `hyfens doctor` | PASS | Fresh Flutter project smoke returned warning result with exit code 0. |
| CLI docs match reality | RELEASE BLOCKER | Latest curl and Windows direct-download instructions do not. |
| Control-plane GHCR | EXTERNAL GATE | Workflow passed; anonymous pull returned 401. |
| Dashboard GHCR | EXTERNAL GATE | Workflow passed; anonymous pull returned 401. |
| Self-host docs reference public images | EXTERNAL GATE | Names are correct, but package visibility prevents anonymous pull. |
| License/notices | PASS | Apache-2.0 and notices remain present and verified. |
| `backend` untouched | PASS | No operation targeted it; remains private. |
| `frontend` untouched | PASS | No operation targeted it; remains private. |

## Next required action

Do not move `v0.1.0`. Correct the latest-release JSON parsing and the
Windows archive-root derivation in a new reviewed source commit, then request
a separate release authorization. Confirm GHCR package visibility through the
organization package settings before advertising self-hosted image pulls.
