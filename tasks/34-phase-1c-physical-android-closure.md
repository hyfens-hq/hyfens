# Task 34 — Phase 1C physical Android closure

Status: [x] Completed

## Goal

Obtain the fresh physical Android evidence required by
`/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_PHYSICAL_ANDROID_CLOSURE.md`
against the completed Task 32 controller trust/high-water journal and Task 33
support hardening, without changing Architecture B, Patch Format v1, or
capability contract v1.

## Scope and Non-goals

Scope: audit/reacquire a physical arm64 Android device; run the automatic
`tool doctor`/release/install/patch/analyze/inspect/verify workflow; observe
BASE, signed activation, pending-health/health confirmation, restart
persistence, signed base rollback, stale-patch rejection, one invalid-artifact
rejection, and one bounded runtime-error-isolation case. Where the existing
development tooling safely exposes it, record a representative key-lifecycle
physical case and pending-health interruption attempt.

The worker may use temporary copies under `/tmp` and existing development
transport/evidence surfaces. It must record exact device, SDK, tool, release,
APK, patch, sequence, and observation details using explicit evidence labels.

Non-goals: emulator substitution, production diagnostic backdoors, source or
Flutter SDK modification, Patch Format v1/capability v1 changes, cloud/product
work, Phase 1D, store-compliance claims, final Phase 1C review, or Android
performance/binary measurements owned by Task 35.

## Owner

Historical owner: `Helmholtz` (`01a029dd-0967-7641-b59e-0176cb259a0c`). Current
retry owner: `Hilbert` (`01a02a1e-9d47-7b32-a455-2b15cb56c0c6`), a
coordinator-assigned `gpt-5.6-luna` max/fast physical Android worker. The
current worker owns this retry's evidence and task update only; the coordinator
owns final evidence acceptance, `docs/PHASE_1C_REVIEW.md`, and
`tasks/31-phase-1c-runtime-hardening.md`.

## Dependencies

- completed `tasks/32-phase-1c-completion-closure.md`;
- completed `tasks/33-phase-1c-support-hardening.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_PHYSICAL_ANDROID_CLOSURE.md`;
- current automatic CLI/toolchain workflow and conformance fixture;
- a connected physical Android arm64 device; an emulator is not acceptable.

## Assumptions

- the worktree is shared; do not reset, revert, or overwrite unrelated edits;
- do not reinstall the app between BASE, activation, restart, rollback, and
  stale-replay observations;
- use the pinned `path_provider_android 2.2.23` unless fresh evidence proves a
  replacement safe;
- historical Phase 1B evidence remains historical and must not be relabeled;
- inability to connect a suitable device is an external blocker, not a reason
  to weaken or waive the physical gate.

## Work Items

- [x] Read the supplied physical-closure and completed Task 32/33 documents;
  inspect current implementation and audit `adb devices -l`/connection paths.
- [x] Acquire or re-establish one physical arm64 Android connection and record
  model, API, architecture, connection method, ADB identifier, host, Flutter,
  Dart, and tool versions. The exact live mDNS target was online and its
  identity was recorded, but its mDNS service disappeared immediately after
  the earlier 2.3.1 install and the bounded retry stopped as instructed. The
  later fresh Wi-Fi run is recorded in the current lifecycle section below.
- [x] Run the fresh automatic release, install once, and establish observable
  BASE behavior with release ID, APK path/digest/size, and build details. The
  automatic 2.3.1 host Release and one install invocation passed, but the
  target disappeared before data clear or launch, so BASE was not claimed for
  that historical attempt. The later `f574...5359` release established BASE
  and is the current physical evidence.
- [x] In an isolated `/tmp` fixture copy, modify one ordinary supported Dart
  function and generate/analyze/inspect/verify a signed patch automatically;
  record patch identity, sequence, size, key ID, changed function, and
  capabilities as host evidence.
- [x] Physically observe activation, health confirmation, restart persistence,
  signed base rollback, restart after rollback, and stale-patch rejection on
  the fresh automatic release without reinstalling between lifecycle stages.
- [x] Exercise one invalid artifact on Android; the corrupted artifact was
  rejected with a payload-digest diagnostic while the base remained active.
- [x] Exercise one bounded valid-runtime failure on Android; host/runtime
  isolation coverage and the exact-release physical case passed.
- [x] Attempt optional key-lifecycle and pending-health physical cases only
  through existing safe tooling; the existing controller/host cases passed and
  the physical flow is not exposed without an Android target.
- [x] Record exact commands, observations, evidence labels, artifacts, and
  blockers in this task file for coordinator review.

## Validation at pre-closure checkpoint

Required physical validation is the no-reinstall lifecycle sequence from the
supplied closure document. Host tests below are supporting evidence only. The
worker did not claim Android performance measurements; Task 35 owns those. The
physical gate remains open because every bounded Android connection audit was
environment-gated.

### Evidence labels

- `HOST REGRESSION`: executed on the macOS host or an isolated `/tmp` fixture.
- `PHYSICAL ANDROID — NOT RUN`: requires a connected physical arm64 Android
  target; no emulator was substituted.
- `HOST/CONTROLLER VALIDATED — PHYSICAL FLOW NOT EXPOSED`: safe host/controller
  coverage exists, but the current development tooling had no physical Android
  target on which to expose it.
- `NOT RUN`: intentionally unexecuted because the physical prerequisite was
  absent.
- `ENVIRONMENT-GATED SKIP`: a required physical assertion was skipped only for
  the documented external environment blocker.

### Host and tool environment

`HOST REGRESSION` on 2026-08-22:

- Host: macOS 26.6.2 (25G83), Darwin 25.6.0, arm64 (`Yuvrajs-Mini`).
- ADB: `/opt/homebrew/bin/adb`, Android Debug Bridge 1.0.41,
  `36.0.2-14143358`; host features included `openscreen_mdns` and `libusb`.
