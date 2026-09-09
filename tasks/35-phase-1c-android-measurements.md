# Task 35 — Phase 1C Android measurements

Status: [x] Completed

## Goal

Produce bounded, reproducible Android dispatch, startup, memory, and binary
growth evidence required by the physical Phase 1C closure, while preserving
the existing runtime/toolchain and clearly separating measured, directional,
derived, and unavailable results.

## Scope and Non-goals

Scope: audit/reuse the existing benchmark harness; prepare or add the smallest
deterministic measurement support under `benchmarks/**`; serialize physical
Android measurements after the lifecycle worker releases the device; compare
stock, instrumented BASE, and active-patch states where directly comparable;
record methodology, samples, medians/p95, absolute/relative overhead, PSS/RSS
measurement points, APK sizes, and limitations in a focused research record
`docs/research/phase-1c-android-closure.md`.

Physical runs must not overlap Task 34's install/activation sequence. The
coordinator will release the device for measurement after the functional gate
or explicitly authorize a bounded measurement window. The functional Android
gate is now released by the fresh Task 37 run; no measurement series has yet
been collected.

Non-goals: changing runtime semantics, Patch Format v1, capability v1,
production profiling infrastructure, cloud/product work, Phase 1D, emulator
substitution for the physical gate, unsupported precision claims, or final
`docs/PHASE_1C_REVIEW.md` edits.

## Owner

`Faraday` (`01a029dd-0abe-7152-9b9c-6ba4bb474949`), a coordinator-assigned
`gpt-5.6-luna` max/fast measurement worker, owns only its focused benchmark
support, research record, and this task file; it must not modify
controller/lifecycle code, Task 34, Task 31, completed Tasks 32/33, or final
review documents.

## Dependencies

- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_PHYSICAL_ANDROID_CLOSURE.md`;
- completed Tasks 32 and 33;
- Task 34's physical device identity/release baseline or coordinator handoff;
- existing `benchmarks/` harness and Phase 1C performance report;
- same fixture/toolchain family for stock/instrumented comparisons.

## Assumptions

- the worktree is shared; preserve unrelated user changes and do not commit;
- no measurement result is valid without an evidence label and methodology;
- process/device noise must be reported rather than attributed to the runtime;
- no Android emulator result satisfies the physical Android gate;
- if the device is unavailable, prepare the harness/report and record the
  external blocker instead of inventing data.

## Work Items

- [x] Read the supplied physical-closure and completed Task 32/33 documents;
  audit the current benchmark harness and existing Phase 1C measurements.
- [x] Define a bounded Android measurement protocol covering direct/native AOT,
  instrumented unpatched, and instrumented patched/interpreted dispatch, with
  warmups, iterations, sample count, median, p95 where meaningful, and
  absolute/relative reporting.
- [x] Prepare or minimally extend benchmark support under `benchmarks/**`
  without changing runtime/toolchain semantics.
- [x] After coordinator handoff, measure startup and memory for instrumented
  BASE and active patch, plus stock where directly comparable; record PSS/RSS
  point and launch methodology. The physical target is now available, but the
  series is not yet run.
- [x] Measure comparable stock/instrumented APK bytes and calculate absolute
  and percentage growth; investigate only material regression from the
  directional Phase 1B ~6.07% result. No fresh comparison values are
  fabricated.
- [x] Write `docs/research/phase-1c-android-closure.md` with explicit
  `MEASURED`, `DIRECTIONAL`, `DERIVED`, and `NOT MEASURED` labels and exact
  commands/device/build context.
- [x] Run task-scoped formatting, analysis, benchmark/report checks, and
  record outcomes and blockers here.

## Validation

Required validation includes the benchmark/report-specific tests or harness
checks, formatting and fatal-info analysis for changed Dart, and coordinator
review of every physical claim. Do not report physical measurements until the
coordinator has serialized access to the device after Task 34.

Completed preparation validation:

- `dart format --set-exit-if-changed benchmarks` — passed; 3 benchmark files,
  0 changes.
- `dart analyze --fatal-infos benchmarks` — passed; no issues found.
- `dart run benchmarks/phase_1c_android_measurement.dart --self-check` —
  passed; checks nearest-rank median/p95, derived dispatch/APK comparisons,
  explicit labels, missing-data behavior, and measured sample-count rejection.
- `dart run benchmarks/phase_1c_android_measurement.dart
  --template=/tmp/hyfens-phase1c-android-template.json` — passed; generated an
  empty capture shape.
- `dart run benchmarks/phase_1c_android_measurement.dart
  --input=/tmp/hyfens-phase1c-android-template.json
  --output=/tmp/hyfens-phase1c-android-not-measured.json` — passed; reduced
  report status remained `NOT MEASURED` with no fabricated values.
- `rg -n '[[:blank:]]+$'
  benchmarks/phase_1c_android_measurement.dart
  docs/research/phase-1c-android-closure.md
  tasks/35-phase-1c-android-measurements.md` — passed; no trailing whitespace.

No `adb`, `flutter build`, `tool release`, install, launch, `dumpsys`, or
physical-device command was run by this worker. No competing build was
started.

## Next Action at pre-device checkpoint

Coordinator handoff is required: acquire a physical arm64 device, finish Task
34, release the device and build directory, provide the temporary marker-
emitting benchmark surface, then collect and normalize the 15-sample
dispatch/startup/memory/APK evidence using
`docs/research/phase-1c-android-closure.md` and
`benchmarks/phase_1c_android_measurement.dart`. This worker must not begin
that device phase while the external device blocker remains.

## Blockers at pre-device checkpoint

External device blocker: Task 34 is `[-] Blocked` because no physical Android
device is available over USB, mDNS, or the historical wireless endpoint. No
physical measurement window can be authorized; stock/instrumented
comparability on-device remains unverified. Consequently all fresh Android
dispatch, startup, memory, and APK-byte evidence is `NOT MEASURED`.

## Outcome at preparation checkpoint

Prepared the bounded protocol and the dependency-free offline reducer/report
support. The reducer defines 10,000,000 dispatch iterations, 2 process
warmups, 15 timed samples, nearest-rank p95, median/MAD/min/max, absolute and
relative dispatch reporting, `am start -W` launch fields, named ready/
post-dispatch PSS/RSS points, and comparable stock/instrumented APK byte
derivation. No physical measurement was attempted; the task is blocked until
a suitable Android device is supplied.

## References

- `/Volumes/970EvoPlus/Downloads/CODEX_PHASE_1C_PHYSICAL_ANDROID_CLOSURE.md`
- `/Volumes/970EvoPlus/Downloads/32-phase-1c-completion-closure.md`
- `/Volumes/970EvoPlus/Downloads/33-phase-1c-support-hardening.md`
- `benchmarks/`
- `docs/research/phase-1c-performance.md`
- `docs/research/phase-1c-android-closure.md`
- `benchmarks/phase_1c_android_measurement.dart`
- `docs/PHASE_1C_REVIEW.md`

## History

- 2026-08-22: Reserved Task 35 as the disjoint Android measurement package
  after reading all three supplied documents. Physical execution is explicitly
  serialized behind Task 34 to avoid competing device/build state.
- 2026-08-22: Assigned to Faraday (`01a029dd-0abe-7152-9b9c-6ba4bb474949`)
  with `gpt-5.6-luna`, maximum reasoning, and priority/fast service.
- 2026-08-22: Audited the existing Phase 1B/1C host harnesses, Task 22's
  authoritative host-AOT dispatch matrix, the historical Android startup/
  memory/size observations, and the supplied Task 34/32/33 closure records.
  Confirmed that no fresh Phase 1C physical Android performance evidence
  exists.
- 2026-08-22: Added the offline Android capture reducer and prepared
  `docs/research/phase-1c-android-closure.md`. Scoped format, fatal-info
  analysis, reducer self-check, empty-template reduction, and whitespace
  checks passed. Physical execution remains serialized behind Task 34 and is
  explicitly `NOT MEASURED`.
- 2026-08-22: Task 34 reported no Android device over USB, mDNS, or the
  historical wireless endpoint. Marked the physical measurement work items
  and this task `[-] Blocked`; preparation remains complete and all fresh
  device values remain explicitly `NOT MEASURED`.
- 2026-08-22: Task 37 completed the visible automatic Android behavior gate
  on the physical Wi-Fi target. The measurement task is no longer externally
  device-blocked; it remains in progress because the current app does not emit
  the required `hotLeaf`/benchmark markers and no dispatch, startup, memory,
  or comparable APK series has been collected.

## Functional-gate clarification — 2026-08-22

Task 37's host diagnosis and controller/bootstrap fix do not satisfy the
physical Android measurement dependency. Before any measurement window opens,
the fresh automatic release must be installed and the physical app must show
the patched business result after a normal invocation/rebuild. The required
functional gate remains:

```text
BASE visible = 540
→ signed patch
→ patched slot invoked
→ visible result != 540
```

The device is currently unavailable over ADB/mDNS. This task therefore remains
`[-] Blocked`; all dispatch, startup, memory, and APK series remain
`NOT MEASURED`, and no host artifact or iOS evidence is substituted.

## Functional-gate handoff — 2026-08-22

Task 37 subsequently completed the previously blocked visible Android gate
against the automatic release: BASE `540`, signed patch invocation `651`,
restart persistence, signed rollback/base persistence, stale sequence
rejection, and invalid-payload retention were observed on the physical Redmi
Note 10 Lite. This releases the device for the measurement protocol. It does
not itself constitute a measurement result; dispatch, startup, memory, and
comparable APK series remain pending and must retain explicit evidence labels.

## Physical measurement execution and closure — 2026-08-23

Coordinator-run `PHYSICAL ANDROID — MEASURED` protocol on the connected Redmi
Note 10 Lite / Android 16 / arm64-v8a device over direct Wi-Fi ADB
`192.168.50.135:39545`. The temporary fixture was `phase1c-android-bench`,
package `dev.hyfens.androidbench`, activity `.MainActivity`, Flutter 3.47.0,
Dart 3.13.0, Release mode. The exact instrumented release was:

```text
release:       sha256:102ed130cdd1d23d03e235230dd7993486da2b0fa4598e243d80d9e2adcf90b4
build:         99853e94e9b615d9a32cc5f400bcd41b14cf9e5278f38f14538df3b657790cf1
patch:         sha256:13886ac5ef13b0bebef160b1de8d440eb6dccd4f58c91afc865d53250fd022cb
patch bytes:   1,858; SHA-256 45af9ed4c6414c7a4278c6cd0c5304bed7238894c2abf9735225c6d927f083c8
```

The physical run used two process warmups and 15 timed, process-isolated
samples for each variant. Dispatch used 10,000,000 iterations, retained all
samples, independently checked checksum `6`, and excluded launch, patch
download, verification, and activation. The normalized capture and reducer
output are preserved at
[`docs/research/evidence/phase-1c-android-2026-08-23/`](../docs/research/evidence/phase-1c-android-2026-08-23).

### Dispatch — `MEASURED` with `DERIVED` per-call comparisons

| Variant | median / p95 total (µs) | median / p95 (ns/call) | comparison |
| --- | ---: | ---: | --- |
| direct native AOT | 172,050 / 249,255 | 17.205 / 24.9255 | baseline |
| instrumented, unpatched | 202,034 / 285,360 | 20.2034 / 28.536 | +2.9984 ns/call, +17.4275% median vs direct |
| instrumented, patched/interpreted | 12,166,529 / 12,421,573 | 1,216.6529 / 1,242.1573 | +1,199.4479 ns/call, 70.715× / +6,971.5% median vs direct; 60.220× vs unpatched |

The interpreted result is a hot-loop measurement and is not a native-equivalent
performance claim. The absolute AOT dispatch delta is small in this benchmark;
application-level impact depends on invocation frequency and workload.

### Startup — `MEASURED` / `DERIVED`

`adb shell am start -W` was used after force-stop. The output did not contain
`ThisTime`, so only `TotalTime` (primary) and `WaitTime` (secondary) are
reported. These are launch-completion timings, not exact Flutter first-frame
measurements.

| Variant | TotalTime median / p95 (ms) | WaitTime median / p95 (ms) | median TotalTime vs stock |
| --- | ---: | ---: | --- |
| stock | 368 / 446 | 373 / 454 | baseline |
| instrumented BASE | 362 / 425 | 367 / 427 | −6 ms / −1.63% |
| instrumented active patch | 391 / 467 | 400 / 472 | +23 ms / +6.25% |

### Memory — `MEASURED` snapshots / `DERIVED` comparisons

`dumpsys meminfo` captured whole-process `TOTAL PSS` and `TOTAL RSS` in KiB at
`ready` and immediately after the dispatch marker. These values include the
Flutter engine/framework and device allocator noise; they are not interpreter-
only attribution.

| Point / variant | PSS median / p95 (KiB) | RSS median / p95 (KiB) | median delta vs stock |
| --- | ---: | ---: | --- |
| ready / stock | 72,755 / 87,180 | 176,860 / 191,316 | baseline |
| ready / instrumented BASE | 85,719 / 89,682 | 189,852 / 193,808 | +12,964 PSS (+17.819%); +12,992 RSS (+7.346%) |
| ready / active patch | 77,992 / 88,332 | 182,036 / 192,392 | +5,237 PSS (+7.198%); +5,176 RSS (+2.927%) |
| postDispatch / stock | 79,259 / 89,851 | 185,056 / 195,952 | baseline |
| postDispatch / instrumented BASE | 92,230 / 92,484 | 198,032 / 198,276 | +12,971 PSS (+16.366%); +12,976 RSS (+7.012%) |
| postDispatch / active patch | 87,302 / 97,608 | 193,392 / 203,704 | +8,043 PSS (+10.148%); +8,336 RSS (+4.505%) |

### APK bytes — `MEASURED` artifacts / `DERIVED` growth

The comparable build key was
`fixture=phase1c-android-bench|flutter=3.47.0|dart=3.13.0|mode=release|apk=universal|deviceAbi=arm64-v8a`.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| stock Release APK | 43,382,412 | `4ae8791cc4ed67810ede045d1b6e19bf271cd39bfafd1b15eb7bf3c1d6e2f41d` |
| instrumented Release APK | 46,659,212 | `bfa25f0daf7ea184dc14b6e9cd54932ac44105e426e485881f559e2978854250` |
| active-patch APK | 46,659,212 | same as instrumented APK; patch does not rebuild native APK |
| Patch Format v1 artifact | 1,858 | `45af9ed4c6414c7a4278c6cd0c5304bed7238894c2abf9735225c6d927f083c8` |

Instrumented minus stock is 3,276,800 bytes, or `+7.5533%`. This is a
same-fixture/toolchain/mode/ABI result, close to the earlier directional
baseline and not a universal binary-size claim.

### Reproduction and validation

The reducer was run with:

```text
dart run benchmarks/phase_1c_android_measurement.dart --input=/tmp/hyfens-phase1c-android.tL15ET/normalized/input.json --output=/tmp/hyfens-phase1c-android.tL15ET/phase-1c-android-report.json
```

The report status is `MEASURED_WITH_LIMITATIONS`; sample counts, checksums,
raw arrays, release/patch identities, APK hashes, canonical labels, medians,
nearest-rank p95, MAD, and derived comparisons passed reducer validation. The
raw log directory is retained for this workspace session at
`/tmp/hyfens-phase1c-android.tL15ET`; the normalized input and reduced report
are the durable repository evidence.

This closes Task 35. It does not claim iOS physical performance, first-frame
timing, thermal/battery behavior, interpreter-only memory attribution, or a
new universal performance threshold.
