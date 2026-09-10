# E1 Android results

Date: 2026-08-22

Host/toolchain: macOS arm64, stock Flutter 3.47.0 stable, Dart 3.13.0. Device:
physical Redmi Note 10 Lite, Android 16/API 36, arm64. Command:

```sh
./scripts/e1_android_physical.sh 192.168.50.135:39323
```

The checked-in `lib/main.dart` SHA-256 was
`0630c4bc496ad99040d816db0572865587aec5427673eee25627cb1b9952fa87`
before and after analyzer-guided overlay generation. The overlay reported one
instrumented and zero excluded top-level functions. A first compile attempt
failed before install because the relocated entrypoint's relative bootstrap
import was absent; the E1 overlay tool was corrected to copy that isolated
dependency beside the ephemeral entrypoint. The subsequent pass produced a
stock-Flutter release APK and completed the device sequence.

## Device evidence

| Stage | UI/observed behavior |
| --- | --- |
| Baseline | `BASE AOT`, quantity 6, tier 1, price 540 |
| State change | Quantity increased to 7 before activation |
| Patch | `PATCH ACTIVE`, quantity still 7, tier 1, price 525 |
| Invalid input | `status: rejected`; patch remained active and price remained 525 |
| Rollback | `BASE AOT`, quantity still 7, price returned to 630 |

This is a meaningful branch/control-flow change: baseline quantity 7 takes the
bulk branch (`7 * 90`), while the patch takes its changed bulk branch (`7 * 75`).
The checked-in and patch source are both normal Dart functions. The app was not
reinstalled between any of these transitions.

The package timestamps captured immediately after the script's sole install and
again after activation/rejection/rollback were byte-for-byte identical:

```text
lastUpdateTime=2026-08-22 01:22:43
firstInstallTime=2026-08-22 01:22:43
```

## Single-run measurements

These are observations from one device run, not performance claims or a
benchmark distribution.

| Measurement | Observed |
| --- | ---: |
| Release APK | 46,625,928 bytes |
| Patch | 329 bytes |
| Android cold-start `TotalTime` | 1,562 ms |
| Android cold-start `WaitTime` | 1,585 ms |
| E1 initial storage/load path | 1,044,083 us |
| Patch localhost download | 19,276 us |
| Patch validation | 160 us |
| Runtime installation | 119 us |
| Invalid-patch localhost download | 11,316 us |
| Invalid-patch rejection | 70 us |
| Post-sequence total PSS | 117,970 KB |
| Post-sequence total RSS | 213,104 KB |
| Post-sequence swap PSS | 738 KB |

The APK uses Flutter's generated debug signing configuration for this local
release-mode experiment. This recorded device run predates Task 15 patch
envelope signing, so it is not device evidence for the new Ed25519 path. No
store readiness, crash-loop health, cross-device performance, or broad Dart
compatibility conclusion follows from this run.

## Task 15 host signing evidence

Task 15 adds deterministic Ed25519 envelopes, app-configured public-key trust,
durable dual-copy/checksummed sequence state, pending-health confirmation,
equal-sequence equivocation rejection, local last-known-good/base recovery, and
an offline keygen/sign CLI. Host tests cover the RFC
8032 known-answer vector, exact-byte deterministic signing, CLI roundtrip,
valid/tampered/wrong-key/malformed/partial/unsigned candidates, signed invalid
or incompatible E0 bytes, sequential activation, restart, stale/equivocating
sequences, runtime failure recovery, higher-sequence signed rollback behavior,
base rollback with retained high-water, corrupt current recovery, orphan temp
files, faulting pending restart recovery, concurrent activations, caller-buffer
mutation, content-addressed artifact repair, pure-Dart key rotation/retirement,
state-write failure injection, missing/torn/corrupt/predecessor-inconsistent
state, CLI path/overwrite/size/permission rules, redirect rejection, and
fail-closed durable-state loss. No Task 15 device run has occurred.

```text
experiments/patch_loading: dart format bin lib test  PASS
experiments/patch_loading: dart analyze              PASS
experiments/patch_loading: dart test                 PASS (25 tests)
experiments/instrumentation: dart analyze            PASS
experiments/instrumentation: dart test               PASS (158 tests)
```

## Earlier device-run validation

```text
experiments/patch_loading: dart analyze              PASS
experiments/patch_loading: dart test                 PASS (6 tests)
fixtures/flutter_conformance_app: flutter analyze   PASS
fixtures/flutter_conformance_app: flutter test ...  PASS (2 tests)
stock Flutter Android release build                 PASS
physical single-install/no-reinstall sequence       PASS
```
