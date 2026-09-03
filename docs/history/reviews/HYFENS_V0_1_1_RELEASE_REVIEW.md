# Hyfens v0.1.1 release review

Status: **RELEASED WITH EXTERNAL GATES**  
Review date: 2026-09-02

## Release identity

- Repository: <https://github.com/hyfens-hq/hyfens>
- Release: <https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.1>
- Release name: `Hyfens CLI v0.1.1`
- Release source commit: `389fc7178b857aeaf9167e69aa5c98b8167c7a43`
- Tag: signed annotated `v0.1.1` (tag object `7c447d2a02a5f9cf64954039e4d5f7b1fbcd266c`)
- `v0.1.0` was not modified.

The tag points to the reviewed source commit. The post-release documentation
update on `main` does not move or recreate the tag.

## Release-boundary reconciliation

Rechecked: 2026-09-03 from a fresh public-repository clone.

The immutable release boundary remains
`389fc7178b857aeaf9167e69aa5c98b8167c7a43`. The signed annotated tag
`v0.1.1` already exists remotely and peels to that exact commit; no tag was
created, moved, deleted, or force-updated during this reconciliation. Current
`main` is `1a4dea95fc7d304139d4f6549decb6fcdace45f8` and remains the development
line.

The commits after the reviewed release candidate were inspected as follows:

| Commits | Classification | Release-boundary decision |
| --- | --- | --- |
| `9d4ed84`, `76f0a68` | `DOCS_ONLY` | Excluded from the immutable artifact boundary. |
| `efbaf3e` | `CLI_AFFECTING` (plus documentation) | Excluded; it is a later managed-Cloud endpoint/profile compatibility fix for a future release. |
| `4da57c8`, `226671c`, `d402031` | `DASHBOARD_ONLY`, `CONTROL_PLANE_ONLY`, and self-host/image-input changes | Excluded; later operational-dashboard development remains on `main`. |
| `7b1ab5d`, `853fbb8`, `1a4dea9` | `DOCS_ONLY` task records | Excluded from release artifacts. |

The selected release commit therefore remains the explicitly validated
`389fc717...`, not `HEAD`. The tag-triggered CLI and image workflows both ran
from that commit and completed successfully. The later CLI change is retained
on `main`; it is not silently absorbed into `v0.1.1`.

The immutable `v0.1.1` binary's root help still contains the legacy
`https://api.hyfens.com/p2/` example. The current `main` source removes that
example, but changing the published binary would require a new release and
was intentionally not attempted here.

## Workflow results

