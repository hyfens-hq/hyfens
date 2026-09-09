# Task 109 — Permission-row callback coverage

Status: [x] Completed

## Goal

Verify locally that every permission row's stable action key invokes the
callback supplied by its caller when tapped.

## Scope and Non-goals

Scope:

- cover callback invocation for Location, Notifications, Camera, and Photo
  library;
- tap each production action key in its permission context and assert the
  supplied callback is invoked;
- preserve the existing status, label, icon, and key assertions.

Non-goals:

- changing production widget behavior or permission request logic;
- requesting or resetting any real OS permission;
- Android, iOS device, simulator, AWS, Docker, or hosted deployment work;
- adding abstractions, parameterization, or dependencies unless the current
  test structure demonstrably requires them;
- claiming platform behavior from widget tests.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Tasks 105–108 permission-row widget coverage;
- existing permission-row callback and key contract.

## Assumptions

- `WaypointPermissionRow` delegates the action directly to its supplied
  `onRequest` callback;
- the worker may extend the existing permission-row test file because no other
  worker owns it;
- affected validation is limited to the changed permission-row test file.

## Work Items

- [x] Inspect the production callback/key contract and existing tests.
- [x] Add minimal callback tests for all four permissions.
- [x] Review the task-owned test diff for scope and factual correctness.
- [x] Run only formatting and the affected widget-test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format test/waypoint_permission_row_test.dart` completed with
  `Formatted 1 file (1 changed)`;
- `flutter test test/waypoint_permission_row_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: `00:01 +11: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 109 is complete. Reserve a local-only widget task for the
`permanentlyDenied`/`Settings` action callback branch. Do not invoke OS
permissions or infer platform behavior from widget tests.

## Blockers

None known.

## Outcome

The worker added one focused loop to
`fixtures/flutter_conformance_app/test/waypoint_permission_row_test.dart`.
It taps the production action key for Location, Notifications, Camera, and
Photo library and asserts that the supplied callback is invoked in each
permission context. Existing Tasks 105–108 assertions remain intact.
Formatting changed one file and the affected file passed with eleven tests.
Strict review accepted the implementation with no blocking findings.

## References

- `tasks/105-permission-row-widget-coverage.md`
- `tasks/106-remaining-permission-status-coverage.md`
- `tasks/107-permission-row-not-checked-coverage.md`
- `tasks/108-permission-row-icon-key-coverage.md`
- `fixtures/flutter_conformance_app/test/waypoint_permission_row_test.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_permission_row.dart`

## History

- 2026-08-29: Reserved Task 109 from the Task 108 strict reviewer’s next-step
  instruction. Scope is local deterministic widget interaction coverage only;
  no OS permission or platform behavior is implied.
- 2026-08-29: Arendt the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  added per-permission callback taps to
  `fixtures/flutter_conformance_app/test/waypoint_permission_row_test.dart`.
  The worker reported `Formatted 1 file (1 changed)` and `00:01 +11: All tests passed!`.
  No production, task, dependency, device, or hosted-service files were
  changed.
- 2026-08-29: Poincare the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed the callback loop, production key contract, retained Task 105–108
  coverage, and recorded validation. Result: `ACCEPT`, with no blocking
  findings. The reviewer confirmed `onRequest` is a zero-argument callback;
  the test verifies invocation in each permission context and does not claim
  argument passing. The next recommendation is coverage of the
  `permanentlyDenied`/`Settings` callback branch.
