# Task 22 — Performance and selective instrumentation

Status: [x] Completed

## Goal
Measure representative stock, instrumented/unpatched, and patched execution and determine an evidence-based instrumentation selection policy.

## Scope and Non-goals
Scope: latency, throughput where useful, startup, lookup, memory, activation, signature verification, file size, binary growth, direct table/cached flag/generation alternatives, app/package/generated/SDK categories, and minimal include/exclude experiment. Non-goals: unmeasured optimization or full user configuration.

## Owner
Performance/build specialist; coordinator integrates.

## Dependencies
Tasks 08–21 provide representative features.

## Assumptions
Broad guards may require automatic selection or cheaper lookup, but measurements must decide.

## Work Items
- [x] Predeclare workloads, sample method, budgets, and noise controls.
- [x] Measure stock/instrumented/patched and artifact costs.
- [x] Benchmark the current lookup and admit no unmeasured alternative.
- [x] Compare application/package/generated/Flutter/SDK selection categories.
- [x] Document policy, raw results, and validate benchmark reproducibility.

## Validation
Planned: process-isolated samples, physical-device startup/memory where possible, identical workloads, raw machine-readable output, binary/patch bytes, before/after optimization tests, and no concurrent build in the same output directory. Pivot trigger: unacceptable unpatched cost or binary growth at useful coverage.

Executed on the macOS arm64 Apple M4 host on 2026-08-22:

- `dart run tool/performance_benchmark.dart` from
  `experiments/instrumentation` — completed the unreduced 10M-call, two-warm-up,
  15-sample randomized host AOT matrix and passed the hard gate. Raw JSON SHA-256:
  `b1dbb76e4859af42d0dde30396a89f8faf13821fa279b958f5aabfb48233e48a`.
- `dart run tool/activation_benchmark.dart` from `experiments/patch_loading` —
  completed all six AOT activation stages with two warm-ups and 15 randomized
  process samples. Raw JSON SHA-256:
  `7e63e7849a2c248974ed11edbfb62b276ec048e303d70281d086649481d29b6c`.
- `dart analyze --fatal-infos` in `experiments/instrumentation` — no issues.
- `dart test test/selective_instrumentation_test.dart test/pure_dart_dependency_test.dart -r expanded`
  — 5 passed, including native AOT and hosted-package regression coverage.
- `dart analyze --fatal-infos` in `experiments/patch_loading` — no issues.
- `dart test test/signed_patch_test.dart -r compact` — 4 passed.
- `dart test test/controller_test.dart -r compact` — 29 passed.

No physical-device task was run. No cached-flag/generation optimization was
implemented or accepted, so there is no unmeasured before/after claim.

The schema-v2 replacement raw files close the independent review's provenance
findings: source and generated artifacts are hashed, build/sample commands and
exit statuses are retained, activation is lock/build protected, and every host
and activation checksum is validated before acceptance.

## Next Action
Attempt Task 23's physical Android cross-feature sequence.

## Blockers
None; Tasks 08–21 provide the representative semantics and fixtures. Physical
device measurements remain separately dependent on device availability.

## Outcome
Host evidence passes the inherited hot-leaf gate: stock measured 2.0103
ns/call and instrumented/unpatched 6.0329 ns/call, adding 4.0226 ns at 3.0010x stock.
The active-unrelated-slot case was 6.4734 ns/call and interpreted execution 557.9237
ns/call. Current dense lookup hit/miss loop diagnostics, reporting-only process
completion/RSS/binary size, and
E1 signed activation are recorded with raw samples. An auditable selection policy
implements app-default, dependency-opt-in, generated-default-exclude, and hard
SDK/Flutter/native boundaries. Focused validation and independent recomputation
pass.

## References
- `experiments/instrumentation/RESULTS.md`
- `experiments/instrumentation/tool/performance/PROTOCOL.md`
- `experiments/instrumentation/tool/performance/results/task22-host-raw.json`
- `experiments/instrumentation/tool/performance/results/task22-activation-raw.json`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 21 passed adversarial review. The inherited hot-leaf gate remains at most 10 ns/call and 5x stock; other new metrics are reporting-only unless a threshold is predeclared before execution.
- 2026-08-22: Predeclared the host-AOT protocol, sample statistics, noise controls,
  checksums, reporting-only metrics, and selective-instrumentation policy in
  `experiments/instrumentation/tool/performance/PROTOCOL.md` before executing any
  Task 22 measurement.
- 2026-08-22: Executed the unreduced 10M-call/15-sample host AOT matrix and the
  15-sample signed-activation matrix. The hot-leaf gate passed. Added selective
  package planning with focused policy tests; retained Task 08 history unchanged.
- 2026-08-22: Independent review recomputed all summaries and the hard gate from
  raw samples. Tightened future harness runs to reject unexpected workload and
  lookup checksums. Reclassified dense-lookup numbers as optimizer-sensitive loop
  diagnostics and startup as process-completion time; the recorded hot-leaf gate
  itself remains valid. Recorded the remaining activation-lock and raw-source-
  provenance gaps without rewriting either raw result.
- 2026-08-22: Appended Protocol Amendment 1 at 2026-08-22T02:57:23Z before any
  replacement measurement. It preserves the original protocol and gates while
  predeclaring schema-v2 process provenance, complete source inventories,
  activation checksum validation, and scratch/concurrent-build protection.
- 2026-08-22: Superseded schema-v1 raw hashes
  `2116d6407c4d1157774baa79bf9516cc62fd59f5b1db4149cff73c1d311f32bf`
  (host) and
  `18767b6875d69dc26a18f56826a375578343d86f173dc8e27c390c22b8995f69`
  (activation) with the predeclared schema-v2 replacement run. Recomputed every
  statistic independently; the corrected hot gate passes at 4.0226 ns added and
  3.0010x stock.
- 2026-08-22: Completed after independent review verified all schema-v2 source/artifact hashes, commands, exit statuses, checksums, statistics, and gates and found no remaining blocker/high issue.
