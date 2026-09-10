# Task 138 — Planning date-range picker coverage

Status: [x] Completed

## Goal

Prove through the real planning form that opening the date-range picker,
cancelling it, and confirming a valid future range produce the expected
visible control state.

## Scope and Non-goals

Scope:

- add one focused app widget test for the existing `waypoint-plan-dates`
  control;
- open the existing planning sheet through a current application action;
- verify the native Flutter `DateRangePickerDialog` opens;
- cancel once and prove the prior date label is unchanged;
- reopen the picker, select a runtime-derived valid future range using
  semantic full-date labels, confirm it, and verify the displayed range.

Non-goals:

- changing production planner, date-rule, or state-management behavior;
- changing test support, dependencies, assets, persistence, or APIs;
- testing native platform picker behavior, device behavior, Docker, AWS,
  hosting, or deployment;
- expanding the existing pure date-rule coverage from Task 119.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 137 local demo-data reload coverage;
- existing planning entry action and `waypoint-plan-dates` control;
- existing `pumpWaypointTestApp` fixture;
- Flutter's in-process `DateRangePickerDialog` semantics.

## Assumptions

- runtime-derived dates will be selected within the picker bounds from its
  current date through 730 days later;
- semantic full-date labels are used so the test does not depend on ambiguous
  bare day numbers;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect, if exposed, is reported rather than expanding this
  test-only package.

## Work Items

- [x] Inspect the planning form, date control, existing notifier path, fixture
  seam, and prior task exclusions.
- [x] Add focused local date-range picker widget coverage in the owned test
  file.
- [x] Review the task-owned test for factual assertions, determinism, and
  scope.
- [x] Run only formatting and the changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart`;
- worker's initial widget test run exited 0 with thirty tests passing (`+30`),
  while its format check reported one file requiring formatting;
- coordinator applied that scoped formatting fix after strict review;
- coordinator post-review format check exited 0 and reported one file with
  zero changes;
- coordinator post-review widget test exited 0 with all thirty tests passing
  (`+30`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository file is untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 138 scope directly:

- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `fd2c6192a4ca8625d8a7bc5f8ba8b72e17419738cac6e9b94258d5952cb508ac`;
- the app test source contains exactly thirty `testWidgets` cases;
- the intentional code change is limited to that app test file; this task
  record is the only additional package artifact.

## Next Action

Task 138 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The real planning sheet date control is now covered end to end in one local
widget test: it opens the in-process date picker, cancellation preserves the
previous label, and a valid runtime-bounded range selected through full-date
semantics updates the localized control label. Strict review returned `ACCEPT`
with no blocking findings, and the coordinator's final scoped validation
passed all thirty app widget tests. No production or platform behavior was
changed or claimed.

## References

- `tasks/119-planning-form-boundaries.md`
- `tasks/135-discover-prefilled-submit-coverage.md`
- `tasks/137-settings-demo-data-reload-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_planner_notifier.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Lorentz the 2nd performed a read-only source audit after Task
  137. The audit found that the planning form wires `Dates` to
  `_DateRangeButton`, which opens `showDateRangePicker` and forwards confirmed
  dates, while current tests cover whitespace, travelers, and style but not
  picker behavior. Task 119 and Task 135 explicitly exclude this gap. Task
  138 is limited to one app widget test file and local Flutter validation.
- 2026-08-29: Plato the 2nd added one focused date-range picker widget test in
  the owned app test file. The worker reported the widget test passing all
  thirty tests; its format check reported one file requiring formatting. No
  production, support, task, dependency, asset, Docker, AWS, hosting, or
  device file was changed.
- 2026-08-29: Hume the 2nd independently reviewed the real planner entry,
  picker dialog, cancellation, bounded semantic date selection, localized
  output, thirty-test count, and one-file scope. Result: `ACCEPT`; no blocking
  findings. Hume's next action was for the coordinator to format and rerun
  the same two scoped checks.
- 2026-08-29: Coordinator applied the worker-reported formatting fix only to
  the owned app test, then ran the final scoped format check and widget test.
  Formatting exited 0 with zero changes and the widget test exited 0 with all
  thirty tests passing. Task 138 is complete; no device, simulator, Docker,
  AWS, hosting, or deployment validation was needed.
