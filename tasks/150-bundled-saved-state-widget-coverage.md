# Task 150 — Bundled Saved state widget coverage

Status: [x] Completed

## Goal

Prove through the real bundled local transport that an initially saved
destination is rendered as saved in Discover and appears in Saved without a
user toggle.

## Scope and Non-goals

Scope:

- add exactly one local app widget test to the existing Waypoint app test file;
- use `WaypointAlphaXDataSource` with the bundled `WaypointDemoTransport` at
  zero latency;
- verify the real bundled Lantern House card, its `Remove saved place` state,
  and its presence in Saved with the expected count.

Non-goals:

- changing production code, asset JSON, saved-state persistence, Saved removal
  or detail behavior, transport contracts, dependencies, support fixtures, or
  other tests;
- changing any other screen or adding a new fixture;
- testing devices, simulators, Docker, AWS, hosting, deployment, or an online
  data source.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 149 Activity navigation-away cancellation;
- bundled `home.json` Lantern House entry with `saved: true`;
- existing `WaypointDemoTransport`, `WaypointAlphaXDataSource`, and
  `WaypointRepository` local seams;
- existing Discover/Saved navigation and destination-card stable keys;
- existing app widget test harness and Saved page count copy.

## Assumptions

- the bundled demo transport merges `home.json` and Discover places into the
  real home payload used by the app;
- the JSON decoder preserves the saved flag and `waypointSavedProvider` uses it
  when no UI override exists;
- zero transport latency keeps the real-source widget test deterministic;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect exposed by this test is reported rather than expanding
  the test-only package.

## Work Items

- [x] Inspect the bundled saved asset, real local transport/decoder/provider,
  Saved page, existing harness, and prior task boundaries.
- [x] Add exactly one real-source Saved-state widget regression test.
- [x] Review the owned test for real-source usage, exact saved assertions,
  cleanup, determinism, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome, validation evidence, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo preserves its initial saved destination"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported one file
  and zero changes; scoped analysis reported no issues; the named regression
  test passed once; and the full app widget test passed all forty-one tests.
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended one-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `03629497566bbf5245a802233f3aa718e6f3afd96dc620243b276c7854280567`
- `testWidgets` declarations in `waypoint_app_test.dart` — `41`, including
  exactly one Task-150-named case.

The worker reported no other implementation paths changed; the missing Git
baseline is retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The bundled AlphaX/local transport path is now covered by one widget
test proving that Lantern House arrives initially saved, renders the exact
`Remove saved place` action without a toggle, and appears in the real Saved
page with one saved place. No production, asset, dependency, support,
platform, external-service, or deployment behavior changed.

## References

- `tasks/99-waypoint-demo-app.md`
- `tasks/149-activity-navigation-away-cancellation.md`
- `fixtures/flutter_conformance_app/assets/data/home.json`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_providers.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_demo_data_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Feynman the 3rd performed a read-only source audit after Task
  149. The audit found that the bundled Lantern House asset is initially
  saved, the real local transport and decoder preserve that state, and the
  Saved provider/page render it, while the widget harness marks its test
  destinations unsaved and current UI tests toggle Kyoto before entering
  Saved. Task 150 is limited to one real-source local widget test.
- 2026-08-29: Harvey the 3rd added exactly one real-source widget test in the
  reserved app test file. The test uses zero-latency `WaypointDemoTransport`,
  closes the injected source in teardown, verifies Lantern House's initial
  saved action, and verifies the Saved page count. Worker validation reported
  formatting, scoped analysis, the named test, and the full app widget test
  passing with forty-one tests.
- 2026-08-29: Helmholtz the 3rd strictly reviewed the test and returned ACCEPT.
  The review verified the AlphaX/local seam, teardown, bundled `saved: true`
  path, exact initial action and Saved count, one-test scope, and provenance
  limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation: format
  exited 0 with one file unchanged, scoped analysis exited 0 with no issues,
  the named test passed once, and the full app widget test exited 0 with all
  forty-one tests passing.
