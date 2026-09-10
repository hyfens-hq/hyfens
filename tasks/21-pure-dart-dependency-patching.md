# Task 21 — Pure-Dart dependency patching and native boundaries

Status: [x] Completed

## Goal
Prove instrumentation of a local pure-Dart package and one practical external pure-Dart package, then classify native/plugin dependencies.

## Scope and Non-goals
Scope: package URI identity, local path dependency, optional external pure-Dart package, MethodChannel/FFI/native classifications, and selective ownership policy. Non-goals: OTA replacement of native binaries/plugins.

## Owner
Build/compiler specialist; coordinator integrates.

## Dependencies
Task 13 identity and representative runtime semantics.

## Assumptions
Pure-Dart package source can enter the overlay with explicit inclusion and stable package identities.

## Work Items
- [x] Add a small local pure-Dart fixture package.
- [x] Instrument and patch package logic.
- [x] Test one external package if it adds meaningful evidence.
- [x] Classify MethodChannel, FFI, Android, and Apple package boundaries.
- [x] Review build-graph behavior and validate.

## Validation
Planned: unchanged package sources, deterministic manifest IDs, package/private imports, release integration, excluded SDK/generated/native code, wrong package/signature rejection, and targeted package tests. Exit: pure-Dart dependency patching works under explicit inclusion or its build-graph blocker is proven.

Executed from `experiments/instrumentation` on 2026-08-22:

- `dart analyze --fatal-infos` — passed with no issues after registering the
  checked-in path fixture as a dev dependency.
- `dart test test/pure_dart_dependency_test.dart -r expanded` — 3 passed,
  including native AOT and hosted `collection` 1.19.1.
- Deterministic canonical patch containers measured 683 bytes for the local
  dependency patch and 663 bytes for the hosted `collection` patch.
- Non-Flutter regression selection — 169 passed in addition to the 3 Task 21
  tests.
- `dart test -r compact` — reached 174 passing tests; one unrelated Flutter
  subprocess test failed because the fixture's generated
  `build/native_assets/macos/native_assets.json` was absent. The failing path is
  outside the Task 21 package overlay and all Task 21 tests passed in that run.

## Next Action
Begin Task 22's predeclared performance and selective-instrumentation matrix.

## Blockers
None; Task 13 is complete. Read-only exploration identified the missing
multi-unit assembly seam and a bounded implementation plan.

## Outcome
An explicit multi-unit
overlay assigns one deterministic global slot table, initializes it once in the
entrypoint, remaps selected packages to ephemeral source copies, and emits a
strict manifest v8 library routing table. Native AOT proves base and patched
direct/tear-off calls for the checked-in `pure_dep` path dependency, with corrupt
and wrong-package artifacts falling back to original code and compiler-side
wrong-package/signature rejection. A JIT integration test also patches
`collection` 1.19.1 `equalsIgnoreAsciiCase` from an ephemeral copy while the Pub
cache hash remains unchanged.

The seam is intentionally unit-explicit, not a transitive package copier. Parts,
generated files, Flutter imports, and `dart:ffi` are rejected. SDK code and native
Android/Apple binaries cannot enter the package-URI source-unit path. MethodChannel
and FFI calls therefore remain host/native capability boundaries, not downloadable
implementation targets.

## References
- `docs/research/function-identity.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 20. Exploration found that runtime global slot tables are sufficient, but the current transformer is entrypoint-only and the overlay builder is single-unit; Task 21 must prove the smallest package-preserving assembler rather than mutate dependency sources.
- 2026-08-22: Added the explicit library-unit/package overlay seam, local and hosted dependency evidence, strict multi-library manifest routing, and fail-closed native/generated boundaries. Focused test and analysis commands pass; task remains in progress pending coordinator review and final integrated validation.
- 2026-08-22: Independent review found and fixed high manifest-view, symlink/output/runtime-pinning, and import-exclusion faults. Final focused analysis, 3 Task 21 tests, 169 non-Flutter regressions, and 33 patch-loader tests passed; accepted limits remain documented.
