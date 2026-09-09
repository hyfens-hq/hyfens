# Task 164 — Bundled home banner content coverage

Status: [x] Completed

## Goal

Verify that the bundled `home.json` time-limited banner reaches the initial
Discover UI with its exact user-visible title, message, and CTA.

## Scope and Non-goals

Scope:

- add exactly one real bundled-source widget test;
- load the app through `WaypointAlphaXDataSource` and
  `WaypointDemoTransport(latency: Duration.zero)`;
- assert the visible banner, exact bundled title, exact bundled message, and
  exact bundled CTA on the initial Discover page;
- reuse the established root-bundle reset, bounded load wait, and safe source
  teardown patterns.

Non-goals:

- changing production code, model, decoder, JSON/assets, transport,
  dependencies, navigation, expiry, dismiss/restore behavior, planning flow,
  or existing banner lifecycle tests;
- adding a generic action engine, metadata abstraction, fixture refresh, or
  any new test support;
- device, simulator, Docker, AWS, hosting, deployment, or online validation.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly one path:

- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 163;
- bundled `home.json` banner data;
- existing `WaypointAlphaXDataSource`, `WaypointDemoTransport`,
  `pumpWaypointTestApp`, and `WaypointOfferBanner`;
- existing offer lifecycle coverage and bundled home-data test seam.

## Assumptions

- `home.json` remains the source of truth for the banner copy;
- the shipped banner remains active before its existing 2030 expiry;
- the existing root-bundle reset and finite load wait are sufficient for a
  deterministic local bundled-source test;
- the owned app test file currently has 54 widget tests, so this test should
  bring the count to 55;
- the worker owns only the test path listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed test file and local bundled data.

## Work Items

- [x] Audit bundled banner data, local source/decoder/UI path, existing tests,
  and prior task exclusions.
- [x] Add exactly one real bundled-source widget test for title, message, and
  CTA.
- [x] Review the combined task-owned diff for source authenticity, assertion
  strength, isolation, teardown, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its time-limited offer"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart`:
  passed; 1 file inspected, 0 changed.
- `flutter analyze test/waypoint_app_test.dart`: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local demo
  renders its time-limited offer"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 55 tests.
- Godel the 3rd independently reviewed the task-owned test and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `test/waypoint_app_test.dart` —
  `60d433d3ef20fd68fb115650dbc123197c40247ddf4ea854a16cc757b5821105`
- Test declaration count in the owned app test file: `55`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–164 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Added one real bundled-source widget test proving that the initial Discover
banner renders the exact title, message, and CTA shipped in `home.json`.
Independent strict review returned `ACCEPT`, and coordinator validation passed
all 55 app tests. No production, data, dependency, platform, device,
deployment, or AWS work was introduced.

## References

- `tasks/163-bundled-trip-detail-itinerary-completion-coverage.md`
- `tasks/155-bundled-home-hero-coverage.md`
- `tasks/120-offer-expiry-dismiss-restore.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:14-23`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:286-318`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:184-194`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_offer_banner.dart:19-63`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:24-41,1803-1879`
- `fixtures/flutter_conformance_app/test/waypoint_demo_data_test.dart:37-70`

## History

- 2026-08-30: Mendel the 3rd performed a read-only audit. It found the real
  bundled banner path and lifecycle coverage but no widget assertion for the
  exact bundled title, message, and CTA. The audit proposed this bounded
  one-path test package; no files were changed or tested.
- 2026-08-30: Dirac the 3rd added the single bundled-source banner-content test
  and reported the planned checks passing with 55 app tests.
- 2026-08-30: Godel the 3rd independently reviewed the task-owned test and
  returned `ACCEPT`; exact rendered copy, real-source setup, isolation,
  teardown, and scope were factually verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
