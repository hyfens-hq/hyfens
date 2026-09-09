# Task 96 — Current-source Android physical evidence

Status: [x] Completed — correction evidence accepted by independent strict review

## Goal

Re-run the current checked-in Flutter fixture on the connected physical
Android device over the explicit ADB Wi-Fi serial and capture fresh
multi-function lifecycle evidence. The result must establish exactly what the
existing Android harness observes today, including business, async, widget,
Riverpod, invalid-signature, rollback, restart, and stale-candidate behavior,
without reopening AWS or hosted deployment work.

## Scope and Non-goals

Scope:

- verify the physical Android identity, connection state, SDK/tool versions,
  and selected direct ADB serial;
- run the existing `scripts/e1_android_cross_feature.sh` once with a fresh
  run ID and no emulator substitution;
- preserve the generated run evidence and record exact receipt stages,
  artifact identities, install count, package timestamps, and any failure;
- classify stale-byte behavior only from the captured receipt/harness path,
  distinguishing direct runtime rejection from delivery-boundary withholding;
  and
- add a redacted, durable evidence summary and strict review outcome to this
  task record.

Non-goals: source/runtime changes, protocol changes, new Android test code,
performance campaigns, power-loss simulation, emulator evidence, AWS/cloud or
online hosting, device-wide compatibility claims, production/store claims,
global Docker cleanup, or changes to completed historical task records.

## Owner

GPT-5.6 Luna Max fast-mode Android evidence worker owns the fresh run and the
task-owned evidence summary. The coordinator owns device serialization,
integration, final acceptance, and task closure. A separate GPT-5.6 Luna Max
fast-mode reviewer owns the strict fact-based review. No commit is authorized.

## Dependencies

- current checked-in `fixtures/flutter_conformance_app`;
- `scripts/e1_android_cross_feature.sh` and its existing local evidence
  server;
- Flutter/Dart and Android SDK already installed on the host; and
- physical Redmi Note 10 Lite / `curtana` reachable through the selected ADB
  Wi-Fi serial.

## Assumptions

- `192.168.50.135:41277` is selected explicitly because the current ADB
  inventory exposes it as a physical `device`; the duplicate mDNS alias is
  not used as an implicit target;
- generated `.dart_tool` evidence is disposable run output, while this task
  file is the durable summary;
- the existing script is the authority for its expected sequence and one
  install boundary; no manual success claim may replace a failed assertion;
- local loopback delivery is sufficient for this direct E1 evidence and does
  not require AWS, MinIO, or hosted infrastructure; and
- no Dart or Flutter test is run because this package changes no source/test
  file. Only the hardware harness and task-owned evidence are validated.

## Work Items

- [x] Inspect the current script, fixture, prior evidence boundary, and
  connected-device inventory.
- [x] Run one fresh current-source Android cross-feature sequence against the
  explicit Wi-Fi serial.
- [x] Verify the raw receipt stage order, exact device/build identities,
  artifact hashes, one-install constraint, restart/rollback/high-water
  observations, and package timestamp stability.
- [x] Write a redacted evidence summary without credentials or unsupported
  generalizations.
- [x] Run one correction sequence with a captured preflight transcript and
  raw harness shell exit status after the original review finding.
- [x] Verify the correction run's transcript, receipt order, package times,
  install result, and artifact hashes.
- [x] Complete independent strict review and fix any factual findings.
- [x] Run the final task-scoped evidence assertions and record the outcome.

## Validation

Planned validation is limited to the changed/evidence scope:

- `adb devices -l`, `adb -s 192.168.50.135:41277 get-state`, and bounded
  physical identity/property checks;
- `bash -n scripts/e1_android_cross_feature.sh`;
- one fresh invocation of the existing cross-feature script with a unique
  `E1_ANDROID_EVIDENCE_RUN_ID` and explicit device serial;
- JSON receipt/order, package-time, install, and artifact/hash assertions
  directly against that run; and
- review of task-owned evidence for secret/path leakage and claim boundaries.

No unrelated repository tests, full builds, AWS calls, or online deployment
checks are authorized by this task.

## Next Action

Task 96 is complete. The next bounded instruction is to finish Task 97's
current-source iPhone USB evidence, including strict review of its minimal
harness corrections. Do not generalize this Android fixture result to other
devices, production, AWS, or hosted deployment.

## Blockers

No harness execution blocker occurred in either run. The correction transcript
records an empty output for
`ro.kernel.qemu`; that output is preserved verbatim and is not normalized to
`0`. The inventory reported the selected target as `device`, and the existing
harness physical-device guard completed successfully. A future device
disconnect, build/signing failure, or harness assertion failure is an evidence
result/blocker to record, not a reason to infer a pass or change the protocol.

## Outcome

The original current-source physical Android cross-feature run passed with exit
status `0`, but review found that its run directory did not contain raw
preflight output or a raw harness shell exit record. The correction run passed
with both evidence gaps addressed, including `harnessExitStatus=0` in its
captured transcript. Laplace independently returned `ACCEPT` after verifying
the correction evidence. The original run remains preserved as a rejected
evidence record and was not relabeled.

