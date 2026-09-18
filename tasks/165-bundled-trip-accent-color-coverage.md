# Task 165 — Bundled trip accent-color rendering

Status: [x] Completed

## Goal

Preserve each bundled trip's optional accent color and use it for that trip
card's progress fill while retaining the current fallback behavior.

## Scope and Non-goals

Scope:

- add an optional typed `accentColor` field to `WaypointTrip`;
- decode the existing `accent`/`accentColor` value with the established
  compatibility convention;
- use the existing `waypointColor` helper for the trip card progress fill;
- fall back to `WaypointColors.mint` when the value is missing or blank;
- add exactly one real zero-latency bundled-source widget test asserting the
  shipped Open skies progress color.

Non-goals:

- changing JSON/assets, transport, merge logic, progress values or
  calculation, card copy/layout/navigation, other screens, dependencies,
  support fixtures, platform files, devices, simulators, Docker, AWS,
  hosting, deployment, or external services;
- changing card semantics, tap behavior, progress percentage text, or any
  existing color tokens/helper;
- adding a color parser, broad theming refactor, or tests outside the owned app
  test file.

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

- completed Task 164;
- existing bundled trip records in `home.json` and `trips.json`;
- existing `waypointColor`/`WaypointColors.mint` helper and reusable
  `WaypointTripCard`;
- existing bundled AlphaX/demo source and widget-test harness.

## Assumptions

- shipped bundled accent values are valid six-digit hex colors, including
  Open skies `#5EB9A1`;
- missing or blank accent values remain compatible with synthetic payloads and
  use the current mint fallback;
- numeric progress and all other card content remain unchanged;
- the worker owns only the four paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit bundled accent values, model, decoder, color helper, card, tests,
  and prior task exclusions.
- [x] Add optional typed accent decoding with missing/blank fallback.
- [x] Bind the existing card progress fill to the decoded trip accent.
- [x] Add exactly one real bundled-source regression test for Open skies.
- [x] Review the combined task-owned diff for data fidelity, fallback,
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
  `lib/waypoint/domain/waypoint_trip.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/widgets/waypoint_trip_card.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same four paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its trip accent"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the four owned paths:
  passed; 4 files inspected, 0 changed.
- `flutter analyze` on the four owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local demo
  renders its trip accent"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 56 tests.
- Ampere the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/domain/waypoint_trip.dart` —
  `5e9fdc138648bf90442ee02faa04dfbfd128d14ff4c38404beb2d07ba0f08e79`
- `lib/waypoint/data/waypoint_json_decoder.dart` —
  `948800a2eaeb565b8babeef0ed36f741c7c0c47fe5eea036447ced5e29427b93`
- `lib/waypoint/presentation/widgets/waypoint_trip_card.dart` —
  `dea5f61124ebb72aa854254e9721aeb9c2bbaac77f5f78b97b2e48663ebc83e4`
- `test/waypoint_app_test.dart` —
  `e467e2d20f40193228006408a614897bc43937c3676a3ac2617f5eb32fc5e569`
- Test declaration count in the owned app test file: `56`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–165 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented optional trip accent propagation from the existing bundled
`accent`/`accentColor` values into the reusable card's progress fill, with the
existing mint fallback preserved. The real Open skies test verifies the
rendered `Color(0xFF5EB9A1)`. Independent strict review returned `ACCEPT`, and
coordinator validation passed all 56 app tests. No JSON, dependency, platform,
device, deployment, or AWS work was introduced.

## References

- `tasks/164-bundled-home-banner-content-coverage.md`
- `tasks/162-bundled-trip-cover-label-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:25-58`
- `fixtures/flutter_conformance_app/assets/data/trips.json:49-61`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart:5-30`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:126-147`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/waypoint_theme.dart:22-28`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_trip_card.dart:108-121`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:854-973`

## History

- 2026-08-30: Hubble the 3rd performed a read-only audit. It found trip
  `accent` values in the bundled payloads, an existing color helper, and a
  hard-coded mint progress fill with no model/decoder/card/test coverage. The
  audit proposed this bounded four-path package; no files were changed or
  tested.
- 2026-08-30: Dalton the 3rd implemented the bounded four-path package and
  reported the planned checks passing with 56 app tests.
- 2026-08-30: Ampere the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; optional decoding, mint fallback, progress-fill binding,
  rendered color assertion, compatibility, and scope were factually verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
