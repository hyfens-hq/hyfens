# CLI distribution and release automation

Status: [x] Completed

## Goal

Build the `hyfens` CLI as SHA-256-checksummed native executables for macOS, Linux, and Windows and publish reproducible GitHub Release artifacts with package-manager metadata that can be adopted once their repositories are available.

## Scope and Non-goals

Scope:

- Define a release version source and cross-platform build matrix for the CLI.
- Package the canonical `hyfens` executable and preserve the deprecated `tool` shim where compatibility requires it.
- Generate checksums and release metadata from tagged builds.
- Add installation/documentation paths for direct GitHub Releases and future Homebrew/Scoop/WinGet publication boundaries.

Non-goals:

- No secrets, signing keys, tokens, or credentials in the repository.
- No package-manager publication to repositories that do not yet exist or whose ownership is unverified.
- No runtime/Flutter behavior changes and no redesign of the CLI command surface.

## Owner

CLI release workstream

## Dependencies

- Existing CLI path dependencies and lockfiles.
- Verified GitHub repository owner/name and release permissions.
- Dart SDK versions supported by the current CLI contract.

## Assumptions

- GitHub Actions hosted runners are available for macOS, Ubuntu, and Windows builds.
- Tagged releases are the only publication trigger; pull requests and branches run validation only.
- GHCR/package-manager publication is separate from the initial binary release and requires repository/token setup outside this task.

## Work Items

- [x] Add release build/packaging scripts and a GitHub Actions workflow.
- [x] Add checksums and machine-readable artifact inventory.
- [x] Add package-manager manifest templates or update automation without claiming publication before external setup.
- [x] Add CLI distribution documentation and focused tests.
- [x] Validate native builds on the available host and validate workflow/configuration syntax locally.

## Validation

- `dart analyze` for the CLI and changed packaging helpers — passed.
- `dart test test/release_packaging_test.dart` from `cli/` — 4 tests passed.
- `dart format --output=none --set-exit-if-changed scripts/cli-release/build.dart scripts/cli-release/inventory.dart cli/test/release_packaging_test.dart` — passed.
- Ruby static parsing of both GitHub workflows and the Homebrew template — passed.
- Host-native `dart build cli` archive build for macOS arm64 — passed; archive ran both `bin/hyfens` and `bin/tool` and included the native library bundle.
- Full `dart test` was attempted but the existing native-assets/deployment tests hit an `objective_c.dylib` race and then stalled; the affected release-packaging tests and CLI analysis pass independently.

## Next Action

Verify the destination repository and push a version tag when a release is
approved; the tagged workflow then publishes the six archives and checksums.

## Blockers

External GitHub repository identity, release permissions, and package-manager destinations must be verified before any push or publication.

## Outcome

The release workflow, checksum/inventory helpers, explicit Homebrew/Scoop/
WinGet templates, compatibility shim packaging, and direct-download
documentation are present. The native packager uses `dart build cli` so Dart
build-hook libraries are shipped with the two executables. Scoped analysis,
tests, formatting, workflow parsing, and a runnable macOS arm64 archive pass.
Full-suite completion remains subject to the pre-existing native-assets test
environment issue noted in Validation.

## References

- `cli/pubspec.yaml`
- `cli/bin/hyfens.dart`
- `cli/bin/tool.dart`
- `cli/lib/src/toolchain.dart`
- `scripts/install-hyfens.sh`
- `docs/cli.md`
- `README.md`

## History

- 2026-09-02: Reserved task 235 after confirming the CLI is source-checkout-only and no `.github` release workflow exists.
- 2026-09-02: Corrected PowerShell environment interpolation, checksum conversion import, focused-test paths, and package-manager placeholder assertions; targeted analysis/tests/formatting pass.
- 2026-09-02: Added x64/arm64 macOS, Linux, and Windows runner targets, enforced complete six-target inventory coverage, validated a runnable host archive, and added direct GitHub distribution documentation.