- Flutter: `/Users/princeteck/.puro/envs/default/flutter/bin/flutter`,
  Flutter 3.47.0 stable, framework revision `4cf2416426`, engine revision
  `5f77625673`, DevTools 2.60.0.
- Dart: `/Users/princeteck/.puro/envs/default/flutter/bin/dart`, Dart 3.13.0.
- Hyfens tool: `0.1.0-phase1c.1` from `dart run cli/bin/tool.dart --version`.
- Android SDK variables both pointed to `/Users/princeteck/Library/Android/sdk`;
  `sdkmanager --version` reported 20.0. Gradle was 9.3.1 and Java was
  OpenJDK/Corretto 17.0.13. Python was 3.14.2.
- The closure documents cite the already-passed adjacent SDK evidence as
  Flutter 3.47.1 / Dart 3.13.1. This run used the installed 3.47.0 / 3.13.0
  pair and records that drift rather than relabeling the earlier evidence.
- The fixture was `fixtures/flutter_conformance_app`, application ID
  `dev.hyfens.conformance`, target `android-arm64-release`. The resolved lock
  currently contains `path_provider_android 2.3.1`, not the Task 34 validated
  pin `2.2.23`; no dependency/source edit was made to conceal or change this.

### Physical Android audit

`PHYSICAL ANDROID — NOT RUN` / `ENVIRONMENT-GATED SKIP`:

- `adb devices -l` before and after the audit returned only `List of devices
  attached` with no rows.
- `adb mdns services` returned `List of discovered mdns services` with no
  services. No wireless-debug pairing endpoint or pairing code was exposed, so
  no speculative `adb pair` or network scan was attempted.
- `system_profiler SPUSBDataType -detailLevel mini` produced no USB summary and
  no filtered Android/ADB/Google/Pixel/Samsung device entry.
- The bounded historical attempt `adb connect 192.168.50.135:39083` returned
  `failed to connect to '192.168.50.135:39083': Connection refused`.
- `flutter devices --machine` listed only a physical iPhone
  (`00008020-001528860E03002E`, iOS 18.7.9), macOS, and Chrome. The iPhone was
  not used as Android evidence; no emulator was used.
- Physical device model, Android version/API, arm64 confirmation, connection
  method, and ADB identifier: `NOT AVAILABLE` because no Android device was
  enumerated.

### Task 32/33 and freeze verification

`HOST REGRESSION`:

- Repository inspection found no committed baseline (`git log` reported no
  commits; `git diff --stat` was empty and the worktree contained 408 existing
  untracked paths). No reset, revert, or unrelated source edit was performed.
- Task 32 integration is present in
  `experiments/patch_loading/lib/src/controller.dart`: controller-owned
  `stateVersion: 4`, retained `state-v3-a.json`/`state-v3-b.json` paths,
  `trustGeneration`, trusted/retired/revoked key state, replay ledger,
  high-water, signed rollback, key-lifecycle commands, recovery, and atomic
  durable-boundary hooks are all present.
- Task 33 hardening is present in the Patch Format and instrumentation code:
  non-octet rejection, bounded 32-bit words/sections/collections, release-owned
  budgets, capability admission, logical URI/source-map restrictions, and
  diagnostic redaction are present. The focused tests below exercised these
  seams.
- Current normative hashes: `docs/spec/patch-format-v1.md` =
  `b64b7f3f398bcfc57c4169044d84fb4517266948b516986a8bf03486be75a7fe`;
  `docs/spec/capability-v1.md` =
  `bccc08529541c1510fdc6fb4fe00b0e25c03cbe187e9fdd7f59deec0839d2f76`.
  The Patch Format inspection below reported `formatVersion: 1` and
  `runtimeCompatibilityVersion: 1`, with no capability declarations.
- Architecture B remains the accepted automatic build-time source
  instrumentation, normal Flutter AOT fallback, bounded signed interpreted
  dispatch design in ADR 0002 and ADR 0003. No `class PatchView`, `@patch`,
  `manualDispatch`, or manual-dispatch source construct was found. Generated
  Android `@Keep` imports are ordinary build/plugin annotations, not a
  per-function patch annotation or dispatch mechanism.
- The automatic Release instrumentation record contained 24 units, all 24
  selected/instrumented, zero absolute source paths, and the release manifest
  contained 40 functions, zero capabilities, and zero widget factories. The
  checked-in fixture source hash remained
  `5182f8dbe6972f91a1aa5c15840c075699e92a93cf5626a115f893387c30bb3b` before
  and after the release build.

### Automatic host Release and patch artifacts

`HOST REGRESSION` — the normal automatic command completed:

```text
dart run cli/bin/tool.dart doctor --project fixtures/flutter_conformance_app --json
→ result READY; Flutter 3.47.0; Dart 3.13.0; runtime SUPPORTED

dart run cli/bin/tool.dart release android --project fixtures/flutter_conformance_app --json
→ exit 0; build SUCCESS; Flutter command `flutter build apk --release --no-pub`
```

Release identity and artifact:

- Release ID:
  `sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16`.
- Application/target/architecture/mode:
  `dev.hyfens.conformance` / `android` / `arm64` / `release`.
- Build fingerprint:
  `524b68c9500763258dff9ccf19edb4dd39042e202b0fa223af0151d520764573`.
- Config fingerprint:
  `b5d85876a81f87d7015fda555fe7ac082a2268a828310aad4bb1f0da5775cad3`.
- APK: `fixtures/flutter_conformance_app/.tool/releases/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/artifacts/app-release.apk`.
- APK bytes: `51,869,536`; SHA-256:
  `72fb91d23cc4217e118f5884dcc0f338fb010d5d7c4a0a0261200fddb3617631`.
- Build duration from the automatic tool record: `54,578 ms`.
- `tool analyze` on the unmodified fixture returned `PATCH_BLOCKED` / `NO_EFFECT`;
  it did not invent a patch from unchanged source. The generated release and
  APK were not installed because no Android target existed.

