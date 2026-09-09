# Task 193 — Bundled destination-card rating and duration coverage

Status: [x] Completed

## Goal

Prove that the real bundled Lantern House rating and duration reach the Discover destination card.

## Scope and Non-goals

Scope:

- Extend the existing real bundled destination-distance widget test with exact card-scoped assertions for the shipped rating and duration.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, renderer, search, filters, categories, detail-sheet metadata, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic destination data or global/ambiguous assertions.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled Lantern House rating and duration values in `home.json`.
- Existing `WaypointJsonDecoder.decodeDestination` mapping and `WaypointDestinationCard` rendering.
- Existing real zero-latency bundled destination-card test with keyed Lantern House card, location, distance, and cleanup assertions.

## Assumptions

- The bundled Lantern House card renders rating `4.9` and duration `3 nights`.
- The existing `waypoint-destination-lantern-house` key uniquely scopes both assertions to the intended card.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled rating/duration values, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add exact card-scoped rating and duration assertions to the existing destination-distance test.
- [x] Review the task-owned test diff for source fidelity, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named destination test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders destination distance"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Lantern House destination-distance test. The test now verifies card-scoped rating `4.9` and duration `3 nights`, while preserving the existing distance, location, visibility, setup, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named destination selector — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:70-79` — bundled Lantern House rating and duration.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:110-123` — destination rating/duration mapping.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:123-143` — destination-card rating/duration rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:356-396` — existing real bundled destination-card test, keyed card scope, and new rating/duration assertions.
- `tasks/179-bundled-discover-detail-metadata.md` — prior detail-sheet rating/duration coverage boundary.
- `tasks/192-bundled-destination-location-coverage.md` — prior destination-card location coverage boundary.
- `tasks/191-bundled-discover-detail-description-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Hooke the 4th completed a read-only audit and identified unasserted bundled Lantern House destination-card rating/duration propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled values, decoder mappings, card rendering, existing real test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 193 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Tesla the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with exact card-scoped `4.9` and `3 nights` assertions; the named destination test passed.
- 2026-08-30 — Heisenberg the 4th identified one Low stale test-range reference during strict review; the coordinator corrected the task reference to include the new assertions.
- 2026-08-30 — Locke the 4th completed strict review with `ACCEPT — no findings` after the reference correction.
- 2026-08-30 — Coordinator completed the declared scoped validation: final format clean, analyzer clean, named destination test passed, and the affected app test file passed all 68 tests.
