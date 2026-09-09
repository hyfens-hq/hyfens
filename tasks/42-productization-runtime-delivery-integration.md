# Task 42 — Productization runtime delivery integration and P1D-02 closure

Status: [x] Completed

## Goal

Connect the existing Flutter/E1 runtime to the already-approved authenticated
`packages/control_plane` `/v1` lookup/fetch contract, then prove that service
availability does not replace local runtime correctness and that direct stale
bytes are rejected by the runtime high-water/replay boundary.

## Scope and Non-goals

Scope: a bounded authenticated runtime delivery adapter; exact service
lookup/fetch identity; transport-only checks before handing bytes to E1;
host integration tests; failure/outage behavior; a safe fixture-only stale-byte
delivery seam; authenticated local end-to-end evidence; physical Android
activation/restart/outage/rollback/stale-byte evidence; and a physical iOS
attempt when the existing signed-device environment permits it.

Non-goals: changing Architecture B, Patch Format v1, capability v1,
state-v4 trust/high-water, signed rollback, fail-closed recovery, runtime
signature authority, or AOT fallback; changing `tool serve`; adding service
features; managed cloud/CDN; dashboards; telemetry; rollout/cohorts; billing;
enterprise/authentication providers; managed KMS/HSM; React Native; or store
submission.

## Owner

Coordinator. No commit is authorized. Preserve Task 41 and all prior Phase
0/0B/1A/1B/1C/1D evidence.

## Dependencies

