# Task 154 — Bundled secondary trip coverage

Status: [x] Completed

## Goal

Make the bundled third trip visible through the local demo transport and prove
that the existing Trips UI can render and open it.

## Scope and Non-goals

Scope:

- add a typed asset-path constant for the existing `assets/data/trips.json`;
- load the existing bundled trip collection in `WaypointDemoTransport`;
- merge only trip IDs not already present in `home.json`, preserving the
  existing home-trip order and avoiding duplicates;
- add exactly one real-source widget test that uses zero-latency local
  AlphaX transport, shows the `Open skies` card, opens its detail sheet, and
  asserts its shipped title and destination.

Non-goals:

- changing `trips.json`, `home.json`, models, decoder, repository, UI layout,
  trip documents, Saved/Activity/share-note behavior, or other routes;
- changing existing Kyoto or Lisbon payloads or their ordering;
- adding generic merge infrastructure, persistence, network/bootstrap, device,
  simulator, Docker, AWS, hosting, deployment, or external-service behavior;
- adding tests outside the changed app test file or broad refactoring.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these three paths:

- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_asset_paths.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

## Dependencies

- completed Tasks 150–153;
- existing `assets/data/trips.json`, already included by the app's data asset
  bundle;
- existing `WaypointDemoTransport`, `WaypointAlphaXDataSource`,
  `WaypointTrip`, `WaypointJsonDecoder`, Trips page/card, and test override
  seam.

## Assumptions

- `trips.json` is the source of truth for the additional bundled trip and must
  not be edited;
- `home.json` remains the base response; merge logic appends only IDs absent
  from its existing `trips` list;
- existing home trips and all their fields remain unchanged;
- the worker owns only the three paths listed in the write set and must not
  revert unrelated edits in this shared checkout;
- if a malformed optional supplemental trip is encountered, report the
  smallest safe behavior rather than adding a broad validation framework.

## Work Items

- [x] Audit the bundled trip asset, asset declarations, local transport route,
  existing Trips rendering path, and current synthetic secondary-trip test.
- [x] Add the trips asset path and local transport merge for previously unseen
  trip IDs.
- [x] Add exactly one real bundled-source widget regression test for `Open
  skies` card and detail rendering.
- [x] Review the combined task-owned diff for ordering, duplicate prevention,
  fixture compatibility, test determinism, and scope compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/data/waypoint_asset_paths.dart`
  `lib/waypoint/data/waypoint_data_source.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze`
  `lib/waypoint/data/waypoint_asset_paths.dart`
  `lib/waypoint/data/waypoint_data_source.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo surfaces the shipped Open skies trip"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported three files
  and zero changes; scoped analysis reported no issues; the named regression
  test passed; and the full changed app widget test passed all forty-five
  tests.
- no unrelated test files, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended three-file write set and
final observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_asset_paths.dart`
  — SHA-256 `fc08b831de0a5dfafe06ce35146e9219623ebc6cac20e5b3dd223360abcba8b6`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
  — SHA-256 `ab395826d6a5f9cf088d253c6da7306bf57ba8ce7ea3e291f56ef03ed1749146`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `a8d76472eadd97f69a0b1cab5077b057a0646bc54c5adcc0c3331191df23844a`.

The app test contains 45 `testWidgets` declarations, including exactly one
Task-154-named case. No temporary debug output was found in the three paths.
The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The local demo transport now loads the existing supplemental trips
asset, preserves the home trip order and values, and appends only the unseen
`Open skies` trip. The real local widget test proves the card and detail sheet
render. No fixture, model, dependency, platform, device, deployment, AWS, or
external-service behavior changed.

## References

- `tasks/150-bundled-saved-state-widget-coverage.md`
- `tasks/151-bundled-activity-stream-widget-coverage.md`
- `tasks/152-trip-document-detail-coverage.md`
- `tasks/153-settings-share-trip-note-action.md`
- `fixtures/flutter_conformance_app/assets/data/trips.json:49-61`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_asset_paths.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Goodall the 3rd performed a read-only audit after Task 153 and
  found that `assets/data/trips.json` contains the shipped `Open skies` trip,
  while the local transport loads only `home.json`, `discover.json`, and
  `actions.json`; the Trips page already renders every trip it receives. The
  existing secondary-trip widget test uses an in-memory synthetic payload.
  The audit proposed this bounded three-path transport/test package; no files
  were edited during the audit.
- 2026-08-29: James the 3rd performed a strict read-only review and returned
  ACCEPT. No verified correctness, compatibility, ordering, duplicate,
  routing, test, or scope findings were reported. It confirmed the existing
  asset bundle, real local transport path, exact card/detail assertions, and
  no unrequested changes. The checkout's missing Git `HEAD` remains an
  explicit provenance limitation.
