# Task 190 — Bundled trip detail title coverage

Status: [x] Completed

## Goal

Prove that the real bundled Kyoto trip title reaches its detail-sheet heading.

## Scope and Non-goals

Scope:

- Extend the existing real bundled trip-document widget test with one exact title assertion scoped to the opened detail `BottomSheet`.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, documents, itinerary, progress, artwork, accent, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic trip data or a global/ambiguous title assertion.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Kyoto trip title in `trips.json`.
- Existing `WaypointJsonDecoder.decodeTrip` title mapping and `WaypointTripsPage` detail-sheet heading.
- Existing real zero-latency bundled trip-document test with Kyoto navigation, detail sheet, document assertions, and cleanup.

## Assumptions

- The opened Kyoto detail sheet renders the exact heading `Kyoto field notes`.
- The existing `BottomSheet` finder uniquely scopes the title assertion to the opened trip detail.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled title, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add one exact `BottomSheet`-scoped title assertion to the existing bundled trip-document test.
- [x] Review the task-owned test diff for source fidelity, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named trip-document test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Trips detail renders its shipped document"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Kyoto trip-document test. The test now verifies `Kyoto field notes` within the opened `BottomSheet`, while preserving all existing document, navigation, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named trip-document selector — `+2: All tests passed!` (the selector also matched the related document-icon test).
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/trips.json:5-10` — bundled Kyoto trip title and identity.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:131-140` — trip title decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:148-166` — detail-sheet title rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1213-1330` — existing real bundled trip-document test and opened detail sheet.
- `tasks/186-bundled-trip-document-merge.md` — prior bundled document coverage boundary.
- `tasks/189-bundled-itinerary-time-detail-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Confucius the 4th completed a read-only scan and identified unasserted bundled Kyoto trip-detail title propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the source title, decoder mapping, detail-sheet heading, existing real test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 190 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Popper the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with one exact `BottomSheet`-scoped title assertion; the targeted test passed.
- 2026-08-30 — Archimedes the 4th completed the strict review with `ACCEPT — no findings`, verifying source fidelity, precise sheet scoping, preserved assertions, cleanup/navigation, and task references.
- 2026-08-30 — Coordinator completed the declared scoped validation: format clean, analyzer clean, the named selector passed both matching tests, and the affected app test file passed all 68 tests.
