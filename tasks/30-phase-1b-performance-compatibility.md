# Task 30 — Phase 1B performance and bounded compatibility evidence

Status: [x] Completed

## Goal

Produce repeatable host-side performance evidence for the existing Phase 1B
CLI boundary and a bounded Flutter/Dart compatibility matrix without changing
toolchain semantics or beginning Phase 1C/product work.

## Scope and Non-goals

Scope: `benchmarks/**`, `docs/research/phase-1b-performance.md`,
`docs/research/flutter-version-compatibility.md`, and a new isolated test
directory only if validation requires it. A task record is also maintained as
required by the repository workflow.

Measure public `tool` command wall-clock behavior for discovery/doctor,
analyze, metadata-only release, patch, format inspection, and verification
where feasible. Record signing as part of the public patch path because the
CLI has no standalone signing command. Record physical-device/build measures
only when actually available; do not infer them from host timings.

Non-goals: core CLI/toolchain changes, Flutter/Dart SDK installation or
mutation, global environment changes, full release/build performance claims,
physical-device product work, hosted delivery, or Phase 1C.

## Owner

Phase 1B performance and compatibility evidence owner.

## Dependencies

Task 28 Phase 1B CLI/toolchain foundation; the checked-in Flutter toolchain
fixture; the locally selected Flutter/Dart SDK; existing Patch Format v1 and
signing behavior.

## Assumptions

- The active local SDK is Flutter 3.47.x with Dart 3.13.x.
- The benchmark may copy the fixture to a temporary project and may run
  `flutter pub get` there, but it must not modify the checked-in fixture or a
  global SDK.
- Public command process wall-clock timing is the useful Phase 1B measure;
  internal stage timings and device/runtime measurements are not claimed
  unless the existing public boundary exposes them.
- A bounded compatibility policy should fail closed for SDK families without
  local evidence rather than imply support from version constraints alone.

## Work Items

- [x] Inspect existing command contracts, benchmark conventions, and local
  SDK availability.
- [x] Add a repeatable temporary-project CLI benchmark harness under
  `benchmarks/`.
- [x] Capture host measurements and compatibility evidence.
- [x] Write the performance and Flutter/Dart compatibility reports.
- [x] Run scoped checks, review the task-owned diff, and record outcomes.

## Validation

Completed scoped checks:

- `dart format --set-exit-if-changed benchmarks` — passed.
- `dart analyze --fatal-infos benchmarks/phase_1b_cli_benchmark.dart` — passed.
- `dart analyze --fatal-infos cli` — passed after the concurrent rollback
  worktree definitions became available.
- `flutter analyze --no-pub` in `fixtures/flutter_toolchain_app` — passed.
- `dart test -j 1 test/cli_process_test.dart` from `cli/` — passed.
- `dart run benchmarks/phase_1b_cli_benchmark.dart --help` — passed.
- `dart run benchmarks/phase_1b_cli_benchmark.dart --samples=5
  --warmups=1 --output=/tmp/hyfens-phase1b-cli.json` — passed; five samples
  and one warmup completed for every measured stage.
- Local report-link, trailing-whitespace, and task-owned status checks —
  passed.
- `flutter --version`, `dart --version`, `flutter channel`, `flutter doctor
  -v`, and `puro ls` — captured current SDK and adjacent-environment status.

No full Flutter build or physical-device run was required for this evidence
task; the reports explicitly separate those unavailable measurements.

## Next Action

No further Phase 1B performance/compatibility work is required in this
package. Future adjacent SDK validation must use a separately installed,
isolated environment and must not broaden the current policy implicitly.

## Blockers

None. Adjacent SDK evidence remains conditional on an independently installed
local environment; SDK installation is outside this task.

## Outcome

Added a repeatable host CLI harness and two evidence reports. On macOS
26.6.2 arm64 with Flutter 3.47.0 stable / Dart 3.13.0, five warm samples
measured medians of 8,887.724 ms for doctor/discovery, 8,904.064 ms for
analyze, 8,320.103 ms for patch, 6,164.198 ms for format inspection, and
6,201.025 ms for verification. Metadata-only release measured 9,168.083 ms
on the cold creation and an 8,884.019 ms warm median. Standalone signing,
full Flutter build, and physical-device measurements remain explicitly
unavailable.

## References

- `tasks/28-phase-1b-toolchain-foundation.md`
- `docs/cli.md`
- `docs/architecture/toolchain.md`
- `experiments/instrumentation/tool/performance/PROTOCOL.md`
- `fixtures/flutter_toolchain_app/README.md`

## History

- 2026-08-22: Reserved Task 30 after concurrent Task 29 reservations were
  observed. The task remains limited to Phase 1B evidence and contains no
  Phase 1C or product work.
- 2026-08-22: Added the temporary-project public CLI benchmark, captured the
  five-sample host run, documented unavailable physical/standalone-signing
  measurements, and recorded the bounded Flutter 3.47.x/Dart 3.13.x policy.
- 2026-08-22: Scoped format, analysis, fixture, CLI smoke test, report-link,
  and whitespace checks passed. No core toolchain or global SDK files were
  changed.
