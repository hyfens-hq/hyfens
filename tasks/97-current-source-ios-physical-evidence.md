# Task 97 — Current-source iOS physical evidence

Status: [x] Completed — independent strict review accepted and scoped validation passed

## Goal

Re-run the current checked-in Flutter fixture on the connected physical iPhone
over USB using the repository's approved XcodeBuildMCP/device workflow and
capture fresh multi-function lifecycle evidence. The result must state the
exact iOS behavior exposed by the existing harness and must not relabel the
USB E1 envelope as a Patch Format v1 LAN/control-plane result.

## Scope and Non-goals

Scope:

- verify the current CoreDevice ID, USB UDID, iOS version/architecture,
  signing team, XcodeBuildMCP availability, and `ios-deploy` visibility;
- run the existing `scripts/e1_ios_cross_feature.sh` once with a fresh run ID,
  USB staging, and no simulator substitution;
- preserve the generated run evidence and record exact receipt stages,
  artifact identities, install count, restart/rollback/high-water behavior,
  invalid-signature handling, and any diagnostic/transport gate;
- classify the result as the existing bounded E1 USB fixture path, separately
  from the remaining automatic CLI/Patch Format v1 LAN caveat; and
- correct the existing cross-feature script only at its proven contract
  boundary: use the repository's existing Patch Format v1 batch composer,
  compile the three supported members at one sequence, enable the fixture's
  explicit iOS multi-function mode, stage its exact USB filenames, and assert
  only the iOS-emitted multi-function stages; and
- add a redacted, durable evidence summary and strict review outcome to this
  task record.

Non-goals: source/runtime changes, protocol changes, new iOS test code, any
non-minimal harness redesign, AWS or hosted deployment,
App Store/production-signing claims, simulator evidence, power-loss simulation,
broad thermal/battery/throughput claims, global Docker cleanup, or changes to
completed historical task records.

## Owner

GPT-5.6 Luna Max fast-mode iOS evidence worker owns the fresh run and the
task-owned evidence summary. The coordinator owns device serialization,
XcodeBuildMCP session checks, integration, final acceptance, and task closure.
A separate GPT-5.6 Luna Max fast-mode reviewer owns the strict fact-based
review. No commit is authorized.

## Dependencies

- current checked-in `fixtures/flutter_conformance_app`;
- `scripts/e1_ios_cross_feature.sh` and its USB evidence path;
- `xcodebuildmcp` device workflow, `ios-deploy`, and the local Flutter/Dart
  toolchain;
- physical USB UDID `00008020-001528860E03002E`; and
- CoreDevice ID `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F` with signing team
  `CYT7A4VAZ3`.

## Assumptions

- the named CoreDevice and USB UDID are selected explicitly and must be
  re-verified immediately before the run;
- the existing XcodeBuildMCP CLI is the build/install/launch/stop boundary;
  raw `xcodebuild`, `xcrun`, and `simctl` workflows are not substitutes;
- generated `.dart_tool` evidence is disposable run output, while this task
  file is the durable summary;
- the script's USB E1 envelope is not automatically equivalent to the
  authenticated current CLI/Patch Format v1 LAN adapter; and
- no Dart or Flutter test is run because this package changes no source/test
  file. Only the hardware harness and task-owned evidence are validated.

## Work Items

- [x] Inspect the current script, fixture, prior evidence boundary, and
  connected-device inventory.
- [x] Preserve the initial failed current-source USB attempts and their actual
  failure reasons; do not relabel them as success.
- [x] Apply the minimal current-source adaptation: reuse the existing batch
  composer, compile the business/async/UI E0 members at sequence `1`, enable
  explicit iOS multi-function mode, and stage the exact two USB filenames.
- [x] Correct the iOS stage gate to require the fixture's fourth-launch
  `multi-complete` receipt, its async output, and four process groups.
- [x] Remove the ambiguous build-settings capture that reported a Mac target;
  retain the actual XcodeBuildMCP device-build result as the build identity.
- [x] Run one final fresh current-source iOS USB multi-function sequence with a
  new run ID after the final script correction.
- [x] Verify exact receipt order/outputs, invalid-artifact rejection,
  rollback/high-water behavior, four launch process groups, two stop records,
  one install, arm64/JIT evidence, and USB staging.
- [x] Write a redacted evidence summary without credentials or unsupported
  generalizations.
- [x] Complete independent strict review of the final script and evidence.
- [x] Run final task-scoped assertions after review and close the task.

## Validation

Planned validation is limited to the changed/evidence scope:

- `xcodebuildmcp --help`, `xcodebuildmcp device list --output json`, and
  command-specific help before build/run actions;
- `ios-deploy --detect` and the approved physical-device preflight;
- `bash -n scripts/e1_ios_cross_feature.sh`;
- one fresh invocation of the corrected existing cross-feature script with
  explicit iOS multi-function mode, USB transport, the CoreDevice ID/team/UDID,
  and a unique `E1_IOS_CROSS_RUN_ID`;
