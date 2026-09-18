# Task 11 — Exception semantics

Status: [x] Completed

## Goal
Prove bounded throw/try/catch/finally behavior and safe translation between interpreted and AOT failures.

## Scope and Non-goals
Scope: interpreted exceptions, caught host-capability failures, stable error representation, finally behavior, runtime faults, and process-safe fallback. Non-goals: perfectly reproducing all Dart stack traces or catching fatal VM errors.

## Owner
Runtime specialist; coordinator integrates.

## Dependencies
Task 10.

## Assumptions
Guest failures can be represented as typed data and separated from verifier/runtime faults.

## Work Items
- [x] Specify guest, host, verifier, and runtime error classes.
- [x] Implement throw/try/catch/finally lowering and execution.
- [x] Test interpreted-to-AOT and AOT-to-interpreted boundaries.
- [x] Prove runtime faults cannot terminate the host process unexpectedly.
- [x] Document stack/error limits and validate.

## Validation
Planned: semantic tests for each construct and nesting, host failure translation, uncaught guest failure, malformed handlers, budget faults, finally on all exits, and integration fallback. Exit: no tested guest/runtime fault escapes as an uncontrolled process failure.

## Next Action
Begin Task 12's async continuation and bounded closure viability design.

## Blockers
None; Task 10 completed.

## Outcome
Version 5 adds bounded handler metadata, guest throws, catch-all handling,
rethrow, nested `try/catch/finally`, pending return/throw completion, and distinct
success/guest-throw/runtime-fault outcomes. A stock native-AOT guard propagated a
patched integer throw to an ordinary AOT catch with a synthetic trace. Explicit
receiver and collection language failures are catchable bounded values; fatal
resource errors, verifier faults, budgets, and runtime invariants are not. The
deterministic exception patch is 576 bytes. Typed/multiple catches, readable catch
bindings, full Dart stack traces, and cross-region break/continue remain unsupported.

## References
- `tasks/10-control-flow-and-collections.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 10 passed adversarial review and consolidated validation.
- 2026-08-22: Adversarial review found and fixed receiver `Error`/arbitrary throw translation and catchable List/Map access failures without weakening sandbox-fault separation.
- 2026-08-22: Completed after format/analyze, 94 instrumentation tests (including native AOT), six loader tests, and two focused Flutter widget tests passed.
