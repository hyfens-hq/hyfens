# Task 28 — Phase 1B toolchain foundation

Status: [x] Completed

## Goal

Convert the Phase 1A runtime/compiler seams into a local developer toolchain
that discovers a supported Flutter project, records a deterministic release
baseline, analyzes ordinary source changes, and produces a signed Patch Format
v1 artifact without experiment-only source units or manually supplied function
metadata.

## Scope and Non-goals

Scope: a testable Dart CLI boundary; doctor/init/configuration; bounded project
and package-graph discovery; conservative source and native-boundary
classification; release metadata and instrumentation-plan generation; change
analysis; local Patch Format v1 compilation/signing/inspection/verification;
developer documentation and fixture coverage.

Non-goals: Phase 1C runtime hardening, hosted or production delivery,
accounts/organizations, cloud infrastructure, dashboards, rollout systems,
Flutter/Dart forks, Kernel transformation, or product infrastructure. Physical
device end-to-end validation is a required review item where the local
environment permits it, but it does not authorize any product work.

## Owner

Coordinator with CLI/toolchain ownership.

## Dependencies

Task 27 and all preserved Phase 0/0B evidence; Patch Format v1; capability
contract v1; the Phase 1A compiler and instrumenter facades; the checked-in
Flutter conformance fixture.

## Assumptions

- Architecture B remains the Phase 1 baseline and is not reconsidered absent a
  fundamental blocker supported by new evidence.
- Patch Format v1 remains unchanged; the CLI must use its existing canonical
  encoding and signing boundary.
- Project inputs are treated as untrusted and are processed with bounded,
  deterministic filesystem traversal.
- The first toolchain policy is conservative: uncertain or unsupported changed
  behavior fails patch generation rather than producing a partial patch.
- Release/build integration must use an ephemeral overlay or another
  non-destructive strategy and must not modify a global Flutter SDK.

## Work Items

- [x] Baseline Phase 1A documents, package boundaries, and validation before
  modification.
- [x] Reserve Task 28 and define the bounded Phase 1B implementation plan.
- [x] Establish the CLI executable and command/error-code architecture.
- [x] Implement doctor, bounded project discovery, tool configuration, and
  `tool init` with dry-run behavior.
- [x] Implement package/build-graph discovery and deterministic normalized
  fingerprints.
- [x] Implement source discovery, instrumentation-plan diagnostics, and native
  boundary classification.
- [x] Implement release baseline generation and target-specific release
  identity without mutating the working tree.
- [x] Implement change-level patchability analysis and stable diagnostics,
  including fail-closed partial-change behavior.
- [x] Implement local Patch Format v1 compilation, signing, inspection, and
  offline verification.
- [x] Add deterministic fixtures, CLI/package/analyzer/conformance tests, and
  actual developer workflow documentation.
- [x] Validate the supported local Flutter workflow, physical Android/iOS
  sequence where available, review friction/performance, and stop at the
  Phase 1B maintainer-review gate.

## Validation

Baseline before implementation:

- Root analysis passed.
- Root tests passed.
- Phase 1A package tests passed: patch format, runtime, compiler, and
  instrumenter.
- Full `experiments/instrumentation` suite passed: 180 tests.

Phase 1B validation to date:

- `dart test -j 1` passed in the root, CLI (22 tests), patch format (5),
  runtime (6), compiler (2), instrumenter (3), and generated Flutter
  integration (2). Patch-loading passed 34 tests with one expected environment
  skip for the optional externally supplied CLI artifact.
- `dart analyze --fatal-infos` passed in every affected package and the root.
- The full `experiments/instrumentation` suite was rerun after the Phase 1B
  transformer/bootstrap changes: 180 tests passed.
- `dart format --set-exit-if-changed cli packages experiments test` passed
  after normalizing one previously unformatted patch-format source file.
- Local Markdown links, trailing-whitespace, and shell syntax checks passed.
- `tool doctor` and `tool init --dry-run` passed against the generated ordinary
  Flutter fixture on Flutter 3.47.0/Dart 3.13.0.
- The clean automatic Android release produced release
  `sha256:a68c12eb2f28e6c8654983a0a1dbff88671e7aa6ef7ca7e56babbe684d1f615b`
  in 28,777 ms, a 44 MiB APK, and a generated bootstrap with no manual E1
  controller or per-function source input. Its ordinary `displayCount` edit
  produced signed Patch Format v1 artifact sequence 1, 1,798 bytes, which
  activated and health-confirmed on the physical arm64 Android device and
  remained active after process restart.
- `tool inspect` and `tool verify --release` passed for that physical Android
  artifact; `tool analyze --json` emitted the stable release/classification/
  diagnostic schema.
- Historical pre-correction `tool release ios` reached Xcode archive but failed
  before IPA export with `T1603` because the generated fixture named a team
  with no local account/provisioning profile. No incomplete iOS baseline was
  committed. This was an external signing gate, not evidence against
  Architecture B.
- The current local signing audit found one connected iPhone on iOS 18.7.9,
  Xcode 26.6, and a managed wildcard development profile for team
  `CYT7A4VAZ3` covering `dev.hyfens.hyfensToolchainApp`. The generated
  toolchain fixture still named the stale team `9BRXC9W8MN`; a signed
  XcodeBuildMCP device build reproduced the missing-profile failure without
  provisioning-update or device-registration flags.
- The bounded fixture correction changed only the three toolchain-host
  `DEVELOPMENT_TEAM` assignments to `CYT7A4VAZ3`. The corrected project then
  built a Release device app through XcodeBuildMCP in 31.2 seconds, using the
  existing wildcard profile; its signed entitlements were
  `CYT7A4VAZ3.dev.hyfens.hyfensToolchainApp` and `codesign --verify` passed.
  No app was installed and no organization-wide signing state was changed.