- receipt/order, install, artifact/hash, and process-group assertions directly
  against that run; and
- review of task-owned evidence for secret/path leakage and the precise USB
  versus Patch Format v1/LAN claim boundary.

Observed validation:

- `xcodebuildmcp --help` and the device command help were inspected before the
  run. `xcodebuildmcp device list --output json` exited `0` and reported CoreDevice
  `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F` connected/available on iOS `18.7.9`.
  `ios-deploy --detect -W` exited `0` and reported USB-only visibility for
  `00008020-001528860E03002E`. `flutter devices --machine` exited `0` and
  reported that UDID as a supported non-emulator iOS target.
- The current script adaptation uses the existing
  `experiments/patch_loading/bin/e1_patch_format_batch.dart` composer with
  three E0 members at sequence `1`: business, async, and `PricingCard`. It
  enables `E1_IOS_EVIDENCE`, `E1_IOS_USB_EVIDENCE`, and
  `E1_IOS_MULTI_FUNCTION`, stages `multi-1.v1.patch` and
  `multi-invalid.v1.patch` through `ios-deploy -W`, clears only the scoped
  remote receipt file before the run, and polls the downloaded receipt file
  with a bounded sync attempt. The gate requires all current iOS stages,
  including the fourth-launch `multi-complete` stage. No runtime, protocol,
  source, or test file changed.
- The ambiguous `xcodebuildmcp device show-build-settings` capture was removed
  after review found it reported a Mac target. The acceptance evidence uses
  `evidence/build.json`, which is the actual XcodeBuildMCP Release iOS device
  build result. The two source hash extractions use `cut`; no unrelated code
  path was changed.
- The final syntax check `bash -n scripts/e1_ios_cross_feature.sh` exited `0`.
  The build-process guard found no competing fixture build before the final
  run. No Dart, Flutter, or unrelated repository tests were run because this
  package changes no source/test file.
