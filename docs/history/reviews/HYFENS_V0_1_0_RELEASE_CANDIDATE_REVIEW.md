# Hyfens v0.1.0 release candidate review

Date: 2026-09-02

Audited public source commit: `370696f54b8f214c62825f3bf028b99d430d196c`

## Disposition

**HYFENS v0.1.0 — READY WITH EXTERNAL GATES**

The public repository is ready for an intentional early `v0.1.0` release
within its declared bounded developer/self-hosted scope. No tag, GitHub
Release, GHCR image, CLI binary, package-manager manifest, or announcement was
created or published during this review.

## Method

The review started from a fresh public clone of
`https://github.com/hyfens-hq/hyfens` at `main`. The clone was clean, passed
`git diff --check` and `git fsck --full --strict`, and contained no release
tags. All build and self-host checks below used the public clone only.

## Release-blocker corrections

The following narrowly scoped fixes were published to `main` before the final
clean-clone pass:

- Added `SECURITY.md` with private GitHub vulnerability-reporting guidance.
- Repaired two public documentation links that pointed to intentionally
  omitted internal evidence files.
- Aligned the CLI and compatibility-shim version output with `cli/pubspec.yaml`
  at `0.1.0`.
- Pinned workflow actions, Docker bases, and Compose service images by digest.
- Changed the control-plane image to a compiled runtime-only image and enabled
  release image provenance/SBOM attestations.

## Acceptance matrix

| Gate | Result | Evidence / classification |
| --- | --- | --- |
| Fresh public clone | PASS | Clean clone at the audited commit; repository integrity checks passed. |
| README onboarding | PASS | OSS/Cloud boundary, source install, CLI workflow, self-host path, security model, and limitations are documented. |
| Apache/license files | PASS | GitHub recognizes `Apache-2.0`; canonical root `LICENSE`, notices, trademark policy, and DCO guidance are present. |
| Asset provenance | PASS | Lucide 1.27.0 mappings and fixture/font provenance are present; Iconsax assets are absent. |
| Secret scan | PASS | No private-key, cloud-token, session, credential, or real `.env` material found. `.env.example` contains placeholders only. |
| CLI analysis/tests | PASS | `dart analyze`; eight focused CLI/release tests; deploy-runtime E2E and release-overlay tests each passed serially. |
| `hyfens` executable | PASS | Help, `doctor` against the public Flutter fixture, and `hyfens --version` passed. |
| CLI archive build | PASS | Native macOS arm64 archive built from the clean clone; archive inventory is minimal and intentional. |
| Checksum verification | PASS | SHA-256 checksum was generated and verified; archive binaries also passed version smoke tests. |
| CLI release workflow validation | PASS | Six-target matrix covers macOS/Linux/Windows x64 and arm64; actions use immutable commit references. |
| Control-plane image build | PASS | Digest-pinned multi-stage build succeeded; runtime image contains the compiled service, license, and notices only under `/opt/hyfens`. |
| Dashboard image build | PASS | Digest-pinned build succeeded; runtime API injection and dashboard serving assets passed checks. |
| Image license/notices | PASS | Both images contain `LICENSE` and `THIRD_PARTY_NOTICES.md`; no unapproved icon assets are present. |
| GHCR naming | PASS | Workflow resolves exactly to `ghcr.io/hyfens-hq/hyfens-control-plane` and `ghcr.io/hyfens-hq/hyfens-dashboard`. |
| Self-host Compose config | PASS | `docker compose config --quiet` passed with the documented environment template. |
| Self-host disposable startup | PASS | Final clone stack started with PostgreSQL, MinIO, control plane, and dashboard; health/readiness/discovery probes passed. |
| First-owner bootstrap | PASS | Organization/application/environment bootstrap and server-local first-owner creation passed without database edits. |
| Self-host CLI login | ENVIRONMENT_BLOCKED | The disposable run had no HTTPS reverse proxy/certificate. Compose deliberately rejects direct cleartext password auth; the documented HTTPS path remains required. |
| Public docs/links | PASS | Required GitHub, self-host, license, security, and project links returned successfully; stale local links were repaired. |
| Release-trigger audit | PASS | `v*` tags trigger the reviewed CLI and image workflows; tag/version equality is enforced; no tag was pushed. |
| GitHub Actions permissions | PASS | CLI build jobs use read access; release publication uses `contents: write`; image publication uses `packages: write`. |
| Release notes draft | PASS | Draft is included below and does not overstate the bounded release. |
| SECURITY reporting path | PASS | `SECURITY.md` directs researchers to private GitHub vulnerability reporting. |
| backend untouched | PASS | No write, push, visibility, rename, archive, delete, or transfer operation targeted `backend`. |
| frontend untouched | PASS | No write, push, visibility, rename, archive, delete, or transfer operation targeted `frontend`. |

## CLI evidence

The public clone used Flutter `3.47.0` and Dart `3.13.0`.

