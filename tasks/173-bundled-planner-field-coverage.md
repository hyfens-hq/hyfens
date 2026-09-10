# Task 173 — Bundled planner field coverage

Status: [x] Completed

## Goal

Make the bundled `open_planner` field metadata drive the existing planning sheet's destination/date/traveler labels and destination hint, traveler initial value, and traveler bounds, with the existing fallback behavior preserved for other callers.

## Scope and Non-goals

Scope:

- Add a small typed planner-field model for the known bundled field metadata.
- Extend `WaypointTestAction` and the existing decoder to preserve only valid, supported `open_planner` field descriptors while retaining the existing `noteField` behavior.
- Apply the bundled destination/date/traveler label and destination placeholder to the existing controls.
- Apply the bundled traveler initial value and min/max bounds through the existing planner notifier/sheet seam.
- Extend the existing real zero-latency bundled hero test with field-copy and traveler-bound assertions.

Non-goals:

- Do not edit JSON/assets, transport, repository, planner state, Discover/offer handoffs, or completed task files.
- Do not create a generic action/form engine or support arbitrary field types; support only `destination`/`text`, `dates`/`date_range`, and `travellers`/`stepper` metadata needed by this fixture.
- Do not change note-sheet/Settings behavior, date-picker rules, travel-style behavior, persistence, dependencies, devices, simulators, Docker/AWS/hosting, deployment, or tests outside `waypoint_app_test.dart`.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `actions.json` `open_planner.fields` metadata.
- Existing Task 169/172 planner action propagation into `WaypointPlanningSheet`.
- Existing planner notifier, sheet controls, local zero-latency transport, and bundled hero test.
- No new dependency.

## Assumptions

- Supported bundled values are `destination`/`text`, `dates`/`date_range`, and `travellers`/`stepper`.
- Valid bundled traveler metadata is initial value `2`, minimum `1`, and maximum `6`; invalid or missing values fall back to current behavior (initial `2`, minimum `1`, and no upper bound).
- No-action and non-planner action callers retain the existing labels, hint, initial state, lower bound, and unbounded increment behavior.
- The existing `bundled local demo renders its home hero` test is extended in place; no second bundled planner widget test is added.

## Work Items

- [x] Audit bundled planner fields, action model/decoder, notifier/sheet behavior, existing tests, and completed-task boundary.
- [x] Add the minimal typed planner-field model and optional action field while preserving `noteField`.
- [x] Decode only valid supported planner field descriptors and ignore malformed/unknown entries safely.
- [x] Apply supported field labels/hint, initial traveler count, and min/max bounds through the existing planner controls.
- [x] Preserve no-action/non-planner fallbacks and planner submission/date/travel-style semantics.
- [x] Extend exactly one existing real bundled-source widget test for labels, hint, initial count, and 1–6 traveler bounds.
- [x] Review the combined six-path diff for correctness and scope.
- [x] Run scoped format, analysis, named test, and affected app test file validation.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/domain/waypoint_planner_field.dart \
  lib/waypoint/domain/waypoint_test_action.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/application/waypoint_planner_notifier.dart \
  lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/domain/waypoint_planner_field.dart \
  lib/waypoint/domain/waypoint_test_action.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/application/waypoint_planner_notifier.dart \
  lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its home hero"

flutter test test/waypoint_app_test.dart
```

Only the six task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test files are required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit six-path scope.

## Outcome

The bundled planner field metadata now drives supported labels, destination hint, initial traveler count, and coherent traveler bounds. Malformed `open_planner` type/copy metadata is rejected before planner fields are decoded. The initial strict review findings were corrected; the fresh independent review accepted the result.

## References

- `fixtures/flutter_conformance_app/assets/data/actions.json:12-15` — bundled planner field labels, placeholder, initial value, and bounds.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_test_action.dart` — current action contract with note-only field decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart` — current field decoding boundary.
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_planner_notifier.dart` — current traveler state mutators.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_planning_sheet.dart` — current hardcoded planner controls and traveler behavior.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — existing real bundled hero flow and planner assertions.
- `tasks/169-bundled-open-planner-action-copy-coverage.md` — completed top-level planner action-copy propagation.
- `tasks/172-bundled-offer-planner-handoff-coverage.md` — completed offer handoff to the planner action.

## History

- 2026-08-30 — Newton the 4th completed a read-only audit and identified dropped bundled planner field metadata; no files changed.
- 2026-08-30 — Coordinator reserved Task 173 with a bounded six-file implementation, review, and local validation scope.
- 2026-08-30 — Galileo the 4th implemented the six-path supported-field change and reported scoped formatting, analysis, the named hero test, all 60 app tests, and 7 planner tests passing.
- 2026-08-30 — Herschel the 4th independently rejected the implementation: parsed `min` was unused, `max: 1` could leave the default initial value at `2`, and required `open_planner` copy was not type/blank validated before planner fields were consumed.
- 2026-08-30 — Galileo the 4th corrected only the decoder, planner notifier, and planning sheet; the model, action, and existing test paths remained unchanged.
- 2026-08-30 — Euler the 4th independently reviewed the corrected implementation and accepted it with no confirmed findings; reviewer validation covered scoped format, analysis, and the named hero test, while the coordinator ran the remaining affected app test file.
- 2026-08-30 — Coordinator validation passed: `dart format --output=none --set-exit-if-changed` over the six paths (6 formatted, 0 changed); scoped `flutter analyze` (no issues); named bundled hero test (`+1`); and `flutter test test/waypoint_app_test.dart` (`61` tests passed). No device, simulator, Docker, AWS, or unrelated test validation was run.
