# Task 166 — Bundled trip-detail itinerary category rendering

Status: [x] Completed

## Goal

Render each bundled itinerary item's existing category in the Trips detail
sheet without changing the itinerary's content or behavior.

## Scope and Non-goals

Scope:

- add a compact, read-only category label to each existing detail itinerary
  row;
- use the existing `WaypointItineraryItem.category` value directly;
- preserve existing time, title, detail, ordering, completion indicator, and
  sheet behavior;
- add exactly one real zero-latency bundled-source widget test asserting the
  shipped Kyoto categories.

Non-goals:

- changing JSON/assets, model, decoder, transport, repository, Riverpod state,
  checklist, progress, documents, cover-label or accent behavior, navigation,
  permissions, dependencies, platform files, devices, simulators, Docker,
  AWS, hosting, deployment, or external services;
- changing the overview timeline, category values/order, itinerary
  completion, persistence, or making rows interactive;
- adding a new widget file or changing tests outside the owned app test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these two paths:

- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 165;
- existing `WaypointItineraryItem.category` model and decoder path;
- bundled Kyoto itinerary categories in `home.json` and `trips.json`;
- existing Trips detail sheet, completion indicators, and bundled AlphaX/demo
  test seam.

## Assumptions

- shipped categories are nonblank and should be displayed as their exact source
  strings (`walk`, `food`, and `culture`);
- the existing scrollable detail sheet can accommodate a compact label;
- category rendering is read-only and does not affect completion or progress;
- the worker owns only the two paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit bundled itinerary categories, model/decoder flow, detail and
  overview UI, tests, and prior task exclusions.
- [x] Render a compact read-only category label in each detail itinerary row.
- [x] Add exactly one real bundled-source regression test for the Kyoto
  `walk`, `food`, and `culture` categories.
- [x] Review the combined task-owned diff for data fidelity, layout,
  accessibility, non-interactivity, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same two paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local Trips detail renders itinerary categories"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the two owned paths:
  passed; 2 files inspected, 0 changed.
- `flutter analyze` on the two owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local Trips
  detail renders itinerary categories"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 57 tests.
- Zeno the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/presentation/screens/waypoint_trips_page.dart` —
  `63d56c490c2cdfdd725e2f6c71b3e7f563382c6b8d3c9926c967dc0edb2e6d32`
- `test/waypoint_app_test.dart` —
  `be8694ec39be6bd0c6442dc9e452156b10e51c9a795ffb618e8f9044448fb178`
- Test declaration count in the owned app test file: `57`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–166 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented compact, read-only category chips in each Trips detail itinerary
row, directly bound to the existing bundled `walk`, `food`, and `culture`
values. The real Kyoto bundled-source regression test verifies all three
rendered categories. Independent strict review returned `ACCEPT`, and
coordinator validation passed all 57 app tests. No source data, model,
dependency, platform, device, deployment, or AWS work was introduced.

## References

- `tasks/165-bundled-trip-accent-color-coverage.md`
- `tasks/163-bundled-trip-detail-itinerary-completion-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:36-40`
- `fixtures/flutter_conformance_app/assets/data/trips.json:15-19`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_itinerary_item.dart:1-14`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:159-168`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:170-195,367-411`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:779-852`

## History

- 2026-08-30: Hypatia the 3rd performed a read-only audit. It found
  `category` values preserved in the existing itinerary model/decoder and
  omitted from Trips detail rows, while the overview also omits them. The
  audit proposed this bounded two-path detail-only package; no files were
  changed or tested.
- 2026-08-30: Ohm the 3rd implemented the bounded two-path package and
  reported the planned checks passing with 57 app tests.
- 2026-08-30: Zeno the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; direct category binding, compact non-interactive UI,
  preserved detail behavior, test authenticity, and scope were factually
  verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