### Observed evidence

- Device preflight: `192.168.50.135:41277`, model `Redmi Note 10 Lite`,
  product `aosp_miatoll`, device `curtana`, Android release `16`, API `36`,
  ABIs `arm64-v8a,armeabi-v7a,armeabi`. The duplicate mDNS serial was visible
  but was not used. The device was reported as `device` and the physical-device
  guard in the existing script passed.
- Toolchain: Flutter `3.47.0` stable (revision `4cf2416426`), Dart `3.13.0`,
  Android Debug Bridge `1.0.41` / platform tools `36.0.2-14143358`, and
  Java `17.0.13`.
- Android package identity observed after install: `dev.hyfens.conformance`,
  version `1.0.0`, version code `1`, min SDK `24`, target SDK `36`. Release APK
  size was `52,131,680` bytes and SHA-256 was
  `23c8582f3f72fa68bf1124bcd7ab5055182e542076bd536be4a71485cac4d174`.
- Run ID: `task96-android-cross-20260828T131927Z-95708`. Raw run root:
  `experiments/patch_loading/.dart_tool/android_e1_runs/task96-android-cross-20260828T131927Z-95708/`.
  Inspected raw evidence includes `evidence/build.log`,
  `evidence/install.txt`, `evidence/startup.txt`,
  `evidence/receipts.jsonl`, `evidence/package-times-before.txt`,
  `evidence/package-times-after.txt`, `evidence/package-times.diff`,
  `evidence/sizes.txt`, `evidence/overlay.log`, `evidence/server.log`, and
  the signed envelopes under `serve/`.
- The receipt file contains 13 successful rows in this exact order:
  `base`, `business-patch`, `async-patch`, `ui-patch`, `riverpod-patch`,
  `restart-required-1`, `riverpod-persisted`, `invalid-rejected`,
  `rolled-back`, `stale-rejected`, `restart-required-2`,
  `rollback-persisted`, `complete`. Every row has the run ID above and app ID
  `dev.hyfens.conformance`; three process IDs correspond to the two restart
  boundaries.
- The captured install evidence is one `adb install -r` invocation with
  `Success`; the script has one install boundary. Package timestamps were
  identical before and after: `firstInstallTime=2026-08-22 01:22:43` and
  `lastUpdateTime=2026-08-28 18:55:15`. `package-times.diff` is zero bytes.
- `business-patch` produced price `450`; `async-patch` produced async price
  `481`; `ui-patch` reported `uiPatched=true`; `riverpod-patch` and
  `riverpod-persisted` retained price `450`. The invalid candidate was
  rejected with phase `rejected` while the active patch remained selected.
- `rolled-back` and `rollback-persisted` reported base mode, price `540`, and
  high-water sequence `4`. `stale-rejected` reported
  `signed patch rejected: replayAfterRollback`, phase `rejected`, base mode,
  price `540`, and high-water sequence `4`. Based on those captured status
  fields, stale behavior is classified as direct runtime rejection; no
  delivery-boundary-withholding result is represented by this run.
- Signed envelope SHA-256 values: `business-1.e1.signed.json` and
  `patch.e1.signed.json` `070fe8a6c52d8b8e20669018dfe609b66ac8f8ef77a1f791008335db10e37b46`;
  `business-4.e1.signed.json`
  `cf2dea06b4b186dde279c9ad529347be44337ab951c0c10ac2ac90a877311af2`;
  `async-2.e1.signed.json`
  `9378b869a803a904a64cab91d889ebb73d6e47d34da37048adce6ebc0da14e5f`;
  `ui-3.e1.signed.json`
  `7a8412040332506aa412169d27d7b6c28cca9d7b213347e9ac03db7f7565eed9`;
  `invalid-signature.e1.signed.json`
  `75b784132e8bf609c693119e18c7027a212ba6e96718ae7ca0882827a7d1d06d`.

No source, runtime, script, or test file was changed. No Dart, Flutter, or
unrelated repository test was run; validation was limited to the physical
harness, its receipt assertions, package-time/install checks, and the bounded
identity/hash inspection. The test-only signing input was not copied into this
record.

### Correction run addendum

- Review finding addressed: the original run remains
  `task96-android-cross-20260828T131927Z-95708` and is not relabeled. The
  correction run is `task96-android-cross-20260828T134823Z-r2`.
- Correction run root:
  `experiments/patch_loading/.dart_tool/android_e1_runs/task96-android-cross-20260828T134823Z-r2/`.
  The durable transcript is
  `evidence/coordinator-preflight-and-exit.txt`; the other raw evidence files
  are under the same run's `evidence/` directory, and signed envelopes are
  under its `serve/` directory.