- `tasks/41-productization-p0-p1-foundation.md`;
- `packages/control_plane/` authenticated local service;
- `packages/flutter_integration/` generated runtime bootstrap;
- `experiments/patch_loading/` E1 controller and durable state;
- `fixtures/flutter_conformance_app/` signed physical fixture;
- existing Android Wi-Fi and iOS USB validation scripts/evidence;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK41_RUNTIME_INTEGRATION_P1D02_CLOSURE.md`.

## Assumptions

- The control plane remains cryptographically untrusted and only transports
  exact bytes; E1 repeats all Patch Format v1, signature, release,
  capability, function, sequence, and health checks.
- A read-only application/environment delivery credential is extractable and
  must never be treated as a signing or control-plane write credential.
- The existing runtime storage and process lifecycle can retain current,
  last-known-good, base, and high-water state when delivery fails.
- A stale-byte test seam may exist only in the fixture/integration path and
  must not create a normal unauthenticated force-delivery endpoint.
- Physical device availability and Xcode/Android tooling may gate evidence;
  unavailable evidence is recorded as `ENVIRONMENT-GATED`, not inferred.

## Work Items

- [x] Reserve this focused runtime-integration task without adding product
  features or changing frozen protocol/runtime boundaries.
- [x] Implement the authenticated lookup/fetch adapter at the existing
  Flutter integration/runtime boundary.
- [x] Validate delivery credential read-only scope and redaction behavior.
- [x] Add host tests for decisions, transport failures, truncation, wrong
  identity/platform, high-water filtering, and service outage before/during
  fetch.
- [x] Extend local E2E through authenticated runtime verification, activation,
  health, restart persistence, signed rollback, and outage behavior.
- [x] Add a fixture-only stale-byte response override and test direct E1
  high-water rejection without weakening normal eligibility.
- [x] Run the physical Android primary sequence and capture evidence without
  recording credentials.
- [x] Attempt the corresponding physical iOS sequence when feasible and label
  only observed results as `PHYSICAL IOS`.
- [x] Update Task 41, the product review, local service guide, threat model,
  Phase 1D conditions, and research log with evidence labels.
- [x] Run consolidated affected regressions and stop at maintainer review
  before any P2 work.

## Validation

Planned validation: Dart formatting and analysis; control-plane, CLI, Patch
Format, runtime, patch-loading, Flutter-integration, fixture, and root tests;
credential/tenant/immutability regressions; authenticated local runtime E2E;
service-outage tests; stale/equivocation/wrong-release rejection; physical
Android; and physical iOS if environment-gated conditions permit.

Evidence labels are `UNIT`, `INTEGRATION`, `END_TO_END_LOCAL`, `PHYSICAL
ANDROID`, `PHYSICAL IOS`, `ENVIRONMENT-GATED`, or `NOT RUN`. Credentials and
private signing material must not appear in logs or committed evidence.

Executed 2026-08-23:

- `dart format` on affected Dart source/tests: passed, no changes.
- `dart analyze packages/flutter_integration cli/lib
  fixtures/flutter_conformance_app/lib` and `packages/control_plane`: passed.
- `packages/flutter_integration`: 17 tests passed, including authenticated
  service lookup/fetch, outage retention, rollback, wrong identity/platform,
  transport failures, and exact stale-byte E1 rejection.
- `cli`: `dart test -j 1` passed, 39 tests, including the real CLI → local
  service → E1 deployment E2E. An initial parallel run had one transient
  macOS `objective_c.dylib` codesign failure; the isolated test and serial full
  suite passed.
- `packages/control_plane`: 8 tests passed; `experiments/patch_loading`: 59
  passed with 2 existing skips; fixture `flutter test`: 18 passed; root
  `dart analyze` and `dart test`: passed; shell syntax checks passed.
- `PHYSICAL IOS`: generated stock Flutter Release IPA built/installed once
  with team `CYT7A4VAZ3`; authenticated patch changed receipt 540→450,
  restart and service-outage retention passed. Direct USB cross-feature run
  `ios-task42-usb-20260823-r2` passed invalid-signature rejection, rollback,
  exact stale-byte rejection, and restart persistence.
- `PHYSICAL ANDROID`: the explicit Wi-Fi device
  `192.168.50.135:38657` (physical Redmi Note 10 Lite, Android 16/API 36)
  passed the direct cross-feature sequence and the generated authenticated
  service path. The final generated arm64 Release APK was installed once;
  the authenticated signed 2,069-byte patch changed the fixture receipt
  `540→450`, survived restart, and survived a stopped control-plane process.
  Package install timestamps remained unchanged. The direct run also passed
  invalid-signature rejection, rollback, exact stale-byte rejection, and
  rollback persistence. Evidence is in
  `docs/research/evidence/task42-android-control-plane.md` and the two
  redacted `.dart_tool` evidence directories.
- Android fixture post-run validation: `dart format --output=none
  --set-exit-if-changed lib/main.dart` passed; `dart analyze lib` passed with
  one intentional `avoid_print` info for the fixture-only log receipt; and
  `flutter test --no-pub` passed (18 tests).

## Next Action

Stop for maintainer review. The bounded Task 42 implementation is complete;
do not start P2/cloud work or expand the runtime scope from this task.

## Blockers

None for the bounded Task 42 scope. Phase 1D beta/production conditions,
performance campaigns, independent-application coverage, power-loss testing,
and store-policy review remain open and are not silently closed by this
fixture result.

## Outcome

The bounded adapter and authenticated local E2E are implemented. Host tests
proved authenticated lookup/fetch, exact-byte handoff to E1, decision/error
handling, wrong platform/release rejection, outage retention, and direct stale
high-water rejection. A stock Flutter iOS Release/arm64 IPA built with the
AUVANA team (`CYT7A4VAZ3`) installed once on the physical iPhone; its generated
bootstrap fetched an authenticated patch over the Mac's private LAN, changed
the ordinary pricing function from 540 to 450, persisted across restart, and
remained active after the service process was stopped. The corresponding
stock Flutter Android arm64 Release APK ran on the physical Wi-Fi device;
its generated bootstrap changed the same ordinary function from 540 to 450,
persisted it across restart and service outage, and the direct Android run
also passed UI/Riverpod/async, invalid-signature, rollback, and stale-byte
gates. Task 42 is complete for the bounded local scope and stops at
maintainer review; P2/cloud work remains prohibited.

## References

- `tasks/41-productization-p0-p1-foundation.md`;
- `docs/PRODUCTIZATION_P0_P1_REVIEW.md`;
- `docs/product/local-control-plane.md`;
- `docs/security/productization-threat-model.md`;
- `packages/control_plane/`;
- `packages/flutter_integration/`;
- `experiments/patch_loading/`;
- `fixtures/flutter_conformance_app/`;
- `docs/research/evidence/task42-ios-control-plane.md`;
- `docs/research/evidence/task42-android-control-plane.md`;
- `/Volumes/970EvoPlus/Downloads/CODEX_TASK41_RUNTIME_INTEGRATION_P1D02_CLOSURE.md`.

## History

- 2026-08-23: Reserved Task 42 as the next unused task number after the
  explicit runtime-integration/P1D-02 closure instruction. Scope is limited
  to the existing authenticated delivery contract and physical evidence; no
  product-service expansion is authorized.
- 2026-08-23: Implemented the authenticated Flutter delivery adapter and
  runtime build-define propagation. Added host/service tests and a real
  CLI-to-control-plane-to-E1 activation E2E; all passed without exposing the
  delivery credential in release metadata.
- 2026-08-23: Fixed generated bootstrap qualification so the aliased Flutter
  integration import is used for control-plane configuration. A stock Flutter
  iOS Release IPA then built and installed with team `CYT7A4VAZ3`.
- 2026-08-23: Physical iOS direct USB cross-feature run `ios-task42-usb-20260823-r2`
  passed base, business/async/UI/Riverpod patches, invalid signature rejection,
  signed rollback, exact stale-byte rejection, restart persistence, and
  high-water retention. The generated authenticated iOS bootstrap run changed
  the receipt price 540→450, survived restart, and survived service outage.
  Runtime delivery used the Mac private-LAN endpoint because `iproxy` is a
  host-to-device tunnel and cannot reverse-forward the app's request to the
  host; installation remained USB/xcodebuildmcp.
- 2026-08-23: Android retry was environment-gated: no ADB or mDNS device was
  visible and the known Wi-Fi endpoints refused connection. No Android
  authenticated-runtime result is claimed.
- 2026-08-23: Consolidated serial validation passed after the generated
  bootstrap alias fix; Task 42 was stopped as `BLOCKED` on the external Android
  transport, pending maintainer review. No P2/cloud work was started.
- 2026-08-23: The Android Wi-Fi device became available as
  `192.168.50.135:38657`. The first fresh cross-feature attempt exposed a
  fixture routing mistake: passing `usbDirectory` to Android Wi-Fi mode sent
  receipts to an inaccessible local file. The call was corrected, and fresh
  run `android-task42-wifi-20260823-r2` passed all direct stages, including
  invalid-signature rejection, rollback, exact stale-byte rejection, and
  restart persistence.
- 2026-08-23: The generated Android authenticated path then passed with a
  stock arm64 Release APK, `tool release android` → `tool patch` → `tool deploy`,
  a 2,069-byte signed patch, receipt `540→450`, restart persistence, service
  outage retention, and unchanged package install timestamps. Task 42 is now
  marked completed for its bounded scope; all wider Phase 1D and store-policy
  conditions remain visible.