For the required ordinary-function patch, the source edit was confined to the
isolated `/tmp/hyfens-task34p-UUyqXL/fixtures/flutter_conformance_app` copy:
`calculatePrice` changed only `return quantity * 90` to
`return quantity * 91` at logical `package:conformance/main.dart:14:5`.
The automatic commands were:

```text
flutter pub get
dart run cli/bin/tool.dart analyze --project /tmp/hyfens-task34p-UUyqXL/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; result PATCHABLE; one function; function ID sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361; 21 non-fatal P2001 exclusion warnings

dart run cli/bin/tool.dart patch --project /tmp/hyfens-task34p-UUyqXL/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; sequence 1; patch ID sha256:3bdc9c8a7ced3c4dc142afef7ee052962234fb60ee1fd507a2eee1193d495e70; key ed25519-8aa2e7a111444605; signature verified

dart run cli/bin/tool.dart inspect <000001.patch> --json
→ formatVersion 1; runtimeCompatibilityVersion 1; function slot 36; capabilities []; extension type [9]

dart run cli/bin/tool.dart verify <000001.patch> --project <temporary fixture> --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; VERIFIED; release matched; key ed25519-8aa2e7a111444605
```

Patch artifact identity:

- Path: `/tmp/hyfens-task34p-UUyqXL/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch`.
- Bytes: `2,069`; SHA-256:
  `6185685fbfeeabe7784d5b13271cb53be8c93d3ab7ddf75e49079bb5027c902d`.
- Patch ID: `sha256:3bdc9c8a7ced3c4dc142afef7ee052962234fb60ee1fd507a2eee1193d495e70`;
  sequence `1`; signing key ID `ed25519-8aa2e7a111444605`.
- Changed function ID:
  `sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361`;
  release slot `36`; signature digest
  `sha256:aa6467d21d029869a38918e81e867005d8b8cbfaa5edbe3a1cacf81de0edab7b`.
- Payload digest from `tool inspect`:
  `v+Zz0sE2WN3nayDizlocicKpyEqNpfQaOzpJI17bQ48=`; required capabilities: none.

The host-only signed rollback command was also exercised in the same
temporary project:

```text
dart run cli/bin/tool.dart rollback --project <temporary fixture> --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --to base --json
→ exit 0; ROLLED_BACK; target base-aot; high-water sequence 1 retained;
  high-water digest 6185685fbfeeabe7784d5b13271cb53be8c93d3ab7ddf75e49079bb5027c902d
```

The host rollback control was 440 bytes with SHA-256
`4fcbcdf9b89b50f82270c777085f0a70a306b4213af0388032539e61ccc2db38`; the
rollback state journal was 324 bytes with SHA-256
`fe19c5d58b849e9b4ea021ffc51ee0541bab0b728b69b26cd7585ee699d8bb36`.

### Physical lifecycle matrix

All rows below are `PHYSICAL ANDROID — NOT RUN` / `ENVIRONMENT-GATED SKIP`.
There was no install, so the no-reinstall sequence did not begin and no
physical behavior is inferred from the host artifacts.

| Required assertion | Physical observation | Host/supporting evidence |
| --- | --- | --- |
| Install Release APK once; BASE AOT visible; runtime state initializes | Not run; install count `0` | Automatic Release APK exists and is hash-recorded above |
| Generated/analyzed/signed patch received; exact release/signature verified | Not run | Host Patch Format v1 patch generated, inspected, and verified |
| Candidate → pending health → healthy; patched behavior visible | Not run | Task 32 lifecycle tests cover pending candidate/health transitions |
| Restart persistence, including a second restart if practical | Not run | Task 32 controller/recovery tests pass; no Android process was launched |
| Signed base rollback; high-water/trust/release identity retained | Not run | Host signed rollback control retained sequence 1; CLI rollback tests pass |
| Restart after rollback; BASE persists | Not run | Host rollback/recovery tests pass; no physical restart occurred |
| Stale patch after rollback rejected; BASE remains active | Not run | Task 32 anti-replay/high-water tests pass; no stale artifact was delivered to a device |
| One invalid artifact rejected without disturbing known-good state | Not run | `tool inspect experiments/patch_loading/patches/invalid.e0.json --json` exited 67 with `R5004` / `P1001 Invalid patch magic`; physical retention not observed |
| One valid bounded runtime failure isolated with logical diagnostics | Not run | Focused runtime-error and logical-source-map host tests passed; no physical diagnostic captured |

No Android package install metadata, device logcat, UI hierarchy, state-v4
files, process IDs, device model/API, or physical artifact receipt exists for
this run.

### Host regression evidence

`HOST REGRESSION`:

- `dart analyze --fatal-infos` in `packages/patch_format`,
  `experiments/instrumentation`, `experiments/patch_loading`, and `cli`: all
  reported `No issues found!`.
- `dart test -j 1` in `packages/patch_format`: 12 passed.
- `dart test -j 1 test/runtime_hardening_v1_test.dart test/runtime_hardening_allocation_test.dart test/capability_registry_v8_test.dart test/fuzz_corpus_test.dart test/async_v6_test.dart` in `experiments/instrumentation`: 71 passed.
- `dart test -j 1 test/controller_test.dart test/lifecycle_recovery_test.dart test/key_lifecycle_test.dart test/integrated_trust_journal_test.dart` in `experiments/patch_loading`: 47 passed. This included rotation, retirement, revocation, recovery replacement, rollback, cleanup, wrong-release, dual-copy corruption, stale replay, and durable fault cases.
- `dart test -j 1 test/toolchain_test.dart test/rollback_cleanup_test.dart` in
  `cli`: 19 passed.
- Targeted runtime isolation test `runtime error isolation invalid opcode becomes
  a bounded runtime fault`: 1 passed. Targeted logical diagnostic test
  `source-mapped diagnostics maps guest traces and runtime faults to logical
  source locations`: 1 passed.
