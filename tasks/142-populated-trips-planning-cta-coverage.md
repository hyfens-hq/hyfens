# Task 142 — Populated Trips planning CTA coverage

Status: [x] Completed

## Goal

Prove through the populated Trips page that its top-level `Plan a trip` CTA
opens the existing blank planning form with submission disabled until a
destination is provided.

## Scope and Non-goals

Scope:

- add exactly one local app widget test in the existing Waypoint app test file;
- use the default populated local home fixture;
- open Trips through the existing bottom-navigation control;
- verify the populated Trips page and absence of the empty-state CTA;
- activate the existing `waypoint-plan-cta` action;
- verify the blank planner destination and disabled submit control.

Non-goals:

- changing production source, adding keys, or changing the existing CTA;
- changing empty Trips, trip detail, planner logic, Discover, persistence,
  APIs, assets, or support fixtures;
- claiming that blank submission creates a trip;
- testing devices, simulators, Docker, AWS, hosting, or deployment.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 141 empty-Trips planning CTA coverage;
- existing default populated `kyoto-trip` fixture;
- existing `waypoint-bottom-navigation`, `waypoint-trips-page`,
  `waypoint-trips-empty-plan`, and `waypoint-plan-cta` keys;
- existing planning sheet destination and submit keys.

## Assumptions

- `pumpWaypointTestApp` uses the populated default fixture unless a custom
  data source is injected;
- the existing stable keys and `pumpAndSettle` are sufficient for this local
  page-to-modal transition;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect, if exposed, is reported rather than expanding this
  test-only package.

## Work Items

- [x] Inspect the populated Trips CTA, default fixture, planner entry, and
  prior task boundaries.
- [x] Add focused local populated-Trips CTA widget coverage in the owned test
  file.
- [x] Review the task-owned test for factual assertions, determinism, and
  scope.
- [x] Run only formatting, the named widget test, and the full changed app
  widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"populated Trips plan CTA opens a blank planning form"`;
- `flutter test test/waypoint_app_test.dart`;
- worker validation reported formatting clean, the named test passing once,
  and the full app widget test file passing thirty-four tests;
- coordinator post-review formatter check exited 0 and reported one file with
  zero changes;
- coordinator post-review named widget test exited 0 with one test passing;
- coordinator post-review full widget test exited 0 with all thirty-four tests
  passing (`+34`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

This checkout has no valid `HEAD` and repository files are untracked, so a Git
historical diff cannot establish provenance. The coordinator records that
limitation explicitly. Task 141 captured the app-test SHA-256 immediately
before Task 142 as
`f7549274c30dc628164450676cb6697e6db09b2b08746f46ce77f86f8a54ed6e`.

- Worker-owned path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Coordinator's current SHA-256 after the Task 142 test:
  `017801747d0ce5f5f1887132d0d04083333092dac2eea12c08aac6407d80089b`.
- The current app test source contains thirty-four `testWidgets`
  declarations and exactly one Task 142-named case.
- The worker reported only the app test path changed; coordinator status for
  the scoped paths shows the app test and this task record as untracked. Any
  repository-wide historical provenance beyond these direct observations is
  unavailable until a valid baseline exists.

## Next Action

Task 142 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The populated Trips page's existing top-level `Plan a trip` CTA is now covered
in one local widget test. The test uses the populated fixture and real Trips
navigation, verifies the empty CTA is absent, opens the existing planner, and
proves the blank destination leaves submit disabled. Strict review returned
`ACCEPT` with no blocking findings, and coordinator final scoped validation
passed the named test and all thirty-four app widget tests. No production or
platform behavior was changed or claimed.

## References

- `tasks/132-surface-all-trips.md`
- `tasks/139-trips-adjust-plan-handoff-coverage.md`
- `tasks/141-empty-trips-planning-cta-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Newton the 3rd performed a read-only source audit after Task
  141. The audit found that the populated Trips branch exposes the existing
  `waypoint-plan-cta`, while current coverage only exercises its empty-Trips
  CTA and populated trip-detail handoff. Tasks 132, 139, and 141 do not cover
  this populated page-level action. Task 142 is limited to one app widget test
  file and local validation.
- 2026-08-29: Lorentz the 3rd added exactly one populated Trips page CTA widget
  test in the owned app test file. The worker reported formatting clean, the
  named test passing once, and the full app widget test file passing thirty-
  four tests. No production, support, task, dependency, asset, platform,
  Docker, AWS, hosting, or device file was changed.
- 2026-08-29: Hegel the 3rd independently reviewed the populated default
  fixture, real Trips navigation, existing page CTA, blank planning sheet,
  disabled submit state, one-case scope, and documented no-`HEAD` limitation.
  Result: `ACCEPT`; no blocking findings. Final coordinator validation remains
  pending.
- 2026-08-29: Coordinator final validation passed: the scoped formatter exited
  0 with zero changes, the named populated-Trips widget test passed once, and
  `flutter test test/waypoint_app_test.dart` exited 0 with all thirty-four tests
  passing. Task 142 is complete; no device, simulator, Docker, AWS, hosting,
  or deployment validation was needed.
