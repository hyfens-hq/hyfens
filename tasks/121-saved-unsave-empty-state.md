# Task 121 — Saved unsave and empty-state navigation coverage

Status: [x] Completed

## Goal

Verify that a saved destination can be removed from the Saved section and that
the empty state offers a working route back to Discover.

## Scope and Non-goals

Scope:

- cover the existing Saved card remove action through the real widget;
- verify the saved count and empty-state copy after removal;
- verify the empty-state Browse destinations action returns to Discover;
- preserve the existing save flow and Saved navigation coverage.

Non-goals:

- changing Saved production behavior or adding persistence;
- adding a new storage layer, repository, API, or state abstraction;
- broad navigation, Trips, Activity, device, simulator, Docker, AWS, or
  hosted-service work;
- inferring behavior for destinations not present in the local fixture;
- adding tests outside the affected app test file.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 120 offer coverage;
- existing Saved page, destination card, notifier override, and app test
  harness;
- local home fixture containing Kyoto as a saved destination after the existing
  save interaction.

## Assumptions

- the existing `waypoint-save-kyoto` key is the production card action in both
  Discover and Saved contexts;
- the existing `waypoint-saved-discover` key is the empty-state navigation
  action;
- the behavior is in-memory for this demo and no persistence claim is needed;
- the worker owns only
  `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to that changed test file.

## Work Items

- [x] Inspect Saved page, card remove action, empty-state action, and current
  app tests.
- [x] Add focused widget coverage for removing the only saved destination.
- [x] Add focused widget coverage for the empty-state Browse destinations
  action.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: formatting reported 0 changes and the affected app test run passed
  all eighteen tests (`+18`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 121 is complete. Reserve the next local-only task for Saved Kyoto detail
bottom-sheet coverage. Do not infer persistence behavior.

## Blockers

None known.

## Outcome

The worker updated only
`fixtures/flutter_conformance_app/test/waypoint_app_test.dart`, extending the
existing save flow through Saved removal, empty-state assertions, and the
Browse destinations return to Discover. Formatting reported 0 changes and the
affected app test file passed all eighteen tests. The first strict review found
and required correction of an inaccurate nineteen-test task-record count; no
production or test-code defect was found. A fresh strict review accepted the
corrected record with no blocking findings.

## References

- `tasks/120-offer-expiry-dismiss-restore.md`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 121 from the strict Task 120 recommendation.
  Scope is local widget coverage for Saved unsave and empty-state navigation;
  no persistence or production behavior change is implied.
- 2026-08-29: Curie the 2nd (GPT-5.6 Luna Max, max reasoning, priority) updated
  only the owned app test file. The worker reported 0 formatting changes and
  `flutter test test/waypoint_app_test.dart` passing all nineteen tests.
- 2026-08-29: Mencius the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly reviewed the real controls and found no code-scope defect, but
  rejected the task record because the source contains eighteen `testWidgets`
  declarations and the run ended at `+18`, not `+19`. The validation and
  outcome records were corrected; fresh strict review is required.
- 2026-08-29: Pascal the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  re-reviewed the corrected count, real control wiring, and test-only scope.
  Result: `ACCEPT`; no blocking findings or fixes required. The next
  instruction is Saved Kyoto detail bottom-sheet coverage.
