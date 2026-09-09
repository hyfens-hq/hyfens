# Task 27 — Phase 1A language/runtime foundation

Status: [x] Completed

## Goal

Turn the validated Architecture B research seams into a stable, testable Phase
1A foundation. Prove representative closures, named and optional parameters,
expanded Future interoperability, capability contract v1, canonical Patch
Format v1, and release-owned stable manifests without starting the Phase 1B
toolchain or any cloud/product work.

## Scope and Non-goals

Scope: preserve Phase 0 evidence; record the Phase 1 Architecture B baseline;
establish real package seams; extend the bounded compiler/interpreter for
representative closure and parameter cases; define capability and manifest
contracts; implement and test Patch Format v1; document supported and
unsupported boundaries.

Non-goals: `tool init`, automatic project discovery, `tool release`,
`tool patch`, update servers, hosted services, product infrastructure, general
Dart compatibility, arbitrary Flutter reflection, native OTA binaries, or a
Flutter/Dart fork. Those remain later milestone work or explicit non-goals.

## Owner

Coordinator with runtime/compiler ownership.

## Dependencies

Phase 0B tasks 08–26 and their preserved evidence, especially the typed value,
async, identity, capability, signing/rollback, and physical-device results.

## Assumptions

- The current source-instrumentation plus bounded interpreted branch remains the
  Phase 1 baseline.
- Closure capture is value-based and bounded; raw host-object capture remains
  unavailable.
- Named/optional parameter metadata is part of exact function compatibility.
- Patch Format v1 is a public protocol and rejects unsafe or ambiguous input
  before runtime activation.

## Work Items

- [x] Preserve and reference Phase 0/0B reports, benchmarks, device evidence,
  and generated artifacts without rewriting their conclusions.
- [x] Create the Phase 1 Architecture B adoption ADR and implementation
  architecture/spec documents.
- [x] Establish package boundaries with real Phase 1A responsibilities.
- [x] Implement representative closure capture/invocation and collection
  higher-order operations with bounded verification.
- [x] Implement named/optional parameter metadata, defaults, binding, and
  compatibility validation.
- [x] Expand the bounded Future model beyond direct capability-only syntax, or
  provide stable diagnostics for the deliberately unsupported remainder.
- [x] Implement capability contract v1 and policy checks at the stable package
  seam, retaining the closed host authority.
- [x] Implement Patch Format v1 deterministic serialization, digest/signature
  boundary, strict parsing, and resource limits.
- [x] Implement stable release/baseline manifest records and deterministic
  identity material for the new protocol.
- [x] Review the combined diff, fix blocking findings, run consolidated scoped
  validation, and stop at the Phase 1A review gate.

## Validation

Completed validation:

- `dart format` on the changed Dart packages, experiment sources, and tests:
  passed.
- `dart analyze --fatal-infos` for the root and Phase 1A package scope: passed.
- Root `dart test -j 1`: 1 test passed.
- `packages/patch_format`: 3 tests passed; `packages/runtime`: 3 tests passed;
  `packages/compiler`: 1 test passed; `packages/instrumenter`: 1 test passed.
- The full `experiments/instrumentation` suite: 180 tests passed.
- Deterministic encode/decode, malformed-input, compatibility, closure,
  parameter, capability-policy, Future, and resource-budget regressions:
  passed through the focused and downstream suites.

Physical-device validation, full Flutter matrices, automatic project discovery,
and Phase 1B toolchain validation were intentionally not run because they are
outside this Phase 1A gate.

## Next Action

Review the combined Phase 1A diff, run the consolidated scoped validation, and
stop for maintainer review before any Phase 1B toolchain work.

## Blockers

None currently.

## Outcome

Phase 1A implementation, self-review, and scoped validation are complete.
Work is stopped at the required maintainer-review gate; no Phase 1B or
cloud/product work was started.

## References

- `docs/PHASE_0B_REVIEW.md`
- `docs/architecture/phase-0b-findings.md`
- `docs/adr/0002-continue-source-instrumentation-with-phase-1-gates.md`
- `experiments/instrumentation/RESULTS.md`
- `docs/spec/patch-format-v1.md`
- `docs/spec/capability-v1.md`

## History

- 2026-08-22: Reserved task number 27 after task 26; started Phase 1A under
  the explicit maintainer instruction to preserve Architecture B and stop at
  the Phase 1A review gate.
- 2026-08-22: Added canonical patch-format/runtime packages, compiler and
  instrumenter facades, and the Phase 1A architecture/specification documents.
- 2026-08-22: Added bounded synchronous closures, named/optional parameter
  binding, and `Future.value` continuation support with focused tests.
- 2026-08-22: Completed combined-diff review and consolidated validation;
  all Phase 1A checks passed, and work stopped at the Phase 1A review gate.
