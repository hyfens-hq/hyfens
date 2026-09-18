# Task 189 — Bundled itinerary time and detail coverage

Status: [x] Completed

## Goal

Prove that all three real bundled Kyoto itinerary time and detail pairs reach their corresponding detail-sheet rows.

## Scope and Non-goals

Scope:

- Extend the existing real bundled itinerary-category widget test with exact row-scoped assertions for all three shipped time/detail pairs.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, progress, documents, artwork, accent, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic itinerary data or global/ambiguous assertions.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Kyoto itinerary time/detail values in `home.json`.
- Existing `WaypointJsonDecoder.decodeItinerary` mapping and `WaypointTripsPage` detail-sheet row rendering.
- Existing real zero-latency bundled itinerary-category test with row finder, category assertions, navigation, and cleanup.

## Assumptions

- The bundled rows render these exact pairs:
  - `Philosopher's Path` — `09:30` and `A slow walk beside the canal`.
  - `Tea house reservation` — `13:00` and `A small room in Gion`.
  - `Lanterns at Yasaka` — `18:40` and `Golden hour in the old quarter`.
- The existing `itineraryRow(title)` finder uniquely scopes each assertion to its corresponding detail-sheet `ListTile`.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled itinerary values, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add six exact row-scoped time/detail assertions to the existing itinerary-category test.
- [x] Review the task-owned test diff for source fidelity, complete pair coverage, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named itinerary test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Trips detail renders itinerary categories"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Kyoto itinerary-category test. The test now verifies all three exact time/detail pairs within their corresponding detail-sheet `ListTile` rows, while preserving the existing category, navigation, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named itinerary test — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:37-39` — bundled Kyoto itinerary time/detail values.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:166-174` — itinerary time/detail decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:166-191` — detail-sheet itinerary row time/detail rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1534-1649` — existing real bundled itinerary-category test, row-scoping helper, and new time/detail assertions.
- `tasks/177-bundled-trip-progress-coverage.md` — prior bundled trip progress coverage boundary.
- `tasks/186-bundled-trip-document-merge.md` — prior bundled trip document merge boundary.
- `tasks/188-bundled-trip-date-duration-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Pauli the 4th completed a read-only audit and identified unasserted bundled Kyoto itinerary time/detail propagation; no files changed.
- 2026-08-30 — Coordinator directly verified all three source pairs, decoder mapping, detail-sheet row rendering, existing row finder, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 189 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Curie the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with six exact row-scoped time/detail assertions; the named itinerary test passed.
- 2026-08-30 — Ampere the 4th identified one Low stale test-range reference during strict review; the coordinator corrected the task reference to include the new assertions.
- 2026-08-30 — Planck the 4th completed the final strict review with `ACCEPT — no findings`, verifying all source pairs, row scoping, preserved assertions, and corrected task references.
- 2026-08-30 — Coordinator completed the declared scoped validation: format clean, analyzer clean, named itinerary test passed, and the affected app test file passed all 68 tests.
