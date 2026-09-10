# Task 134 — Discover planning handoff coverage

Status: [x] Completed

## Goal

Prove the existing Discover destination detail flow closes its detail sheet and
opens the planning form with the selected destination prefilled.

## Scope and Non-goals

Scope:

- add one focused app widget test using the existing local test harness;
- open the Kyoto destination card from Discover;
- verify the destination detail sheet and its plan action;
- verify the planning sheet opens with `Kyoto` already in the destination
  field and the existing submit action enabled.
- if the regression test exposes the confirmed provider-lifecycle defect,
  apply the smallest lifecycle-safe fix in the existing planning sheet so the
  handoff works without a build-time provider mutation.

Non-goals:

- broad changes to the already-wired Discover, destination-card, or navigation
  production code;
- redesigning planner state management; only the confirmed planning-sheet
  lifecycle defect may be corrected in this task;
- changing persistence, repository behavior, models, test support, assets,
  dependencies, or API contracts;
- adding planning validation scenarios already covered by existing tests;
- device, simulator, Docker, AWS, hosting, or deployment work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 133 Activity cancellation coverage;
- existing Discover destination card key and detail action;
- existing `showWaypointPlanningSheet` handoff and planner state;
- existing `pumpWaypointTestApp` local fixture.

## Assumptions

- the current Discover detail action is the production path under test;
- the new regression test has proven a concrete defect: the planning sheet
  mutates `waypointPlannerProvider` from `initState`, so the minimal fix may
  include the planning sheet path;
- the existing planner submit button becomes enabled from the prefilled
  destination without re-entering text;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` and, for the
  verified lifecycle fix,
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`;
- affected validation is limited to formatting those two files and running the
  changed app widget test file.

## Work Items

- [x] Inspect the Discover card/detail route, planning handoff, and existing
  planning tests.
- [x] Add focused Discover-to-prefilled-planner widget coverage that exposes
  the provider-lifecycle defect.
- [x] Apply the smallest lifecycle-safe planner initialization fix proven by
  the regression test.
- [x] Review the task-owned source/test changes for factual assertions and
  scope.
- [x] Run only formatting and the changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart`;
- worker and strict reviewer reported formatting with two files and zero
  changes, and the app test passing all twenty-six tests (`+26`);
- coordinator post-review validation: `dart format --output=none
  --set-exit-if-changed lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart
  test/waypoint_app_test.dart` reported two files with zero changes;
- coordinator post-review validation: `flutter test
  test/waypoint_app_test.dart` exited 0 with all twenty-six tests passing
  (`+26`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository files are untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 134 scope directly:

- planner sheet path:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`;
  SHA-256 `79278528892adf3ba1c0c6b510e8fbbdda89a3b51ee465ddca81b93dbe316f37`;
- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `3d6db62faec32fc1c2338cfd27898ce6100b753a095655c07640e34248487c24`;
- the app test source contains exactly twenty-six `testWidgets` cases;
- the task-owned status is limited to these two paths and this task record;
  no unrelated file was modified by the package.

## Next Action

Task 134 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The Discover handoff regression test exposed the existing planning sheet's
build-time provider mutation. Kepler the 2nd applied the minimal fix by
deferring the non-empty initial destination write with a post-frame callback
and a mounted guard. The final test proves the real destination detail action
transitions to a planner with `Kyoto` in its controller and an enabled submit
action. The worker, strict reviewer, and coordinator validation all report
twenty-six app widget tests passing. Strict review returned `ACCEPT` with no
blocking findings. The only limitation recorded is the checkout's missing Git
`HEAD` and untracked-file state.

## References

- `tasks/133-activity-stop-cancellation-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved after Feynman the 2nd's source review. Discover already
  routes destination-card taps to a detail bottom sheet and exposes the keyed
  `waypoint-destination-plan` action, which opens the planner with an initial
  destination, but no test covers this end-to-end handoff. Scope is limited to
  the existing app widget test file.
- 2026-08-29: Kepler the 2nd added the focused handoff test. The coordinator's
  direct run reproduced Riverpod's `Tried to modify a provider while the widget
  tree was building` from `WaypointPlanningSheet.initState` calling
  `setDestination`; the planning field was not mounted and the 26-test file
  reported two failures because of the resulting widget-tree exception. The
  verified production fix is limited to deferring that initialization safely
  in the planning sheet.
- 2026-08-29: Kepler the 2nd applied the verified planner fix in the planning
  sheet and preserved the handoff test. The worker reported scoped formatting
  with zero changes and all twenty-six app tests passing. No other production
  or task file was modified.
- 2026-08-29: Huygens the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  independently reviewed the real Discover-to-planner route, the post-frame
  mounted guard, preservation of empty-destination behavior, regression-test
  strength, and the two-path scope. Result: `ACCEPT`; no blocking findings or
  fixes required. The only limitation recorded is the checkout's missing Git
  `HEAD` and untracked-file state.
- 2026-08-29: Coordinator final validation passed: scoped formatting reported
  two files with zero changes, and `flutter test test/waypoint_app_test.dart`
  passed all twenty-six tests. Task 134 is complete; no device, simulator,
  Docker, AWS, or hosted-service validation was needed.
