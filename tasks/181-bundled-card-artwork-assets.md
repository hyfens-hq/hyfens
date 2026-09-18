# Task 181 — Bundled card artwork assets

Status: [x] Completed

## Goal

Prove that every bundled destination and trip card renders the source-declared local artwork asset through the existing `WaypointAssetArtwork` seam.

## Scope and Non-goals

Scope:

- Extend the existing real bundled Flutter widget coverage to assert the exact `imageAsset` path for all five destination cards.
- Extend the same local coverage boundary to assert the exact `imageAsset` path for both bundled trip cards.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, card layout, navigation, dependencies, or infrastructure.
- Do not add a generic asset registry, synthetic source data, new test files, or tests outside `test/waypoint_app_test.dart`.
- Do not validate actual raster/SVG pixels; this task proves source-to-widget asset-path propagation only.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` and `discover.json` destination/trip `imageAsset` values.
- `WaypointJsonDecoder` destination/trip mapping.
- Existing `WaypointDestinationCard`, `WaypointTripCard`, and `WaypointAssetArtwork` rendering seams.
- Existing local zero-latency AlphaX/demo source and stable card keys.

## Assumptions

- Destination cards use the existing stable `waypoint-destination-<id>` keys and contain one `WaypointAssetArtwork` child.
- Trip cards use the existing stable `waypoint-trip-<id>` keys and contain one `WaypointAssetArtwork` child.
- The existing bundled destination and trip flows can be extended in place without changing production code.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled destination/trip asset values, decoder/model/rendering paths, existing tests, and completed-task boundary.
- [x] Add exact `WaypointAssetArtwork.assetPath` assertions for all bundled destination and trip cards in `waypoint_app_test.dart`.
- [x] Review the task-owned test diff for source fidelity, complete record coverage, stable scoping, and determinism.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named artwork test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its card artwork assets"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled card-artwork test now proves all five destination and both trip `imageAsset` values reach exactly one stable-card-scoped `WaypointAssetArtwork`. No production code, fixture data, or asset files changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:25-68` — bundled trip records and their `imageAsset` paths.
- `fixtures/flutter_conformance_app/assets/data/home.json:71-99` — bundled home destination records and their `imageAsset` paths.
- `fixtures/flutter_conformance_app/assets/data/discover.json:17-61` — bundled Discover destination records and their `imageAsset` paths.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:94-151` — destination and trip decoding paths.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:29-46` — destination card key and artwork child.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_trip_card.dart:18-34` — trip card key and artwork child.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:435-484` — existing bundled destination-card loop without artwork-path assertions.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:1425-1469` — existing bundled trip-card visual coverage without artwork-path assertions.
- `tasks/180-bundled-discover-category-icons.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Coordinator direct evidence audit identified unasserted bundled destination and trip card `imageAsset` propagation; no source files changed.
- 2026-08-30 — Coordinator reserved Task 181 with a bounded test-only implementation, review, and local validation scope.
- 2026-08-30 — Noether the 4th added the named real bundled card-artwork widget test with exact assertions for five destinations and two trips; worker reported only `test/waypoint_app_test.dart` changed and did not run validation.
- 2026-08-30 — Aristotle the 4th independently accepted the test with no High, Medium, or Low findings; direct JSON, decoder, data-source, card-key, and widget-seam evidence matched the seven assertions.
- 2026-08-30 — Coordinator direct scope check found only `test/waypoint_app_test.dart` newer than the Task 181 record; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (`Formatted 1 file (0 changed)`); `flutter analyze test/waypoint_app_test.dart` (`No issues found`); named artwork test (`+1`); and `flutter test test/waypoint_app_test.dart` (`67` tests passed). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