- Final run ID:
  `task97-ios-multi-usb-accepted4-20260828T190000Z`. Raw evidence root:
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_cross_runs/task97-ios-multi-usb-accepted4-20260828T190000Z/`.
  Its `evidence/preflight-and-command.txt` records the explicit USB UDID,
  CoreDevice ID, signing team, bundle ID, and `harnessExitStatus=0`.
- The final receipt file contains 10 successful rows in this exact order:
  `multi-base`, `multi-function-patch`, `restart-required-1`,
  `multi-persisted`, `multi-invalid-rejected`, `multi-rolled-back`,
  `restart-required-2`, `multi-rollback-persisted`, `complete`,
  `multi-complete`. Every row has the final run ID, app ID
  `dev.hyfens.conformance`, release ID `android-e1-release-1`, and build
  fingerprint `conformance-build-1`.
- Receipt behavior is exact: base reports price/async `540`/`540`,
  `uiPatched=false`, base mode, and high-water `0`; the batch reports
  `450`/`481`, `uiPatched=true`, patch mode, and high-water `1`; restart
  persistence retains the batch; the tampered artifact is rejected with
  phase `rejected` while the valid batch remains active; rollback reports
  base `540`/`540` and high-water `1`; the post-rollback restart persists
  base mode; `complete` and the fourth-launch `multi-complete` are healthy
  base receipts, with `multi-complete` reporting async `540`.
- The four receipt process groups are PIDs `64741`, `64820`, `64834`, and
  `64848`. `launches.jsonl` contains four successful XcodeBuildMCP launches;
  `restarts.jsonl` contains two successful stops at the two restart
  boundaries. `install.txt` contains exactly one successful XcodeBuildMCP
  install to CoreDevice `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`.
- `build.json` reports a `SUCCEEDED` Release target `device` build with no
  errors. `architectures.txt` reports arm64 for Runner and App.framework/App;
  `jit-artifacts.txt` is empty; entitlements record team `CYT7A4VAZ3`.
  The composed and tampered Patch Format v1 artifacts are each `7505` bytes,
  with SHA-256 values retained in `evidence/artifact-sha256.txt`:
  `5c7c493ab52e7fc66cdd524552acbdec083e702e5d602759c4d8c30649ef66d4` and
  `cb7965a4f8dada50e9fb75e1dbac9937b7b1477004fed5f056a35efa0b3573d5`.
  `usb-staging-list.txt` contains both exact staged patch filenames and the
  receipt file.

The earlier failed attempts remain preserved in their raw run directories and
are summarized in History. No AWS calls, online deployment checks, simulator
validation, or production-signing claims were made. The final hardware run is
evidence for this named iPhone USB fixture only; it is not evidence of LAN,
CLI, hosted, or production delivery equivalence.

## Next Action

Task 97 is complete. The next bounded instruction is to address the remaining
environment-gated hardware checks only when their prerequisites are available:
power-loss recovery, LAN/automatic CLI delivery, independent-app integration,
performance/thermal/battery behavior, and distribution/hosting. Do not reopen
this USB fixture task or infer those capabilities from this result.

## Blockers

No blocker remains for the bounded USB fixture run. It does not cover
power-loss recovery, LAN/automatic CLI delivery, independent-app integration,
performance/thermal/battery behavior, App Store distribution, hosted
deployment, AWS, or other devices; those remain separate environment or scope
gates.

## Outcome

The final current-source run passed the corrected iOS multi-function gate with
10 receipts, four launches/process groups, two restart stops, invalid-signature
rejection while retaining the active batch, rollback/high-water persistence,
and a single successful Release device install. Turing independently returned
`ACCEPT`, and the final task-scoped read-only assertions passed. The result is
strictly bounded to the named iPhone over USB.

## References

- `scripts/e1_ios_cross_feature.sh`
- `fixtures/flutter_conformance_app/lib/physical_ios_evidence.dart`
- `tasks/36-phase-1c-physical-ios-caveat-closure.md`
- `tasks/42-productization-runtime-delivery-integration.md`
- `tasks/51-ios-diagnostics-and-performance-rerun.md`
- `docs/PHASE_1D_REVIEW.md`
- `xcodebuildmcp-cli` skill at `/Users/princeteck/.agents/skills/xcodebuildmcp-cli/SKILL.md`

## History

- 2026-08-28: Task 97 reserved after the physical iPhone was confirmed
  connected over USB. This package is a fresh current-source evidence run; it
  does not rewrite or relabel completed historical tasks.
- 2026-08-28: The first attempt `task97-ios-cross-20260828T133103Z` built and
  installed through XcodeBuildMCP but exited `1` because line 106 of
  `scripts/e1_ios_cross_feature.sh` passed `E1_ANDROID_*` flags. The local
  receipts were stale Task 51 records, so no current iOS result was claimed.
- 2026-08-28: The authorized flag correction produced
  `task97-ios-cross-fixed-20260828T133844Z`, which reached the current run's
  `base` receipt but exited `1` because the script had not staged
  `patch.e1.signed.json`, the filename consumed by the normal iOS evidence
  session. Read-only `ios-deploy` checks also showed both USB and Wi-Fi paths;
  the next minimal correction must force USB and stage that exact filename.
- 2026-08-28: The third attempt `task97-ios-cross-usb-20260828T135746Z` used
  the corrected iOS flags and forced USB, but still exited `1`. The device
  listing showed `business-1.e1.signed.json` and the other staged files, but no
  `patch.e1.signed.json`; the host copy existed but the staging loop did not
  upload it. The next authorized correction changes only the first staging
  loop name from `business-1` to `patch`.
- 2026-08-28: The final authorized correction changed only the staging loop
  name from `business-1` to `patch`; iOS defines, the host copy, and `-W`
  flags were retained. `bash -n` exited `0`. The run
  `task97-ios-cross-final-20260828T140633Z` staged the expected patch and
  produced fresh `base`, `patch-active`, and `restart-required-1` receipts,
  but exited `1` waiting for the non-iOS stage name `business-patch`. No
  complete 13-stage success was claimed; Task 97 remains In Progress pending
  independent strict review.
- 2026-08-28: The coordinator inspected the current fixture and confirmed
  that `PhysicalIosEvidenceSession` has a separate multi-function contract,
  while the existing script was generating individual E1 envelopes and
  asserting the Android stage list. The smallest authorized correction is to
  reuse `e1_patch_format_batch.dart`, compile the three E0 members at sequence
  `1`, enable `E1_IOS_MULTI_FUNCTION`, stage `multi-1.v1.patch` and
  `multi-invalid.v1.patch`, and assert the fixture's exact iOS multi-function
  stages. No runtime, protocol, or test-file change is authorized.
- 2026-08-28: Run
  `task97-ios-multi-usb-accepted2-20260828T170000Z` reached the intermediate
  `complete` receipt and exited `1` after the gate waited for
  `multi-complete`; its evidence was preserved and not accepted. Independent
  reviewer Ptolemy correctly identified that the fixture emits
  `multi-complete` only on a fourth launch and that an unrelated build-settings
  capture reported a Mac target.
- 2026-08-28: The coordinator corrected only that contract boundary: added the
  fourth launch/`multi-complete` assertions, required four process groups, and
  removed the ambiguous build-settings capture. Run
  `task97-ios-multi-usb-accepted3-20260828T180000Z` exited `0` with the full 10
  stage sequence and four process groups.
- 2026-08-28: The final current-script run
  `task97-ios-multi-usb-accepted4-20260828T190000Z` exited `0` after the
  equivalent `cut` hash extraction cleanup. It is the current review
  candidate; its raw evidence records the full 10-stage sequence, one install,
  four launches, two stops, and all scoped lifecycle assertions. No source or
  test files were changed and no Dart/Flutter tests were run.
- 2026-08-28: Turing independently returned `ACCEPT` after verifying the
  fourth-launch `multi-complete` gate, removal of the ambiguous build-settings
  capture, exact accepted4 evidence, secret/claim boundaries, and task-state
  consistency. The consolidated final validation then passed with
  `task97_scoped_final_validation=PASS`; Task 97 was closed.
