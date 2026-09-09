# Task 31 — Phase 1C runtime hardening

Status: [x] Completed

## Goal

Harden the validated Architecture B runtime against interrupted lifecycle
transitions, malformed or adversarial patch inputs, resource exhaustion,
runtime failures, trust/key lifecycle mistakes, and bounded toolchain drift,
without changing Patch Format v1 or capability contract v1.

## Scope and Non-goals

Scope: runtime state invariants and fault injection, crash/restart recovery,
boot-loop protection, resource-budget enforcement, runtime error isolation,
source-mapped diagnostics, malformed-patch and lifecycle fuzz regression,
bounded key lifecycle behavior, physical hardening evidence, performance
measurements, and adjacent Flutter/Dart compatibility evidence.

Non-goals: Architecture B redesign, Patch Format v1 changes, capability v1
expansion, Flutter/Dart forks, hosted or production delivery, cloud/SaaS,
product infrastructure, Phase 1D feature expansion, store-compliance claims,
or broad new language/runtime coverage.

## Owner

Coordinator-owned integration and maintainer-review package. Four shared-
workspace workers have disjoint implementation ownership:

- lifecycle/recovery: `experiments/patch_loading/lib/src/controller.dart`,
  lifecycle-focused new files/tests, and `docs/architecture/runtime-state-machine.md`;
- interpreter hardening: `experiments/instrumentation/lib/**` runtime seams,
  focused instrumentation tests, and runtime diagnostic/source-map code;
- fuzz/corpus: `packages/patch_format/**` parser/verifier regression fixtures,
  focused fuzz harnesses, and malformed input tests;
- trust/measurement: key lifecycle files/tests, key lifecycle documentation,
  Phase 1C benchmark/report files, and compatibility report updates.

The coordinator owns this task record, ADR, threat-model integration, physical
device runs, final review, and cross-package validation. Workers must not
rewrite historical task files or modify files outside their assigned scope.

## Dependencies

- completed Phase 1B baseline in Task 28 and `docs/PHASE_1B_REVIEW.md`;
- Architecture B ADR 0002;
- normative Patch Format v1 and capability contract v1;
- durable app-support storage, signed rollback, anti-replay, and cleanup
  boundaries already validated in Phase 1B;
- physical Android/iOS evidence and the current Flutter 3.47.x/Dart 3.13.x
  environment.

## Assumptions

- existing Phase 1B behavior is the compatibility baseline;
- the local worktree is shared by workers and may contain unrelated user
  changes; no worker may reset or revert them;
- recovery may remain conservative and fall back to base/last-known-good;
- transport is untrusted and no local development-server feature becomes a
  production protocol;
- a genuine Patch Format v1 limitation requires an explicit maintainer stop,
  not a silent protocol mutation.

## Work Items

- [x] Record the clean Phase 1B baseline and Phase 1C ADR.
- [x] Formalize lifecycle states, invariants, deterministic durable-boundary
  fault injection, recovery, and one-attempt boot-loop protection.
- [x] Harden interpreter budgets, runtime error isolation, and logical
  source-mapped diagnostics.
- [x] Add malformed corpora, bounded parser/verifier/interpreter/lifecycle
  fuzz regressions, and capability adversarial coverage.
- [x] Add bounded key rotation/revocation/recovery behavior and complete the
  anti-replay cross-feature review; Task 32 integrated the controller-owned
  `state-v4` trust/high-water journal. The standalone key-lifecycle model
  remains a test/policy seam, not the runtime authority.
- [x] Record physical dispatch/startup/memory evidence and adjacent SDK
  compatibility status; fresh iOS lifecycle evidence passes and the Android
  physical runtime-error and Task 35 measurement gates are closed with the
  limitations recorded in the final review.
- [x] Run consolidated regression validation and review the task-owned changes.
- [x] Create `docs/PHASE_1C_REVIEW.md` and stop at the maintainer gate before
  Phase 1D.

## Validation

Validation executed on 2026-08-22 includes `dart format --output=none
--set-exit-if-changed cli packages experiments benchmarks test`, fatal-info
analysis for root and all package/experiment boundaries, root/CLI/package
tests, the 200-test instrumentation suite, the 55-test patch-loading suite
with one expected environment-gated skip, malformed Patch Format v1 corpus,
resource-budget/source-map/key-lifecycle/lifecycle tests, adjacent
3.47.1/3.13.1 instrumentation and fixture analysis, Markdown link and
trailing-whitespace checks, shell syntax, and Python syntax. The fresh Task 36
iOS E1 release/install/activation/restart/rollback path passed on the connected
physical iPhone. The Android retry built and installed the current 2.3.1
release but stopped when its live mDNS service disappeared before launch; prior
Android Phase 1B physical evidence remains preserved and is not relabeled.

## Next Action

Maintainer review must decide whether to continue Phase 1C for the remaining
Android device hardening and Task 35 performance evidence. Phase 1D and all
product/cloud work remain out of scope.

