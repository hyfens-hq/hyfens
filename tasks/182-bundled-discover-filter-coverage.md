# Task 182 — Bundled Discover filter coverage

Status: [x] Completed

## Goal

Prove that Discover category filters operate on the merged bundled home and Discover records, not only on the synthetic test source.

## Scope and Non-goals

Scope:

- Add one real bundled-source widget test covering Stay, Food, Nature, and Culture filters.
- Assert both inclusion and exclusion for all five bundled destination card IDs through their stable keys.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, transport, search behavior, category icons, navigation, dependencies, or infrastructure.
- Do not alter the existing synthetic filter test or add a new test file.
- Do not test category labels/icons, which are covered by Task 180.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` and `discover.json` destination kinds and IDs.
- Existing local transport merge, JSON decoder, repository, filter state, and stable destination-card keys.
- Existing `pumpWaypointTestApp` helper and `WaypointAlphaXDataSource`.

## Assumptions

- The bundled filter outcomes are Stay → Lantern House; Food → Blue Tram Table and Coastline Table; Nature → Aurora Cabin; Culture → Rose Courtyard.
- The real local source uses `WaypointDemoTransport(latency: Duration.zero)` and no network access.
- The test can be contained in `test/waypoint_app_test.dart`; no production seam is needed.

## Work Items

- [x] Audit bundled destination kinds, merge/decoder/filter paths, existing synthetic coverage, and completed-task boundary.
- [x] Add one real bundled-source test covering all four filter branches with inclusion and exclusion assertions.
- [x] Review the task-owned test diff for source fidelity, complete ID coverage, stable keys, and deterministic state transitions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named filter test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local Discover filters its merged destinations"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled Discover-filter test now proves Stay, Food, Nature, and Culture results over all five merged destination records, with inclusion and exclusion assertions through stable card keys. No production code, fixture data, or dependencies changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:69-99` — bundled home destination kinds and IDs.
- `fixtures/flutter_conformance_app/assets/data/discover.json:15-61` — bundled Discover destination kinds and IDs.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:287-321` — local bundled source merge path.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:104-128,394-403` — destination kind decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:249-283,337-351` — filtered result rendering and filter resolver.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:29-30` — stable destination card key.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:2460-2478` — existing synthetic filter coverage.
- `tasks/181-bundled-card-artwork-assets.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Meitner the 4th completed a fresh read-only audit and identified that existing filter coverage uses the synthetic default source; no files changed.
- 2026-08-30 — Coordinator directly verified the bundled kind records, merge path, decoder, filter resolver, and synthetic-test boundary.
- 2026-08-30 — Coordinator reserved Task 182 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — McClintock the 4th added the named real bundled filter test; worker-reported named validation passed (`+1`) and only `test/waypoint_app_test.dart` changed.
- 2026-08-30 — Turing the 4th independently reviewed the implementation and found no code findings; one Low task-reference range issue was corrected from Task 180 to Task 181 and from `2459-2480` to `2460-2478`.
- 2026-08-30 — Coordinator applied the required formatter to the worker-added test block, then the final Harvey the 4th strict re-review accepted the formatted source with no High, Medium, or Low findings.
- 2026-08-30 — Coordinator direct scope check found only `test/waypoint_app_test.dart` newer than the Task 182 record; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (`Formatted 1 file (0 changed)`); `flutter analyze test/waypoint_app_test.dart` (`No issues found`); named bundled-filter test (`+1`); and `flutter test test/waypoint_app_test.dart` (`67` tests passed). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
