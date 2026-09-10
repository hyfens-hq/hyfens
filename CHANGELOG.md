# Changelog

Hyfens uses this file as the curated source for user-visible public release
notes. The `[Unreleased]` section is for the next real product release; it does
not select a version or publish software.

## [Unreleased]

### Added

- Added an explicit managed Cloud signup and email-verification contract that
  creates a customer-owned organization and owner session without changing
  the legacy self-hosted client-access registration flow.

### Changed

- Added managed Cloud onboarding handoff guidance for creating the first
  application and environment and connecting the public CLI. Managed Cloud
  deployments must enable the verification delivery configuration; signup is
  fail-closed when it is unavailable.
- Simplified the managed dashboard authentication surface by removing
  non-action session/status copy and focusing the entry screen on sign-in,
  account creation, and invitation access.

## [0.1.10] - 2026-09-08

### Added

- Added admission-bound signed runtime install receipts with durable,
  idempotent `successful_patch_install` settlement.
- Added explicit development-acceptance and provider-neutral Android/Apple
  attestation adapter seams for deployment-owned production trust policy.

### Changed

- Added a release-candidate and release-verification process for real-app,
  archive, installer, package-manager, and MCP acceptance.
- Added explicit opt-in non-billable self-hosted runtime acceptance; production
  billability remains disabled by default.
- Existing delivery credentials must be reissued to receive the new
  `runtime:install` scope.

### Known limitations

- Production Play Integrity and App Attest verification require deployment
  credentials, application configuration, and the applicable store/provider
  context.
- New or changed assets and fonts, native plugins/configuration, and engine
  changes remain new-base-release boundaries.

### Upgrade

```bash
brew upgrade hyfens
```

## [0.1.9] - 2026-09-07

### Fixed

- Aligned patch analysis with patch compilation for supported asynchronous Dart
  code, so known compiler boundaries are reported before patch generation.

### Added

- Bounded stable-signature `Future`/`await` patch support, including
  `Future<void>.delayed` and host-owned asynchronous widget callbacks.
- Public CLI/runtime distribution through GitHub archives, curl, Homebrew, and
  Scoop with checksums and artifact inventory.

### Verified

- A real private Flutter acceptance application completed public iPhone base
  installation, no-reinstall async patch activation, restart persistence, and
  signed rollback.

### Known limitations

- Adding or changing assets and fonts, native plugins or configuration, or the
  Flutter/Dart engine still requires a new base release.
- Production trust settlement, managed Cloud acceptance, and Android project
  signing remain separately gated workflows.

### Upgrade

```bash
brew upgrade hyfens
```

The [CLI distribution guide](https://github.com/hyfens-hq/hyfens/blob/v0.1.9/docs/cli-distribution.md)
covers curl and direct archive installation.

## [0.1.8] - 2026-09-07

### Fixed

- Preserved Flutter widget-registry authority across a runtime bootstrap reset,
  preventing stale registry state from being used after reset.

### Compatibility

- Retained the bounded Flutter patch ABI and fail-closed resource, native, and
  engine boundaries from the previous release.

## [0.1.7] - 2026-09-07

### Added

- Expanded the bounded Flutter patch ABI and transformed widget/runtime
  coverage.
- Added artifact-backed resource evidence for asset, font, and Material icon
  compatibility checks.

### Changed

- Kept unsupported resource, native, and engine changes closed to patches and
  directed them to a new base release.

## [0.1.6] - 2026-09-07

### Fixed

- Corrected the public Flutter runtime package surface and added focused
  runtime-surface regression coverage.

## [0.1.5] - 2026-09-07

### Added

- Introduced the shared bounded patch-compatibility vocabulary and source /
  artifact resource snapshot model.
- Added the first public bounded Flutter widget and state patching seam,
  including a release-owned widget registry.

### Changed

- Exposed compatibility and resource-boundary results through the CLI, MCP,
  diagnostics, and runtime release metadata.

## [0.1.4] - 2026-09-07

### Fixed

- Bound flavored releases to their selected native Android and iOS application
  identities, preventing a stale unflavored identity from replacing a flavor
  identity during release or patch workflows.

### Changed

- Kept the selected project, flavor, entrypoint, target identity, and runtime
  binding aligned in persisted configuration and discovery diagnostics.

## [0.1.3] - 2026-09-05

### Added

- Added automatic Flutter app, flavor, and entrypoint discovery for normal
  projects, Melos, Pub Workspaces, and multi-app repositories.
- Added app-scoped installation keys, signed delivery admissions, and
  successful-activation receipt primitives with durable retry behavior.

### Changed

- Added fail-closed checks for changed assets, fonts, native build inputs, and
  Flutter engine identity.
- Bundled the standalone runtime dependencies required by the public CLI.

### Compatibility

- Patches carry supported code rather than asset or font bundles. Broader
  independent real-app widget, state, routing, and cross-platform acceptance
  remained in progress at this release boundary.

## [0.1.2] - 2026-09-04

### Added

- Added Flutter flavor and custom Dart entrypoint selection support to the CLI.

### Changed

- Expanded the public project, profile, self-hosted workspace, and distribution
  documentation around the initial flavor-aware workflow.

## [0.1.1] - 2026-09-02

### Fixed

- Fixed latest-release curl resolution and Windows archive roots so the full
  semantic version is preserved in direct and package-manager installation
  paths.

### Added

- Added the complete public CLI help/version surface.
- Added the built-in stdio MCP server for compatible AI coding agents, using
  the CLI's existing authorization and credential boundaries.

### Known limitations

- WinGet publication and anonymous GHCR package visibility remained external
  distribution gates.

## [0.1.0] - 2026-09-02

### Added

- Published the initial Apache-2.0 Hyfens CLI and open-source foundation.
- Added the bounded release, patch, verification, deployment, and rollback
  command surface with signed release/application binding checks.
- Published macOS, Linux, and Windows x64/arm64 archives with SHA-256
  checksums and artifact inventory.

### Known limitations

- This was an early public developer release with bounded Flutter/Dart support,
  platform-signing and notarization gates, and initial installer/package/image
  distribution limitations documented in its release review.

[Unreleased]: https://github.com/hyfens-hq/hyfens/compare/v0.1.10...HEAD
[0.1.9]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.9
[0.1.8]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.8
[0.1.7]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.7
[0.1.6]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.6
[0.1.5]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.5
[0.1.4]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.4
[0.1.3]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.3
[0.1.2]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.2
[0.1.1]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.1
[0.1.0]: https://github.com/hyfens-hq/hyfens/releases/tag/v0.1.0
