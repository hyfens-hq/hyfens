# Task 125 — Wide-layout navigation rail coverage

Status: [x] Completed

## Goal

Verify the wide-layout shell selects the navigation rail at the production
breakpoint and that the rail supports the same Saved detail to Discover context
clearing flow as the mobile bottom navigation.

## Scope and Non-goals

Scope:

- set a wide Flutter test viewport at or above the existing 900 logical-pixel
  breakpoint;
- verify the `WaypointNavigationRail` is rendered and bottom navigation is not;
- use the real rail controls to navigate through Saved, open the saved Kyoto
  detail sheet, return to Discover, then navigate Trips -> Discover;
- verify selected context is shown after the Saved action and cleared after the
  rail navigation cycle.

Non-goals:

- changing shell, rail, bottom-navigation, or state production code;
- testing arbitrary desktop sizes, responsive redesign, or visual snapshots;
- changing existing tests outside the affected app test file;
- device, simulator, Docker, AWS, or hosted-service work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 124 selected-destination context and clearing behavior;
- existing `WaypointNavigationRail`, shell breakpoint, Saved detail action, and
  test fixture;
- existing app widget test harness.

## Assumptions

- the existing production breakpoint is `MediaQuery.sizeOf(context).width >=
  900`;
- `waypoint-nav-*` keys identify the real rail controls;
- setting and resetting `tester.view.physicalSize` and device pixel ratio is
  sufficient for a deterministic local wide-layout test;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to that changed test file.

## Work Items

- [x] Inspect the shell breakpoint, rail keys, and existing viewport-test
  cleanup pattern.
- [x] Add focused wide-layout widget coverage for rail rendering.
- [x] Exercise Saved detail context and rail-based clearing behavior.
- [x] Preserve and review Task 121–124 coverage.
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
- result: formatting reported 0 changes and the affected app test run passed
  all twenty tests (`+20`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 125
source-level scope as follows:

- implementation path: `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- the added test is the contiguous block at current lines 832–907 and is the
  only task-owned source change;
- it sets a 1200×900 test viewport, resets physical size and pixel ratio, proves
  the real navigation rail is present and bottom navigation absent, then uses
  the existing `waypoint-nav-*` keys for Saved, Trips, and Discover;
- the test confirms the selected Kyoto context appears after the Saved detail
  action and is absent after the rail Trips -> Discover cycle;
- current SHA-256 for the app test is
  `169b4abbcc4696311b69c4bbb9b18d3c25ac1c998c05b2ebfb84b364819fde13`;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 125 is complete. Reserve the next local-only task to centralize the
duplicated wide-layout breakpoint decision while preserving the current UI
behavior.

## Blockers

None known.

## Outcome

The worker updated only `waypoint_app_test.dart`, adding a wide 1200×900 test
that verifies the real navigation rail replaces bottom navigation and supports
the Saved detail context-clearing flow. Formatting reported 0 changes and the
affected app test file passed all twenty tests. Strict review accepted the
behavior, scope manifest, and validation with no blocking findings or fixes
required.

## References

- `tasks/124-selected-destination-context.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_app.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/navigation/waypoint_navigation_rail.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/navigation/waypoint_bottom_navigation.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 125 from the accepted Task 124 review. Scope is
  local wide-layout rail coverage only; no responsive production change is
  implied.
- 2026-08-29: Cicero the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the owned app test file. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` passing all twenty tests.
- 2026-08-29: Helmholtz the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the production breakpoint, viewport teardown, real rail
  controls, context clearing, validation, and source-level scope manifest.
  Result: `ACCEPT`; no blocking findings or fixes required. The next
  instruction is centralized breakpoint ownership.
