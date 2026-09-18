# Task 15 — Asymmetric signing and rollback hardening

Status: [x] Completed

## Goal
Replace integrity-only activation with deterministic asymmetric signing and a last-known-good lifecycle.

## Scope and Non-goals
Scope: local offline signing CLI, Ed25519/library evaluation, embedded/trusted public key, signature/tamper/wrong-key rejection, sequence defense, sequential patches, restart, last-known-good, rollback N→N-1→base, and future rotation design. Non-goals: KMS, hosted signing, crash analytics, or enterprise key management.

## Owner
Security/runtime specialist; coordinator integrates.

## Dependencies
Tasks 13–14.

## Assumptions
A maintained permissively licensed Dart Ed25519 implementation can satisfy physical Android/iOS verification.

## Work Items
- [x] Evaluate algorithm/library/license and specify signed bytes/key trust.
- [x] Implement deterministic local signing and verification.
- [x] Harden staged/current/last-known-good/previous/base transitions.
- [x] Test all required signature, corruption, sequence, restart, and rollback cases.
- [x] Document key rotation requirements and validate.

## Validation
Planned: known-answer tests, deterministic signed payload, valid/tampered/wrong-key/invalid-bytecode/incompatible/stale/partial patches, multiple sequential patches, restart, runtime exception, rollback targets, atomic file failures, and device-ready CLI flow. Exit: unsigned or invalid content never activates and recovery retains a safe executable path.

## Next Action
Begin Task 16's ordinary `Widget.build` interception experiment. Retain physical
signed-patch verification for the consolidated Android/iOS device packages.

## Blockers
None; Tasks 13–14 are complete.

## Outcome
Implemented a strict canonical E1 Ed25519 envelope, local offline key/sign CLI,
release-owned trusted public keys, verify-before-decode activation, serialized
durable high-water state, explicit pending/health/LKG transitions, signed
higher-sequence rollback, fail-closed dual-copy recovery, and fixture-ready
signed delivery. This is bounded prototype evidence, not production approval.

## References
- `docs/research/patch-format-options.md`
- `docs/research/signing-rollback.md`
- `experiments/patch_loading/README.md`
- `THIRD_PARTY_NOTICES.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 14 passed adversarial review and downstream validation.
- 2026-08-22: Selected Apache-2.0 `cryptography` 2.9.0 with explicit pure-Dart `DartEd25519`; added canonical signed bytes, CLI, verification, and RFC 8032 known-answer evidence.
- 2026-08-22: Adversarial review found lifecycle serialization, artifact repair, pending/LKG, state-integrity, input-alias, redirect, CLI-key-safety, and explicit-implementation gaps; all blocker/high findings were fixed and re-reviewed.
- 2026-08-22: Final loader format and analysis passed; 25 loader tests passed. The existing 158 instrumentation tests and two focused Flutter widget tests passed downstream. The Flutter malformed-input test uses `WidgetTester.runAsync` for real file/crypto futures.
- 2026-08-22: Completed without physical-device claims; those remain Tasks 23–25.
