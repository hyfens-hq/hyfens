# Task 98 — Physical iOS dispatch-throughput evidence

Status: [x] Completed — bounded physical iOS dispatch-throughput evidence accepted; broader performance gates remain open

## Goal

Close only the documented iOS dispatch-throughput evidence gap with one
bounded, opt-in benchmark on the already verified physical iPhone. The result
must distinguish stock/direct, instrumented-unpatched, and active-patch paths
using captured checksums, fixed call counts, exact device/build identity, and
conservative statistics. It must not be presented as a universal iOS or
production performance claim.

## Scope and Non-goals

Scope:

- add a fixture-only compile-time-gated dispatch benchmark mode;
- measure the three declared variants with the same workload, call count,
  warmup policy, and timer boundary;
- capture two untimed warmups and 15 timed samples per variant, retaining every
  sample plus median and nearest-rank p95;
- use the existing public runtime/patch seams and existing USB/XcodeBuildMCP
  workflow only; do not add runtime or compiler hooks;
- write a schema-validated report to the app's USB-readable Documents area and
  reduce/validate it locally;
- run one fresh physical USB campaign on the named iPhone after code review;
  and
- update the Phase 1D research/condition records only from the captured result,
  with the device-specific boundary and all skipped dimensions explicit.

Non-goals: RSS/heap, Allocations, thermal, battery, long soak, power-loss,
first-frame or Flutter-frame performance, Android, independent-app evidence,
AWS, hosted deployment, Shorebird runtime/compiler parity, CLI/dashboard
changes, production/store claims, or runtime/compiler modifications.

## Owner

The coordinator owns the fixture benchmark, reducer, runner integration, local
validation, device serialization, physical run, evidence integration, and task
closure after the delegated implementation workers returned incomplete. A
separate GPT-5.6 Luna Max reviewer owns the strict code/spec review. A separate
evidence reviewer must review the final raw run before completion. No commit is
authorized.

## Dependencies

- current `fixtures/flutter_conformance_app` and its existing patch bootstrap;
- existing public E0/runtime benchmark seams and Patch Format v1 composer;
- `xcodebuildmcp` device workflow and `ios-deploy -W` USB transfer;
- physical iPhone USB UDID `00008020-001528860E03002E`;
- CoreDevice ID `CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F`; and
- development team `CYT7A4VAZ3`.

## Assumptions

- all three variants run on the same named device, build, workload, and
  fixed-count invocation protocol;
- the benchmark must record the exact callable path for each variant; a path
  that cannot be demonstrated as stock/direct, instrumented-unpatched, or
  active-patch is reported `NOT MEASURED`, not renamed for convenience;
- two warmups are untimed and excluded from the 15 reported samples;
- timing uses a monotonic in-process timer around only the repeated dispatch
  loop; build, install, patch loading, USB transfer, and report I/O are
  excluded;
- generated device evidence remains disposable under `.dart_tool`; durable
  reports contain no signing seed, bearer token, private key, or secret; and
- no Dart/Flutter test is run for unchanged files. Local validation is limited
  to the changed benchmark, fixture wiring, runner, reducer, and docs.

## Work Items

- [x] Inspect the documented P1D-04 gap, existing benchmark conventions,
  current fixture wiring, and physical-device prerequisites.
- [x] Implement the opt-in fixture benchmark mode with explicit variant labels,
  fixed call count, checksums, warmups, samples, and schema output.
- [x] Implement the local reducer/self-check and USB/XcodeBuildMCP runner with
  explicit device identity, one install boundary, and no simulator fallback.
- [x] Run changed-file format/analyze/self-check validation only.
- [x] Complete independent strict code/spec review and fix blocking findings.
- [x] Run exactly one fresh physical USB campaign after review; if preflight or
  assertions fail, record `NOT RUN`/the actual failure and stop.
- [x] Verify raw report identity, variant semantics, sample counts, checksums,
  medians/p95, process/install boundary, and report transport.
- [x] Update the Phase 1D research/condition records only from accepted
  evidence; retain resource/thermal/battery/soak gaps.
- [x] Complete independent strict evidence review and final scoped validation.

## Validation

Planned validation is limited to the task-owned changed scope:

- `xcodebuildmcp --help`, `xcodebuildmcp tools`, and relevant device command
  help before any iOS build/run action;
- `bash -n scripts/e1_ios_dispatch_throughput.sh`;
- `dart format --output=none --set-exit-if-changed` on the new reducer,
  benchmark source, and changed fixture wiring;
- `dart analyze` on the new reducer and `flutter analyze` on only the changed
  fixture Dart files;
- `dart run benchmarks/ios_dispatch_throughput_reducer.dart --self-check`;
- one fresh USB/XcodeBuildMCP run using the explicit UDID/CoreDevice/team and a
  unique run ID; and
- direct assertions over the resulting report, raw receipt/launch/install
  evidence, device/build identity, and documentation claim boundary.

No AWS, hosted deployment, simulator, unrelated package test, full repository
test suite, or unchanged-file test is authorized by this task.

## Next Action

Stop at maintainer review. No AWS, hosted, production, or broader performance
claim is authorized by this task.

