# Task 201 — Dismissed-offer Settings guidance coverage

Status: [x] Completed

## Goal

Prove that Settings gives the user explicit feedback while an offer is dismissed and removes that feedback after the offer is restored.

## Scope and Non-goals

Scope:

- Extend the existing dismissed-offer restore widget test with exact assertions for the Settings guidance message before and after restoration.
- Preserve the existing dismiss, restore, navigation, and visible-banner assertions.

Non-goals:

- Do not change production code, bundled JSON/assets, models, decoder, repository, dependencies, or other tests.
- Do not test offer expiry, banner rendering, planning submission, device/simulator/Docker/AWS/hosting/deployment, screenshots, or unrelated Settings controls.
- Do not add a duplicate offer flow, synthetic production behavior, new key, or abstraction.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- `WaypointUiNotifier.dismissOffer` and `restoreOffer` state transitions.
- Conditional dismissed-offer guidance in `WaypointSettingsPage`.
- Existing `restores a dismissed active offer from Settings` widget test.

## Assumptions

- After the existing banner dismiss action, Settings renders exactly `The offer is currently dismissed. Use Show banner to test it again.`.
- After the existing Show banner action and one pump, that guidance is absent and the current test can continue to verify the restored Discover banner.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the dismissed-offer state path, Settings conditional rendering, existing restore test, and task boundary.
- [x] Add exact guidance-present and guidance-absent assertions to the existing restore test.
- [x] Review the task-owned test diff for source fidelity, state timing, stable scoping, cleanup, and preservation of existing assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named restore test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "restores a dismissed active offer from Settings"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or deployment validation is required.

## Next Action

Audit the next supported local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD` or tracked index; direct file evidence and the explicit test-only scope are required for review.

## Outcome

Completed as a test-only extension of the existing dismissed-offer restore flow. The test now verifies that Settings renders `The offer is currently dismissed. Use Show banner to test it again.` after dismissal and removes that guidance after the keyed Show banner action restores the offer, while preserving the existing Discover navigation and visible-banner assertions. No production, fixture, dependency, or other test files changed.

Hume the 5th completed the strict independent review with `ACCEPT — no findings`, confirming the state timing, exact message, existing flow, and task boundary. The checkout has no usable Git `HEAD` or tracked index, so historical preservation of pre-existing untracked content cannot be independently proven; this provenance limitation is recorded without speculative changes.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named dismissed-offer restore selector — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+69: All tests passed!`.

## References

- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart:55-59` — dismissed-offer state transition.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart:289-300` — conditional Settings guidance and restore control context.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:3021-3072` — existing dismiss/restore flow, guidance assertions, and restored Discover banner assertion.
- `tasks/200-bundled-settings-media-dismiss-coverage.md` — preceding completed local Settings coverage task.

## History

- 2026-08-30 — Coordinator directly audited the dismissed-offer state transition, Settings conditional guidance, existing restore test, and task boundary; no files changed during the audit.
- 2026-08-30 — Coordinator reserved Task 201 with a bounded single-file test implementation, strict review, and local validation scope.
- 2026-08-30 — Newton the 5th added only the guidance-present and guidance-absent assertions in `waypoint_app_test.dart`; no tests were run by the worker.
- 2026-08-30 — Coordinator formatted the bounded test insertion before review.
- 2026-08-30 — Hume the 5th completed the strict independent review with `ACCEPT — no findings`.
- 2026-08-30 — Coordinator completed scoped validation: format clean, analyzer clean, named dismissed-offer restore test passed, and all 69 tests in the affected app test file passed.
