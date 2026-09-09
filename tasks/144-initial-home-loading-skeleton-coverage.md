# Task 144 — Initial home-loading skeleton coverage

Status: [x] Completed

## Goal

Prove locally that the real Waypoint shell displays its production loading
skeleton while the initial home response is pending, then transitions to the
existing Discover content when the local response resolves.

## Scope and Non-goals

Scope:

- create a test-only `WaypointDataSource` wrapper that gates only `/api/home`
  with a `Completer` and delegates other behavior;
- add exactly one app widget test for the initial pending-to-loaded transition;
- assert `WaypointLoadingPage` is visible and Discover is absent while gated;
- release the gate and assert the existing Discover page and Kyoto content.

Non-goals:

- changing `WaypointHomeNotifier`, `WaypointLoadingPage`, reload behavior,
  error/retry behavior, skeleton animation, or production code;
- changing test support, dependencies, assets, integration tests, or task
  records;
- claiming network latency, native rendering, device behavior, or platform
  behavior;
- testing search, permissions, trips, planning, video, Docker, AWS, hosting,
  or deployment.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 143 local video-preview coverage;
- existing `WaypointDataSource`, `WaypointRepository`, and
  `WaypointTestDataSource` seams;
- existing `pumpWaypointTestApp` helper;
- existing `WaypointLoadingPage` and Discover keys.

## Assumptions

- the test-only wrapper gates only the initial `/api/home` call and delegates
  all other data-source methods to a local `WaypointTestDataSource`;
- a `Completer` gate and explicit release provide deterministic pending-state
  control without sleeps or timing assumptions;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_loading_data_source.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- the gate is always released in teardown so no test can leave a pending
  future behind.

## Work Items

- [x] Inspect the home notifier, shell loading branch, production skeleton,
  fixture seams, and prior loading/retry task boundaries.
- [x] Add the test-only gated source and focused initial-loading widget
  coverage.
- [x] Review the owned source/test changes for factual assertions,
  determinism, cleanup, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the
  full changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_loading_data_source.dart` `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_loading_data_source.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"shows the home loading skeleton until initial data resolves"`;
- `flutter test test/waypoint_app_test.dart`;
- worker validation reported formatting clean for both files, scoped analysis
  with no issues, the named test passing once, and the full app widget test
  file passing thirty-five tests;
- coordinator post-review formatter check exited 0 and reported two files
  with zero changes;
- coordinator post-review analyzer exited 0 with no issues;
- coordinator post-review named widget test exited 0 with one test passing;
- coordinator post-review full widget test exited 0 with all thirty-five tests
  passing (`+35`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

This checkout has no valid `HEAD` and repository files are untracked, so a Git
historical diff cannot establish provenance. The coordinator records that
limitation explicitly. Task 142 captured the app-test SHA-256 before the later
Task 143 package and before Task 144 as
`017801747d0ce5f5f1887132d0d04083333092dac2eea12c08aac6407d80089b`.
No pre-Task-144 hash for the new loading-source file was recorded.

- Current loading data source SHA-256:
  `431d0a81d044e2f18e7123983782aea9a88419cde725d0a6402ab16e40433697`.
- Current app-test SHA-256:
  `53cf3f6cdbd0a88984004b323484024c930bf989c534a9e1c331e2b0fc8235df`.
- The app test source contains thirty-five `testWidgets` declarations and
  exactly one Task 144-named case.
- The worker reported only the new loading source and app test changed;
  coordinator status for the scoped paths shows those paths and this task
  record as untracked. Any repository-wide historical provenance beyond these
  direct observations is unavailable until a valid baseline exists.

## Next Action

Task 144 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The initial Waypoint home load is now covered with a completer-gated local data
source. The test proves the real loading skeleton is visible while `/api/home`
is pending, then proves the existing Discover page and Kyoto content appear
after release. Strict review returned `ACCEPT` with no blocking findings, and
coordinator final scoped validation passed analysis and all thirty-five app
widget tests. No production or platform behavior was changed or claimed.

## References

- `tasks/99-waypoint-demo-app.md`
- `tasks/100-android-device-overflow-fix.md`
- `tasks/117-home-load-failure-retry.md`
- `tasks/137-settings-demo-data-reload-coverage.md`
- `tasks/143-waypoint-video-preview-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_home_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: McClintock the 3rd performed a read-only source audit after
  Task 143. The audit found that the initial home load awaits the repository,
  the shell maps pending state to `WaypointLoadingPage`, and the production
  skeleton has no deterministic Waypoint widget coverage. Existing checks cover
  retry and eventual data, not the pending transition. Task 144 is limited to
  one gated test source and one app widget test, with no production changes.
- 2026-08-29: Beauvoir the 3rd created the completer-gated test source and
  added exactly one initial-loading widget test. The worker reported clean
  formatting, no analyzer issues, one named test passing, and the full app
  widget test file passing thirty-five tests. No production, task, dependency,
  asset, integration, Docker, AWS, hosting, device, or simulator file was
  changed.
- 2026-08-29: Halley the 3rd independently reviewed the data-source contract,
  `/api/home` gate, delegation, idempotent teardown release, pending/loaded
  assertions, no-timer behavior, one-test scope, and documented no-`HEAD`
  limitation. Result: `ACCEPT`; no blocking findings.
- 2026-08-29: Coordinator final validation passed: the scoped formatter exited
  0 with zero changes for both files, scoped analysis reported no issues, the
  named loading widget test passed once, and `flutter test
  test/waypoint_app_test.dart` exited 0 with all thirty-five tests passing.
  Task 144 is complete; no device, simulator, Docker, AWS, hosting, or
  deployment validation was needed.
