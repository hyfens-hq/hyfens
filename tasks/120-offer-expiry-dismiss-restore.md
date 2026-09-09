# Task 120 — Offer expiry, dismissal, and restore coverage

Status: [x] Completed

## Goal

Verify the Waypoint offer's time boundary and its user-visible dismiss/restore
behavior with deterministic local tests.

## Scope and Non-goals

Scope:

- cover `WaypointOffer.isActive` before expiry, at exact expiry, and after
  expiry;
- cover the active Discover banner being dismissible;
- cover Settings `Show banner` restoring a dismissed active banner;
- preserve the existing offer CTA/planning flow.

Non-goals:

- changing offer domain, clock, persistence, or UI behavior;
- real remote timing, push notifications, AWS, Docker, hosted deployment,
  device, or simulator work;
- implementing JSON-driven actions/forms, which remain an explicitly
  unapproved product scope;
- broad navigation or unrelated feature coverage;
- claiming production timing or persistence from local tests.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. Strict fact-based review is assigned
after implementation.

## Dependencies

- completed Task 119 planning coverage;
- existing `WaypointOffer`, `WaypointUiNotifier`, Discover, Settings, and test
  harness;
- existing local home payload with an active offer.

## Assumptions

- deterministic `DateTime` values are sufficient for domain expiry tests;
- the active local offer is sufficient to exercise dismiss/restore without
  changing production data;
- the worker owns `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  and may add `test/waypoint_offer_test.dart`;
- affected validation is limited to the changed offer/app test files.

## Work Items

- [x] Inspect offer expiry, dismiss, restore, and Settings control paths.
- [x] Add focused domain tests for the three expiry boundaries.
- [x] Add focused widget coverage for dismiss and Settings restore.
- [x] Review the task-owned diff for scope and factual correctness.
- [x] Run only formatting and the affected offer/app test files.
- [x] Obtain strict fact-based review and fix verified blocking findings.
- [x] Record outcome and next instruction.

## Validation

Planned affected-file validation only:

- `dart format --output=none --set-exit-if-changed` on changed offer/app test
  files completed with 0 changed;
- `flutter test test/waypoint_offer_test.dart test/waypoint_app_test.dart`
  from `fixtures/flutter_conformance_app`;
- result: `00:10 +21: All tests passed!`;
- no unrelated test files, device commands, simulator commands, Docker, AWS,
  or hosted-service checks.

## Next Action

Task 120 is complete. Reserve the next local-only task for Saved unsave and
empty-state navigation coverage. Do not infer persistence behavior.

## Blockers

None known.

## Outcome

The worker added `fixtures/flutter_conformance_app/test/waypoint_offer_test.dart`
with before/exact/after expiry tests and a focused dismiss -> Settings -> Show
banner -> Discover test in
`fixtures/flutter_conformance_app/test/waypoint_app_test.dart`. Existing offer
CTA/planning coverage remains intact. Formatting made no changes and the
combined affected tests passed with twenty-one tests. Strict review accepted the
implementation with no blocking findings.

## References

- `tasks/119-planning-form-boundaries.md`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_offer.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/application/waypoint_ui_notifier.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_settings_page.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart`

## History

- 2026-08-29: Reserved Task 120 from the read-only app-gap assessment. Scope is
  local offer expiry and dismiss/restore behavior only; no remote timing or
  unapproved JSON-action implementation is implied.
- 2026-08-29: Hubble the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  added the expiry boundary tests and dismiss/restore flow. The worker reported
  zero formatting changes and `00:10 +21: All tests passed!`. No production or
  external-service files were changed.
- 2026-08-29: Halley the 2nd (GPT-5.6 Luna Max, max reasoning, priority)
  reviewed exact expiry semantics, real dismiss control, Settings navigation and
  Show banner restoration, retained CTA coverage, animation timing, and the
  recorded test count. Result: `ACCEPT`, with no blocking findings. The
  reviewer recommended Saved unsave and empty-state navigation next.