- CLI release workflow: [run 33657294918](https://github.com/hyfens-hq/hyfens/actions/runs/33657294918) — PASS.
- Image release workflow: [run 33657294920](https://github.com/hyfens-hq/hyfens/actions/runs/33657294920) — PASS.
- All six CLI artifact jobs and release assembly completed successfully.

## Published CLI artifacts

All six archives downloaded and matched the published `SHA256SUMS` file.

| Platform | Artifact | SHA-256 |
| --- | --- | --- |
| Linux arm64 | [hyfens-0.1.1-linux-arm64.tar.gz](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-linux-arm64.tar.gz) | `bf760163766cba168a808356430a5b748b74352e3df3af1c37b9a34a381185fe` |
| Linux x64 | [hyfens-0.1.1-linux-x64.tar.gz](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-linux-x64.tar.gz) | `10b7f8de9cac3c2bcea6994f2cce6653b19906740f9236cc219ca847df1e7e34` |
| macOS arm64 | [hyfens-0.1.1-macos-arm64.tar.gz](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-macos-arm64.tar.gz) | `3c98894c1b0aeab98cbe2d1a113bd5a020d699ff6df7fba806d742f341533abd` |
| macOS x64 | [hyfens-0.1.1-macos-x64.tar.gz](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-macos-x64.tar.gz) | `155b2c9bbe5262ff53ff5f61fa980fcbb898103934357b3d7c6f5f0045c9b66f` |
| Windows arm64 | [hyfens-0.1.1-windows-arm64.zip](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-windows-arm64.zip) | `5d4563fe6bb790e3bb3e54e868b19c32c72c48f280630047f8274b9ae8d186c8` |
| Windows x64 | [hyfens-0.1.1-windows-x64.zip](https://github.com/hyfens-hq/hyfens/releases/download/v0.1.1/hyfens-0.1.1-windows-x64.zip) | `9744cac01d730ffd0bc61f0e1ac5cb562a62ae7513ae5c7601afae8c00c9a8ba` |

The Windows archives contain roots named `hyfens-0.1.1-windows-x64/` and
`hyfens-0.1.1-windows-arm64/`; each contains `bin/hyfens.exe` and the
intentional `tool.exe` compatibility shim. Archive inventories contain no
credentials, profiles, keys, `.env` files, or temporary evidence.

## Installation validation

- Default curl installer: PASS. The public installer resolved the latest stable
  release as `0.1.1`, downloaded the correct macOS arm64 archive, verified its
  SHA-256, and installed it on a clean disposable HOME/prefix.
- Explicit curl installer: PASS using the documented
  `--version v0.1.1` form.
- Direct archive installation: PASS for a representative macOS arm64 archive;
  extraction, `hyfens --version`, help, and MCP help worked without a source
  checkout.
- Installed CLI: `hyfens --version`, `--help`, `-h`, `help`, command-level help,
  and `hyfens mcp --help` all PASS.
- `hyfens doctor`: PASS from the supported Flutter conformance fixture. It
  reports the expected runtime/package-graph warnings for the bounded fixture.
- `tool --help`: PASS; it emits a deprecation warning and delegates to the
  canonical Hyfens help surface.

## Package-manager status

- Homebrew: **LIVE / PASS**. Formula publication commit:
  `d8cf49dea8186bbb0fe65bb0612656ef86dde421` in
  <https://github.com/hyfens-hq/homebrew-tap>. Clean tap installation,
  `hyfens --version`, help, MCP help, and `brew test` passed.
- Scoop: **LIVE / MANIFEST PASS**. Bucket publication commit:
  `0db447bd2d8c02bc4e80b6b6b2e7e986da48b4e2` in
  <https://github.com/hyfens-hq/scoop-bucket>. Both Windows URLs, checksums,
  executable paths, and corrected full-version roots were validated against
  the public release. Windows execution was unavailable in this environment,
  so Scoop runtime smoke is an environment gate, not a claimed pass.
- WinGet: **EXTERNAL GATE**. The validated template remains aligned with
  `0.1.1`; Microsoft publication was not performed.

## MCP validation

The published macOS arm64 binary passed an MCP stdio smoke test:

- initialize: PASS; server identity `hyfens`, version `0.1.1`;
- tools/list: PASS; exactly 14 reviewed structured tools;
- profile/status call: PASS with metadata-only output;
- stdout contained clean JSON-RPC traffic and stderr remained clean;
- process shutdown: PASS;
- secret-redaction checks: PASS; no access/refresh/session credentials,
  private keys, database credentials, or cloud secrets were returned.

MCP reuses the authenticated CLI profile/session and existing authorization;
remote authenticated-session validation remains dependent on an available
control plane and is not weakened for this release.

## Container status

The tag workflow published both reviewed images:

| Image | Digest | Anonymous pull |
| --- | --- | --- |
| `ghcr.io/hyfens-hq/hyfens-control-plane:0.1.1` | `sha256:a4ba7b6501844e956780dc829a1ecab107d42e805c0bc8f6c76e2d2d5d841727` | HTTP 401 |
| `ghcr.io/hyfens-hq/hyfens-dashboard:0.1.1` | `sha256:9bc8fdb9a2c9111cf7e522ce0817c22f79cef669c0bcf07bc00a235e6b21d5e8` | HTTP 401 |

GHCR publication is PASS, but anonymous package visibility is an **EXTERNAL
GATE**. Self-host documentation accurately tells operators to authenticate to
GHCR or use a mirror; it does not claim anonymous public pulls.

## Licensing, security, and release hygiene

- Root `LICENSE`: canonical Apache-2.0; GitHub license detection remains
  Apache-2.0.
- `THIRD_PARTY_NOTICES.md`, `TRADEMARKS.md`, and asset provenance remain
  present and unchanged by the release.
- Iconsax/unapproved loose assets remain absent; approved project-owned and
  permissively licensed assets are retained.
- Final focused tracked-tree secret scan: PASS. No private keys, tokens,
  credentials, real `.env` files, profiles, or temporary acceptance artifacts
  were included in the release source or archives.
- The Git tag is GPG-signed. Platform binary signing, macOS notarization, and
  Windows Authenticode are not configured and remain external gates; no such
  claims are made.

## Protected repositories

Read-only verification shows `hyfens-hq/backend` and `hyfens-hq/frontend` remain
private and unchanged. No push, rename, archive, deletion, transfer, or
visibility change was performed on either repository.

## Final disposition

**HYFENS v0.1.1 — RELEASED WITH EXTERNAL GATES**

The primary CLI objective is satisfied: an external developer can install the
published `hyfens` binary, verify its checksum, run the complete help surface,
run `doctor`, and start the built-in MCP server without cloning the repository,
installing Dart/Flutter for the binary, or copying bearer credentials into an
agent configuration. Remaining gates are GHCR anonymous visibility, WinGet
publication, Windows Scoop execution in a Windows environment, and platform
binary signing/notarization.
