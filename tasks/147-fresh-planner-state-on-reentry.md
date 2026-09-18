# Task 147 — Fresh planner state on default re-entry

Status: [x] Completed

## Goal

Ensure a default planning-form entry starts blank and disabled after a
previous prefilled plan was submitted, while preserving prefilled Discover and
Trips handoffs.

## Scope and Non-goals

Scope:

- add the smallest reset/initialization operation to the existing planner
  notifier;
- invoke it when the shared planning sheet opens without an initial
  destination;
- preserve the existing deferred prefilled-destination initialization;
- add exactly one local app widget regression test covering prefilled submit,
  Settings navigation, and default planning-form re-entry;
- verify the default destination field is empty and `Create planning brief` is
  disabled, while the submitted confirmation remains observable.

Non-goals:

- changing draft persistence, submission APIs, trip creation, navigation
  design, date handling, or validation rules;
- changing Discover or Trips prefilled handoff behavior;
- changing dependencies, assets, fixtures, permissions, platform code,
  integration tests, devices, simulators, Docker, AWS, hosting, or deployment;
- adding a separate planner state-management abstraction or broad refactor.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 146 latest-search-result-wins coverage;
- existing `WaypointPlannerNotifier`, `WaypointPlannerState`, and
  `waypointPlannerProvider`;
- existing shared `WaypointPlanningSheet` and Settings `Open planning form`
  action;
- existing prefilled Discover planning flow and stable planner keys;
- existing `pumpWaypointTestApp` local app test seam.

## Assumptions

- the non-auto-disposed planner provider is the reason state can outlive a
  closed planning sheet;
- a default entry is identified by an empty `initialDestination`;
- resetting only the default entry will not overwrite a non-empty prefilled
  destination, which continues to be initialized after the first frame;
- the worker owns only the two production files and the existing app test file
  listed below;
- a production issue outside this bounded lifecycle behavior is reported
  rather than expanding scope.

## Work Items

- [x] Inspect the planner provider lifetime, submit path, shared sheet entry,
  Settings action, existing handoff coverage, and prior task boundaries.
- [x] Add the narrow planner reset and default-entry initialization.
- [x] Add exactly one local widget regression test for submit then default
  re-entry.
- [x] Review the owned source/test changes for lifecycle correctness,
  prefilled-handoff preservation, exact assertions, determinism, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome, validation evidence, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/application/waypoint_planner_notifier.dart`
  `lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze`
  `lib/waypoint/application/waypoint_planner_notifier.dart`
  `lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"default planner entry resets after a submitted prefilled plan"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported three files
  and zero changes; scoped analysis reported no issues; the named regression
  test passed once; and the full app widget test passed all thirty-eight tests.
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended three-file write set and
post-correction observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_planner_notifier.dart` —
  SHA-256 `97b401887044b716fa4dd04240861b27360d58ccae768ebe3d3d9be5a72249a2`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart` —
  SHA-256 `4717c68da868efb0282296430aa072bc37ab9fcccd34fd2ba3e44ad30b1e965d`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `7549f2e294752a1acf1b28e34160b1a22d2e507fceda069a976f386124272553`
- `testWidgets` declarations in `waypoint_app_test.dart` — `38`, including
  exactly one Task-147-named case.

The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. Default planning-sheet entries now reset synchronously before modal
construction, so the first frame is blank with submission disabled after a
prior prefilled submission. Non-empty Discover and Trips handoffs retain their
post-frame prefilled initialization. Strict review initially rejected the
deferred empty reset; the verified correction passed re-review. No unrelated
production, dependency, asset, platform, external-service, or deployment
behavior changed.

## References

- `tasks/141-empty-trips-planning-cta-coverage.md`
- `tasks/142-populated-trips-planning-cta-coverage.md`
- `tasks/146-latest-search-result-wins.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_planner_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_providers.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Nietzsche the 3rd performed a read-only source audit after Task
  146 and recommended this bounded lifecycle regression. The audit found that
  the planner provider is non-auto-disposed, `submit()` does not reset state,
  the default sheet entry has an empty controller but reads validity from
  persisted provider state, and existing blank-form tests use fresh provider
  scopes. No external blocker was proven.
- 2026-08-29: Sartre the 3rd strictly reviewed the implementation and returned
  REJECT. The reviewer verified that the post-frame empty-entry reset permits a
  first-frame stale enabled submit state, while the settled assertion misses
  it. The coordinator also confirmed Task 134 evidence that synchronous
  mutation from `initState` previously triggered a Riverpod build-time error;
  correction is assigned to reset from the shared event helper before modal
  construction and to add a first-frame assertion.
- 2026-08-29: Arendt the 3rd applied the correction only in the three reserved
  paths. The reset now runs through `ProviderScope.containerOf` before modal
  construction, the non-empty mounted-guarded post-frame handoff remains, and
  the existing single Task-147 test asserts the first frame before settling.
  The worker reported scoped formatting, analysis, named-test, and full-file
  checks passing.
- 2026-08-29: Sartre the 3rd re-reviewed the corrected paths and returned
  ACCEPT. The review verified lifecycle safety, exact first-frame assertions,
  preservation of prefilled Discover/Trips flows, scope, and the recorded
  three-path manifest.
- 2026-08-29: Coordinator reran the planned changed-file validation: format
  exited 0 with three files unchanged, scoped analysis exited 0 with no issues,
  the named test passed once, and the full app widget test exited 0 with all
  thirty-eight tests passing.
