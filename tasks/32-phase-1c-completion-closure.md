# Task 32 — Phase 1C completion closure

Status: [x] Completed

## Goal

Close the narrow completion gaps identified by
`/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_COMPLETION_INSTRUCTION.md`:
integrate key rotation/revocation into the controller's single durable
trust/high-water authority and prove the anti-replay invariants without
changing Architecture B, Patch Format v1, or capability contract v1.

## Scope and Non-goals

Scope: controller-integrated trust state, atomic trust/high-water transitions,
trust-journal recovery, rotation and revocation behavior, anti-replay
cross-feature regressions, and the directly corresponding runtime/security
documentation.

The worker may inspect local device/tool availability and report evidence or
blockers, but the coordinator owns final physical-device claims, performance
measurements, consolidated validation, and `docs/PHASE_1C_REVIEW.md`.

Non-goals: Patch Format v1 changes, capability v1 expansion, Flutter/Dart
forks, Phase 1D feature work, cloud/SaaS/product infrastructure, production
transport, store-compliance claims, or broad unrelated refactoring.

## Owner

`Beauvoir` (`01a0299c-c884-7e11-8c50-75acff255f1d`), a coordinator-assigned
`gpt-5.6-luna` max/fast worker, owns the controller trust and
completion-closure package. The worker owns only the files and responsibilities
listed below and must not revert or rewrite other workers' changes.

## Dependencies

- `tasks/31-phase-1c-runtime-hardening.md` and its existing lifecycle model;
- `docs/PHASE_1C_REVIEW.md` and the Phase 1B evidence it preserves;
- `experiments/patch_loading/lib/src/controller.dart` and existing lifecycle
  storage/tests;
- the standalone key policy model already present in the repository;
- normative `docs/spec/patch-format-v1.md` and `docs/spec/capability-v1.md`.

## Assumptions

- the current worktree is shared; unrelated changes belong to the user;
- one authoritative durable recovery view is required—do not create a second
  trust store that can disagree with lifecycle state;
- recovery may conservatively fall back to base/last-known-good;
- local filesystem and transport inputs are untrusted;
- a genuine Patch Format v1 limitation is a maintainer-stop trigger, not a
  license to mutate the protocol.

## Work Items

- [x] Read both supplied Phase 1C documents and inspect the existing controller,
  lifecycle journal, standalone key model, and tests before editing.
- [x] Integrate trusted/retired/revoked keys, trust generation, release
  identity, patch high-water, rollback state, and recovery metadata into one
  authoritative controller-owned durable view.
- [x] Make rotation/revocation transitions atomic with high-water state and
  add deterministic interruption/corruption tests for each durable boundary.
- [x] Add focused invariants and regressions for unknown/retired/revoked keys,
  wrong releases, cleanup, rollback, dual-copy recovery, and stale replay.
- [x] Complete an anti-replay cross-feature matrix in the implementation tests
  and update only the directly affected runtime/security documentation.
- [x] Run the task-scoped tests and record commands, outcomes, changed files,
  and any maintainer-stop trigger in this task file.

## Validation

Completed targeted validation in `experiments/patch_loading`:

- `dart format lib/src/controller.dart lib/src/key_lifecycle.dart lib/patch_loading_e1.dart test/controller_test.dart test/lifecycle_recovery_test.dart test/key_lifecycle_test.dart test/integrated_trust_journal_test.dart` — formatted 7 files; final run reported `0 changed`.
- Final review pass: `dart format lib/src/controller.dart` — `0 changed` after the v4 nested canonical round-trip check.
- `dart analyze --fatal-infos` — `No issues found!`.
- `dart test -j 1 test/controller_test.dart test/lifecycle_recovery_test.dart test/key_lifecycle_test.dart test/integrated_trust_journal_test.dart` — 47 passed.
- `dart test -j 1` — 59 passed, 1 skipped. The only skip is `test/cli_artifact_test.dart`, which requires `HYFENS_CLI_PATCH`, `HYFENS_CLI_RELEASE`, and `HYFENS_CLI_PUBLIC_KEY`; no artifact was supplied for this host run.

No physical Android/iOS evidence is claimed. No files under
`packages/patch_format/**` or `experiments/instrumentation/**` were changed.

## Next Action

Coordinator review of the bounded controller/trust diff. Physical/device and
final Phase 1C review claims remain coordinator-owned.

## Blockers

None. No Patch Format v1 limitation, weakened anti-replay guarantee, or
non-atomic trust recovery was observed. Physical/device evidence remains
outside this worker's scope.

## Outcome

Implemented one controller-owned state-version-4 journal (retaining the
historical `state-v3-a.json`/`state-v3-b.json` paths) containing release
identity, trust state, trust generation, patch high-water, replay identities,
health/candidate/LKG selection, and rollback/recovery metadata. Signed
add/retire/revoke/recover commands and signed rollback controls now use the
same persisted lifecycle state; revoking a selected artifact removes it from
executable selection without lowering high-water. Legacy state upgrades remain
fail-closed, and dual-copy selection rejects trust/replay predecessor
regressions.

Added controller-integrated anti-replay and fault-injection coverage for key
rotation, retirement, revocation, recovery replacement, cleanup, rollback,
wrong release, both-copy trust corruption, stale replay, and state-copy faults.
Updated the directly affected runtime/security specifications and lifecycle
comments. Patch Format v1, capability v1, Architecture B, and instrumentation
runtime files were left unchanged.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_COMPLETION_INSTRUCTION.md`
- `/Volumes/970EvoPlus/Downloads/31-phase-1c-runtime-hardening.md`
- `tasks/31-phase-1c-runtime-hardening.md`
- `docs/PHASE_1C_REVIEW.md`
- `docs/architecture/runtime-state-machine.md`
- `docs/security/key-lifecycle.md`
- `docs/security/threat-model.md`

## History

- 2026-08-22: Reserved Task 32 as the completion-instruction package after
  reading both supplied Phase 1C documents. Kept Task 31 historical and
  unchanged; delegated ownership is limited to controller trust integration
  and its anti-replay evidence.
- 2026-08-22: Assigned to Beauvoir (`01a0299c-c884-7e11-8c50-75acff255f1d`)
  with `gpt-5.6-luna`, maximum reasoning, and priority/fast service.
- 2026-08-22: Completed controller-integrated trust/high-water journal,
  lifecycle transition fault coverage, cross-feature anti-replay regressions,
  and directly affected runtime/security documentation. Scoped analysis and
  package validation passed; no maintainer-stop trigger was found.
- 2026-08-22: Final self-review added v4 nested trust/ledger canonical
  round-trip validation; the analyzer and full patch-loading package suite
  remained green.
