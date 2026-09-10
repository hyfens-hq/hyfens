# Task 37 — Phase 1C Android patch-application debug

Status: [x] Completed

## Goal

Reproduce and explain why a CLI-generated Patch Format v1 artifact can be
admitted and reported healthy on physical Android while the visible pricing
behavior remains the BASE AOT value, implement only the proven minimal fix,
add focused regressions, and rerun the required physical Android lifecycle.

## Scope and Non-goals

Scope: trace the target pricing function from source discovery and release
instrumentation through function identity/slot metadata, generated wrapper,
runtime registry/controller admission, interpreter invocation/result, and
fixture state/UI rendering. Reproduce the admitted-but-not-applied mismatch on
host first, classify hypotheses, fix the smallest proven layer, then validate
the physical Android behavior and the required lifecycle safety cases.

Non-goals: Task 35 performance measurements before visible patched behavior is
proven; Architecture B changes; Patch Format v1 or capability v1 changes;
Flutter/Dart forks; broad language/widget expansion; global Flutter/ADB/SDK
changes; cloud/product work; Phase 1D; iOS as an Android substitute; store or
policy-compliance claims; and rewriting historical Task 34 or Phase 1C
evidence.

## Owner

Coordinator owns final integration, physical evidence acceptance, Task 34 and
Phase 1C review updates. Read-only investigation packages are delegated to
independent `gpt-5.6-luna` max agents with disjoint responsibility boundaries.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/34-phase-1c-physical-android-closure.md`;
- `/Volumes/970EvoPlus/Downloads/PHASE_1C_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_ANDROID_BEHAVIORAL_APPLICATION_CLOSURE.md`;
- completed Tasks 31–36;
- the installed/reproducible Android conformance fixture and current v1
  release/patch evidence;
- a connected physical arm64 Android device for final behavioral validation;
- Patch Format v1, capability v1, and the controller-owned state-v4 trust /
  high-water journal remaining unchanged.

## Assumptions

- The prior Android observation is an admitted-but-not-applied behavior
  mismatch, not evidence of a protocol or architecture failure.
- An established ADB serial remains authoritative while its state is `device`;
  mDNS is discovery only.
- A fresh release/install is required if the fix changes release-side
  instrumentation, bootstrap, or runtime integration. A patch-only fix may
  reuse the installed release only when compatibility is demonstrated.
- No app reinstall or data clear occurs after a fresh BASE is established
  during the lifecycle sequence.
- Health/admission evidence is kept distinct from patched-slot invocation and
  visible UI evidence.

## Work Items

- [x] Read and preserve the supplied Task 34, Phase 1C review, and behavioral
  closure instruction.
- [x] Trace the target function identity, release slot, generated wrapper,
  runtime registry, controller admission, interpreter invocation, and result
  bridge.
- [x] Trace the conformance fixture's pricing call, state/provider path, and
  visible widget value; determine whether the UI recomputes after activation.
- [x] Reproduce the mismatch in the smallest faithful host/integration test
  without mocking away the suspected boundary.
- [x] Classify H1–H14 from the behavioral closure instruction with evidence.
- [x] Implement the smallest evidence-backed fix, if a code defect is proven.
- [x] Add focused regression tests and run affected package/toolchain checks.
- [x] Rebuild/reinstall only if release-side integration changed; establish a
  fresh physical BASE and run the no-reinstall Android lifecycle.
- [x] Capture patched-slot invocation plus visible changed behavior, restart
  persistence, corrupt-artifact rejection while BASE was active, signed
  rollback/base persistence, and stale delivery-boundary rejection. Healthy
  patch replacement retention and the bounded runtime-error case remain
  separate pending items below.
- [x] Capture one bounded valid-runtime failure and verify that the host
  process remains alive with the documented fallback/error-isolation policy.
- [x] Update Task 34, Task 31, `docs/PHASE_1C_REVIEW.md`, and the applicable
  research documents with exact evidence, preserving historical sections.
- [x] Start Task 35 measurements now that visible patched behavior passes;
  the coordinator completed the physical protocol and retained explicit
  evidence labels.

## Host trace and root-cause finding — 2026-08-22

The primary visible path is:

```text
runApp
  → PriceScreenState.build
  → widget.priceCalculator(quantity, tier)
  → calculatePrice(6, 1)
  → Text('price: 540')
