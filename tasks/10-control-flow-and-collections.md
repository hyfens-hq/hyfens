# Task 10 — Control flow and collections

Status: [x] Completed

## Goal
Derive the smallest safe instruction set that supports required branching, loops, and useful List/Map/Set operations.

## Scope and Non-goals
Scope: if/else, nested conditions, switch, for, while, early return, indexing, lookup, assignment, length, iteration, contains, and simple transformations. Non-goals: complete Dart lowering or automatic higher-order closure support.

## Owner
Compiler/VM specialist; coordinator integrates.

## Dependencies
Tasks 08–09.

## Assumptions
Structured source constructs can lower to a bounded verifier-friendly control-flow graph.

## Work Items
- [x] Add tests that derive required instructions and encodings.
- [x] Implement structured branching/loop compilation and verification.
- [x] Implement bounded List/Map/Set semantics.
- [x] Classify higher-order operations and closures honestly.
- [x] Update opcode specification/support matrix and validate.

## Validation
Planned: semantic parity tests, invalid jumps/joins/indices/types, loop instruction budgets, collection size/mutation limits, deterministic encoding, unsupported-feature diagnostics, and native integration. Exit: required constructs pass or are explicitly classified with evidence.

## Next Action
Begin Task 11's exception representation and handler-semantics design.

## Blockers
None; Tasks 08–09 completed.

## Outcome
Version 4 adds verified typed locals, definite-initialization joins, structured
branching and bounded loops, plus List/Map/Set construction, lookup, assignment,
membership, length, addition, and iteration. A stock native-AOT fixture applied a
765-byte patch and returned `[4,6,7]` while leaving its host input unchanged.
Unsupported fallthrough, higher-order closure APIs, receiver-origin mutation,
malformed locals/Sets, invalid joins, and exhausted loop budgets fail closed.
Argument collection mutation is intentionally by value and therefore is not
transparent Dart caller-visible mutation; this remains an explicit limitation.

## References
- `experiments/instrumentation/SPEC.md`
- `docs/research/control-flow-collections.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 09 passed review and validation.
- 2026-08-22: Read-only design retained the stack VM, added definite-initialization joins and invocation-local collection-copy requirements, and kept closures/higher-order APIs explicit rejections.
- 2026-08-22: Coordinator review found and fixed implicit switch fallthrough and receiver-origin collection mutation through direct and aliased paths; runtime iteration was confirmed to preserve Dart insertion order.
- 2026-08-22: Completed after format/analyze, 72 instrumentation tests (including native AOT), six loader tests, and two focused Flutter widget tests passed.
