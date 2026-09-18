# Task 152 — Trip document detail coverage

Status: [x] Completed

## Goal

Preserve the bundled trip document through the real local AlphaX/data-decoder
path and render it in the Trips detail sheet so the demo app covers a shipped
document use case.

## Scope and Non-goals

Scope:

- add a typed trip-document domain model with the fields present in the
  bundled fixture (`name`, `kind`, `sizeLabel`, and the optional icon value if
  the implementation needs it);
- add an empty document collection to `WaypointTrip` for trips without
  documents;
- decode the existing `documents` array from the bundled trip JSON;
- render a conditional, read-only Documents section in the trip detail sheet
  showing the shipped document's name, kind, and size;
- add exactly one widget test using the real zero-latency
  `WaypointAlphaXDataSource` and bundled local transport to prove the Kyoto
  document reaches the visible Trips detail sheet.

Non-goals:

- changing `home.json` or adding document assets;
- downloading, opening, sharing, previewing, or persisting files;
- backend/API, AlphaX transport, repository, platform/device, Docker, AWS,
  hosting, deployment, or permission work;
- changing existing trip navigation, checklist, itinerary, planner, or card
  behavior;
- adding tests outside the changed app test file or broad refactoring.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Tasks 145 and 150–151;
- existing bundled Kyoto trip document at
  `fixtures/flutter_conformance_app/assets/data/home.json`;
- existing `WaypointAlphaXDataSource`, `WaypointDemoTransport`,
  `WaypointRepository`, `WaypointTrip`, `WaypointJsonDecoder`, and Trips
  detail sheet;
- existing Trips navigation and Kyoto trip test keys.

## Assumptions

- the current bundled document payload is the source of truth and must be
  decoded without fixture changes;
- trips with a missing or empty `documents` field remain valid and render no
  Documents section;
- the document section is informational only because no file operation is in
  scope;
- the worker owns only the five paths listed in the write set below and must
  not revert unrelated work in this shared checkout;
- if the test exposes a production defect outside this bounded path, report it
  rather than expanding scope.

## Work Items

- [x] Audit the bundled payload, current trip model/decoder/detail UI, prior
  task exclusions, and existing real-source widget-test seam.
- [x] Add the typed trip-document model, model field, decoder mapping, and
  conditional detail-sheet section.
- [x] Add exactly one real bundled-source Trips document widget regression
  test.
- [x] Review the combined task-owned diff for compatibility, null/empty data,
  exact visible content, and scope compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_trip_document.dart`
  `lib/waypoint/domain/waypoint_trip.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze`
  `lib/waypoint/domain/waypoint_trip_document.dart`
  `lib/waypoint/domain/waypoint_trip.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local Trips detail renders its shipped document"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported five files
  and zero changes; scoped analysis reported no issues; the named regression
  test passed; and the full changed app widget test passed all forty-three
  tests.
- no unrelated test files, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended five-file write set and
final observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip_document.dart`
  — SHA-256 `1428d47d75c6fa21668a6fa34e6b0fc31492821eb050263a30c913cdebccd135`;
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart`
  — SHA-256 `c37068fed947e8d523d20c2147ab553834b9b08a260c8189df0ce894b7682250`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `d57b812ab78339a96be6916233c7958deca10b5b5f9f79f8775f6d65ff9bbd94`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  — SHA-256 `3fac13a91d1065f78b79232ca4b8c66c26ae5f7a172527510e1c4762dda8a753`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `b937132ca620a86aa0e243837119605beb55492229019d0816c6e6ec7c74d1f1`.

The app test contains 43 `testWidgets` declarations, including exactly one
Task-152-named case. No debug output was found in the five paths. The worker
reported no other implementation paths changed; the missing Git baseline is
retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The real bundled AlphaX/local transport now preserves the Kyoto
document through decoding and renders a conditional read-only Documents
section in the Trips detail sheet. Trips without documents retain an empty
collection and no Documents section. The named and full changed-file tests
pass, with no fixture, dependency, platform, device, deployment, or external
service changes.

## References

- `tasks/145-trips-checklist-detail-coverage.md`
- `tasks/150-bundled-saved-state-widget-coverage.md`
- `tasks/151-bundled-activity-stream-widget-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:45-46`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Leibniz the 3rd performed a read-only audit after Task 151 and
  found that the shipped Kyoto document is present in `home.json` but is not
  represented by `WaypointTrip`, decoded by `WaypointJsonDecoder`, rendered
  by the Trips detail sheet, or asserted by existing tests. Task 145 had
  explicitly excluded documents. The audit proposed this five-path bounded
  package; no files were edited during the audit.
- 2026-08-29: Raman the 3rd implemented the bounded five-path package: a typed
  document model, backward-compatible trip field, decoder mapping,
  conditional read-only detail section, and one real zero-latency bundled
  source widget test. The worker reported scoped formatting and analysis
  passing, the named test passing, and all forty-three tests in the changed
  app test file passing. Strict review and coordinator validation remain
  pending.
- 2026-08-29: Nash the 3rd performed a strict read-only review and returned
  ACCEPT. The review found no verified correctness, compatibility, UI, test,
  or scope findings; confirmed the real local source path, empty-document
  behavior, exact visible assertions, and no dependency/platform changes. It
  reported the scoped checks passing, including the full forty-three-test app
  file twice. The checkout's missing Git `HEAD` remains an explicit
  provenance limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with five files unchanged, scoped analysis exited 0
  with no issues, the named document test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all forty-three tests passing.