- `dart run cli/bin/tool.dart inspect experiments/patch_loading/patches/invalid.e0.json --json`: exit 67, `R5004`, underlying `P1001 Invalid patch magic`.
- `HOST/CONTROLLER VALIDATED — PHYSICAL FLOW NOT EXPOSED`: key lifecycle and
  pending-health coverage was exercised by the passed controller tests, but no
  production or ad-hoc physical trust-control API was invented.
- Full consolidated Phase 1C validation was not claimed. Task 35 Android
  dispatch/startup/memory/binary measurements were explicitly not run.

## Next Action

Acquire or re-establish a physical arm64 Android device through USB or a
known, paired wireless-debug endpoint, then rerun only the blocked physical
rows with the recorded Release APK/patch identities or a newly generated
normal-toolchain pair. Keep the recommendation `CONTINUE PHASE 1C` until the
fresh Android no-reinstall evidence is accepted. Do not use the visible iPhone,
macOS, Chrome, or an emulator as a substitute.

## Blockers

- No physical Android device was enumerated over USB, ADB, or mDNS wireless
  discovery. The only known wireless endpoint, `192.168.50.135:39083`, refused
  the bounded connection attempt. No pairing endpoint/code was available.
- Therefore no Android model/API/arm64/connection identity, Release APK
  installation, BASE observation, activation/health receipt, restart,
  rollback/stale-replay receipt, invalid-artifact device result, or physical
  logical diagnostic exists. The Phase 1C physical gate is intentionally open.
- The current fixture lock resolves `path_provider_android 2.3.1` while Task 34
  requires the previously validated `2.2.23` pin unless fresh physical evidence
  proves a replacement safe. This was recorded, not changed, because source
  and dependency edits are outside the bounded physical closure run.
- `apkanalyzer` was present but failed host metadata inspection with
  `Cannot locate latest build tools`; the normal automatic Flutter Release APK
  build itself succeeded. This is recorded as a host tooling limitation, not a
  fabricated package-install result.
- On the closure retry, the exact required serial `192.168.50.135:39979`
  became `offline` and then refused bounded reconnects. mDNS advertised only
  the prohibited historical endpoint `192.168.50.135:39083`; no alternate
  endpoint was guessed or used. This run therefore has no fresh 2.3.1 physical
  compatibility result and no physical Android lifecycle evidence.
- Fresh retry blocker: the exact live serial
  `adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp` was online, and mDNS
  advertised it at `192.168.50.135:38217`. The 2.3.1 APK install returned
  `Success`; the next required pre-device-operation check showed
  `adb mdns services` with only its header and no live target. The retry
  stopped without `pm clear`, launch, logcat capture, or any further adb
  operation. No JNI/bootstrap failure was reproduced, so no 2.2.23 fallback
  was selected.

## Outcome

