# Task 09 — Instance methods and bounded object state

Status: [x] Completed

## Goal
Determine whether ordinary instance methods can be transparently instrumented while exposing only explicit, typed object state.

## Scope and Non-goals
Scope: `this`, selected fields/getters/setters, private-member identity, inheritance, host-object adapters, and `PricingService` conformance. Non-goals: unrestricted reflection, arbitrary object traversal, class-layout OTA changes, or constructors.

## Owner
Compiler/runtime specialist; coordinator integrates.

## Dependencies
Task 08.

## Assumptions
Generated per-release adapters can expose a least-privilege view of an AOT receiver.

## Work Items
- [x] Specify receiver schemas and object/capability boundary.
- [x] Instrument named instance methods and generate bounded adapters.
- [x] Test fields, getters, setters, private members, and inherited methods.
- [x] Reject unsupported receiver access and incompatible layouts.
- [x] Review and run consolidated scoped validation.

## Validation
Planned: compiler/runtime/integration tests for receiver access and mutations, private/inherited identity, wrong receiver/schema, hidden-member rejection, and unpatched fallback; focused native AOT execution. Exit: the required service works without reflection or silent access expansion.

## Next Action
Task 10 may derive structured control flow and collection instructions on the bounded typed/receiver runtime.

## Blockers
None; Task 08 completed.

## Outcome
Version 3 transparently instruments same-unit ordinary instance method declarations and binds each patch to a class-qualified function ID plus a deterministic receiver descriptor. Only typed properties explicitly read as `this.property` in the release method become dense read slots. A same-library adapter is created only after the patch lookup succeeds; the interpreter receives typed slot reads, never `this`, reflection, arbitrary property names, or method invocation.

Native AOT proved a `PricingService` patch using a public field, private same-library field, and pure getter. Direct, inherited virtual, and pre-existing tear-off calls changed from 18.5 to 26.5; a subclass override retained its distinct ID and 99.0 result. Wrong adapters, descriptors, slots, and values fail closed. Raw `this`, method calls, unselected properties, static/abstract/accessor/operator/generic/async targets, and receiver writes are rejected. Setter writes remain unsupported because staged atomic commit is not implemented; side-effecting or throwing getters are likewise outside the demonstrated safe boundary.

Review fixed deterministic collisions for runtime import prefixes, guard locals, and generated adapter classes. A native regression uses the former collision names, analyzes the overlay, compiles it, and runs it. Unqualified field access is explicitly not selected by the syntax-only prototype and receives a clear patch diagnostic. Cross-library private members, parts, mixins, extensions, and resolved multi-file inheritance remain unproved.

Consolidated validation passed: instrumentation format/analyze and 57 tests including analyzed native AOT; loader analyze and 6 tests; Flutter fixture analyze and 2 widget tests.

## References
- `tasks/08-typed-runtime-values.md`
- `docs/research/instance-methods.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 08 passed its review and validation gates.
- 2026-08-22: Read-only seam analysis selected a generated typed receiver capability; setter mutation remains rejection-first until atomic fallback semantics are proven.
- 2026-08-22: Instance format/runtime v3 completed. Coordinator review fixed generated-name collisions and clarified unqualified/side-effecting getter boundaries; all 65 scoped/downstream tests passed.
