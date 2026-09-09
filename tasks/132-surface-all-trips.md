# Task 132 — Surface all loaded Trips

Status: [x] Completed

## Goal

Make the Trips page render every loaded trip while preserving the current
featured first-trip presentation, empty state, and existing detail sheet.

## Scope and Non-goals

Scope:

- keep the first trip in the existing featured card and planning pulse;
- render additional loaded trips using the existing keyed
  `WaypointTripCard` component;
- route an additional trip to the existing `_showTrip` detail sheet;
- extend the existing app widget test with a second in-memory trip and verify
  both cards plus the second trip's detail content.

Non-goals:

- changing models, JSON decoding, repositories, navigation, persistence, or
  API contracts;
- changing the default asset payload or adding assets;
- changing Activity, permissions, dashboards, planning behavior, or the empty
  state;
- adding dependencies or responsive/layout systems beyond the smallest
  overflow-safe collection needed for the extra cards;
- device, simulator, Docker, AWS, hosting, or deployment work.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Dependencies

- completed Task 131 and the current `WaypointHomeData.trips` list;
- existing `WaypointTripCard` stable key and tap callback;
- existing `_showTrip` detail sheet;
- `WaypointTestDataSource(home: ...)` and `waypointTestHomePayload()` in the
  existing test harness.

## Assumptions

- `data.trips.first` is intentionally the current featured trip and should
  remain unchanged;
- additional trips can be represented by the existing JSON-shaped in-memory
  test payload without modifying test support;
- the worker owns only these two paths:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  and
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to formatting those two files and the changed
  app widget test file.

## Work Items

- [x] Inspect the Trips page, card/detail components, payload, and test seam.
- [x] Render additional loaded trips without changing the featured trip.
- [x] Add focused two-trip card and secondary-detail widget coverage.
- [x] Review the task-owned diff for correctness, scope, layout safety, and
  regressions.
- [x] Run only formatting and the changed app widget test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next source-based instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/screens/waypoint_trips_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart`;
- worker and strict reviewer reported formatting with two files and zero
  changes, and the app test passing all twenty-four tests (`+24`);
- coordinator post-review validation: `dart format --output=none
  --set-exit-if-changed lib/waypoint/presentation/screens/waypoint_trips_page.dart
  test/waypoint_app_test.dart` reported two files with zero changes;
- coordinator post-review validation: `flutter test
  test/waypoint_app_test.dart` exited 0 with all twenty-four tests passing
  (`+24`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and the named repository files are untracked,
so Git cannot provide historical diff provenance. The coordinator verified the
Task 132 scope directly:

- production Trips page path:
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`;
  SHA-256 `c681172dd54d8b3fc5e54c237758b92f4d82036c9e5297adcb491b17367092d6`;
- app widget test path:
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
  SHA-256 `6f6f10260834c4a3ba25df2edc0c27baf68050b8d27427d0004743666f6102fe`;
- the app test source contains exactly twenty-four `testWidgets` cases;
- the task-owned status is limited to these two paths and this task record;
  no unrelated file was modified by the package.

## Next Action

Task 132 is complete. Reserve the next numbered package only after a fresh
source inspection identifies the next bounded local capability.

## Blockers

None known.

## Outcome

The Trips page now preserves the first loaded trip as the featured card and
renders every additional trip through the existing `WaypointTripCard` and
detail sheet path. Focused coverage supplies a second local trip, verifies both
stable card keys, scrolls to the second card, and verifies its title,
destination, and itinerary. The worker, strict reviewer, and coordinator
validation all report twenty-four app widget tests passing. Strict review
returned `ACCEPT` with no blocking findings. The only limitation recorded is
the checkout's missing Git `HEAD` and untracked-file state.

## References

- `tasks/131-activity-stream-retry.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_trips_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_trip_card.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_trip.dart`
- `fixtures/flutter_conformance_app/assets/data/home.json`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`

## History

- 2026-08-29: Reserved after Harvey the 2nd's source review. The current page
  selects `data.trips.first`, while the production local payload includes the
  additional `lisbon-light` trip and the existing card/detail path accepts any
  `WaypointTrip`. Scope is limited to the page and app widget test.
- 2026-08-29: Carson the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the page and app widget test. The worker added a responsive
  `data.trips.skip(1)` card collection and a two-trip secondary-detail test,
  with scoped formatting unchanged and twenty-four app tests passing. No task
  file was modified.
- 2026-08-29: Avicenna the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  independently reviewed preservation of the featured trip, additional-card
  layout bounds, secondary-detail assertions, empty/one-trip behavior, and
  the two-file scope. Result: `ACCEPT`; no blocking findings or fixes
  required. The reviewer confirmed the source contains twenty-four widget
  tests and the scoped test passed.
- 2026-08-29: Coordinator final validation passed: scoped formatting reported
  two files with zero changes, and `flutter test test/waypoint_app_test.dart`
  passed all twenty-four tests. Task 132 is complete; no device, simulator,
  Docker, AWS, or hosted-service validation was needed.
