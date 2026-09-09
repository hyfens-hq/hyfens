# Task 29 — Phase 1B durable app-owned runtime storage

Status: [x] Completed

## Goal

Move the generated Flutter bootstrap's E1 lifecycle directory from the shared
system temporary root to the app-private support/data directory supplied by
the Android/iOS host, while preserving E1 persistence and atomic activation.

## Scope and Non-goals

Scope: the internal storage resolver and generated bootstrap in
`packages/flutter_integration/**`, host-runnable focused tests under its
`test/**` directory, and `docs/architecture/runtime-storage.md`.

Non-goals: changes to Architecture B, Patch Format v1, capability v1, the E1
controller's persistence/atomic semantics, competing stores, rollback UX, or
Phase 1C fault injection.

## Owner

Phase 1B runtime integration.

## Dependencies

Existing generated bootstrap, E1 controller storage contract, Flutter Android
and iOS host path providers, Patch Format v1, and capability v1.

## Assumptions

- `getApplicationSupportDirectory()` is the smallest shared Flutter boundary
  that supplies private app-owned storage on both Android and iOS.
- The package must remain host-testable with `dart test`; the Flutter-only path
  lookup therefore stays behind a conditional import.
- The existing `hyfens/<appId>/<releaseId>` relative layout remains stable so
  E1 retains its current release binding and atomic file semantics.

## Work Items

- [x] Reserve the runtime-storage package boundary and validation scope.
- [x] Add the internal conditional platform path resolver and safety checks.
- [x] Replace the generated bootstrap's system-temp lifecycle root.
- [x] Add host-runnable path, traversal-safety, and restart persistence tests.
- [x] Add focused runtime-storage architecture documentation.
- [x] Review the combined diff and run scoped format, analysis, and tests.

## Validation

- `dart format --set-exit-if-changed` on changed Dart files.
- `dart analyze --fatal-infos` for `packages/flutter_integration`.
- `dart test` for `packages/flutter_integration/test`.

## Next Action

Hand off the completed Phase 1B runtime-storage boundary for maintainer review.

## Blockers

None known.

## Outcome

The generated bootstrap now resolves Flutter application-support storage and
keeps the existing E1 release-scoped directory layout. Host tests cover path
construction, namespace separation, traversal/control-character rejection,
restart reuse, and the absence of a pure-Dart system-temp fallback. E1,
Architecture B, Patch Format v1, capability v1, and Phase 1C fault injection
were not changed.

## References

- `tasks/28-phase-1b-toolchain-foundation.md`
- `docs/PHASE_1B_REVIEW.md`
- `experiments/patch_loading/lib/src/controller.dart`

## History

- 2026-08-22: Reserved Task 29 for the Phase 1B durable app-owned runtime
  storage boundary.
- 2026-08-22: Added the conditional Flutter application-support resolver,
  replaced the bootstrap system-temp root, added host path/restart tests and
  focused architecture documentation, and passed scoped format, Dart/Flutter
  analysis, and package tests.