- A higher-level `tool release --project <temporary fixture> --json` retry was
  blocked before Flutter/Xcode execution by unrelated CLI compile errors:
  `RollbackResult` and `CleanupResult` are undefined in
  `cli/lib/src/toolchain.dart`. The iOS signing correction does not claim a
  successful IPA export or physical-device run.

Planned final scope:

- `dart format --set-exit-if-changed` on CLI and changed Dart code;
- root and CLI/package `dart analyze --fatal-infos`;
- root, package, CLI, discovery, analyzer, signing, and conformance tests;
- deterministic identity/artifact and malformed-input tests;
- full instrumentation suite;
- Flutter fixture release/analysis/patch workflow and physical-device checks
  only when the toolchain and devices are available.

The final bounded matrix remains Flutter 3.47.x/Dart 3.13.x; adjacent SDK
families were not installed and remain `NOT TESTED`.

Final gate-closure validation:

- `dart format --set-exit-if-changed cli packages experiments benchmarks test`
  passed; root, CLI/package, and Flutter fixture `dart analyze`/`flutter
  analyze --no-pub` passed with fatal infos.
- Root tests, CLI tests (31), patch format, runtime, compiler, instrumenter,
  Flutter integration (5), patch-loading (40 plus one expected environment
  skip), and the full instrumentation suite (180) passed.
- New durable-storage, rollback-control, rollback/cleanup, lifecycle-state,
  anti-replay, malformed-state, and trusted local-server tests passed.
- Final automatic Android and iOS release commands passed. Stock versus
  instrumented artifact sizes, CLI timing, bounded Android startup/memory,
  Markdown links, trailing whitespace, shell syntax, and Python syntax checks
  passed. Evidence is summarized in `docs/PHASE_1B_REVIEW.md`.

## Next Action

Stop at the completed Phase 1B maintainer review. Phase 1C requires explicit
maintainer approval and is not started by this task.

## Blockers

No current Phase 1B blocker remains for the validated fixture and connected
devices. The historical stale-team `T1603` was closed by a bounded project-local
fixture correction using existing development signing material. Adjacent
Flutter/Dart SDK validation and production signing/transport are outside the
closed local scope and remain explicitly untested/non-goals. No Architecture B
blocker has been found.

## Outcome

Phase 1B toolchain implementation is complete for the bounded local scope:
automatic Android and iOS release/patch/activation, durable app-support
restart persistence, signed base rollback, anti-replay, cleanup, Patch Format
v1/capability conformance, and the consolidated regression suite all passed.
The final recommendation is `PROCEED TO PHASE 1C WITH CONDITIONS`; Phase 1C
and all cloud/product work remain unstarted.

## References

- `tasks/27-phase-1a-language-runtime-foundation.md`
- `docs/adr/0002-adopt-source-instrumentation-for-phase-1.md`
- `docs/spec/patch-format-v1.md`
- `docs/spec/capability-v1.md`
- `docs/architecture/compiler.md`
- `docs/architecture/instrumentation.md`
- `docs/architecture/toolchain.md`
- `docs/architecture/runtime-storage.md`
- `docs/architecture/rollback.md`
- `docs/PHASE_1B_REVIEW.md`
- `docs/research/phase-1b-performance.md`
- `docs/research/flutter-version-compatibility.md`
- `docs/research/developer-workflow.md`
- `docs/security/threat-model.md`
- `fixtures/flutter_conformance_app/README.md`
- `fixtures/flutter_toolchain_app/README.md`

## History

- 2026-08-22: Reserved Task 28 after Task 27; recorded the clean Phase 1A
  baseline and began Phase 1B under the explicit Architecture B and
  no-cloud/no-Phase-1C constraints.
- 2026-08-22: Added the CLI, project/graph/source discovery, conservative
  native-boundary analysis, non-destructive release overlay, Patch Format v1
  compiler/signing path, local development server, generated Flutter bootstrap,
  deterministic fixtures, and developer workflow documentation.
- 2026-08-22: Consolidated package, analyzer, instrumentation, format, link,
  whitespace, and script validation. Physical Android automatic bootstrap,
  signed patch activation, health confirmation, and restart persistence passed;
  generated-fixture iOS export remains blocked by external provisioning setup.
- 2026-08-22: Audited the live Xcode/iPhone signing environment, corrected only
  the generated toolchain fixture's stale local team assignment, and verified a
  signed Release device build through XcodeBuildMCP without install or
  provisioning-update flags. The CLI-level retry remains pending on unrelated
  missing result types; no physical iOS claim was added.
- 2026-08-22: Closed the remaining Phase 1B gates under this task: moved
  lifecycle state to private app-support storage, added signed release-bound
  base rollback and explicit cleanup, corrected the overlay Flutter plugin
  graph/registrant integration, and pinned `path_provider_android 2.2.23`
  after reproducing the newer JNI bootstrap crash. Automatic Android and iOS
  physical activation, health confirmation, restart persistence, rollback, and
  anti-replay behavior passed without reinstalling between base and patch.
- 2026-08-22: Recorded stock/instrumented Android and iOS artifact comparison,
  CLI timing, bounded Android startup/memory evidence, and the Flutter
  3.47.x/Dart 3.13.x compatibility matrix. Final format, analysis, root,
  package, CLI, runtime, rollback, server, patch-loading, instrumentation,
  fixture, link, whitespace, shell, and Python checks passed. The subprocess
  bounds test now has a two-minute test timeout because four `dart run`
  launches exceeded the test package's default 30-second limit on this host.
