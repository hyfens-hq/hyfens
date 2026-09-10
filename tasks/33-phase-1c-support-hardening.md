# Task 33 — Phase 1C supporting hardening audit

Status: [x] Completed

## Goal

Audit and, where evidence requires it, strengthen the supporting runtime
hardening surfaces identified by Task 31 without overlapping the controller
trust-journal package in Task 32. Preserve the existing host-hardening
baseline while adding only bounded, test-backed fixes.

## Scope and Non-goals

Scope and write ownership:

- `packages/patch_format/lib/**` and its focused tests/corpus for parser,
  verifier, canonical-boundary, and malformed-input safety;
- `experiments/instrumentation/lib/**` runtime seams and focused tests for
  resource budgets, interpreter error isolation, capability admission, and
  logical source-map diagnostics;
- `docs/diagnostics.md` only where new or corrected support-hardening
  behavior requires documentation;
- bounded test/fixture files directly under those package/experiment areas.

The worker must first audit the current implementation. If the existing
behavior already satisfies the supplied requirements, record that evidence and
avoid speculative rewrites.

Non-goals: `experiments/patch_loading/**`, controller/lifecycle/key-journal
integration, Patch Format v1 encoding or semantics, capability v1 expansion,
physical-device claims, Phase 1D, Flutter/Dart forks, cloud/SaaS, production
transport, and unrelated formatting/refactors.

## Owner

`McClintock` (`01a0299c-c761-7923-b01c-f4db556c3bdf`), a coordinator-assigned
`gpt-5.6-luna` max/fast worker, owns the supporting runtime hardening package.
The worker must not modify Task 31, Task 32, historical reviews, or files
outside the explicit write set without coordinator approval.

## Dependencies

- `tasks/31-phase-1c-runtime-hardening.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_COMPLETION_INSTRUCTION.md`;
- `/Volumes/970EvoPlus/Downloads/31-phase-1c-runtime-hardening.md`;
- current Patch Format v1 and capability v1 tests;
- existing instrumentation resource-budget, diagnostics, and malformed-input
  regressions.

## Assumptions

- the worktree is shared with another worker; accommodate concurrent changes
  and never reset/revert unrelated edits;
- Patch Format v1 and capability v1 are frozen normative contracts;
- malformed or adversarial input must fail closed before active state changes;
- all limits remain release-owned and cannot be raised by a patch;
- a systemic verifier/interpreter safety issue is a maintainer-stop trigger.

## Work Items

- [x] Read both supplied Phase 1C documents and audit the current patch-format
  parser/verifier and instrumentation runtime against their stated support-
  hardening requirements.
- [x] Add or refine focused malformed corpus, bounds, budget, capability,
  source-map, and runtime-error-isolation regressions only where a concrete
  coverage gap exists.
- [x] Verify deterministic rejection/no active-state mutation for malformed
  parser/verifier inputs and deterministic behavior for resource exhaustion.
- [x] Verify diagnostics remain logical-path based and do not leak absolute
  paths, secrets, or unstable internal structures.
- [x] Run task-scoped package/experiment tests and static checks; report any
  unresolved systemic safety issue immediately to the coordinator.

## Validation

Required targeted validation completed:

- `dart format --output=none --set-exit-if-changed packages/patch_format/lib/patch_format.dart packages/patch_format/test/malformed_fuzz_test.dart experiments/instrumentation/lib/e0_runtime.dart experiments/instrumentation/lib/src/offset_map.dart experiments/instrumentation/lib/src/runtime_diagnostics.dart experiments/instrumentation/test/runtime_hardening_allocation_test.dart experiments/instrumentation/test/fuzz_corpus_test.dart experiments/instrumentation/test/async_v6_test.dart` — passed; no changes required.
- `dart analyze --fatal-infos` in `packages/patch_format` — passed, no issues.
- `dart analyze --fatal-infos` in `experiments/instrumentation` — passed, no issues.
- `dart test` in `packages/patch_format` — passed, 12 tests.
- `dart test test/runtime_hardening_v1_test.dart test/runtime_hardening_allocation_test.dart test/capability_registry_v8_test.dart test/fuzz_corpus_test.dart test/async_v6_test.dart` in `experiments/instrumentation` — passed, 71 tests.
- A full `dart test` in `experiments/instrumentation` reached 201 passing tests and 3 unrelated pre-existing Flutter/conformance failures outside this task: missing generated `native_assets.json`, and existing compile mismatches in `experiments/patch_loading/lib/src/controller.dart` and `key_lifecycle.dart`. Those files were not modified.

## Next Action

Hand off the changed-file list and validation results to the coordinator for
review; no further Task 33 implementation is pending.

## Blockers

None for Task 33. No Patch Format v1 mutation, capability-authority weakening,
budget bypass, or unresolved parser/verifier/interpreter crash or hang was
found in the owned audit or targeted regressions. The unrelated full-suite
failures are recorded under Validation and remain outside this task's write
ownership.

## Outcome

Completed evidence-backed support hardening without changing Patch Format v1
encoding/semantics or capability v1. Patch input and in-memory byte payloads
now reject non-octets deterministically; the E0 container/verifier rejects
out-of-range 32-bit words before operand analysis; offset/source maps enforce
UTF-8 byte budgets and admit only logical `package:`/`e0-overlay:` schemes;
path-like labels and diagnostic path/URL/credential values are rejected or
redacted; and async continuation resource faults carry the stable budget code.
Focused regressions cover malformed active-state preservation, verifier safety,
resource exhaustion, capability admission/error isolation, and logical source
diagnostics.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_COMPLETION_INSTRUCTION.md`
- `/Volumes/970EvoPlus/Downloads/31-phase-1c-runtime-hardening.md`
- `tasks/31-phase-1c-runtime-hardening.md`
- `docs/spec/patch-format-v1.md`
- `docs/spec/capability-v1.md`
- `docs/diagnostics.md`

## History

- 2026-08-22: Reserved Task 33 as the disjoint supporting-hardening package
  after reading both supplied Phase 1C documents. Controller trust/lifecycle
  files remain exclusively owned by Task 32 and coordinator evidence work.
- 2026-08-22: Assigned to McClintock (`01a0299c-c761-7923-b01c-f4db556c3bdf`)
  with `gpt-5.6-luna`, maximum reasoning, and priority/fast service.
- 2026-08-22: Completed the supporting audit and bounded fixes. Preserved the
  existing exact capability admission and atomic install behavior after audit;
  added only concrete parser/verifier, budget classification, source-map, and
  diagnostic-sanitization changes plus deterministic regressions. Targeted
  format, fatal-info analysis, Patch Format tests, and 71 instrumentation
  hardening/capability/fuzz/async tests passed. Full instrumentation test
  failures are unrelated to the owned support package and are recorded above.
