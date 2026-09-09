# Task 184 — Bundled destination accent coverage

Status: [x] Completed

## Goal

Prove that each bundled destination accent value is decoded and applied to its rendered rating star.

## Scope and Non-goals

Scope:

- Add one real bundled-source widget test covering the five bundled destination cards.
- Assert the exact rating-star color for each stable destination card key.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, card layout, search/filter behavior, Saved behavior, navigation, dependencies, or infrastructure.
- Do not change existing tests outside `test/waypoint_app_test.dart` or add a new test file.
- Do not validate pixels, asset files, trip accents, Activity accents, or platform behavior.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` and `discover.json` destination accent values and IDs.
- Existing local source merge, destination decoder, `WaypointDestinationCard`, `waypointColor`, and stable destination-card keys.
- Existing local zero-latency AlphaX/demo test support.

## Assumptions

- The five expected star colors are: Lantern House `Color(0xFFD98267)`, Blue Tram Table `Color(0xFFE6A24F)`, Aurora Cabin `Color(0xFF5EB9A1)`, Rose Courtyard `Color(0xFFC46868)`, and Coastline Table `Color(0xFF3C8E9F)`.
- Each destination card contains exactly one `Icons.star_rounded` rating icon.
- Assertions can be scoped to stable `waypoint-destination-<id>` card keys and the rating icon within each card.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled destination accent values, merge/decoder/card paths, existing coverage, and completed-task boundary.
- [x] Add exact star-color assertions for all five bundled destination cards.
- [x] Review the task-owned test diff for source fidelity, complete ID/color coverage, stable scoping, and determinism.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named destination-accent test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders destination accent colors"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled destination-accent test now proves all five source accent values reach the corresponding rating-star icons through stable card-scoped assertions. No production code, fixture data, or dependencies changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:71-99` — bundled home destination accent values and IDs.
- `fixtures/flutter_conformance_app/assets/data/discover.json:17-61` — bundled Discover destination accent values and IDs.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-321` — merged local source path.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:104-128` — destination accent decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:29-30,123-128` — stable card key and accent-colored rating star.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:435-484` — existing bundled destination coverage without accent assertions.
- `tasks/165-bundled-trip-accent-color-coverage.md` — trip accent coverage boundary.
- `tasks/183-bundled-activity-accent-coverage.md` — immediately preceding completed local coverage task and Activity accent boundary.

## History

- 2026-08-30 — Carver the 4th completed a fresh read-only audit and identified unasserted bundled destination rating-star accent propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the five source colors, merge/decoder path, rating-star application, and existing test boundary.
- 2026-08-30 — Coordinator reserved Task 184 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Anscombe the 4th added the named real bundled destination-accent widget test with exact five-card star-color assertions; worker-reported named validation passed (`+1`) and only `test/waypoint_app_test.dart` changed.
- 2026-08-30 — Peirce the 4th independently accepted the implementation with no High, Medium, or Low findings; direct source, decoder, card, and test evidence matched all five mappings.
- 2026-08-30 — Coordinator direct scope check found only `test/waypoint_app_test.dart` newer than the Task 184 record; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (`Formatted 1 file (0 changed)`); `flutter analyze test/waypoint_app_test.dart` (`No issues found`); named destination-accent test (`+1`); and `flutter test test/waypoint_app_test.dart` (`68` tests passed). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
