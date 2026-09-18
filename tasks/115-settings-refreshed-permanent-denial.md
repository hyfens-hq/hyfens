# Task 115 — Settings refreshed permanent denial

Status: [x] Completed

## Goal

Verify that a refreshed `permanentlyDenied` result changes the Settings row to
the `Settings` action and routes the tap to the injected app-settings callback.

## Scope and Non-goals

Scope:

- open Settings with the existing in-memory permission service;
- change one injected permission result to `permanentlyDenied`;
- tap the production refresh key and assert the matching row shows
  `Permanently denied` and `Settings`;
- tap that row and assert the injected `openAppSettings` call is made without a
  permission request.

Non-goals:

- changing production Settings-page, notifier, or permission routing logic;
- opening real OS settings or requesting any real permission;
- Android, iOS device, simulator, AWS, Docker, or hosted deployment work;
- adding dependencies, broad flows, or unrelated coverage;
- claiming platform behavior from the injected test service.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Tasks 111–114 Settings permission wiring and refresh coverage;
- existing mutable `WaypointTestPermissionService.statuses` map and
  `openSettingsCalls` recorder;
- existing Settings widget-test harness.

## Assumptions

- a mutable injected response is sufficient to model a later refresh result;
- the test-only `openSettingsCalls` counter observes app wiring without opening
  real settings;
- the worker owns `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  for this task and must preserve existing tests;
- affected validation is limited to the changed app-test file.

## Work Items

- [x] Inspect the refresh-to-action-label and permanent-denial routing path.
- [x] Add one focused transition and callback test.
- [x] Review the task-owned test diff for scope and factual correctness.
- [x] Run only formatting and the affected app-test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart`
  completed with `Changed test/waypoint_app_test.dart` and
  `Formatted 1 file (1 changed) in 0.03 seconds.`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `00:03 +10: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 115 is complete. Reserve a local-only task covering the same refreshed
`permanentlyDenied` -> `Settings`/no-request behavior for the remaining
permissions using only the injected service. Do not invoke OS settings.

## Blockers

None known.

## Outcome

The worker added a focused test to
`fixtures/flutter_conformance_app/test/waypoint_app_test.dart` that changes the
injected Camera result to `permanentlyDenied`, refreshes Settings, scopes the
assertions to the Camera row, taps its action key, and verifies the injected
settings call increases while no Camera request is recorded. Existing tests
remain intact. Formatting changed one file and the affected app-test passed
with ten tests. Strict review accepted the implementation with no blocking
findings.

## References

- `tasks/114-settings-refreshed-status-labels.md`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_permission_notifier.dart`

## History

- 2026-08-29: Reserved Task 115 from the Task 114 strict reviewer’s next-step
  instruction. Scope is local injected-state transition coverage only; no OS
  settings or platform behavior is implied.
- 2026-08-29: Nash the 2nd (GPT-5.6 Luna Max, max reasoning, priority) added
  the refreshed permanent-denial transition test to
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
  The worker reported `Formatted 1 file (1 changed)` and `00:03 +10: All tests passed!`.
  No production or platform files were changed.
- 2026-08-29: Dalton the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the injected Camera status transition, refresh key, row-scoped
  labels, settings-call counter, no-request assertion, retained coverage, and
  validation. Result: `ACCEPT`, with no blocking findings. The reviewer
  recommended covering the same refreshed permanent-denial branch for the
  remaining permissions.