`CONTINUE PHASE 1C`. Task 32 controller trust/high-water integration and Task 33
support hardening were verified by source inspection, fatal-info analysis, and
focused host regressions. The normal Phase 1C automatic toolchain produced a
fresh host Android arm64 Release baseline and a fresh signed Patch Format v1
artifact in an isolated temporary source copy; host signed rollback, invalid
artifact rejection, bounded runtime-error isolation, and logical source-map
diagnostics all passed. No tracked source was modified, no Flutter SDK was
modified, no emulator was used, and no physical Android installation or
lifecycle claim was made. Physical Android closure remains blocked by device
availability and the path-provider pin drift remains for maintainer review.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_PHYSICAL_ANDROID_CLOSURE.md`
- `/Volumes/970EvoPlus/Downloads/32-phase-1c-completion-closure.md`
- `/Volumes/970EvoPlus/Downloads/33-phase-1c-support-hardening.md`
- `tasks/31-phase-1c-runtime-hardening.md`
- `docs/PHASE_1C_REVIEW.md`
- `docs/architecture/runtime-state-machine.md`
- `docs/security/key-lifecycle.md`

## History

- 2026-08-22: Reserved Task 34 as the physical Android closure package after
  reading all three supplied documents. The task deliberately excludes
  performance measurements and final review so device work remains serialized
  and evidence ownership is clear.
- 2026-08-22: Assigned to Helmholtz (`01a029dd-0967-7641-b59e-0176cb259a0c`)
  with `gpt-5.6-luna`, maximum reasoning, and priority/fast service.
- 2026-08-22: Audited USB, ADB, and bounded wireless options. `adb devices -l`
  and `adb mdns services` were empty, USB inventory exposed no Android device,
  and `adb connect 192.168.50.135:39083` returned `Connection refused`. No
  emulator was substituted.
- 2026-08-22: Verified Task 32/33 implementation markers, Patch Format v1,
  capability v1, and Architecture B freeze. Fatal-info analysis and focused
  Patch Format, instrumentation, controller/trust, lifecycle, CLI toolchain,
  rollback, runtime-isolation, and source-map tests passed.
- 2026-08-22: Ran `tool doctor` and the normal automatic Android Release command.
  Release `sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16`
  built successfully; APK and host-only patch/rollback identities and digests
  are recorded above. No install was attempted without an Android target.
- 2026-08-22: Marked Task 34 externally blocked with recommendation
  `CONTINUE PHASE 1C`; physical evidence rows remain open for a future
  coordinator/maintainer run.

- 2026-08-22: Closure worker retry used the exact supplied serial
  `192.168.50.135:39979`. The bounded audit command
  `ANDROID_SERIAL=192.168.50.135:39979 adb devices -l` initially listed the
  target as `offline` with product `aosp_miatoll`, model
  `Redmi_Note_10_Lite`, and device `curtana`; every explicit
  `adb -s 192.168.50.135:39979` property query returned `error: device offline`.
  `adb connect 192.168.50.135:39979` then returned
  `Connection refused`. One bounded `ANDROID_SERIAL=... adb reconnect offline`
  followed by a second exact `adb connect 192.168.50.135:39979` also returned
  no exact target / `Connection refused`. The current
  `ANDROID_SERIAL=192.168.50.135:39979 adb mdns services` output advertised
  only historical endpoint `192.168.50.135:39083`; that endpoint was not used
  because the closure instructions require the exact supplied serial and
  prohibit guessing or substituting another port. `ANDROID_SERIAL=...
  flutter devices --machine` completed with only the physical iPhone,
  macOS, and Chrome; no Android target was available to Flutter. No emulator,
  iPhone, historical endpoint, network scan, build, install, or Task 35
  measurement was used.

- 2026-08-22: Recorded the available host evidence without running a release:
  macOS 26.6.2 / Darwin 25.6.0 arm64; ADB 1.0.41
  (`36.0.2-14143358`); Flutter 3.47.0 / Dart 3.13.0; Hyfens tool
  `0.1.0-phase1c.1`; Android SDK `/Users/princeteck/Library/Android/sdk`,
  `sdkmanager 20.0`, Gradle 9.3.1, Java 17.0.13; fixture lock remained at
  `path_provider_android 2.3.1`. The required 2.3.1 physical launch/logcat
  compatibility result, release/APK digest, one-install BASE result, patch
  delivery, lifecycle transitions, invalid-artifact result, and physical
  runtime-error isolation were all **NOT RUN** because the exact target was
  not online. Task 34 remains `[-] Blocked`; the blocker is external device
  availability, not a reproduced dependency or runtime failure.

- 2026-08-22: Reassigned the next physical retry to Hilbert after Wireless
  debugging was manually re-enabled and the live mDNS transport became
  available. The retry must use the live mDNS identity rather than stale IP
  port 39979 or historical port 39083.
- 2026-08-22: Coordinator completed the fresh automatic Wi-Fi lifecycle on
  `adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp`: BASE `540`, visible patch
  `651`, restart persistence, signed rollback/base persistence, stale delivery
  boundary `NO_UPDATE`, and corrupt-payload `P1041` rejection. The task is
  now in progress only for the physical valid-runtime-error case and the
  separately owned Task 35 measurements.

## Fresh retry evidence — 2026-08-22

The following is appended fresh evidence for the Hilbert retry. It does not
replace the historical blocked evidence above. No Task 36/iOS evidence, Task
35 measurement, Architecture B, Patch Format v1, capability v1, runtime or
compiler semantic, Task 35, Task 31, or final-review document was changed.

### Evidence labels and Wi-Fi debugging finding

The Wi-Fi debugging finding below is `HOST/ENVIRONMENT`, not a runtime
conclusion:

- Wireless debugging was manually re-enabled. The bounded identity query
  reported `adb_wifi_enabled=1`, `adb_enabled=1`, and
  `development_settings_enabled=1`.
- Before the first device query, the exact commands were:

  ```text
  adb devices -l
  adb mdns services
  ```

  The live row was:

  ```text
  adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp device product:aosp_miatoll model:Redmi_Note_10_Lite device:curtana transport_id:6854
  ```

  and mDNS advertised:

  ```text
  adb-ce57506c-N761V5 (2)  _adb-tls-connect._tcp  192.168.50.135:38217
  adb-ce57506c-N761V5     _adb-tls-connect._tcp  192.168.50.135:39083
  ```

- The old `192.168.50.135:39979` transport is historical stale/offline and
  refused in the prior bounded retry recorded above. The
  `192.168.50.135:39083` mDNS service is also historical and was not used.
  No port was guessed, scanned, connected, or substituted.
- The physical identity was `aosp_miatoll`, model `Redmi Note 10 Lite`,
  device `curtana`, Android `16`/API `36`, `arm64-v8a`/`aarch64`, with
  `ro.kernel.qemu` empty. The connection method was wireless ADB over the live
  mDNS transport.
- The exact host command
  `ANDROID_SERIAL='adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp' flutter devices --machine`
  exited 0 but listed only the physical iPhone, macOS, and Chrome. No mDNS
  parse warning was emitted by this machine-readable invocation; no global
  Flutter SDK change or workaround was made.

### Fresh host tool and dependency evidence

This section is `HOST REGRESSION` unless another label is shown:

- Host: macOS 26.6.2 (25G83), Darwin 25.6.0, arm64.
- ADB: `/opt/homebrew/bin/adb`, Android Debug Bridge 1.0.41,
  `36.0.2-14143358`.
- Flutter: `/Users/princeteck/.puro/envs/default/flutter/bin/flutter`,
  Flutter 3.47.0 stable, framework `4cf2416426`, engine `5f77625673`,
  DevTools 2.60.0. Dart: 3.13.0. Hyfens tool: `0.1.0-phase1c.1`.
- Android SDK: `/Users/princeteck/Library/Android/sdk`, sdkmanager 21.0;
  Gradle 9.3.1; Corretto/OpenJDK 17.0.13; Python 3.14.2.
- The exact dependency checks were:

  ```text
  rg -n -A8 -B2 '^  path_provider_android:|^  path_provider:' fixtures/flutter_conformance_app/pubspec.lock
  (cd fixtures/flutter_conformance_app && flutter pub deps --style=compact)
  ```

  The fixture resolved `path_provider 2.1.6` and
  `path_provider_android 2.3.1` with `jni 1.0.3` and `jni_flutter 1.0.2` in
  the transitive graph. `pubspec.lock` SHA-256 was
  `6d215e2ea4edadcd53e97f9721713673d111c9dbe88d4041f049a42a283f28b6`.
  No dependency pin or Flutter SDK change was made.

### Automatic 2.3.1 release and install probe

`HOST REGRESSION` for the release and `PHYSICAL ANDROID` only for the install
line:

```text
dart run cli/bin/tool.dart doctor --project fixtures/flutter_conformance_app --json
→ exit 0; result READY; Flutter 3.47.0; Dart 3.13.0; runtime SUPPORTED

