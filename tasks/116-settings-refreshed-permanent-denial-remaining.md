# Task 116 — Remaining refreshed permanent denial coverage

Status: [x] Completed

## Goal

Complete local Settings coverage for refreshed `permanentlyDenied` results on
the permissions not exercised by Task 115.

## Scope and Non-goals

Scope:

- cover Location, Notifications, and Photo library transitions from a
  requestable status to `permanentlyDenied` after refresh;
- assert each matching row shows `Settings`;
- tap each row and assert the injected settings callback is used without a
  permission request;
- preserve Task 115 Camera coverage and all existing tests.

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

- completed Tasks 111–115 Settings permission wiring and refreshed denial
  coverage;
- existing mutable test-service status map, settings-call counter, and request
  recorder;
- existing Settings widget-test harness.

## Assumptions

- the injected service is sufficient to exercise app-level routing without OS
  interaction;
- the worker owns `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  for this task and must preserve all existing tests;
- affected validation is limited to the changed app-test file.

## Work Items

- [x] Inspect Task 115 and identify the remaining refreshed permission branches.
- [x] Add minimal coverage for Location, Notifications, and Photo library.
- [x] Review the task-owned test diff for scope and factual correctness.
- [x] Run only formatting and the affected app-test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format test/waypoint_app_test.dart` completed with
  `Formatted 1 file (1 changed)`;
- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart`
  completed with `Formatted 1 file (0 changed)`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `00:04 +11: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 116 is complete. No further mandatory permission-row work is indicated by
the review. Continue with the next meaningful local-only app gap rather than
duplicating aggregate permission coverage.

## Blockers

None known.

## Outcome

The worker added one focused loop to
`fixtures/flutter_conformance_app/test/waypoint_app_test.dart` for Location,
Notifications, and Photo library. Each injected status is refreshed to
`permanentlyDenied`, its row is checked for `Permanently denied` and `Settings`,
the action is tapped, and the injected settings-call counter is checked while
the permission remains absent from `requested`. Existing tests remain intact.
Formatting made one file change and the final affected app-test passed with
eleven tests. Strict review accepted the implementation with no blocking
findings.

## References

- `tasks/115-settings-refreshed-permanent-denial.md`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`

## History

- 2026-08-29: Reserved Task 116 from the Task 115 strict reviewer’s next-step
  instruction. Scope is local injected-state transition coverage only; no OS
  settings or platform behavior is implied.
- 2026-08-29: Boole the 2nd (GPT-5.6 Luna Max, max reasoning, priority) added
  the remaining refreshed permanent-denial loop to
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
  The worker reported one formatting change, a clean formatter check, and
  `00:04 +11: All tests passed!`. No production or platform files were changed.
- 2026-08-29: Sartre the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the three remaining transitions, production refresh key and
  permanent-denial mapping, row-scoped assertions, settings-call/no-request
  checks, retained Camera coverage, and validation. Result: `ACCEPT`, with no
  blocking findings. The reviewer found no mandatory permission-row gap and
  advised avoiding redundant aggregate coverage unless the contract requires it.
