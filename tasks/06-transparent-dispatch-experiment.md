# Task 06 — Transparent dispatch experiment

Status: [x] Completed

## Goal
Build the cheapest reproducible experiment that proves or rejects automatic dispatch from an ordinary Dart function to a runtime-provided implementation, and measure unpatched dispatch overhead.

## Scope and Non-goals
Scope: one normal Dart function, an automatic source or Kernel transformation chosen from evidence, stable-ID prototype, original-AOT fallback, runtime replacement, focused tests, generated-output inspection, and benchmarks. A physical Android release/no-reinstall proof is included only if the mechanism reaches that boundary within this package. Non-goals: broad Dart support, a large VM/opcode set, server infrastructure, production signing/container design, or Phase 0B conformance breadth.

## Owner
Coordinator for E0; a device specialist may own E1 after the E0 gate. Task-file ownership remains with the coordinator.

## Dependencies
Tasks 03–05; Task 02 informs the baseline and integration comparison.

## Assumptions
The experiment can isolate dispatch feasibility before implementing a general interpreter.

## Work Items
- [x] Define experiment hypothesis, transformation seam, stable-ID rule, benchmark method, and exit/rejection criteria.
- [x] Implement the smallest automatic transformation and runtime dispatch/fallback mechanism.
- [x] Test transformation semantics, patched/unpatched behavior, malformed metadata, and deterministic output as applicable.
- [x] Benchmark direct AOT-equivalent call, instrumented unpatched call, and patched call with reproducible output.
- [x] Attempt Android release/local patch/no-reinstall execution if prerequisites are met; otherwise record the exact missing proof rather than simulating success.
- [x] Review the combined diff and run one consolidated scoped validation pass.

## Validation
Selected E0 seam: analyzer-guided, offset-based callee-entry rewriting in an ephemeral source overlay, using the installed Dart 3.13.0 toolchain. Stable ID material is versioned package/library/declaration identity; a release-local dense slot is embedded in the guard. Planned validation: scoped format/analyze/tests; compile and run a native executable; compare deterministic transformed source/manifests across two absolute directories; run baseline, unpatched-dispatch, and patched benchmarks from compiled executables; inspect original-source hashes; and reject malformed/unknown patch data safely. Pre-measurement E1 performance gate: the compiled hot-leaf unpatched path must add no more than 10 ns/call and be no more than 5× the compiled direct baseline, with zero per-call argument-list allocation; exceeding either threshold keeps B viable only for selective/coarse boundaries and blocks broad-instrumentation claims. No patched-interpreter speed threshold is set in E0 because the derived VM is intentionally minimal; its result is measurement, not an optimization claim. E1 adds a stock Flutter Android release build and physical-device no-reinstall activation only after E0 passes all non-performance gates and this broad-instrumentation gate, or proceeds explicitly as a selective-boundary experiment if only the ratio gate fails due to a sub-nanosecond baseline.

## Next Action
Task 07 must synthesize the conditional result and stop before Phase 0B.

## Blockers
None for the bounded Task 06 scope. Broad conformance and iOS remain explicitly outside this completed package.

## Outcome
E0 proved automatic callee-entry dispatch for one ordinary synchronous top-level function on stock Dart AOT, with deterministic source/manifest/map/patch output and safe malformed-input rejection. The seven-sample five-million-call benchmark measured 2.19 ns/call direct, 3.55 ns/call instrumented/unpatched (+1.36 ns, 1.62x), and 214.56 ns/call interpreted; the predeclared unpatched gate passed.

E1 built a stock Flutter 3.47.0 Android release APK and ran it on a physical device. After one install, a 329-byte local data patch changed a multi-branch price function from 630 to 525 at quantity 7 while preserving widget state; invalid input retained the active patch and manual rollback restored base AOT behavior. Package install/update timestamps remained unchanged. The final content-address binding hardening was covered by six lifecycle tests after the device run and did not alter the exercised valid-patch path.

Validation passed for E0 (format, analyze, 17 tests, native compilation/behavior, deterministic artifacts and benchmark), E1 loader (format, analyze, 6 tests), Flutter fixture (analyze, 2 widget tests), stock Android release build, and the physical sequence. This outcome proves neither broad Dart/Flutter coverage nor iOS, signing, crash-loop health, store acceptance, or production readiness.

## References
- `docs/research/flutter-aot.md`
- `docs/architecture/options.md`

## History
- 2026-08-22: Task number reserved before delegation.
- 2026-08-22: E0 source-overlay/callee-entry seam selected from completed research; implementation started.
- 2026-08-22: E0 passed 17 tests, native compilation and behavior checks, deterministic source/manifest/map checks, and the performance gate (3.55 ns/call unpatched versus 2.19 ns/call baseline; 214.56 ns/call interpreted). E1 authorized.
- 2026-08-22: E1 passed loader/widget validation, a stock release build, and a physical one-install activation/rejection/rollback sequence. Review added stored-patch digest binding and two regression tests; Task 06 completed with narrow-scope limitations recorded.