dart run cli/bin/tool.dart release android --project fixtures/flutter_conformance_app --json
→ exit 0; status SUCCESS; command flutter build apk --release --no-pub;
  elapsed 47,816 ms
```

The 2.3.1 release identity was:

- Release ID: `sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16`.
- Application/target/architecture/mode:
  `dev.hyfens.conformance` / Android / arm64 / Release.
- Build fingerprint:
  `524b68c9500763258dff9ccf19edb4dd39042e202b0fa223af0151d520764573`.
- APK:
  `fixtures/flutter_conformance_app/.tool/releases/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/artifacts/app-release.apk`.
- APK size: `51,869,536` bytes. APK SHA-256:
  `72fb91d23cc4217e118f5884dcc0f338fb010d5d7c4a0a0261200fddb3617631`.

Before install, the bounded check also ran:

```text
adb -s 'adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp' shell pm path dev.hyfens.conformance
→ an existing package path was present
```

The one install invocation in this retry was:

```text
adb -s 'adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp' install -r fixtures/flutter_conformance_app/.tool/releases/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/artifacts/app-release.apk
→ Performing Streamed Install; Success; exit 0
```

This was an update of a pre-existing package path, not a clean first install.
It is the only install invocation in this retry. No `pm clear`, launch, or
second install was attempted. The next required bounded check was:

```text
adb devices -l
→ target row still appeared briefly
adb mdns services
→ List of discovered mdns services
→ no service rows; exact `(2)` service/38217 endpoint absent
→ STOP
```

This is the exact external blocker. The 2.3.1 launch/JNI/bootstrap result is
`PHYSICAL ANDROID — NOT RUN`, not pass and not failure, because the live mDNS
target disappeared before launch. Consequently, no 2.2.23 fallback release
was generated and no compatibility conclusion was drawn.

### Automatic patch evidence for the exact release

`HOST REGRESSION` in isolated temporary project
`/tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app`; the
checked-in fixture remained unchanged. The ordinary supported source change
was only `lib/main.dart:14:5`, changing `return quantity * 90` to
`return quantity * 91`. No manual function targeting, source annotation,
manual dispatch, `PatchView`, or runtime/compiler semantic change was used.

Exact host commands:

```text
flutter pub get
dart run cli/bin/tool.dart analyze --project /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16
→ exit 0; PATCHABLE; lib/main.dart:14:5

dart run cli/bin/tool.dart analyze --project /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; result PATCHABLE; one ordinary function selected; 21 non-fatal P2001 warnings

dart run cli/bin/tool.dart patch --project /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; sequence 1; signature verified

dart run cli/bin/tool.dart inspect /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch --json
→ exit 0; formatVersion 1; runtimeCompatibilityVersion 1; capabilities []; artifactBytes 2,069

dart run cli/bin/tool.dart verify /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch --project /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app --release sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16 --json
→ exit 0; VERIFIED; exact release matched
```

Patch identity:

- Path: `/tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch`.
- Size: `2,069` bytes. SHA-256:
  `6185685fbfeeabe7784d5b13271cb53be8c93d3ab7ddf75e49079bb5027c902d`.
- Patch ID: `sha256:3bdc9c8a7ced3c4dc142afef7ee052962234fb60ee1fd507a2eee1193d495e70`.
- Sequence: `1`. Signing key ID:
  `ed25519-8aa2e7a111444605`. Signature was verified; private signing
  material was not logged.
- Patch Format/runtime: `1` / `1`; capabilities: none; extension type: `9`.
  Payload digest: `v+Zz0sE2WN3nayDizlocicKpyEqNpfQaOzpJI17bQ48=`.

### Physical lifecycle and skipped assertions

All rows below are `PHYSICAL ANDROID — NOT RUN` / `ENVIRONMENT-GATED SKIP`
after the exact live mDNS guard stopped the retry. No host result is
substituted for a physical observation:

| Required assertion | Fresh physical observation | Reason/skipped evidence |
| --- | --- | --- |
| 2.3.1 launch/JNI-bootstrap compatibility and BASE AOT | Not run | Target disappeared after successful install and before `pm clear`/launch; no launch logcat exists. |
| Candidate/pending-health/healthy patched behavior | Not run | No app launch or patch receipt. |
| Force-stop/relaunch persistence | Not run | No physical process was started by this retry. |
| Signed base rollback with retained high-water/trust/release identity | Not run | No physical delivery/runtime state was established. |
| Restart after rollback and BASE persistence | Not run | No physical rollback occurred. |
| Stale old-patch rejection | Not run | No physical patch was delivered. |
| Invalid signature/wrong-release/corrupt artifact rejection | Not run | No physical artifact delivery or retention assertion occurred. |
| Valid bounded runtime failure with logical source mapping | Not run | No physical runtime execution or logcat was captured. |
| Key-lifecycle/pending-health interruption optional cases | Not run fresh | Existing host/controller evidence remains historical supporting evidence only. |

No Task 35 measurement was run. No store-compliance claim or Phase 1C final
completion claim is made. Task 34 remains `[-] Blocked` on the disappeared live
mDNS target and the mandatory physical rows remain open.

### Task-scoped review and validation

The task-owned documentation review and artifact recheck were host-only:

```text
git diff --no-index --check /dev/null tasks/34-phase-1c-physical-android-closure.md
→ exit 1 as expected for an untracked task file; no whitespace diagnostics

awk '/[[:blank:]]$/{print NR ":" $0}' tasks/34-phase-1c-physical-android-closure.md
→ no trailing whitespace

shasum -a 256 fixtures/flutter_conformance_app/pubspec.yaml fixtures/flutter_conformance_app/pubspec.lock fixtures/flutter_conformance_app/lib/main.dart
→ 0b7ffcf861d0d895e69378725dab34818881f002bb3497a6089d3d4f7235b8db
  6d215e2ea4edadcd53e97f9721713673d111c9dbe88d4041f049a42a283f28b6
  5182f8dbe6972f91a1aa5c15840c075699e92a93cf5626a115f893387c30bb3b

