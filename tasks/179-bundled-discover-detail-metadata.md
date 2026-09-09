# Task 179 — Bundled Discover detail metadata

Status: [x] Completed

## Goal

Prove that the real bundled Discover flow preserves Lantern House's source-driven category, rating, and duration metadata in the existing destination detail sheet.

## Scope and Non-goals

Scope:

- Add one real zero-latency bundled-source widget test that opens Lantern House and asserts its existing detail-sheet metadata.

Non-goals:

- Do not change production code, JSON/assets, model/decoder/repository behavior, planner handoff, search/filter/saved behavior, layout, navigation, dependencies, or infrastructure.
- Do not change detail-sheet copy or presentation, add fixtures, or create another test file.
- Do not tap or validate the planner CTA in this task.
- No device, simulator, Docker, AWS, online hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled Lantern House payload and local zero-latency AlphaX/demo source.
- Existing destination-card key, detail-sheet flow, and typed metadata rendering.
- Existing `waypoint_app_test.dart` bundled test conventions.

## Assumptions

- Lantern House remains the bundled destination key `waypoint-destination-lantern-house` with category `Stay`, rating `4.9`, and duration `3 nights`.
- The test opens the existing destination detail sheet and scopes all three metadata assertions to `BottomSheet`.
- One test-only change is sufficient because the source/model/UI pipeline is already implemented and the task intentionally does not authorize production edits.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled Lantern House values, local data/decoder/model path, detail-sheet rendering, existing tests, and completed-task boundary.
- [x] Add one real bundled-source detail-metadata regression test within `waypoint_app_test.dart`.
- [x] Review the task-owned test diff for source fidelity, sheet-scoped assertions, scope, and determinism.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named detail-metadata test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Discover detail renders source metadata"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled Discover flow now proves Lantern House's source-driven `Stay`, `4.9 rating`, and `3 nights` metadata in the existing destination detail sheet. No production behavior or data was changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:71-84` — bundled Lantern House metadata.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-313` — local bundled payload loading and place merge.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:111-126` — destination metadata decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart:12-35` — typed destination metadata.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:374-398` — existing destination detail metadata rendering.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:352-379` — existing real-source Lantern House coverage.
- `tasks/178-bundled-activity-icon-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Lovelace the 4th completed a fresh read-only audit and identified unverified bundled Discover detail metadata; no files changed.
- 2026-08-30 — Coordinator reserved Task 179 with a bounded test-only implementation, review, and local validation scope.
- 2026-08-30 — Halley the 4th added the one real zero-latency bundled detail-metadata test with BottomSheet-scoped assertions; worker-reported scoped checks passed.
- 2026-08-30 — Zeno the 4th independently accepted the test with no findings and verified the real source, stable key, deterministic sheet flow, and exact bundled values.
- 2026-08-30 — Coordinator validation passed: `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (1 formatted, 0 changed); `flutter analyze test/waypoint_app_test.dart` (no issues); named detail-metadata test (`+1`); and `flutter test test/waypoint_app_test.dart` (`66` tests passed). No device, simulator, Docker, AWS, or unrelated test validation was run.
