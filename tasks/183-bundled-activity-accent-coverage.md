# Task 183 — Bundled Activity accent coverage

Status: [x] Completed

## Goal

Prove that the two bundled Activity accent values are decoded and applied to the corresponding rendered Activity tiles.

## Scope and Non-goals

Scope:

- Extend the existing real bundled Activity widget test with exact title-scoped accent-color assertions for both shipped Activity records.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, Activity icons, stream lifecycle, retry/cancellation behavior, copy, dependencies, or infrastructure.
- Do not add a new test file or change tests outside `test/waypoint_app_test.dart`.
- Do not use global/ambiguous widget lookups or synthetic Activity data.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` Activity accent values.
- Existing `WaypointJsonDecoder.decodeActivity` accent mapping.
- Existing `WaypointActivityTile` color application and stable title-scoped Activity test flow.

## Assumptions

- `Your Kyoto plan was refreshed` uses `Color(0xFFD98267)`.
- `Asha saved Lantern House` uses `Color(0xFF4B927B)`.
- Each Activity tile contains one accent-bearing `Container`, so a lookup scoped to that title’s `WaypointActivityTile` is deterministic.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled Activity accent values, decoder/tile paths, existing test, and completed-task boundary.
- [x] Add exact title-scoped accent-color assertions for both bundled Activity records.
- [x] Review the task-owned test diff for source fidelity, unambiguous tile scoping, and preservation of existing icon/lifecycle assertions.
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

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled Activity test now proves both source accent colors reach their title-scoped rendered tile containers: `#D98267` becomes `Color(0xFFD98267)` and `#4B927B` becomes `Color(0xFF4B927B)`. No production code, fixture data, or dependencies changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:101-104` — bundled Activity records and accent values.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:177-187` — Activity accent decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_activity_tile.dart:17-22` — accent application to the leading tile container.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1003-1118` — existing real bundled Activity flow, icon assertions, and accent assertions.
- `tasks/178-bundled-activity-icon-coverage.md` — prior Activity task that explicitly excluded accent colors.
- `tasks/182-bundled-discover-filter-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Kierkegaard the 4th completed a fresh read-only audit and identified unasserted bundled Activity accent propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the two source colors, decoder mapping, tile application, and existing real Activity test boundary.
- 2026-08-30 — Coordinator reserved Task 183 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Bacon the 4th extended the existing bundled Activity test with exact title-scoped single-Container/BoxDecoration color assertions; worker-reported named Activity validation passed (`+1`) and only `test/waypoint_app_test.dart` changed.
- 2026-08-30 — Wegener the 4th independently rejected the first task record only for a stale test-range reference; no code findings were reported.
- 2026-08-30 — Coordinator corrected the reference to `waypoint_app_test.dart:1003-1118`; Banach the 4th performed the final strict review and accepted with no High, Medium, or Low findings.
- 2026-08-30 — Coordinator direct scope check found only `test/waypoint_app_test.dart` newer than the Task 183 record; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (`Formatted 1 file (0 changed)`); `flutter analyze test/waypoint_app_test.dart` (`No issues found`); named Activity test (`+1`); and `flutter test test/waypoint_app_test.dart` (`67` tests passed). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