stat -f '%z' fixtures/flutter_conformance_app/.tool/releases/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/artifacts/app-release.apk
shasum -a 256 fixtures/flutter_conformance_app/.tool/releases/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/artifacts/app-release.apk
→ 51869536 bytes; 72fb91d23cc4217e118f5884dcc0f338fb010d5d7c4a0a0261200fddb3617631

stat -f '%z' /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch
shasum -a 256 /tmp/hyfens-task34-patch.TuS9tI/fixtures/flutter_conformance_app/.tool/patches/sha256:683381a0de9903994e598065d4bba4b620c4784e3538dc91daf230c5fdeecc16/000001.patch
→ 2069 bytes; 6185685fbfeeabe7784d5b13271cb53be8c93d3ab7ddf75e49079bb5027c902d
```

The automatic doctor/release/analyze/analyze-JSON/patch/inspect/verify
commands above all passed. The required physical lifecycle, invalid-artifact,
runtime-error/logcat, and rollback assertions remain explicitly skipped under
the disappeared-target blocker.

## Coordinator transport and iOS-caveat follow-up — 2026-08-22

This addendum preserves the historical retry record above and records the
coordinator's later bounded observation. It does not close Task 34 or replace
the requirement for visible changed behavior on a physical Android device.

### Android Wi-Fi debugging diagnosis

The available evidence does not demonstrate that Android Wireless debugging
turned itself off during the monitored interval:

- `adb shell settings get global adb_wifi_enabled` remained `1` and
  `adb -s "adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp" get-state` remained
  `device` across all 12 samples.
- The live endpoint was `192.168.50.135:38217`; `192.168.50.135:39083` and the
  earlier `39979` endpoint were stale/refused and were not used as substitutes.
- `adb mdns services` alternated between no service rows and simultaneous
  stale/live advertisements while the established serial remained usable.
- The device remained reachable by IP during the bounded probe, and the
  filtered log showed `WirelessDebuggingFrag onEnabled(): connect_port=38217`
  but no corresponding `onDisabled` event.

The supported diagnosis is therefore host/network mDNS discovery and endpoint
churn, not a confirmed device-side Wireless debugging shutdown. The initial
manual re-enable is still an external prerequisite when the service is not
advertised at all. Once the serial is `device`, the operator should keep using
that exact serial and ignore transient mDNS gaps; perform at most one bounded
same-device rediscovery after an actual transport drop. The host also used an
ADB client `36.0.2` with a running ADB server `37.0.0`; this is a plausible
environment contributor, not a proven root cause and no global SDK change was
made.

### Android v1 transport follow-up

With the established serial, the already installed 2.3.1 Release APK was not
reinstalled and application data was not cleared. A local loopback v1 endpoint
was exposed through the bounded development reverse tunnel. The app generated
v1 polling traffic, and the runtime recorded signed sequence-4 admission as
healthy, tampered-payload rejection, signed rollback to base with high-water
retention, and stale sequence-4 rejection after rollback. The earlier
sequence-3 attempt was correctly blocked by retained high-water state.

This remains partial evidence, not a physical lifecycle pass: the visible app
behavior stayed at base `price 540` instead of showing the changed business
result. Therefore BASE-to-patched behavior, restart persistence of the changed
result, and the complete mandatory Android closure are still not accepted. The
bounded follow-up evidence is retained at
`/tmp/hyfens-android-v1-seq4.GF5THh`; no temporary server or reverse tunnel
remains active. Task 35 measurements were not started.

### iOS caveat

The connected physical iPhone is available under the existing development
team `CYT7A4VAZ3` and iOS 18.7.9. The fresh Task 36 USB run is valid bounded
physical lifecycle evidence: one signed Release install, base behavior,
patched behavior, restart persistence, invalid-signature rejection, rollback,
and rollback persistence all passed. It is intentionally scoped to the E1 USB
harness and is not relabeled as a current CLI-generated Patch Format v1 LAN
run. The historical Phase 1B v1 LAN record remains separate. No App Store,
production-signing, or policy-approval claim is made.

### Current disposition

Historical pre-closure checkpoint; superseded for current disposition by the
fresh automatic Android lifecycle section below.

Task 34 remains `[-] Blocked` because the current automatic Android v1 run did
not visibly demonstrate changed behavior. The transport diagnosis does not
waive that gate, and no iOS evidence is being used as an Android substitute.

## Fresh automatic Android lifecycle — 2026-08-22

The previously missing physical gate was rerun against the fresh automatic
release after Wi-Fi ADB became reachable:

```text
serial:       adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp
device:       Redmi Note 10 Lite / curtana
Android:      16 / SDK 36 / eng.avanin
ABI:          arm64-v8a
transport:    Wi-Fi ADB; adb reverse tcp:18080 -> tcp:18080
release:      sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359
APK:          51,951,456 bytes; SHA-256 24ec7c24875b7e2ce5f9c97020986a48bad812193f0c03d4d89b8666734fc594
patch:        sha256:e2829df698c9a185e948b12a5fb732664cf59cdd8953385a3663e6845f2c8c92
patch:        2,069 bytes; SHA-256 0c8270441ffe9b270745f9ac2f7c341e34d8d29fc57436fd6304ae8f431d1a32
sequence:     1; function slot 36; key ed25519-8aa2e7a111444605
```

The exact no-reinstall observation was:

```text
BASE launch                         healthy/base; visible price 540
signed automatic admission          pendingHealth -> healthy/patch
normal button invocation            quantity 7; visible price 651
restart with app data retained      current healthy signed patch active
restart + normal invocation         quantity 7; visible price 651
signed rollback to base              rolledBack; high-water sequence 1 retained
rollback + normal rebuild           visible base price 720 at quantity 8
restart after rollback               base persists; quantity 7 -> price 630
stale sequence-1 delivery            HTTP 404 NO_UPDATE; runtime stays base
corrupt signed payload              P1041 digest mismatch; BASE stays active
```

The generated runtime emitted the lifecycle records directly. The fixture's
archival manual status label stayed `status: created` by design and was not
used as automatic-controller evidence. A temporary local test server was used
only for the corrupt-payload response; no production transport or trust rule
was changed. The rollback-control file was restored after the stale check and
the corrupt test server was stopped.

Current disposition: the transport and visible-behavior gates are no longer
blocked. The bounded physical runtime-error case and Task 35 measurements are
still open. The stale observation is a delivery-boundary `NO_UPDATE` result,
not direct delivery and runtime rejection of old valid bytes. The corrupt
artifact observation was made while BASE was active, not while a healthy patch
was active. No final Phase 1C completion is claimed.

## Behavioral-application follow-up — 2026-08-22

Historical pre-closure checkpoint; the later fresh automatic lifecycle below
supersedes its physical-pending disposition while preserving this diagnosis.

Task 37 traced the admitted-but-visible-BASE mismatch on the host and found a
process-global runtime ownership defect in the mixed automatic/manual fixture
bootstrap. The generated integration and archival manual controller could
both reset the static E0 registry; the manual controller could therefore
remain `PATCH`/healthy while its installed slot had been cleared. The
generated controller also had no UI status bridge to the archival screen.

The bounded fix is recorded in Task 37: one process-local E1 runtime lease,
generated-start single-flight, and automatic-fixture suppression of the
archival manual initialization. The focused regression and a fresh automatic
release/analyze/patch/inspect/verify host run passed. The fresh host artifact
is release `sha256:c9283534fe98c41d1318fcb88752bfccf1c2652cae67c8d2c82e3cad64ec3e94`,
with Patch Format v1 patch sequence 1, 2,069 bytes, and function slot 36.

This is host evidence only. At the time of this addendum `adb devices -l` and
`adb mdns services` were empty, so no post-fix APK install, visible patched
value, restart persistence, rollback, stale-replay, or runtime-error result
is claimed. Task 34 remains blocked and Task 35 remains deferred until a
physical Android run proves the visible behavior gate.

The final host-only rebuild after bootstrap-marker and failed-initialization
cleanup hardening is release
`sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359`.
Its 51,951,456-byte APK and 2,069-byte signed Patch Format v1 artifact were
verified against the exact release. This does not change the blocked physical
disposition: no install, patched visible result, restart, rollback, or stale
replay is claimed until the device is reachable.

For closure review, the evidence categories are explicit:

- **HOST REGRESSION:** Task 37's duplicate-controller/E0-reset diagnosis,
  ownership/marker fix, and automatic host artifact verification.
- **PHYSICAL ANDROID — PARTIAL:** the earlier installed run's signed
  admission/health, rejection, rollback, and stale-replay observations while
  the UI remained at \`price 540\`.
- **PHYSICAL ANDROID — REQUIRED NEXT RUN:** install the fresh release once,
  show BASE \`540\`, deliver the signed patch, trigger a natural rebuild/invocation
  and capture the changed visible value, then complete restart, rejection,
  rollback, and stale-replay assertions without reinstalling.

## Physical valid-runtime-error closure — 2026-08-23

`PHYSICAL ANDROID — MEASURED` on the same Redmi Note 10 Lite / Android 16 /
arm64-v8a target using direct Wi-Fi ADB serial `192.168.50.135:39545`. This is
a separate exact-release automatic artifact from the lifecycle record above;
the earlier lifecycle observations remain preserved without relabeling.

```text
release:       sha256:86bfc9c4ef76813ba68b8627b02d5e34938d5f11e57b79930bdf0d6f2c127809
APK:           51,967,840 bytes; SHA-256 7f34e8844f120a9a906a33ccb8e9d6db5829e02b1f554136f61fba3b92a94d7
patch:         sha256:0abb984083033cecb0257211178b78a42369635d9f5891b1f2adf8dc57f47221
patch bytes:   2,061; SHA-256 8c85a035e1ed27e9dfca5c2c06ac225406c197b920898a6fdf922c4ba55d9336
sequence:      1
function:      calculatePrice / sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361
slot:          37
fault:         instruction budget exceeded
diagnostic:    E8101
```

The patch passed exact-release compatibility, Patch Format v1 parsing,
signature/digest verification, and admission. A normal invocation then
produced the bounded runtime fault. The physical release log emitted:

```text
HYFENS_PATCH runtime fault: E0RuntimeFault E8101 in calculatePrice at package:conformance/main.dart (pc 41): Instruction budget exhausted
```

The logical URI and function/PC were reported; line/column was unavailable in
this emitted record. No absolute checkout path, temporary path, private key,
credential-bearing URL, or unbounded guest value was emitted. The process
remained alive, the failing slot was disabled, and the existing AOT guard
returned the documented fallback behavior (quantity: 7, price: 630). No
boot loop or lifecycle corruption was observed. The exact same generated
Patch Format v1 artifact also passed the host
`experiments/patch_loading/test/cli_runtime_fault_test.dart` regression, which
asserts slot disable, one bounded `E8101` diagnostic, and fallback result.

This closes the mandatory physical runtime-error isolation assertion. Direct
delivery of stale valid bytes after rollback and replacement retention while a
healthy patch is active remain untested physically, as required by the closure
scope.

## Current disposition — 2026-08-23

Task 34's mandatory Android assertions are complete. The historical
`path_provider_android 2.2.23` pin evidence is preserved; the later current
fixture's `2.3.1` dependency also passed the current Redmi Note 10 Lite /
Android 16 fixture lifecycle and did not reproduce the historical JNI/bootstrap
failure. This is a bounded fixture result, not universal Android support.

The final physical measurement series is recorded by Task 35. No emulator,
Flutter SDK modification, production transport, or store-compliance claim was
used.
