# Task 149 — Activity navigation-away cancellation

Status: [x] Completed

## Goal

Ensure an active Activity feed is cancelled when its page is left, late
streamed data cannot surface, and re-entering Activity starts idle.

## Scope and Non-goals

Scope:

- change the existing Activity provider to auto-dispose when its page no longer
  watches it;
- reuse the existing cancellation-aware local test data source;
- add exactly one app widget regression test that starts Activity, navigates
  away while the stream is gated, verifies cancellation and no late item, then
  re-enters Activity and verifies the idle `Start feed` state.

Non-goals:

- changing the Activity notifier API, stream transport, explicit Stop behavior,
  retry behavior, navigation UI, home data, or provider lifetime for other
  features;
- changing support fixtures, dependencies, assets, integration tests,
  permissions, devices, simulators, Docker, AWS, hosting, or deployment;
- adding background-feed persistence, telemetry, backoff, or a new lifecycle
  abstraction;
- adding more than one test or changing unrelated test files.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 148 persistent unavailable source regression;
- existing `WaypointActivityNotifier.ref.onDispose` cancellation hook;
- existing `waypointActivityProvider` and Activity page watcher;
- existing `WaypointActivityCancellationDataSource` gate and cancellation
  observation;
- existing bottom navigation and Activity/Trips stable keys.

## Assumptions

- the Activity provider has no other production consumers beyond the Activity
  page, so auto-dispose reflects page ownership;
- `ref.onDispose` is the intended cancellation boundary and cancelling the
  existing token prevents the gated source from emitting its late item;
- the existing AnimatedSwitcher transition can be drained with
  `pumpAndSettle` in the local widget test;
- the worker owns only
  `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_providers.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production issue outside provider lifetime or this test is reported rather
  than expanding scope.

## Work Items

- [x] Inspect Activity provider lifetime, notifier disposal cancellation, page
  consumers, gated fixture, navigation path, and prior task boundaries.
- [x] Make only the Activity provider auto-dispose.
- [x] Add exactly one local navigation-away cancellation widget test.
- [x] Review the owned source/test changes for provider lifetime, cancellation
  ordering, late-item absence, idle re-entry, determinism, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome, validation evidence, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/application/waypoint_providers.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze lib/waypoint/application/waypoint_providers.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"navigating away from Activity cancels the active feed"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported two files
  and zero changes; scoped analysis reported no issues; the named regression
  test passed once; and the full app widget test passed all forty tests.
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended two-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_providers.dart` —
  SHA-256 `b497f3f879eaff1cafdc113bbfb3546ef7350c5b0c34759c6e5b94b002f446bc`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `9cad0dc16c40e5b10f326d01e6fb0b361c62cddf1eecf9a3c47ff2f53dfaaa83`
- `testWidgets` declarations in `waypoint_app_test.dart` — `40`, including
  exactly one Task-149-named case.

The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The Activity provider now auto-disposes when its page is left, using
the existing notifier disposal hook to cancel the active stream. The local
regression test starts the feed, navigates to Trips without tapping Stop,
releases the gated source only after the transition, verifies cancellation and
absence of the late item, and confirms Activity re-entry is idle. No unrelated
production, dependency, fixture, platform, external-service, or deployment
behavior changed.

## References

- `tasks/133-activity-stop-cancellation-coverage.md`
- `tasks/148-persistent-unavailable-source-fail-closed.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_activity_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_providers.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Einstein the 3rd performed a read-only source audit after Task
  148. The audit found that `waypointActivityProvider` is always alive even
  though only the Activity page watches it, while the notifier already cancels
  its active token from `ref.onDispose`. Existing Task 133 coverage explicitly
  stops before navigating and does not cover leaving an active feed. Task 149
  is limited to the provider lifetime and one local widget regression test.
- 2026-08-29: Poincare the 3rd changed only the Activity provider declaration
  and the existing app widget test. The provider now uses Riverpod
  auto-dispose, and the test covers navigation-away cancellation and idle
  re-entry. Worker validation reported formatting, scoped analysis, the named
  test, and the full app widget test passing with forty tests.
- 2026-08-29: Peirce the 3rd strictly reviewed the two paths and returned
  ACCEPT. The review verified the valid Riverpod API, the notifier's existing
  disposal cancellation hook, gate ordering, no explicit Stop tap, late-item
  absence, idle re-entry, and the provenance limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation: format
  exited 0 with two files unchanged, scoped analysis exited 0 with no issues,
  the named test passed once, and the full app widget test exited 0 with all
  forty tests passing.