## Blockers

The Android retry target was reachable through a live mDNS identity long enough
to build and install, but the service disappeared before launch; the physical
Android lifecycle gate and Task 35 measurements remain blocked. The fresh iOS
E1 USB runtime sequence passed; current CLI/Patch Format v1 LAN delivery
remains a separate unvalidated transport path and is not being claimed as a
Phase 1C gate. Task 32's controller-owned `state-v4` trust/high-water
journal is integrated and remains the durable authority. The Android gates
prevent a full Phase 1C completion claim.

## Outcome

Phase 1C maintainer review prepared with recommendation `CONTINUE PHASE 1C`.
The runtime hardening packages, controller trust integration, and consolidated
host validation are complete; Android physical/performance closure remains
pending. Phase 1D has not started.

## References

- `docs/PHASE_1B_REVIEW.md`
- `tasks/28-phase-1b-toolchain-foundation.md`
- `docs/adr/0002-adopt-source-instrumentation-for-phase-1.md`
- `docs/spec/patch-format-v1.md`
- `docs/spec/capability-v1.md`
- `docs/security/threat-model.md`
- `docs/PHASE_1C_REVIEW.md`

## History

- 2026-08-22: Reserved Task 31 because Task 29 is already used by two
  completed Phase 1B boundary records and repository numbering is monotonic.
  Recorded the Phase 1B baseline and began Phase 1C under maintainer-approved
  `PROCEED TO PHASE 1C WITH CONDITIONS`.
- 2026-08-22: Integrated lifecycle, interpreter, malformed-corpus, trust,
  compatibility, performance, and security evidence. Preserved the prior
  physical-device records, recorded the current Android connectivity blocker,
  and stopped at the Phase 1C maintainer gate with `CONTINUE PHASE 1C`.
- 2026-08-22: Fresh Task 36 physical iOS USB evidence passed the complete
  bounded E1 lifecycle: one install, healthy patch activation, restart
  persistence, invalid-signature retention, signed rollback, and rollback
  persistence. The Android retry built and installed the current 2.3.1
  release, then stopped when live mDNS disappeared before launch; no Android
  lifecycle or measurement claim was added.
- 2026-08-22: Reconciled current-state wording with completed Tasks 32 and 33.
  The controller-owned `state-v4` trust/high-water journal is integrated
  and authoritative; the standalone key-lifecycle model remains a test/policy
  seam. Kept `CONTINUE PHASE 1C` and left only the Android physical lifecycle
  and Task 35 measurement gates open.

## Behavioral application follow-up — 2026-08-22

Task 37 identified and fixed a host-reproducible mixed-bootstrap hazard: the
generated integration and archival/manual E1 controllers shared static/global
E0 state but could independently reset it. The fix adds a process-local
controller lease, generated-start coalescing, and fixture-side suppression of
the archival manual initialization when the generated integration is active.
It leaves Architecture B, Patch Format v1, capability v1, release identity,
and the controller-owned state-v4 trust/high-water journal unchanged.

The focused regression, affected package tests, and serial Flutter overlay
regressions passed, and a fresh automatic Android release/patch host pipeline
passed. A full instrumentation run still encountered the known macOS
native-assets/code-signing race in two overlay cases; this does not
replace the open physical Android behavioral gate: the device was not
reachable at the checkpoint, so no post-fix physical visible-result or
restart/rollback claim is added. Task 35 remains blocked until that gate is
closed.

The post-fix automatic release was rebuilt after generated-marker and
bootstrap-cleanup hardening as release
`sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359`;
its signed 2,069-byte Patch Format v1 artifact verified against that release
on the host. This is not a physical Android result; the device/lifecycle and
Task 35 measurement gates remain open.

## Final evidence closure — 2026-08-23

The coordinator completed the two remaining device-gated records without
changing Architecture B, Patch Format v1, capability v1, or the controller-
owned state-v4 trust/high-water journal:

- exact-release physical Android valid-runtime-error isolation passed with
  `E8101`, slot disable, AOT fallback, process liveness, and redacted logical
  diagnostics;
- Task 35 completed the prepared physical Android dispatch, launch, memory,
  and comparable APK protocol on Redmi Note 10 Lite / Android 16 / arm64;
- the current fixture's `path_provider_android 2.3.1` passed the bounded
  current-device lifecycle and did not reproduce the historical JNI/bootstrap
  failure; universal compatibility is not claimed;
- the accepted physical iOS E1 USB lifecycle remains valid, while fresh
  automatic CLI/Patch Format v1 LAN iOS delivery remains explicitly unclaimed.

Deterministic host fault-injection, parser/verifier/interpreter/lifecycle
corpus, key/trust, anti-replay, source-map, and adjacent SDK evidence remain
bounded as documented. Physical power-loss and long-duration fuzz campaigns
remain limitations, not silently promoted claims.

The maintainer-review recommendation is recorded in
`docs/PHASE_1C_REVIEW.md`. No Phase 1D or product work was started.
