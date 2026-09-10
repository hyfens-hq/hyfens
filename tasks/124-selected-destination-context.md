# Task 124 — Preserve selected destination context on Discover return

Status: [x] Completed

## Goal

Preserve the saved destination selected from its detail sheet when the user
returns to Discover, so the existing comparison action gives visible context
instead of only changing sections.

## Scope and Non-goals

Scope:

- carry the selected destination identity through the existing Riverpod UI
  state path;
- show a small, explicit Discover context notice for that destination;
- clear stale context when leaving Discover through ordinary section
  navigation, where the current state model requires it;
- extend the existing Saved detail action test to verify the context notice.

Non-goals:

- adding a routing package, persistence, deep links, search behavior, or API;
- changing destination card layout or introducing a second destination data
  source;
- changing the existing Saved detail action, offer, permissions, Trips,
  Activity, or settings behavior beyond the selected-context handoff;
- device, simulator, Docker, AWS, or hosted-service work;
- speculative focus management, scrolling, animation, or generic selection
  abstractions.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 123 Saved detail Discover action;
- existing `WaypointUiState`, `WaypointUiNotifier`, Saved detail sheet, and
  Discover page;
- local Kyoto fixture and existing app widget test.

## Assumptions

- the selected destination ID is sufficient to resolve the destination from
  the existing `WaypointHomeData.destinations` list;
- a compact context notice on Discover is the smallest visible behavior that
  fulfills the reviewer’s highlight/focus recommendation;
- entering Discover through the Saved detail action should preserve context,
  while ordinary navigation away should not retain stale context;
- the worker owns only these five files:
  `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_state.dart`,
  `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`,
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`,
  `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`,
  and `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`;
- affected validation is limited to those changed source/test files.

## Work Items

- [x] Inspect the existing section state, Saved handoff, and Discover layout.
- [x] Add the smallest selected-destination state and handoff method.
- [x] Render a compact selected-destination context notice on Discover.
- [x] Extend focused widget coverage for Saved -> Discover context, including
  clearing stale context after ordinary navigation away.
- [x] Preserve and review Task 121/122/123 coverage.
- [x] Review the task-owned change for scope and factual correctness.
- [x] Run only formatting and the changed app test file.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/application/waypoint_ui_state.dart`
  `lib/waypoint/application/waypoint_ui_notifier.dart`
  `lib/waypoint/presentation/screens/waypoint_saved_page.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart` from `fixtures/flutter_conformance_app`;
- `flutter test test/waypoint_app_test.dart` from
  `fixtures/flutter_conformance_app`;
- result: the initial five-file formatting check reported 0 changes; the
  review-fix app-test-only formatting check also reported 0 changes; the
  affected app test run passed all nineteen tests (`+19`);
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

### Scope Manifest

The checkout has no valid `HEAD` and repository files are untracked, so Git
cannot provide a historical diff. The coordinator verified the Task 124
source-level scope as follows:

- implementation paths are exactly the five worker-owned files listed in the
  Assumptions section;
- the UI state adds one nullable selected-destination ID and its clear-copy
  support; the notifier adds one focused Saved-to-Discover handoff method;
- the Saved sheet passes the selected ID through that method;
- Discover resolves the ID from its existing home-data destinations and renders
  one keyed context notice;
- the app test extends the existing Saved detail flow with the context-notice
  assertion block at current lines 145–169 and the stale-context clearing flow
  at current lines 170–190;
- current SHA-256 values are
  `c861cdad409e6bcd701c0cb162cd30e83ff9a7286e0259b45ebab10d6748eedb` for
  `waypoint_ui_state.dart`,
  `67df13b6562d4aba42c14995e3b6ca76a29e0e615e2724ff1b287afde8474e48` for
  `waypoint_ui_notifier.dart`,
  `256d6d6d548f3313d20dd6b610b8f1e79b00f30052fcd125ee5c70c28d074678` for
  `waypoint_saved_page.dart`,
  `8b79a8268b8e0708f7db21b907156f1fca1e49b8bece01c6331cd9d2761c20ba` for
  `waypoint_discover_page.dart`, and
  `eb9d920ee185511df465d5d528518ceb655a20a064fa26000414d5410c9a7f92` for
  `waypoint_app_test.dart`;
- the worker reported no other files modified, and no unrelated file was
  observed in the task-owned inspection;
- this manifest records the missing Git provenance explicitly and does not
  claim a commit, tracked baseline, or persistence behavior.

## Next Action

Task 124 is complete. Reserve the next local-only task for wide-layout
navigation-rail coverage of the same context-clearing behavior.

## Blockers

None known.

## Outcome

The worker updated only the five assigned state, notifier, Saved, Discover, and
app-test files. Selected destination context now flows through Riverpod, the
Discover page renders a keyed Kyoto notice, and ordinary navigation away clears
the context. Formatting reported 0 changes and the affected app test file
passed all nineteen tests. The first strict review found the clearing logic
correct but required an explicit test for that state transition. The test-only
fix establishes context, navigates through real Trips and Discover controls,
and asserts the notice is absent. Fresh strict review accepted the complete
behavior, scope manifest, and validation with no blocking findings or fixes
required.

## References

- `tasks/123-saved-sheet-discover-action.md`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_state.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Reserved Task 124 from the accepted Task 123 review. Scope is
  selected-destination context on Discover only; no persistence, routing
  package, or speculative focus behavior is implied.
- 2026-08-29: Ptolemy the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  updated only the five owned files. The worker reported 0 formatting changes
  and `flutter test test/waypoint_app_test.dart` passing all nineteen tests.
- 2026-08-29: Erdos the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  strictly verified the state handoff, Discover notice, scope manifest, and
  validation, but rejected the task because the stale-context clearing path was
  not covered by a test. No source-logic defect was found; a focused test-only
  fix is required.
- 2026-08-29: James the 2nd (GPT-5.6 Luna Max, max reasoning, priority) added
  the requested Trips -> Discover navigation assertions and verified the
  selected-context key is absent after return. The worker reported 0 formatting
  changes and all nineteen affected app tests passing. Fresh strict review is
  required.
- 2026-08-29: Pauli the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  re-reviewed the corrected test coverage, state handoff, source-level scope
  manifest, and validation. Result: `ACCEPT`; no blocking findings or fixes
  required. The next instruction is wide-layout navigation-rail coverage.
