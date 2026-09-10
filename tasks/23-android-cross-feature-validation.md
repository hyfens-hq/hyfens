# Task 23 — Physical Android cross-feature validation

Status: [x] Completed

## Goal
Run the required one-install release-mode Android sequence across successful business, async, UI, ecosystem/navigation, invalid, rollback, and restart scenarios.

## Scope and Non-goals
Scope: reproducible local delivery script, patches 1–4, invalid rejection, rollback, persistence, install timestamps, device logs, measurements, and exact evidence. Non-goals: production distribution or cloud delivery.

## Owner
Android device specialist; coordinator reviews evidence.

## Dependencies
Tasks 15–22; only features that passed their gates are included and omissions are explicit.

## Assumptions
Successful isolated features will compose in one installed stock-Flutter release.

## Work Items
- [x] Define and execute the prepared narrow E1 sequence/assertions.
- [x] Build one stock release and install once on the physical Wi-Fi device.
- [x] Activate the business-logic patch without reinstalling.
- [x] Exercise invalid-patch retention and rollback; package timestamps remained unchanged.
- [x] Compose async, UI, Riverpod, and restart/persistence scenarios in the same installed release.
- [x] Record commands/artifacts/results and validate the expanded evidence.

## Validation
Executed with explicit device serial, one `adb install`, package timestamp comparison, signed-payload verification, receipt assertions for each transition, restart, rollback target, and cleanup of task-owned processes. Performance remains covered by Task 22's host benchmark rather than being inferred from this device run.

## Next Action
No further Phase 0B Android work is required. The current-source narrow and
broad physical runs passed on the connected Wi-Fi device without reinstall.

## Blockers
None.

## Outcome
The current-source narrow regression passed on Android device serial
`192.168.50.135:39083` over Wi-Fi. The broad run
`E1_ANDROID_EVIDENCE_RUN_ID=android-cross-20260822-6
scripts/e1_android_cross_feature.sh 192.168.50.135:39083` installed a
51,361,632-byte Release APK once and recorded base 540, business 450, async
481, a rendered UI patch, Riverpod 450, invalid-signature retention, rollback
to base, two process restarts, and unchanged package timestamps. Signed
envelopes were 1,349 bytes (business), 1,769 bytes (async), and 3,733 bytes
(UI). Evidence is retained under
`experiments/patch_loading/.dart_tool/android_e1_runs/android-cross-20260822-6/evidence/`.

## References
- `scripts/e1_android_physical.sh`
- `scripts/e1_android_cross_feature.sh`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Activated after Task 22. Repeated device audits found no Android device; the required expanded release sequence remains unexecuted and no emulator evidence was substituted.
- 2026-08-22: Physical Android became available over Wi-Fi. `scripts/e1_android_physical.sh 192.168.50.135:39083` passed one-install build, signed activation, invalid retention, rollback, UI/state assertions, and package timestamp comparison. This is the prepared narrow E1 path; broader cross-feature stages remain pending.
- 2026-08-22: Current-source narrow regression passed again. The broad one-install run `android-cross-20260822-6` passed business, capability-mediated async, widget build, Riverpod, invalid signature, rollback, restart, persistence, and process/timestamp assertions without reinstall.
