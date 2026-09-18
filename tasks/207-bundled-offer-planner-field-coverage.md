# Task 207: Bundled offer planner-field coverage

Status: [x] Completed

## Goal

Extend the bundled offer flow test to prove that the local `open_planner` action supplies its field labels, destination hint, initial travelers value, and traveler bounds to the planning sheet.

## Scope and Non-goals

Scope:

- Extend only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Reuse the existing bundled time-limited offer test.
- After tapping the bundled offer CTA, assert the action-defined labels `Where to?`, `When?`, and `Travellers`.
- Assert the action-defined destination hint `City, coast, or countryside` and initial travelers value `2`.
- Exercise the declared traveler range and assert the increase control disables at `6` and the decrease control disables at `1`.

Non-goals:

- No production code, fixture data, assets, dependencies, task files beyond this record, or platform changes.
- No changes to planner behavior, action decoding, date selection, submission, or hero-entry coverage.
- No new test support source, device, simulator, Docker, AWS, hosting, or deployment work.
- No unrelated test-file or repository-wide test changes.

## Owner

GPT-5.6 Luna Max worker, priority/fast service; coordinator integrates the result. A separate GPT-5.6 Luna Max reviewer owns the strict fact-based review.

## Dependencies

- Bundled `open_planner` action in `assets/data/actions.json`.
- Existing AlphaX local data source and zero-latency demo transport.
- Existing `WaypointPlanningSheet` field and traveler-control keys.
- Existing bundled time-limited offer test.

## Assumptions

- The bundled offer action remains `open_planner`/`bottom_sheet` and is loaded into the home payload.
- The planner consumes the action fields only when their IDs/types and required labels are valid.
- The current action declares destination placeholder `City, coast, or countryside`, initial travelers `2`, minimum `1`, and maximum `6`.
- The repository has no resolvable Git `HEAD`; review evidence will use direct current-file/source evidence rather than a fabricated commit diff.

## Work Items

- [x] Reserve Task 207 and document the evidence-backed bundled offer/planner scope.
- [x] Extend the existing bundled offer test with action-field and traveler-bound assertions.
- [x] Perform self-review and strict independent review against the task and current source.
- [x] Run scoped formatting, analysis, the named test, and the complete changed app test file; record results.
- [x] Mark the task complete only after all findings and required validation pass.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart
flutter analyze test/waypoint_app_test.dart
flutter test test/waypoint_app_test.dart --plain-name "bundled local demo renders its time-limited offer"
flutter test test/waypoint_app_test.dart
```

Results on 2026-08-30: format passed (`Formatted 1 file (0 changed)`), scoped analysis passed (`No issues found!`), the named test passed (`+1`), and the complete changed app test file passed (`+70`). Only the changed app test file and its directly exercised Flutter test target were in scope. No device or Docker validation was required for this test-only change.

## Next Action

Continue with a read-only audit for the next concrete source-backed local fixture gap; reserve a new task only when the gap and validation boundary are confirmed.

## Blockers

None.

## Outcome

Test-only extension of the bundled time-limited offer test. The test now asserts the actual action-defined planner labels, destination hint, initial traveler count, and min/max traveler control behavior without changing production code or fixtures.

## References

- `fixtures/flutter_conformance_app/assets/data/actions.json:6-15` — bundled planner action fields and traveler bounds.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:343-356` — local action payload loading.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:158-168` — offer CTA passes the validated planner action.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart:90-155` — action field labels, destination hint, and traveler configuration consumption.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart:248-295` — traveler controls and min/max behavior.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:351-399` — bundled test `bundled local demo renders its time-limited offer` now covers offer content/CTA, action fields, and traveler bounds.
- Read-only audit by Einstein the 5th on 2026-08-30 — confirmed the bundled offer/planner coverage gap and no production change is needed.
- Strict review by Faraday the 5th on 2026-08-30 — ACCEPT, no findings.
- Final validation on 2026-08-30 — all commands in the Validation section passed.

## History

- 2026-08-30: Reserved serial Task 207 after direct source/test audit; implementation pending.
- 2026-08-30: Luna Max worker extended the bundled offer test with action-defined labels/hint/initial value and traveler min/max assertions.
- 2026-08-30: Strict review found stale task metadata only; coordinator updated the current implementation state and reference.
- 2026-08-30: Coordinator recorded Faraday the 5th's strict acceptance and the final scoped validation results; task completed.