- The transcript records, before the harness, `adb devices -l`,
  `adb -s 192.168.50.135:41277 get-state`, model, Android release/API, ABI,
  and `ro.kernel.qemu` queries. The selected entry was
  `192.168.50.135:41277 device product:aosp_miatoll model:Redmi_Note_10_Lite
  device:curtana`; `get-state` returned `device`; model was `Redmi Note 10
  Lite`; release/API were `16`/`36`; ABIs were
  `arm64-v8a,armeabi-v7a,armeabi`. The duplicate mDNS alias was visible but
  was not selected. The `ro.kernel.qemu` query returned an empty output in the
  transcript, and the existing script's physical-device guard completed
  without rejecting the target.
- The transcript records this exact non-secret harness command:
  `E1_ANDROID_EVIDENCE_RUN_ID=task96-android-cross-20260828T134823Z-r2 E1_ANDROID_EVIDENCE_PORT=18080 bash scripts/e1_android_cross_feature.sh 192.168.50.135:41277`.
  After the harness returned, the transcript records
  `harnessExitStatus=0`. The wrapper completed with status `0`, and its
  transcript redaction check passed without exposing bearer or private-key
  material.
- Correction receipts contain 13 successful rows in the same expected order:
  `base`, `business-patch`, `async-patch`, `ui-patch`, `riverpod-patch`,
  `restart-required-1`, `riverpod-persisted`, `invalid-rejected`,
  `rolled-back`, `stale-rejected`, `restart-required-2`,
  `rollback-persisted`, `complete`. Receipt/order and process-boundary
  assertions passed. The correction install evidence contains one
  `adb install -r` result with `Success`.
- Correction package timestamps were identical before and after:
  `firstInstallTime=2026-08-22 01:22:43` and
  `lastUpdateTime=2026-08-28 19:23:24`; `package-times.diff` is zero bytes.
  Package identity remained `dev.hyfens.conformance`, version `1.0.0`,
  version code `1`, min SDK `24`, target SDK `36`. The release APK remained
  `52,131,680` bytes and its correction-run SHA-256 is
  `91f6820eebc6c9787c4d68ab2d2e5d0dcdcc687d035c785989e88461aae0d022`.
- Correction signed-envelope SHA-256 values are unchanged from the original
  generated candidates: `business-1.e1.signed.json` and
  `patch.e1.signed.json`
  `070fe8a6c52d8b8e20669018dfe609b66ac8f8ef77a1f791008335db10e37b46`;
  `business-4.e1.signed.json`
  `cf2dea06b4b186dde279c9ad529347be44337ab951c0c10ac2ac90a877311af2`;
  `async-2.e1.signed.json`
  `9378b869a803a904a64cab91d889ebb73d6e47d34da37048adce6ebc0da14e5f`;
  `ui-3.e1.signed.json`
  `7a8412040332506aa412169d27d7b6c28cca9d7b213347e9ac03db7f7565eed9`;
  `invalid-signature.e1.signed.json`
  `75b784132e8bf609c693119e18c7027a212ba6e96718ae7ca0882827a7d1d06d`.
- No source, runtime, script, or test file was changed by the correction. No
  Dart, Flutter, or unrelated repository test was run. Correction validation
  was limited to the wrapper transcript, existing physical harness, receipt
  assertions, package-time/install checks, redaction check, and artifact/hash
  inspection.

## References

- `scripts/e1_android_cross_feature.sh`
- `fixtures/flutter_conformance_app/README.md`
- `tasks/34-phase-1c-physical-android-closure.md`
- `tasks/35-phase-1c-android-measurements.md`
- `tasks/42-productization-runtime-delivery-integration.md`
- `docs/PHASE_1D_REVIEW.md`

## History

- 2026-08-28: Task 96 reserved after the current physical Android target was
  confirmed online over ADB Wi-Fi. This package is a fresh current-source
  evidence run; it does not rewrite or relabel completed historical tasks.
- 2026-08-28: Ran `scripts/e1_android_cross_feature.sh` once with the explicit
  serial and fresh run ID above. The harness exited `0`; all 13 receipts,
  restart boundaries, invalid-signature rejection, rollback/high-water
  retention, stale rejection, one-install evidence, package-time stability,
  and artifact identity checks passed. Independent strict review is pending.
- 2026-08-28: Independent review identified two evidence-only gaps in the
  original run: no raw preflight transcript proving the selected serial and
  physical-target check, and no raw record of the harness shell exit status.
  No source, script, or test change was authorized.
- 2026-08-28: Executed the one authorized correction run with fresh ID
  `task96-android-cross-20260828T134823Z-r2`, explicit serial, and port
  `18080`. Preserved the redacted preflight/command/exit transcript, verified
  all receipts, package times, install result, and hashes with status `0`.
- 2026-08-28: Laplace re-reviewed the correction run and returned `ACCEPT`.
  The coordinator's consolidated task-scoped receipt, package-time, install,
  transcript-redaction, APK hash/size, and shell-syntax validation passed.
  The empty `ro.kernel.qemu` output is retained as a limitation; no universal
  emulator, compatibility, production, AWS, or hosted claim is made.