```

`PriceScreen` recomputes the price on every build and does not cache the
numeric result. Its status listener belongs to the archival/manual controller
created by `patch_bootstrap.dart`. The generated CLI integration creates a
separate controller asynchronously. Both controllers previously called
`E0PatchRuntime.reset()` through `E1PatchController._resetRuntime()`, while E0
slots, authorities, and sequence are process-global static state. The
generated controller could therefore clear the runtime installed by the
manual controller while the manual controller still reported `PATCH` and
`healthy`. The generated controller also had no UI status bridge to the
manual screen, so a patch admitted by the automatic path did not itself cause
that archival screen to rebuild. A natural interaction remains the intended
next-invocation boundary for the automatic integration.

The faithful regression at
`packages/flutter_integration/test/global_e0_reset_regression_test.dart`
installs a signed patch through controller A, observes changed result `450`,
then attempts controller B initialization and proves B is rejected before it
can clear A's runtime slot. The regression passed.

### Hypothesis classification

| Hypothesis | Result | Evidence |
| --- | --- | --- |
| H1 wrong function ID | REJECTED | Automatic manifest, patch, and host compiler agree on `sha256:d5a3...fe361`. |
| H2 wrong release slot | REJECTED | Automatic release and generated patch both use slot `36`; archived E1 slot `1` is a separate harness. |
| H3 wrong release baseline | REJECTED | Host verify binds the patch to release `sha256:c928...e3e94`. |
| H4 wrapper queries wrong slot | REJECTED | Transformer guard and release manifest use the same release-owned slot table; host transformed tests pass. |
| H5 runtime lookup misses installed slot | REJECTED | Single-controller host invocation returns the changed result; the apparent miss was caused by the second controller clearing E0, which is classified under H6. |
| H6 wrong runtime/registry instance | CONFIRMED | E0 is static/global while generated and manual E1 controllers independently reset/configure it. |
| H7 interpreter returns wrong result | REJECTED | Host signed patch invocation returns `450` rather than BASE `540`. |
| H8 result conversion loses value | REJECTED for the primary path | `invokeInt2` validates and returns the integer result; no silent conversion to `540`. |
| H9 caller ignores result | REJECTED | `PriceScreenState.build` assigns the calculator result to `price` and renders it. |
| H10 UI caches/precomputes value | REJECTED for primary screen | The primary screen recomputes on every build; secondary provider fixtures have separate cache semantics. |
| H11 provider/state does not recompute | REJECTED | The primary screen has no provider cache; the remaining automatic-refresh limitation is a controller/UI status-bridge issue, not provider recomputation. |
| H12 visible widget uses another function | REJECTED | `ConformanceApp` passes `calculatePrice` directly to the primary screen. |
| H13 health precedes behavioral invocation | CONFIRMED | `markHealthy()` confirms durable candidate state and does not invoke a patched business function. |
| H14 stale/current controller selects another behavior | CONFIRMED in the mixed-bootstrap fixture | Per-controller durable status can remain `PATCH` while another controller has reset the global E0 table. |

### Minimal fix

- `E1PatchController` now owns a process-local runtime lease. A conflicting
  controller fails before storage creation or E0 reset; the owner clears E0
  before releasing the lease on close.
- `HyfensFlutterIntegration.start()` now coalesces identical generated
  bootstrap calls and rejects/logs conflicting calls instead of creating
  multiple pollers/controllers.
- The conformance fixture detects the generated integration marker and does
  not initialize its archival manual controller in an automatic CLI release.
  The manual E1 evidence path remains unchanged when that marker is absent.
- The generated marker survives the E0 reset performed during asynchronous
  controller initialization; failed generated initialization closes/removes
  its controller so the process lease can be retried safely, and polling has
  an in-flight guard.

No Patch Format v1, capability v1, function identity, release identity, or
Architecture B change was made.

### Host automatic artifact evidence

```text
release:       sha256:c9283534fe98c41d1318fcb88752bfccf1c2652cae67c8d2c82e3cad64ec3e94
build:         SUCCESS; 73,037 ms; 40 functions; 24 source units
APK:           51,869,536 bytes
APK SHA-256:   1ed86cc47814be695a85771b7be2f60baeda3f671f9e596a325dad21fb88e878
function:      sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361
slot:          36
signature:     sha256:aa6467d21d029869a38918e81e867005d8b8cbfaa5edbe3a1cacf81de0edab7b
patch:         sha256:33ce3129685da9567b9ec4a82c8df9ab64f194b5a6830c30f635267130144ba0
sequence:      1
patch bytes:   2,069
key:           ed25519-8aa2e7a111444605
inspect:       Patch Format v1, slot 36, no capabilities
verify:        VERIFIED against the exact release
```

After the marker/cleanup hardening, a second fresh host artifact was built
from the restored BASE source and verified:

```text
release:       sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359
build:         SUCCESS; 125,323 ms; 40 functions; 24 source units
APK:           51,951,456 bytes
APK SHA-256:   24ec7c24875b7e2ce5f9c97020986a48bad812193f0c03d4d89b8666734fc594
patch:         sha256:e2829df698c9a185e948b12a5fb732664cf59cdd8953385a3663e6845f2c8c92
patch SHA-256: 0c8270441ffe9b270745f9ac2f7c341e34d8d29fc57436fd6304ae8f431d1a32
sequence:      1; patch bytes 2,069; function slot 36
inspect/verify: Patch Format v1; VERIFIED against the exact release
```

This remains host/build evidence. It does not establish physical Android
installation, slot invocation, visible changed behavior, or lifecycle safety.

Historical pre-closure checkpoint. These are host/build artifacts only. The
fresh APK had not been installed or
launched on Android because `adb devices -l` and `adb mdns services` are both
currently empty. No physical patched-visible result, restart, rollback, or
stale-replay assertion is claimed, and Task 35 remains blocked.

## Validation at pre-device checkpoint

Planned targeted validation before device work:

```text
affected Dart package fatal-info analysis
focused instrumentation/transformer/compiler regression
focused runtime/controller/patch-loading regression
CLI release/patch/inspect/verify checks if affected
fixture analysis
```

Host validation completed after the fix and cleanup hardening:

```text
dart format <changed Dart files>                                  PASS
dart analyze --fatal-infos in experiments/instrumentation/lib      PASS
dart analyze --fatal-infos in experiments/patch_loading/lib        PASS
dart analyze --fatal-infos in packages/flutter_integration/lib test PASS
flutter analyze --no-pub in fixtures/flutter_conformance_app     PASS
dart test packages/flutter_integration global regression           PASS (3)
dart test packages/flutter_integration all tests                   PASS (8)
dart test experiments/patch_loading controller_test.dart           PASS (32)
dart test experiments/instrumentation full suite                   FAIL: two Flutter
  overlay tests hit the known macOS native-assets/code-signing race; the
  focused reruns below passed.
