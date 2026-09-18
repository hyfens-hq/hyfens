# Task 162 — Bundled trip cover-label rendering

Status: [x] Completed

## Goal

Preserve each bundled trip's optional `coverLabel` in typed data and render it
on the existing reusable trip card.

## Scope and Non-goals

Scope:

- add an optional `coverLabel` field to `WaypointTrip`;
- decode nonblank bundled `coverLabel` values using the existing optional-string
  convention;
- render the label on `WaypointTripCard`, capped at two lines with ellipsis;
- add exactly one real zero-latency bundled-source widget test asserting the
  shipped Open skies label.

Non-goals:

- changing JSON/assets, transport, repositories, Riverpod state, progress
  calculation, checklist, itinerary, documents, navigation, permissions,
  dependencies, platform files, devices, simulators, Docker, AWS, hosting,
  deployment, or external services;
- changing card tap behavior, card semantics, existing title/destination/date/
  duration/progress content, or tests outside the owned app test file;
- adding a new card abstraction or changing the card's fixed layout beyond the
  bounded label row.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these four paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_trip_card.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 161;
- existing bundled `home.json` and `trips.json` trip records;
- existing `WaypointAlphaXDataSource`, `WaypointDemoTransport`, repository,
  decoder, and reusable `WaypointTripCard`;
- existing bundled Open skies widget-test seam.

## Assumptions

- the checked-in bundled `coverLabel` values are the source of truth and will
  not be edited;
- a missing or blank label is absent rather than rendered as a placeholder;
- the optional field preserves compatibility with synthetic payloads that do
  not provide `coverLabel`;
- long future labels are bounded with `maxLines: 2` and ellipsis so the
  existing card does not grow unpredictably;
- the worker owns only the four paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit bundled `coverLabel` values, model, decoder, card, tests, and prior
  task exclusions.
- [x] Add optional typed `coverLabel` decoding with blank-safe behavior.
- [x] Render the label in the existing reusable trip card without changing
  existing card behavior.
- [x] Add exactly one real bundled-source regression test for the Open skies
  label.
- [x] Review the combined task-owned diff for data fidelity, compatibility,
  layout, semantics, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_trip.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/widgets/waypoint_trip_card.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same four paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its trip cover label"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the four owned paths:
  passed; 4 files inspected, 0 changed.
- `flutter analyze` on the four owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local demo
  renders its trip cover label"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 53 tests.
- Kuhn the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/domain/waypoint_trip.dart` —
  `9bf66f2331c79242f2ae48028d10366cd092688459d8e5e6e16337ca4e28b49d`
- `lib/waypoint/data/waypoint_json_decoder.dart` —
  `6d94625a35b80c13e836380352b49b6ee10de9c18df2f322487dca70fd22ff06`
- `lib/waypoint/presentation/widgets/waypoint_trip_card.dart` —
  `439bdc0656e85421cc756ad1d2091b5b6231baaca90208d8f4e380eceda1f9f4`
- `test/waypoint_app_test.dart` —
  `16d56be20f302fac45198a586b1e8f436390c3bc955bd53defac0f47af8bb0e7`
- Test declaration count in the owned app test file: `53`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–162 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented optional typed `coverLabel` propagation from the bundled trip
payload into the reusable trip card. Nonblank labels render with two-line
ellipsis and missing/blank values render no placeholder. The real Open skies
zero-latency regression test verifies the exact shipped label. Independent
strict review returned `ACCEPT`, and coordinator validation passed all 53 app
tests. No asset, dependency, platform, device, deployment, or AWS work was
introduced.

## References

- `tasks/161-trip-checklist-completion-coverage.md`
- `tasks/154-bundled-secondary-trip-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:32,55`
- `fixtures/flutter_conformance_app/assets/data/trips.json:11,36,55`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart:5-30`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:126-146,304-307`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_trip_card.dart:83-127`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:725-792`

## History

- 2026-08-30: Plato the 3rd performed a read-only audit. It found bundled
  `coverLabel` values in `home.json` and `trips.json` with no non-asset source,
  model, card, or test usage. The audit proposed this bounded four-path
  package; no files were changed or tested.
- 2026-08-30: Mill the 3rd implemented the bounded four-path package and
  reported the planned checks passing with 53 app tests.
- 2026-08-30: Kuhn the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; the data flow, blank-safe behavior, card compatibility,
  test authenticity, and scope were factually verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
