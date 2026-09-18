# Task 14 — Versioned host capability registry

Status: [x] Completed

## Goal
Formalize a closed, typed, versioned boundary for host services already compiled into the application.

## Scope and Non-goals
Scope: stable IDs, versions, argument/return schemas, activation resolution, resource/cancellation rules, and narrow HTTP/storage/navigation/logging/clock fixtures. Non-goals: reflection, raw platform channels, FFI, arbitrary plugin invocation, or cloud services.

## Owner
Runtime/security specialist; coordinator integrates.

## Dependencies
Tasks 08 and 13; Task 12 consumes async capability behavior.

## Assumptions
Capabilities can provide useful interoperability without exposing host object internals.

## Work Items
- [x] Specify capability descriptor, invocation, and lifecycle contracts.
- [x] Implement registry and compatibility resolution.
- [x] Add typed sync/async fixture capabilities and explicit permission/resource gates.
- [x] Reject unknown/incompatible/malformed invocations atomically.
- [x] Document object/plugin boundary and validate.

## Validation
Planned: schema/version mismatches, missing capability activation, argument/result validation, timeouts/cancellation, output limits, duplicate IDs, attempted reflection/raw channel access, and integration tests. Exit: patch authority is exactly the declared compiled registry.

## Next Action
Begin Task 15 signing and durable rollback work using frozen authority and
canonical v8 bytes as compatibility inputs.

## Blockers
None; Tasks 08, 12, and 13 are complete.

## Outcome
Implemented patch/runtime v8 and release-manifest v6 with a configure-once,
immutable, release-owned capability authority. Contracts bind stable ID,
version, execution kind, typed schemas, resources, timeout/output/effect policy,
detach-only cancellation, and canonical digest. Typed sync/async opcodes copy
and validate values, preserve fatal/runtime faults, redact ordinary host
failures, produce stable deadline/resource errors, and never rerun AOT after a
side effect begins. Fake HTTP, storage, navigation, logging, and clock adapters
execute bounded domain gates. Raw reflection/channels/FFI/plugins are rejected.
Real services, concurrency quotas, broader cancellation, and OS permissions
remain unproved. Validation passed 158 instrumentation, six loader, and two
focused Flutter tests with clean analysis.

## References
- `docs/architecture/options.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 13 passed adversarial review and downstream validation.
- 2026-08-22: Initial v8 registry passed 146 tests; review found mutable fallback, authority drift, shallow descriptors, missing sync/fixture evidence, and error leakage.
- 2026-08-22: Replaced it with frozen shipped authority, pinned continuations, typed sync/async calls, stable failures, deep immutability, and executed fake policy adapters.
- 2026-08-22: Final verifier, descriptor, hash, and receiver-schema findings were fixed; coordinator and downstream validation passed.
