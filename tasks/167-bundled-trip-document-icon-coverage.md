# Task 167 — Bundled trip document icon rendering

Status: [x] Completed

## Goal

Render the existing bundled document icon metadata in the Trips detail sheet
while preserving the current generic fallback.

## Scope and Non-goals

Scope:

- add a small icon resolver in the existing Trips screen;
- map the shipped known document icon values such as `route` and `note` to
  built-in Material icons;
- preserve `Icons.description_outlined` for null or unknown values;
- keep the existing document row slot and behavior;
- add exactly one real zero-latency bundled-source widget test for the Kyoto
  document icon.

Non-goals:

- changing JSON/assets, model, decoder, transport, repository, document
  actions, downloads, sharing, dependencies, support fixtures, navigation,
  permissions, platform files, devices, simulators, Docker, AWS, hosting,
  deployment, or external services;
- changing document text/order/semantics or adding a document-icon framework;
- changing tests outside the owned app test file or adding synthetic-only
  coverage.

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

- completed Task 166;
- existing `WaypointTripDocument.icon` domain field and decoder mapping;
- bundled Kyoto and secondary-trip document records;
- existing Trips detail sheet, Material Icons, and bundled AlphaX/demo test
  seam.

## Assumptions

- `home.json` is the visible source for the primary Kyoto document and its
  `icon: "route"` value;
- unknown or missing icon strings must continue to use the generic description
  icon;
- the existing `ListTile.leading` slot can contain the mapped icon without
  changing document row layout or semantics;
- the worker owns only the two paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit bundled document icon data, model/decoder flow, detail UI, tests,
  and prior task exclusions.
- [x] Add known-icon mapping with generic fallback in the existing detail UI.
- [x] Add exactly one real bundled-source regression test for the Kyoto
  `route` document icon.
- [x] Review the combined task-owned diff for source fidelity, fallback,
  compatibility, layout, semantics, and scope.
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
  `"bundled local Trips detail renders its shipped document icon"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the two owned paths:
  passed; 2 files inspected, 0 changed.
- `flutter analyze` on the two owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local Trips
  detail renders its shipped document icon"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 58 tests.
- Carson the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/presentation/screens/waypoint_trips_page.dart` —
  `03fe2bba36d838281f39cb0a7bb63f6c466df067561db35026c0c4b5fcba22d3`
- `test/waypoint_app_test.dart` —
  `089c15ca684d07a8d739e7e4912a31f9a1e3a79bef924abffba8b631574c58fb`
- Test declaration count in the owned app test file: `58`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–167 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented known bundled document-icon mappings for the Trips detail sheet,
preserving the generic fallback and existing document behavior. The real Kyoto
bundled-source regression test verifies the rendered route icon. Independent
strict review returned `ACCEPT`, and coordinator validation passed all 58 app
tests. No model, decoder, data, dependency, platform, device, deployment, or
AWS work was introduced.

## References

- `tasks/166-bundled-trip-detail-itinerary-category-coverage.md`
- `tasks/152-trip-document-detail-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:45-46`
- `fixtures/flutter_conformance_app/assets/data/trips.json:25-27`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip_document.dart:1-13`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:149-158`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart:254-283`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:626-690`

## History

- 2026-08-30: Locke the 3rd performed a read-only audit. It found bundled
  document `icon` values preserved by the model/decoder but ignored by the
  detail row, which always renders `Icons.description_outlined`. The audit
  proposed this bounded two-path package; no files were changed or tested.
- 2026-08-30: Copernicus the 3rd implemented the bounded two-path package and
  reported the planned checks passing with 58 app tests.
- 2026-08-30: Carson the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; known icon mapping, generic fallback, preserved document
  behavior, test authenticity, and scope were factually verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