## Blockers

None currently. The physical run remains dependent on the named iPhone staying
connected/unlocked and the existing local signing/XcodeBuildMCP workflow
remaining available. Any disconnect, build/signing failure, unsupported
variant path, or report assertion failure must be recorded as the actual
outcome rather than converted into a performance claim.

## Outcome

Implementation, local validation, strict code review, one accepted physical
USB run, raw evidence review, Phase 1D documentation update, and final scoped
consistency review are complete. The result is a device/run-specific
dispatch-throughput record only; it cannot close resource, thermal, battery,
soak, power-loss, independent-app, production, or hosting gates.

## References

- `tasks/51-ios-diagnostics-and-performance-rerun.md`
- `tasks/97-current-source-ios-physical-evidence.md`
- `docs/product/phase-1d-conditions.md`
- `docs/research/phase-1d-performance.md`
- `benchmarks/phase_1c_android_measurement.dart`
- `benchmarks/phase_1d_performance_benchmark.dart`
- `fixtures/flutter_conformance_app/lib/main.dart`
- `fixtures/flutter_conformance_app/lib/patch_bootstrap.dart`
- `scripts/e1_ios_cross_feature.sh`
- `xcodebuildmcp-cli` skill at `/Users/princeteck/.agents/skills/xcodebuildmcp-cli/SKILL.md`

## History

- 2026-08-28: Task 98 reserved as the next monotonic task number after the
  documented gap review found no other non-AWS pending task. Curie identified
  the missing iOS dispatch-throughput evidence in Task 51 and the P1D-04
  condition record. No files were changed by the gap review.
- 2026-08-28: The initial delegated implementation and runner workers returned
  incomplete without changes. The coordinator completed the bounded reducer,
  fixture readiness marker, compile-time-gated main wiring, and USB runner in
  the task-owned paths. Scoped checks passed: Dart format, `dart analyze` for
  the reducer, reducer self-check, Flutter analysis for `main.dart` and the
  fixture benchmark library, and `bash -n` for the runner. McClintock's strict
  read-only review accepted the four-path slice with no blocking findings after
  requiring a run-derived report path and an unconditional exact-bundle
  uninstall. Physical evidence remains pending.
- 2026-08-28: The first campaign attempt reached local overlay and E0 patch
  compilation but stopped before build/install/launch because the runner passed
  one program to `e1_patch_format_batch.dart`, which factually requires at
  least two programs (`FormatException: multi-function evidence requires two
  programs`). The run root is
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T172907Z`;
  no device evidence or performance claim was produced. The runner was
  corrected to compose the existing price and async E0 programs, and the code
  review gate was reopened.
- 2026-08-28: The fresh reviewed campaign reached USB readiness, uploaded the
  Patch Format v1 artifact, built/installed/launched/stopped the iPhone app, and
  captured `report.v1.json`. The reducer rejected the report because active
  patch samples serialized negative `elapsedNanoseconds` while retaining
  positive `elapsedTicks`; the captured values prove 64-bit multiplication
  overflow in the conversion, not a negative timer. Run root:
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173136Z`.
  No performance claim was accepted. The fixture conversion was changed to
  quotient/remainder arithmetic and the reducer now checks the conversion
  against timer frequency; strict review is required again before a fresh run.
- 2026-08-28: Feynman's strict re-review accepted the overflow correction. The
  fresh run `task98-ios-dispatch-usb-20260828T173915Z` then completed with
  successful Release/device build, exact-bundle uninstall/install, USB launch,
  readiness-marker upload handshake, report transport, process stop, raw
  assertions, and reducer acceptance. The iPhone XR/iOS 18.7.9 USB identity is
  recorded in
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/flutter-devices.json`
  and
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/ios-deploy-detect-usb.txt`;
  Release/device build and arm64 are recorded in
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/build.json`
  and
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/architectures.txt`;
  the empty JIT scan is
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/jit-artifacts.txt`;
  and uninstall/install/launch/stop are recorded in
  `fixtures/flutter_conformance_app/.dart_tool/e1_ios_dispatch_runs/task98-ios-dispatch-usb-20260828T173915Z/evidence/uninstall.txt`,
  `install.txt`, `launch.json`, and `stop.json`. Medians/p95 were recorded for
  all three variants; the raw and reduced evidence remain under the run's
  `.dart_tool` evidence directory.
- 2026-08-28: Erdos independently accepted the raw evidence and instructed the
  coordinator to update the Phase 1D research/condition records while retaining
  all skipped dimensions. Those records were updated with the exact run
  identity, measurements, hashes, and claim boundary. Final scoped validation
  and task closure remain pending.
- 2026-08-28: Copernicus' final strict review found only stale task-record
  markers: Status, the final review work item, Outcome, and closure language
  still said the accepted evidence was pending. The coordinator corrected
  those fields to `[x] Completed` and retained the maintainer-review boundary.
- 2026-08-28: The coordinator's final read-only consistency assertions passed
  for the completed status, work-item markers, required task sections, raw and
  reduced evidence paths, and the Phase 1D documentation claim boundary. No
  additional tests or builds were run because this closure check changed no
  source files.
