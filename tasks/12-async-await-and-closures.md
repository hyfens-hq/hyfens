# Task 12 — Async/await and closure viability

Status: [x] Completed

## Goal
Test the critical async gate with non-blocking continuations and bound the architectural cost of closures/captures.

## Scope and Non-goals
Scope: immediate/delayed Future, await, multiple awaits, async exceptions, host async capability calls, continuation representation, cancellation assumptions, closure/capture spike, and required research documents. Non-goals: complete Dart async/generator/closure semantics.

## Owner
Async runtime specialist; coordinator integrates.

## Dependencies
Tasks 10–11 and capability interface coordination.

## Assumptions
Interpreter frames can suspend as explicit heap state without blocking the Flutter UI isolate.

## Work Items
- [x] Specify continuation/frame lifecycle and cancellation/resource limits.
- [x] Implement the smallest non-blocking Future/await model.
- [x] Prove required async cases and failure propagation.
- [x] Spike closures, captured variables, and nested scopes; classify status.
- [x] Produce `docs/research/async-runtime.md`, update matrix, and validate.

## Validation
Planned: compiler/runtime/integration timing tests proving the event loop remains responsive; immediate/delayed/multiple await; exceptions; cancellation assumptions; host Future completion after rollback; capture and nested-scope cases; malformed continuation/state rejection. Pivot trigger: async requires invasive source/compiler emulation or blocks the UI isolate.

## Next Action
Begin Task 13 identity and compatibility work. Revisit bounded closures only if
the representative widget/ecosystem fixtures prove them necessary.

## Blockers
None; Tasks 10–11 completed. Capability invocation will use a minimal internal
test bridge until Task 14 formalizes the registry.

## Outcome
Version 6 proved a typed, capability-mediated, non-blocking continuation for
ordinary top-level and instance `Future<int>` functions, plus a bounded
`Future<Map<String, dynamic>>` capability result. It preserves zones, handler
frames, budgets, deadlines, and immutable program generations. Atomic failed
activation preserves the known-good patch; fatal runtime errors remain
uncatchable and disable the active slot; timed-out host Futures retain only a
detachable token after continuation state is cleared. Native AOT changed a
top-level result from 4 to 18 and an instance result from 7 to 28. The
two-await patch measured 1,022 bytes and 6.1769 microseconds median per
invocation over seven 10,000-call samples. Closures are NOT YET SUPPORTED and
fail explicitly. Async remains PARTIAL; no physical-device or heap-profiler
claim is made.

## References
- `docs/PHASE_0_INITIAL_REVIEW.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 11 passed adversarial review and consolidated validation.
- 2026-08-22: Implemented v6 typed continuations and bounded capability awaits; initial 112-test pass and native-AOT evidence succeeded.
- 2026-08-22: Adversarial review found non-atomic failed activation, retained timeout state, fatal-error translation, and an async-instance evidence gap.
- 2026-08-22: Fixed and re-reviewed all four findings. Coordinator validation passed format, `dart analyze --fatal-infos`, and all 122 instrumentation tests.
