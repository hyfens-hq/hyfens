# Task 298 — Flutter-aware CLI release build

Status: [x] Completed

## Goal

Make the public CLI release workflow resolve and build its checked-in Flutter
dependent lockfile on every native runner instead of provisioning Dart alone.

## Scope and Non-goals

Scope:

- the native CLI release workflow's SDK setup;
- the pinned tested Flutter/Dart toolchain selection; and
- workflow/configuration validation and task evidence.

Non-goals:

- changing the CLI dependency graph or lockfile;
- running a tagged release, publishing artifacts, or changing GitHub settings;
- changing the application runtime or mobile release pipeline; and
- adding private Cloud code or credentials.

## Owner

Public release-maintenance coordinator.

## Dependencies

- `cli/pubspec.lock` and `packages/flutter_integration`'s Flutter SDK
  dependency;
- the existing six-runner native release matrix; and
- the tested Flutter 3.47.x / Dart 3.13.x compatibility family.

## Assumptions

- Flutter's bundled Dart SDK is the resolver/compiler used by the CLI release
  jobs.
- The setup action is pinned to a reviewed upstream commit and no dependency
  cache is enabled by this change.
- Hosted runners remain the authority for native cross-platform build proof.

## Work Items

- [x] Replace Dart-only setup with pinned Flutter setup for every native CLI
  build and assembly job.
- [x] Validate workflow syntax, action pins, and the affected release scripts.
- [x] Review the combined diff and record the handoff for a hosted tagged run.

## Validation

Executed on 2026-09-19:

- Actionlint 1.7.12 on the release workflows: passed.
- Dart format/analyze on the release scripts and focused packaging test:
  passed with no changes.
- `git diff --check`: passed.

Hosted native builds, OIDC attestations, and GitHub release publication remain
outside this local change.

## Next Action

The source blocker is closed. Hand off the branch for review and a hosted
dry-run/tagged release acceptance.

## Blockers

None for the source change. Hosted runner availability and release-owner
approval remain external to local validation.

## Outcome

The native CLI release jobs now install the pinned Flutter 3.47.1 stable
toolchain, which supplies the compatible Dart SDK and resolves the checked-in
Flutter-dependent lockfile.

## References

- `.github/workflows/release-cli.yml`
- `cli/pubspec.lock`
- `packages/flutter_integration/pubspec.yaml`
- Task 290 release supply-chain hardening

## History

- 2026-09-19: Reserved after review confirmed that the CLI lockfile includes
  Flutter SDK dependencies while the native release jobs provisioned Dart only.
- 2026-09-19: Replaced Dart-only setup with the pinned
  `subosito/flutter-action` v2.23.0 commit and Flutter 3.47.1 in the build and
  assembly jobs; local workflow/script validation passed.