dart test test/flutter_widget_overlay_v9_test.dart                PASS (1)
dart test test/flutter_stateful_overlay_v10_test.dart              PASS (1)
flutter test test/conformance_widget_test.dart                     PASS (8)
tool release android                                                   PASS
tool analyze --json                                                   PASS
tool patch --json                                                     PASS
tool inspect                                                          PASS
tool verify --release --json                                          PASS
```

The fresh automatic release/patch/inspect/verify host evidence is recorded
above. The release-side fix requires a fresh physical install; the mandatory
Android lifecycle remains pending because no device is currently reachable.

Required physical validation after a fix:

```text
BASE 540
→ signed patch admitted
→ patched slot invoked
→ visible value changes
→ restart persistence
→ invalid-signature retention
→ signed rollback to visible BASE
→ rollback persistence
→ stale-patch rejection
→ bounded runtime-error isolation
```

Task 35 dispatch/startup/memory/APK measurements are out of scope until the
visible patched behavior gate passes. Final consolidated validation must record
actual commands, totals, skips, and evidence labels; no unexecuted result may
be claimed.

## Next Action at pre-device checkpoint

Rerun the two Flutter overlay regressions serially, then reinstall the fresh
automatic APK on a reachable physical Android device and capture the required
visible patched result before any Task 35 measurements.

## Blockers

- The physical Android device may be unavailable or transport discovery may
  churn; this is an external gate and must not be replaced by an emulator or
  iOS evidence.
- The prior physical run did not capture patched-slot invocation or visible
  changed behavior, so Task 34 and Task 35 remain open.
- The current checkpoint has no ADB device or mDNS service, so the fresh
  release-side fix cannot yet be installed for the mandatory behavioral run.

## Outcome at pre-device checkpoint

Host root cause and the bounded controller/bootstrap fix are complete. The
focused host regression preserves changed result `450`, and the automatic
release/patch pipeline is valid. Physical Android visible behavior and the
remaining lifecycle are still pending; Task 35 remains blocked. Architecture
B, Patch Format v1, capability v1, and historical Phase 1C evidence remain
unchanged.

## References

- `/Volumes/970EvoPlus/Downloads/34-phase-1c-physical-android-closure.md`;
- `/Volumes/970EvoPlus/Downloads/PHASE_1C_REVIEW.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_ANDROID_BEHAVIORAL_APPLICATION_CLOSURE.md`;
- `tasks/34-phase-1c-physical-android-closure.md`;
- `tasks/31-phase-1c-runtime-hardening.md`;
- `docs/spec/patch-format-v1.md`;
- `docs/spec/capability-v1.md`;
- `docs/architecture/runtime-state-machine.md`.

## Physical Android automatic lifecycle closure — 2026-08-22

The established Wi-Fi ADB target was online as:

```text
serial:       adb-ce57506c-N761V5 (2)._adb-tls-connect._tcp
model:        Redmi Note 10 Lite (curtana)
Android:      16 / SDK 36 / eng.avanin
ABI:          arm64-v8a (device also reports armeabi-v7a, armeabi)
wifi setting: adb_wifi_enabled=1
transport:    Wi-Fi ADB with adb reverse tcp:18080 -> tcp:18080
observed:     2026-08-22T18:02:23Z
```

The fresh automatic artifact was installed once after a controlled fixture
data reset. No reinstall or data clear occurred between the BASE, activation,
restart, rollback, and stale-replay observations:

```text
release:      sha256:f574b76233a18268441011262a7bde7b414ef38e27ca231054e3c95625405359
APK:          51,951,456 bytes
APK SHA-256:  24ec7c24875b7e2ce5f9c97020986a48bad812193f0c03d4d89b8666734fc594
patch:        sha256:e2829df698c9a185e948b12a5fb732664cf59cdd8953385a3663e6845f2c8c92
patch bytes:  2,069
patch SHA-256:0c8270441ffe9b270745f9ac2f7c341e34d8d29fc57436fd6304ae8f431d1a32
sequence:     1
function:     sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361
slot:         36
key:          ed25519-8aa2e7a111444605
```

Observed physical sequence:

1. With the delivery server unavailable, the freshly launched app reported
   `healthy / base` and the UI showed `quantity: 6`, `price: 540`.
2. After the verified local server and reverse tunnel were restored, the
   generated integration admitted the signed Patch Format v1 artifact and
   logged `pendingHealth` followed by `healthy / patch`. A normal tap on the
   existing `Increase quantity` button invoked the patched slot and changed
   the visible UI to `quantity: 7`, `price: 651`.
3. After force-stop/relaunch with the same app data, the runtime logged
   `current healthy signed patch active`. The first frame remained at the
   ordinary base value until a normal rebuild boundary; the next button tap
   again produced `quantity: 7`, `price: 651`. This is restart persistence of
   the active patch, not a reinstall result.
4. `tool rollback --release <exact-release> --to base --json` produced
   `ROLLED_BACK` with `highWaterSequence: 1` and the exact patch digest. The
   runtime logged `rolledBack ... high-water retained`; after a normal rebuild
   the visible result was base behavior (`quantity: 8`, `price: 720`). After a
   second process restart and rebuild, the base result remained (`quantity: 7`,
   `price: 630`).
5. With only the rollback-control file temporarily moved aside and restored
   afterward, the old sequence-1 patch endpoint returned HTTP 404
   `NO_UPDATE`. The app logged HTTP 404 rejection while remaining in
   `mode: base`; the visible result remained `price: 630`. This proves the
   development delivery boundary withheld a stale sequence after rollback and
   that the app stayed base. It is not a direct runtime rejection of old valid
   patch bytes delivered after rollback; controller/host anti-replay tests
   cover that byte-level case.
6. A bounded local rejection server returned the existing patch with one final
   byte changed and returned no rollback control. The app repeatedly rejected
   it with `PatchFormatException(P1041): Payload digest mismatch`, remained in
   `mode: base`, and the UI remained at `price: 630`. This is a physical
   corrupt-artifact rejection while BASE was active; it does not prove
   retention of a healthy active patch after a bad replacement and does not
   claim a production transport.

The fixture's archival/manual status label remains `status: created` because
the automatic generated controller is intentionally not exposed through that
manual controller's UI listener. The accepted behavioral evidence is the
runtime lifecycle log plus the normal UI function invocation/value change,
not that archival label.

The bounded valid-runtime-error case was not run in this sequence. Task 35's
dispatch/startup/memory/APK measurement gate is now unblocked by the visible
behavior result but remains unmeasured. No iOS result is inferred from this
Android run.

## History

- 2026-08-22: Reserved Task 37 after the Android transport investigation
  established that the remaining defect is behavioral application: signed v1
  admission/health was observed while the visible fixture remained at BASE
  `price 540`. Task 35 is intentionally deferred.
- 2026-08-22: Completed the host trace, H1–H14 classification, minimal
  process-global E0 ownership fix, generated-bootstrap cleanup hardening, and
  focused regressions. The automatic release/patch host artifact passed, but
  the physical Android device was unavailable, so Task 37 remains in progress
  at the physical behavioral gate.
- 2026-08-22: After the final transport re-check still returned no ADB device
  or mDNS service, normalized the overall task status to `[-] Blocked` on the
  external physical-device dependency. Host work remains complete; no physical
  Android result or Task 35 measurement is claimed.
- 2026-08-22: The established Wi-Fi ADB target became reachable. The fresh
  `sha256:f574...5359` automatic release was installed once and physically
  demonstrated BASE `540`, signed admission/health, visible patched `651`,
  restart persistence, signed base rollback with retained high-water, base
  persistence after rollback, stale sequence rejection, and invalid-payload
  retention. The task is no longer transport-blocked; the bounded runtime
  error and Task 35 measurements remain pending.

## Coordinator closure handoff — 2026-08-23

The behavioral defect is closed and the remaining physical runtime-fault gate
was accepted separately by Task 34. The exact automatic runtime-fault artifact
used release `sha256:86bfc9c4ef76813ba68b8627b02d5e34938d5f11e57b79930bdf0d6f2c127809`,
Patch Format v1 sequence 1, patch ID
`sha256:0abb984083033cecb0257211178b78a42369635d9f5891b1f2adf8dc57f47221`,
and function slot 37. The host exact-artifact regression and the physical
`E8101` log/fallback evidence passed. Task 35's separate physical measurement
protocol also completed and is recorded in its task/research report.

The process-global E0 ownership root cause and bounded fix remain unchanged:
one process-local runtime lease, generated-start single-flight, and
automatic-fixture suppression of archival manual initialization. No protocol,
capability, Architecture B, or Flutter/Dart fork change was introduced.
