# Task 146 — Latest search result wins coverage

Status: [x] Completed

## Goal

Prove locally that an older delayed search response cannot overwrite the
results for a newer query.

## Scope and Non-goals

Scope:

- create a test-only delayed-search data-source wrapper;
- gate only the first non-empty `/api/search` response with a `Completer` and
  let the newer response resolve immediately;
- add exactly one widget test that submits Lisbon, then Kyoto, resolves the
  older Lisbon response late, and verifies Kyoto remains visible while Lisbon
  is absent;
- release the gate in teardown so failures cannot leave a pending future.

Non-goals:

- changing `WaypointSearchNotifier`, debounce behavior, cancellation, API
  contracts, filtering logic, or UI design;
- changing production code, dependencies, assets, or integration tests;
- claiming a current production defect beyond coverage of the existing
  generation guard;
- testing network, devices, simulators, Docker, AWS, hosting, or deployment.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 145 Trips checklist detail coverage;
- existing `WaypointDataSource`, `WaypointTestDataSource`, and
  `pumpWaypointTestApp` seams;
- existing Kyoto/Lisbon local fixture data;
- existing `WaypointSearchNotifier` generation guard and search UI keys.

## Assumptions

- the wrapper delegates all non-search requests to the existing local test
  source;
- the first non-empty search response is the Lisbon request and the second is
  the Kyoto request in the focused test;
- explicit completer release and `pumpAndSettle` provide deterministic ordering
  without sleeps or timers;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_test_support.dart` and
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- a production defect, if exposed, is reported rather than expanding scope.

## Work Items

- [x] Inspect the search notifier generation guard, current search tests,
  fixture data source, and prior task exclusions.
- [x] Add the test-only delayed-search source and focused race widget coverage.
- [x] Review the owned source/test changes for factual assertions,
  determinism, cleanup, and scope.
- [x] Run only formatting, scoped analysis, the named widget test, and the
  full changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and the next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_test_support.dart` `test/waypoint_app_test.dart`;
- `flutter analyze test/waypoint_test_support.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"latest search result wins when an earlier response resolves late"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The test-only race fixture gates the first non-empty search response,
allows the newer Kyoto response to resolve first, and verifies that the late
Lisbon response cannot replace Kyoto. No production code, dependency, asset,
device, Docker, AWS, hosting, or deployment files changed.

## Scope Manifest

No valid Git baseline is available for these untracked repository files, so the
manifest records the post-task hashes and the observed widget-test count:

- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart` —
  SHA-256 `8a58ce473d9a184798a16f57dad72eb71a19c3a76c1306183e1aa4ae1c69ed40`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — SHA-256
  `4503ae8a85f74fb9052e01c28f2ca1218503529d37d375e1167ab6cd5385d566`
- `testWidgets` declarations in `waypoint_app_test.dart` — `37`

## References

- `tasks/118-search-filter-resilience.md`
- `tasks/145-trips-checklist-detail-coverage.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_search_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Mencius the 3rd performed a read-only source audit after Task
  145. The audit found that the notifier already guards result publication by
  query generation, while current tests cover sequential filtering, empty and
  clear behavior, and retry but never resolve an older search response after a
  newer query. Task 118 explicitly excluded stale-generation testing. Task 146
  is limited to test support and one app widget test, with no production
  changes.
- 2026-08-29: Boyle the 3rd implemented the bounded test-only race fixture and
  widget test in the two owned test files. The worker reported formatting,
  scoped analysis, the named test, and the full app widget test file passing;
  strict coordinator review remains pending.
- 2026-08-29: Kepler the 3rd performed strict fact-based review and returned
  ACCEPT. The review verified the overlapping request order, generation-guard
  evidence, exact Kyoto/Lisbon assertions, idempotent teardown release, and
  test-only delegation without scope expansion.
- 2026-08-29: Coordinator ran the planned changed-file validation. Formatting
  reported two files and zero changes; scoped analysis reported no issues; the
  named race test passed; and all 37 tests in `waypoint_app_test.dart` passed.
