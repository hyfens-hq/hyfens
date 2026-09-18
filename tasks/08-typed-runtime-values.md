# Task 08 — Typed runtime values and generalized functions

Status: [x] Completed

## Goal
Replace the `int Function(int, int)` experiment boundary with a deterministic, validated value and function-signature model for null, bool, int, double, String, List, and Map.

## Scope and Non-goals
Scope: typed values, nullable schemas, generalized positional functions, deterministic encoding, safe argument/return validation, five required conformance functions, malformed-value tests, and support-matrix updates. Non-goals: objects, async, closures, widgets, signing, and unrestricted `dynamic`.

## Owner
Runtime/compiler specialist; coordinator integrates.

## Dependencies
Task 06 E0/E1 baseline.

## Assumptions
An explicit recursive value schema can preserve useful Dart types without exposing arbitrary host objects.

## Work Items
- [x] Specify value/signature semantics and pivot criteria.
- [x] Implement generalized compiler, verifier, interpreter, and dispatch adapters.
- [x] Prove the five required functions and nullable cases.
- [x] Add malformed argument/value/return and deterministic-output tests.
- [x] Review the package diff and run consolidated scoped validation.

## Validation
Planned: format/analyze; compiler/runtime unit tests for each value kind and required signature; malformed UTF-8/JSON, nesting, size, schema, return-type, and nullability cases; deterministic bytes across repeated builds; native AOT integration. Exit: all supported signatures execute patched/unpatched safely, unsupported schemas fail at compile/activation, and no malformed value escapes into host code.

## Next Action
Task 09 may build bounded receiver adapters on the completed typed signature/value boundary.

## Blockers
None.

## Outcome
Patch/runtime format v2 now carries explicit function signatures and recursively tagged values for null, bool, int, finite double, String, List, and String-keyed Map. Host conversion validates nullability, exact primitive types, collection element/value schemas, depth, nodes, entries, strings, and encoded bytes; maps encode in canonical lexical key order. Top-level `dynamic`, arbitrary objects, optional/named parameters, non-String map keys, and unsupported signatures fail explicitly.

All five required functions passed compiler/runtime tests, including nullable String coverage. A native AOT test changed a typed `transform` patch while leaving unrelated functions on their bundled behavior. The typed patch was 540 bytes. This package added only the required comparison, short-circuit, indexing, and literal construction instructions; it does not claim general collection/control-flow support.

Review found and fixed two blocking issues: omitted expected signatures now bind to the legacy int2 contract instead of becoming a wildcard, and `&&` now uses verified short-circuit jumps. Consolidated validation passed: instrumentation format/analyze and 40 tests (including native AOT), patch loader analyze and 6 tests, and Flutter fixture analyze and 2 widget tests. No physical-device generalized-value claim is made until Task 23.

## References
- `docs/PHASE_0_INITIAL_REVIEW.md`
- `docs/research/typed-runtime-values.md`
- `docs/dart-support-matrix.md`
- `experiments/instrumentation/SPEC.md`

## History
- 2026-08-22: Phase 0B package reserved and started after maintainer authorization.
- 2026-08-22: Primary-source value research completed; format/runtime v2 implemented and reviewed. Two blocking review findings were fixed; all 48 scoped and downstream tests passed. Task completed within its stated boundary.
