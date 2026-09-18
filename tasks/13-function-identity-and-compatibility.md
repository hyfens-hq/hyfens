# Task 13 — Stable function identity and compatibility manifest

Status: [x] Completed

## Goal
Define robust declaration identity and an explicit activation compatibility manifest.

## Scope and Non-goals
Scope: library URI, class/member kind/name/signature, build metadata, collision/signature checks, refactor behavior, runtime/app/release/function/capability/hash/sequence fields, stale/incompatible rejection, and `docs/research/function-identity.md`. Non-goals: promising identity across arbitrary semantic refactors.

## Owner
Compiler/protocol specialist; coordinator integrates.

## Dependencies
Tasks 08–12 define actual signatures and declaration shapes.

## Assumptions
Semantic declaration identity plus explicit compatibility metadata is safer than offsets or line numbers.

## Work Items
- [x] Specify identity material and documented refactor behavior.
- [x] Implement deterministic identity/collision/signature validation.
- [x] Introduce strict versioned compatibility manifests.
- [x] Test all required refactor and rejection cases.
- [x] Write research evidence and validate deterministic output.

## Validation
Planned: whitespace, method/file movement, class/function rename, signature change, private library, collision injection, wrong release/runtime, missing capability, stale sequence, corrupt hash, unknown fields, and equivalent-build determinism. Exit: every mismatch fails closed with a stable diagnostic.

## Next Action
Begin Task 14's general host capability registry. Task 15 must persist sequence
high-water state and replace prototype rollback with a higher-sequence signed
rollback artifact.

## Blockers
None; Tasks 08–12 are complete.

## Outcome
Implemented structured semantic declaration IDs separate from exact signature
compatibility, package-config-resolved canonical URIs for real overlay files,
strict release-manifest v5, and patch/runtime v7. The compatibility envelope
binds app release, caller-provided deterministic build fingerprint, function
identity/signature/receiver, capabilities, canonical payload hash, and sequence.
Tests prove whitespace/order/checkout-root stability; rename/library-move ID
changes; signature-change compatibility rejection; collision/forgery/path
rejection; exact tables; corrupt/noncanonical input rejection; stale,
idempotent, and equivocation behavior; and atomic activation. Parts and broader
declaration kinds are unsupported. Hashing is not signing, and the high-water
mark is process-local. Final validation passed 139 instrumentation tests, six
loader tests, and two focused Flutter widget tests with clean analysis.

## References
- `docs/assumptions.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 12 passed adversarial review and consolidated validation.
- 2026-08-22: Initial v7 implementation passed 130 tests; review rejected signature-coupled IDs, opaque identity material, noncanonical hashing, incomplete sequence semantics, and caller-trusted paths.
- 2026-08-22: Implemented semantic ID/signature separation, structured cross-validation, package-config resolution, canonical bytes, exact compatibility tables, build binding, and idempotent/equivocation behavior.
- 2026-08-22: Final review fixed configured outside-package masquerading and argument-loader state loss. Coordinator validation passed 139 instrumentation, six loader, and two Flutter tests.
