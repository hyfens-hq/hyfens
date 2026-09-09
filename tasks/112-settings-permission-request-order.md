# Task 112 — Settings permission request order

Status: [x] Completed

## Goal

Strengthen the local Settings permission-section test with an exact request
list assertion so one tap per permission verifies order, count, and identity.

## Scope and Non-goals

Scope:

- retain the existing Settings navigation and per-row taps;
- assert the injected service's final request list exactly matches the
  expected permission sequence;
- preserve the permanently-denied Settings branch and all existing app tests.

Non-goals:

- changing production Settings-page, Riverpod, or permission-service logic;
- opening real OS settings or requesting any real permission;
- Android, iOS device, simulator, AWS, Docker, or hosted deployment work;
- adding dependencies or unrelated test coverage;
- claiming platform behavior from the injected service test.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 111 settings permission-section wiring;
- existing `WaypointTestPermissionService.requested` list and enum order.

## Assumptions

- `WaypointPermission.values` is the intended stable sequence for the existing
  Settings-page loop;
- the worker may extend the existing app test file because no other worker owns
  it;
- affected validation is limited to the changed app-test file.

## Work Items

- [x] Inspect the existing request loop and service recording behavior.
- [x] Add one exact ordered/count request-list assertion.
- [x] Review the task-owned test diff for scope and factual correctness.
- [x] Run only formatting and the affected app-test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart`
  completed with `Changed test/waypoint_app_test.dart` and
  `Formatted 1 file (1 changed) in 0.02 seconds.`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `00:03 +7: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 112 is complete. Reserve a local-only task covering the Settings
`Refresh permission status` callback and injected-service read recording. Do not
invoke OS permissions or infer platform behavior.

## Blockers

None known.

## Outcome

The worker added an exact equality assertion after the Settings permission taps
in `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`, comparing
the recorded list with `WaypointPermission.values` to verify order and count.
Existing positive checks and the permanently-denied test remain intact.
Formatting changed one file and the affected file passed with seven tests.
Strict review accepted the implementation with no blocking findings.

## References

- `tasks/111-settings-permission-section-wiring.md`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/platform/waypoint_permission.dart`

## History

- 2026-08-29: Reserved Task 112 from the Task 111 strict reviewer’s next-step
  instruction. Scope is a precise local injected-service assertion only; no OS
  or platform behavior is implied.
- 2026-08-29: McClintock the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  added the exact `permissionService.requested == WaypointPermission.values`
  assertion to `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
  The worker reported `Formatted 1 file (1 changed)` and `00:03 +7: All tests passed!`.
  No production or platform files were changed.
- 2026-08-29: Darwin the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the enum order, Settings loop, injected-service append behavior,
  retained branches, and recorded validation. Result: `ACCEPT`, with no
  blocking findings. The reviewer recommended covering the Settings refresh
  callback and injected-service reads next.
