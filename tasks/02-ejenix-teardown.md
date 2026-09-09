# Task 02 — Ejenix teardown

Status: [x] Completed

## Goal
Verify Ejenix's compiler, runtime, integration, patch distribution, security, persistence, backend, and limitations directly from public source and first-party documentation.

## Scope and Non-goals
Scope: the public `ejenix/opensource` repository and official Ejenix materials, including an evidence table and architecture diagram. Non-goals: copying implementation, accepting marketing claims, or selecting Ejenix's architecture.

## Owner
Ejenix research specialist; coordinator retains task-file ownership.

## Dependencies
Task 01 evidence structure.

## Assumptions
The public repository contains enough source to distinguish verified behavior from absent or closed components.

## Work Items
- [x] Inspect repository license, compiler/parser/IR/VM/opcodes, widget and host bindings.
- [x] Trace `EjenixPatchView`, channels, wire format, signing, caching, rollback, protocol, backend, and self-hosting.
- [x] Identify explicit integration, normal-screen transparency, unsupported constructs, and unverifiable claims.
- [x] Produce `docs/competitors/ejenix.md` with claim/evidence/source/verification table and diagram.
- [x] Review citations and evidence classifications.

## Validation
Completed source/citation review at Ejenix revision `3e40c661b0440a5694fdaebe4ba3eb3c4e9620b4`. Local validation passed 792 tests across eight Dart packages and 50 Flutter bridge tests (842 total). Device/store behavior was not tested and is labeled unverified.

## Next Action
Use the verified explicit-view constraints as Architecture A's baseline in Task 05.

## Blockers
None.

## Outcome
Verified that Ejenix is an explicit interpreted-subtree architecture with separate patch source and finite host bindings; normal existing screens/functions are not transparently patchable. Documented source-backed operational strengths and limitations.

## References
- https://github.com/ejenix/opensource

## History
- 2026-08-22: Task number reserved before delegation.
- 2026-08-22: Research package assigned; source inspection started.
- 2026-08-22: Completed after pinned-source review and 842 passing upstream tests.
