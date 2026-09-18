# Task 140 — Permission request result coverage

Status: [x] Completed

## Goal

Prove through the real Settings permission flow that a requestable permission's
service result reaches the notifier and updates the visible permission row.

## Scope and Non-goals

Scope:

- add exactly one focused app widget test in the existing Waypoint app test
  file;
- use the existing local `WaypointTestPermissionService`;
- open Settings through the real app control;
- set the fake location request result to `granted`;
- activate the existing `waypoint-permission-location` request control;
- verify the row visibly changes to `Granted`, keeps the `Test` action label,
  and records the location request.

Non-goals:

- changing production Settings, notifier, or permission-row code;
- changing test support, dependencies, assets, persistence, or APIs;
- testing OS prompts, physical devices, simulators, refresh ordering,
  permanent denial, Docker, AWS, hosting, or deployment;
- expanding the existing permission status matrix or isolated row tests.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 139 Trips-to-planner handoff coverage;
- existing `pumpWaypointTestApp` fixture;
- existing `WaypointTestPermissionService.statuses` and request recording;
- existing requestable location row and stable key.

## Assumptions

- the local fake permission service returns the current value in its mutable
  `statuses` map when its request method is called;
- `WaypointPermissionStatus.granted` is rendered as `Granted` and the
  requestable row keeps its `Test` action label;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect, if exposed, is reported rather than expanding this
  test-only package.

## Work Items

- [x] Inspect the Settings request callback, permission notifier, row label,
  fake service seam, and prior permission task boundaries.
- [x] Add focused local permission request-result widget coverage in the owned
  test file.
- [x] Review the task-owned test for factual assertions, determinism, and
  scope.
- [x] Run only the named changed-file test, full changed app widget test file,
  and formatter.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"updates a permission row after request returns a new status"`;
- `flutter test test/waypoint_app_test.dart`;
- worker validation reported the formatter passing with one file and zero
  changes, the named test passing once, and the full app widget test file
  passing thirty-two tests;
- coordinator post-review formatter check exited 0 and reported one file with
  zero changes;
- coordinator post-review named widget test exited 0 with one test passing;
- coordinator post-review full widget test exited 0 with all thirty-two tests
  passing (`+32`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

This checkout has no valid `HEAD` and repository files are untracked, so a Git
historical diff cannot establish provenance. The coordinator records that
limitation explicitly. The completed Task 139 record captured the app-test
SHA-256 immediately before Task 140 as
`0cc65b29d25abaa435e759779ab277528c64314b84942e2fea4ccbc7b8a818e0`.

- Worker-owned path: `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Coordinator's current SHA-256 after the Task 140 test:
  `aef3637157662ee0aaef07a0cf3d21722dde5d15cc5e6f55719517cbab9d951d`.
- The current source contains thirty-two `testWidgets` declarations, with
  the Task 140 case named `updates a permission row after request returns a
  new status`.
- The worker reported only the app test path changed; coordinator status for
  the scoped paths shows the app test and this task record as untracked. Any
  repository-wide historical provenance beyond those direct observations is
  unavailable until a valid baseline exists.

## Next Action

Task 140 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The real Settings permission request-result path is covered in one local
widget test. It observes the initial Denied location row, changes the local
fake service result to Granted, invokes the real request control, and verifies
the same row renders exact Granted and Test labels while recording the request.
Strict review returned `ACCEPT` with no blocking findings. Coordinator final
scoped validation passed the named test and all thirty-two app widget tests.
No production or platform behavior was changed or claimed.

## References

- `tasks/105-settings-permission-row-coverage.md`
- `tasks/113-settings-permission-refresh-coverage.md`
- `tasks/114-settings-refreshed-status-labels.md`
- `tasks/115-settings-refreshed-permanent-denial.md`
- `tasks/116-settings-refreshed-permanent-denial-remaining.md`
- `tasks/139-trips-adjust-plan-handoff-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_permission_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_permission_row.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Pasteur the 3rd performed a read-only source audit after Task
  139. The audit found that Settings calls the permission notifier, the
  notifier awaits the service result and updates state, and the row renders
  the result label, while current Settings coverage records request calls but
  does not verify the visible post-request state. Existing fake service state
  mutation makes this a local-only one-test package. Tasks 105–116 cover row
  details, refresh ordering, and refreshed/permanent-denial statuses, not this
  request-result transition. Task 140 is limited to one app widget test file.
- 2026-08-29: Dewey the 3rd added exactly one local permission request-result
  widget test in the owned app test file. The worker reported the formatter
  passing, the named test passing once, and the full app widget test file
  passing thirty-two tests. No production, support, task, dependency, asset,
  Docker, AWS, hosting, or device file was changed.
- 2026-08-29: Euclid the 3rd independently reviewed the Settings entry,
  initial Denied row, mutable fake-service result, notifier update, exact
  Granted/Test labels, request recording, stable finders, one-case scope, and
  the no-`HEAD` provenance limitation. Result: `ACCEPT`; no blocking findings.
  Final coordinator validation remains pending.
- 2026-08-29: Coordinator final validation passed: the scoped formatter exited
  0 with zero changes, the named permission widget test passed once, and
  `flutter test test/waypoint_app_test.dart` exited 0 with all thirty-two tests
  passing. Task 140 is complete; no device, simulator, Docker, AWS, hosting,
  or deployment validation was needed.
