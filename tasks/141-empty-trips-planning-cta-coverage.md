# Task 141 — Empty Trips planning CTA coverage

Status: [x] Completed

## Goal

Prove through the real Trips flow that an empty local trip collection renders
the empty state and opens a blank planning form from its planning CTA.

## Scope and Non-goals

Scope:

- add one stable key to the existing empty-Trips `Plan a trip` button;
- add exactly one local app widget test for the empty Trips branch;
- inject a home payload whose only changed field is an empty `trips` list;
- verify the empty-state copy and absence of the Kyoto trip card;
- activate the keyed CTA and verify the existing blank planning sheet opens
  with its submit control disabled.

Non-goals:

- changing populated Trips, trip detail, planner rules, persistence, assets,
  dependencies, support fixtures, or integration tests;
- changing copy, layout, navigation, or planner behavior beyond the stable key;
- claiming that a blank planner submission creates a trip;
- testing devices, simulators, Docker, AWS, hosting, or deployment.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 140 permission request-result coverage;
- existing `WaypointTestDataSource(home: ...)` and `pumpWaypointTestApp`;
- existing bottom-navigation Trips control;
- existing `WaypointTripsPage._EmptyTrips` and planning sheet.

## Assumptions

- cloning `waypointTestHomePayload()` and replacing only `home['trips']` with
  an empty list preserves the rest of the valid local home fixture;
- the stable key `waypoint-trips-empty-plan` is added only to the existing
  empty-state `Plan a trip` button;
- the worker owns only
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect, if exposed, is reported rather than expanding this
  bounded package.

## Work Items

- [x] Inspect the empty Trips branch, CTA, fixture seam, planner entry, and
  prior task boundaries.
- [x] Add the stable CTA key and focused local empty-Trips widget coverage.
- [x] Review the task-owned source and test changes for factual assertions,
  determinism, and scope.
- [x] Run only formatting for the two changed files, the named widget test,
  and the full changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"empty Trips state opens a blank planning form"`;
- `flutter test test/waypoint_app_test.dart`;
- worker validation reported formatting clean for both files, the named test
  passing once, and the full app widget test file passing thirty-three tests;
- coordinator post-review formatter check exited 0 and reported two files
  with zero changes;
- coordinator post-review named widget test exited 0 with one test passing;
- coordinator post-review full widget test exited 0 with all thirty-three tests
  passing (`+33`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

This checkout has no valid `HEAD` and repository files are untracked, so a Git
historical diff cannot establish provenance. The coordinator records that
limitation explicitly. Task 140 captured the app-test SHA-256 immediately
before Task 141 as
`aef3637157662ee0aaef07a0cf3d21722dde5d15cc5e6f55719517cbab9d951d`.
No pre-Task-141 hash for the Trips screen was recorded, so its historical
change provenance is likewise unavailable.

- Current production screen SHA-256:
  `4aa65cb9f375da8069b05ffd58ce02474c76c7a316d0f784ec90cb5d8b9bef15`.
- Current app-test SHA-256:
  `f7549274c30dc628164450676cb6697e6db09b2b08746f46ce77f86f8a54ed6e`.
- The current app test source contains thirty-three `testWidgets`
  declarations and exactly one Task 141-named case.
- The worker reported only the two owned code/test paths changed; coordinator
  status for the scoped paths shows those paths and this task record as
  untracked. Any repository-wide historical provenance beyond these direct
  observations is unavailable until a valid baseline exists.

## Next Action

Task 141 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The empty Trips branch now has a stable planning CTA key and one local widget
test. The test injects an empty trip list, verifies the real empty-state copy
and absent Kyoto card, opens the existing planner, and proves the blank
destination leaves submit disabled. Strict review returned `ACCEPT` with no
blocking findings, and coordinator final scoped validation passed the named
test and all thirty-three app widget tests. No unrelated production behavior
or platform behavior was changed or claimed.

## References

- `tasks/99-waypoint-demo-app.md`
- `tasks/121-saved-unsave-empty-state.md`
- `tasks/132-surface-all-trips.md`
- `tasks/140-permission-request-result-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Euler the 3rd performed a read-only source audit after Task
  140. The audit found that `WaypointTripsPage` returns `_EmptyTrips` for an
  empty trip list and renders a planning CTA without a stable key, while
  current coverage exercises populated Trips only. Task 132 explicitly
  excluded the empty state, and Task 121 covers Saved rather than Trips. Task
  141 is limited to one CTA key, one app widget test, and local validation.
- 2026-08-29: Hume the 3rd added only the requested stable empty-Trips CTA key
  and one local widget test. The worker reported formatting clean for both
  owned files, the named test passing once, and the full app widget test file
  passing thirty-three tests. No support, dependency, asset, task, platform,
  Docker, AWS, hosting, or device file was changed.
- 2026-08-29: Pascal the 3rd independently reviewed the empty branch, key-only
  production change, local empty payload, real Trips navigation, empty-state
  assertions, blank planner, disabled submit control, one-case scope, and
  documented no-`HEAD` limitation. Result: `ACCEPT`; no blocking findings.
- 2026-08-29: Coordinator final validation passed: the scoped formatter exited
  0 with zero changes for both owned files, the named empty-Trips widget test
  passed once, and `flutter test test/waypoint_app_test.dart` exited 0 with all
  thirty-three tests passing. Task 141 is complete; no device, simulator,
  Docker, AWS, hosting, or deployment validation was needed.
- 2026-08-29: Coordinator reconciled the overall status marker with the
  already-completed work items, validation, and outcome. No task scope or
  implementation content changed.