- `flutter pub get --enforce-lockfile --no-example`: passed.
- `dart analyze`: passed with no issues.
- Focused CLI process and release-packaging tests: 8 passed.
- `hyfens doctor --json` against `fixtures/flutter_toolchain_app`: `READY`.
- `hyfens --version`: `hyfens 0.1.0`.
- `tool --version`: `0.1.0`, with the deprecation notice.
- `hyfens-0.1.0-macos-arm64.tar.gz`: built and checksum verified.
- The two previously slow/parallel-sensitive tests passed when run serially;
  the earlier concurrent-suite timeout is a test-harness backlog item, not a
  release-artifact failure.

The CLI workflow derives release identity from `cli/pubspec.yaml`, builds six
native archives, creates `SHA256SUMS` and `artifact-inventory.json`, and then
creates the GitHub Release only after all matrix builds succeed.

## Container and self-host evidence

Both public image Dockerfiles build from digest-pinned bases. The control-plane
image compiles the service in a builder stage and does not ship package tests,
`.dart_tool`, or a Pub cache. The dashboard image keeps runtime configuration
injection ephemeral and contains no Iconsax files.

The final disposable Compose run proved the documented service dependency
order, loopback port binding, object-store bootstrap, control-plane health and
readiness, discovery, dashboard health, organization bootstrap, and first-owner
bootstrap. Disposable containers, volumes, and local validation images were
removed after the run.

The full user-facing self-host login path requires the documented host-level
HTTPS reverse proxy. Direct HTTP password login being rejected is an intended
security boundary, not a defect.

## Licensing, assets, and security

- Root software licensing remains canonical Apache-2.0.
- `TRADEMARKS.md` stays separate from the software license and is a conservative
  draft pending maintainer/legal review.
- `CONTRIBUTING.md` preserves the DCO-only model; no CLA was added.
- `THIRD_PARTY_NOTICES.md` and `docs/ASSET_PROVENANCE.md` document Lucide,
  fonts, fixture artwork, Dart/Flutter dependencies, and image bases.
- No high-confidence secret markers or tracked credential stores were found.
- The remaining Google Play Services Cronet closure is explicitly marked
  `REVIEW_REQUIRED` for a future mobile artifact distribution. No mobile binary
  is part of this release publication.

## Workflow behavior when `v0.1.0` is authorized

Pushing `v0.1.0` will trigger both tag workflows:

- The CLI workflow validates the tag against `cli/pubspec.yaml`, builds the six
  archives, generates checksums/inventory, and creates the GitHub Release.
- The image workflow validates the same version and publishes multi-architecture
  control-plane and dashboard images. Stable tags also move `latest`.
- Image builds now request provenance and SBOM attestations and carry source,
  version, revision, license, title, and URL labels.

These workflows were reviewed but intentionally not executed against GitHub
Actions or GHCR during this milestone.

## External gates and accepted limitations

These are outside the source-release blocker decision:

- A maintainer must still configure/approve GitHub Actions and GHCR publication
  permissions and then explicitly authorize the tag.
- A self-host operator must provide DNS, TLS, reverse proxy routing, backups,
  and production operations appropriate to their environment.
- The managed Cloud discovery endpoint currently advertises browser/device
  authentication pages whose live `app.hyfens.com` routes returned 404 during
  this review. This is a Cloud deployment gate outside this public repository;
  the README does not claim browser/device auth as generally deployed.
- Homebrew, Scoop, and WinGet remain templates, not live publication channels.
- Android/iOS store, legal, compliance, production HA/DR, and native dependency
  artifact reviews remain outside the bounded OSS developer release.

## Draft release notes

### Hyfens v0.1.0

Initial public developer release of the Apache-2.0 Hyfens Flutter live-update
foundation.

Included:

- `hyfens` CLI with macOS, Linux, and Windows x64/arm64 release workflow;
- signed release and bounded patch workflow;
- exact release/application binding, verification, rollback, and replay
  protections;
- self-hosted control plane, dashboard, PostgreSQL, and S3-compatible/MinIO
  Compose deployment;
- human auth, scoped service credentials, basic audit, and first-owner
  bootstrap; and
- CLI checksums, artifact inventory, and image provenance/SBOM workflow.

Supported boundary:

- Flutter `3.47.x` / Dart `3.13.x` family as documented;
- the declared bounded Dart/Flutter patch subset; and
- local or single-node self-hosted operation, or the same CLI/protocol against
  Hyfens Cloud.

Known limitations:

- This is an early public developer release, not a `1.0` or a production,
  enterprise, store-compliance, or availability guarantee.
- Unsupported Dart/native/dependency/manifest changes require a normal app
  release or separate review.
- Production TLS, HA/DR, key custody, store approval, legal/compliance review,
  and package-manager publication remain external gates.

Security:

- Patch authenticity and runtime acceptance remain separate from delivery
  eligibility and human-session auth.
- See `SECURITY.md` for private vulnerability reporting.
