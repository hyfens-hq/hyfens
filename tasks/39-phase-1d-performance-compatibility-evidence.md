# Task 39 — Phase 1D performance and compatibility evidence

Status: [x] Completed

## Goal

Provide bounded, reproducible Phase 1D host evidence for supported application
workload classes, public interpreter-layer timing, and Patch Format v1 patch-size
scaling, while preserving the Phase 1C baselines and evidence labels.

## Scope and Non-goals

Scope: audit the existing benchmark and reducer harnesses; add the smallest
supported benchmark under `benchmarks/`; record executed host evidence and
explicit NOT RUN gaps in the Phase 1D performance and Flutter/Dart compatibility
research notes.

Non-goals: runtime, lifecycle, controller, compiler, physical-device, cloud,
product, transport, store-compliance, long-fuzz, soak, or final Phase 1D review
work; changing Phase 1C baselines or labels; editing task 38.

## Owner

Phase 1D performance/compatibility evidence worker.

## Dependencies

- Existing Phase 1C performance baselines and Android reducer;
- existing Task 22 host performance/activation harnesses;
- public E0 interpreter, Patch Format v1 bridge, and atomic batch-install seams;
- current Flutter 3.47.0/Dart 3.13.0 environment and isolated 3.47.1/Dart 3.13.1 environment.

## Assumptions

- Host-only application/profile results remain directional and are not promoted
  to physical or user-visible device performance claims.
- Internal interpreter stage attribution is unavailable without runtime changes;
  unsupported attribution remains explicitly NOT RUN.
- Existing Phase 1C values and labels are historical baselines and remain
  unchanged.

## Work Items

- [x] Audit existing benchmark/reducer harnesses and establish the bounded seam.
- [x] Add and exercise Phase 1D application/profile and patch-size benchmark support.
- [x] Update the two permitted research documents with executed evidence and gaps.
- [x] Review the task-owned diff and run scoped formatting, analysis, self-check,
  benchmark, reducer, and compatibility checks.

## Validation

Executed scoped checks and results:

- `dart format --output=none --set-exit-if-changed benchmarks/phase_1d_performance_benchmark.dart` — PASS;
- `dart analyze --fatal-infos benchmarks/phase_1d_performance_benchmark.dart` — PASS;
- `dart run benchmarks/phase_1d_performance_benchmark.dart --self-check` — PASS;
- `dart run benchmarks/phase_1c_android_measurement.dart --self-check` — PASS;
- active `dart --version`, `flutter --version`, `flutter channel`, `puro ls`,
  and fixture `flutter analyze --no-pub` — PASS;
- the 3-sample/1-warmup Phase 1D host run with size counts 1, 5, 20, and 50 —
  PASS; raw output `/tmp/hyfens-phase1d-performance-final.json`;
- isolated `phase1c-3471` Phase 1D rerun — NOT RUN at bounded closeout;
- physical/device, Flutter-engine, controller, long-fuzz, soak, and internal
  interpreter-stage attribution — NOT RUN.

No physical-device or full repository suite was in scope.

## Next Action

Coordinator should resolve the duplicate task-39 reservation at integration
without renumbering or rewriting either task history. No further performance
worker action is pending within this bounded package.

## Blockers

None currently. Physical/device and private interpreter-stage evidence are
bounded gaps, not blockers for this evidence package.

## Outcome

Completed as a host-only evidence package. Added the bounded Phase 1D
application/profile and Patch Format v1 bridge scaling harness, preserved the
Phase 1C physical Android baseline table and labels, and recorded explicit
physical/device and adjacent Phase 1D compatibility gaps. No runtime,
lifecycle, controller, physical-evidence, review, cloud, or product files were
changed.

## References

- `tasks/38-phase-1d-runtime-integration-readiness.md`
- `benchmarks/phase_1c_android_measurement.dart`
- `experiments/instrumentation/tool/performance/PROTOCOL.md`
- `experiments/instrumentation/tool/performance_benchmark.dart`
- `experiments/patch_loading/tool/activation_benchmark.dart`
- `docs/research/phase-1c-performance.md`
- `docs/research/flutter-version-compatibility.md`

## History

- 2026-08-23: Task 39 reserved for the disjoint Phase 1D performance and
  compatibility evidence package; task 38 remains untouched.
- 2026-08-23: Completed bounded host benchmark, reducer self-check, active
  toolchain checks, and research-note updates. A second owner also has a
  `tasks/39-phase-1d-local-observability.md` file; this worker did not rename,
  renumber, or modify that file. Coordinator resolution is required at
  integration while preserving both histories.
