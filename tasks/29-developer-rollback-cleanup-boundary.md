# Task 29 — Developer rollback and cleanup boundary

Status: [x] Completed

## Goal

Expose a conservative Phase 1B developer-facing rollback to a trusted,
store-installed AOT release and narrowly scoped cleanup without weakening E1
high-water, replay, immutable-release, key, source, or evidence protections.

## Scope and Non-goals

Scope: `cli/lib/src/cli_runner.dart`, `cli/lib/src/toolchain.dart`,
`cli/lib/src/diagnostics.dart`, focused CLI tests, and
`docs/architecture/rollback.md`.

Non-goals: Patch Format v1 changes, capability v1 changes, runtime package
changes, downloaded rollback artifacts, source mutation, immutable release
deletion, signing-key deletion, broad cleanup, or Phase 1C work.

## Owner

Phase 1B developer-facing rollback and cleanup boundary owner.

## Dependencies

Task 15 E1 signing/rollback semantics and Task 28 Phase 1B toolchain store.

## Assumptions

- A base rollback is valid only when the selected release has a non-metadata,
  locally retained store artifact.
- The CLI journal is developer-side intent/state; the E1 runtime remains the
  authority for app activation and preserves its own high-water state.
- A prior-patch manual rollback is not safe without a newly authenticated
  higher-sequence selection, so this boundary rejects it.
- Cleanup may remove only exact, explicitly confirmed mutable patch artifacts or
  ephemeral build staging; it never removes keys, releases, source, journals,
  sequence state, or evidence by broad scope.

## Work Items

- [x] Add checksummed rollback state with high-water monotonicity.
- [x] Add explicit rollback and cleanup toolchain operations.
- [x] Add CLI commands and stable diagnostics.
- [x] Add persistence, anti-replay, and cleanup safety tests.
- [x] Document the boundary and validate the scoped CLI.

## Validation

Passed: changed-scope `dart format --set-exit-if-changed` (0 changes),
`dart analyze --fatal-infos` in `cli`, the full CLI `dart test -j 1` suite (30
tests), and the focused rollback/cleanup suite (9 tests). The tests cover
trusted-base rejection, rollback persistence, high-water/sequence
monotonicity, prior-patch refusal, exact cleanup confirmation, protected paths,
symlink refusal, and preservation of release/source/key/evidence files.

## Next Action

Hand the bounded Phase 1B boundary to maintainer review; do not expand it into
runtime hardening or Phase 1C.

## Blockers

None.

## Outcome

Implemented the E1-compatible developer rollback/cleanup boundary. Base
rollback records the trusted store-installed AOT target in a checksummed
two-copy journal while retaining high-water and patch evidence. Manual
prior-patch selection is rejected unless a future already-safe runtime path is
available. Cleanup requires exact scope/target confirmation and cannot remove
keys, immutable releases, source, journals, sequence state, or protected
evidence.

## References

- `tasks/15-signing-and-rollback-hardening.md`
- `tasks/28-phase-1b-toolchain-foundation.md`
- `experiments/patch_loading/README.md`
- `experiments/patch_loading/SPEC.md`
- `docs/research/signing-rollback.md`

## History

- 2026-08-22: Reserved Task 29 after inspecting the existing Phase 1B store
  and E1 rollback contract.
- 2026-08-22: Implemented rollback/cleanup commands, monotonic journal and
  sequence guards, stable diagnostics, focused tests, and architecture docs.
- 2026-08-22: Scoped format, CLI analysis, full CLI tests (30), and focused
  rollback/cleanup tests (9) passed.
