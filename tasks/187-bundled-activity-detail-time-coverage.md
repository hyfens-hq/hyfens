# Task 187 — Bundled Activity detail and time coverage

Status: [x] Completed

## Goal

Prove that both bundled Activity detail strings and relative-time labels reach their corresponding rendered Activity tiles.

## Scope and Non-goals

Scope:

- Extend the existing real bundled Activity widget test with exact title/tile-scoped assertions for both shipped detail/time pairs.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, Activity icons, accent colors, stream lifecycle, retry/cancellation behavior, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `test/waypoint_app_test.dart`.
- Do not use synthetic Activity data or global/ambiguous assertions.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` Activity detail/time values.
- Existing `WaypointJsonDecoder.decodeActivity` mapping and `WaypointActivityTile` rendering.
- Existing real zero-latency bundled Activity test with title, icon, accent, and completion assertions.

## Assumptions

- `Your Kyoto plan was refreshed` renders detail `Two new tea houses match your saved route.` and time `8 min ago`.
- `Asha saved Lantern House` renders detail `It is now on your Kyoto shortlist.` and time `Yesterday`.
- Existing unique title lookups can scope all four assertions to their corresponding `WaypointActivityTile`.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled Activity detail/time values, decoder/rendering path, existing coverage, and completed-task boundary.
- [x] Add exact title/tile-scoped detail and time assertions for both bundled Activity records.
- [x] Review the task-owned test diff for source fidelity, complete pair coverage, stable scoping, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named Activity test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Activity feed renders both shipped updates"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled Activity test. The test now verifies the exact detail and relative-time pair for each shipped Activity update within its matching `WaypointActivityTile`, while preserving the existing title, icon, accent, navigation, and completion assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named Activity test — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:101-104` — bundled Activity detail and time values.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:177-187` — Activity detail/time decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_activity_tile.dart:35-50` — detail/time rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1071-1214` — existing real bundled Activity test with title, icon, accent, detail/time, and completion assertions.
- `tasks/151-bundled-activity-stream-widget-coverage.md` — prior Activity stream/title coverage boundary.
- `tasks/178-bundled-activity-icon-coverage.md` — Activity icon coverage boundary.
- `tasks/183-bundled-activity-accent-coverage.md` — Activity accent coverage boundary.
- `tasks/186-bundled-trip-document-merge.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Poincare the 4th completed a fresh read-only audit and identified unasserted bundled Activity detail/time propagation; no files changed.
- 2026-08-30 — Coordinator directly verified both source pairs, decoder mapping, tile rendering, and existing Activity test coverage.
- 2026-08-30 — Coordinator reserved Task 187 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Lorentz the 4th extended only `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` with four exact tile-scoped detail/time assertions; the named Activity test passed.
- 2026-08-30 — Cicero the 4th identified stale line pointers during strict review; the coordinator corrected the task references before final review.
- 2026-08-30 — Nietzsche the 4th completed a strict review with no code findings before the formatter was applied; the coordinator formatted the test and confirmed no further changes.
- 2026-08-30 — Schrodinger the 4th completed the final strict review with `ACCEPT — no findings`, verifying source pairs, decoder/rendering path, zero-latency data path, tile scoping, cleanup, task references, and the single-file boundary.
- 2026-08-30 — Coordinator completed the declared scoped validation: format clean, analyzer clean, named Activity test passed, and the affected app test file passed all 68 tests.
