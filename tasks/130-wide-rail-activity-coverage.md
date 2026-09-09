# Task 130 — Wide-layout rail Activity coverage

Status: [x] Completed

## Goal

Verify that the wide-layout navigation rail opens the Activity section through
its real Activity destination.

## Scope and Non-goals

Scope:

- extend the existing 1200×900 navigation-rail widget test;
- activate the real `waypoint-nav-activity` rail control;
- verify the existing `waypoint-activity-page` is shown;
- preserve the existing Saved, Discover, Trips, Settings, context, and
  narrow-layout assertions.

Non-goals:

- changing navigation rail, Activity, shell, or state production code;
- adding another viewport, visual snapshot, feed behavior, or desktop matrix;
- changing tests outside the affected app test file;
- device, simulator, Docker, AWS, or hosted-service work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 129 wide rail Settings coverage;
- existing 1200-wide rail test and `waypoint-nav-activity` key;
- existing Activity page and app widget test harness.

## Assumptions

- the current 1200×900 test remains the correct wide-layout fixture;
- `waypoint-nav-activity` is the real rail control and routes through the
  existing section selection path;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to that changed test file.

## Work Items

- [x] Inspect the wide rail test and Activity rail wiring.
- [x] Add focused rail Activity activation and destination assertions.
- [x] Preserve and review Task 121–129 coverage.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: formatting reported 0 changes and the coordinator rerun of the
  affected app test file exited 0 with all twenty-two tests passing (`+22`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 130
source-level scope as follows:

- implementation path: `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- the existing 1200-wide rail test retains its Saved, Discover, Trips, context,
  and Settings assertions and adds only the `waypoint-nav-activity` tap and
  `waypoint-activity-page` assertion at current lines 970–977;
- current SHA-256 for the app test is
  `5c9a8543498e3e901fc1dd53db0dd7d6544545b91ada869443a0cf6ca4eee9b7`;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 130 is complete. Reserve the next local-only task for Activity-feed error
recovery.

## Blockers

None known.

## Outcome

The worker updated only the existing app test, extending the 1200-wide rail
flow with the real Activity destination and Activity-page assertion. Formatting
reported 0 changes and the coordinator reran the affected app test with all
twenty-two tests passing. Strict review accepted the Activity rail interaction,
preserved coverage, scope manifest, and validation with no blocking findings or
fixes required.

## References

- `tasks/129-wide-rail-settings-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/navigation/waypoint_navigation_rail.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_activity_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 130 from the accepted Task 129 review. Scope is
  one existing wide rail Activity interaction; no production behavior change
  is implied.
- 2026-08-29: Mendel the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the owned app test file. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` passing all twenty-two tests.
- 2026-08-29: Bacon the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the real Activity rail key, wide-flow preservation,
  validation, and source-level scope manifest. Result: `ACCEPT`; no blocking
  findings or fixes required. The next instruction is Activity-feed error
  recovery.
