# Task 174 — Bundled offer dismissibility coverage

Status: [x] Completed

## Goal

Preserve the bundled offer's `dismissible` metadata through the local domain/decoder seam and render the existing offer close control only when the decoded offer permits dismissal, while keeping legacy offers dismissible by default.

## Scope and Non-goals

Scope:

- Add the smallest typed dismissibility property to `WaypointOffer` with a backward-compatible default.
- Decode the existing `dismissible` boolean from the offer payload, using the default for missing or non-boolean values.
- Conditionally render the existing `waypoint-offer-dismiss` control in `WaypointOfferBanner`.
- Extend the existing app test file to prove the bundled `true` path and a local synthetic `false` path.

Non-goals:

- Do not edit bundled JSON/assets, transport, repository, expiry handling, offer action/CTA or planner handoff, `banner.kind`, UI dismissal/restore state, dependencies, or unrelated tests.
- Do not change offer copy, layout beyond hiding the existing close control, settings behavior, or external/device infrastructure.
- Do not add a generic banner configuration system or change completed task files.
- No AWS, online hosting, Docker, simulator, or physical-device work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing `home.json` `banner.dismissible: true` payload.
- Existing `WaypointOffer` decoder and `WaypointOfferBanner` seam.
- Existing local bundled offer test and `WaypointOffer` constructor.
- No new dependency.

## Assumptions

- The domain property may be named according to repository convention, but it must represent the JSON `dismissible` flag clearly.
- Missing or non-boolean `dismissible` preserves current behavior by defaulting to `true`; explicit boolean `false` hides only the dismiss control.
- Existing action, expiry, dismissal, restoration, and banner rendering behavior remain unchanged when the flag is `true`.
- The existing `waypoint_app_test.dart` is the only test file changed; the bundled test proves `true`, and one focused synthetic banner test proves `false`.

## Work Items

- [x] Audit the bundled offer payload, model, decoder, banner, existing dismissal state, tests, and completed-task boundary.
- [x] Add the typed dismissibility property, decoder preservation, conditional close-control rendering, and focused tests within the four-file scope.
- [x] Review the combined four-path diff for correctness, compatibility, scope, and test adequacy.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, focused offer tests, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/domain/waypoint_offer.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/widgets/waypoint_offer_banner.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/domain/waypoint_offer.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/widgets/waypoint_offer_banner.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its time-limited offer"

flutter test test/waypoint_app_test.dart
```

Only the four task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit four-file scope.

## Outcome

The bundled offer's `dismissible` metadata now reaches `WaypointOffer`; the existing close control is rendered only for dismissible offers, with missing or non-boolean metadata retaining the legacy dismissible default. Bundled `true` and synthetic `false` behavior are covered.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:21` — bundled `dismissible: true` declaration.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_offer.dart` — current offer domain contract without dismissibility.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:190-201` — current offer decoding boundary.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_offer_banner.dart:58-64` — unconditional close control.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:210-275` — bundled offer copy/action coverage.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:2156-2190` — existing dismissal flow coverage.
- `fixtures/flutter_conformance_app/test/waypoint_test_support.dart:459-477` — synthetic offer without a dismissibility field, preserving the default case.
- `tasks/173-bundled-planner-field-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Faraday the 4th completed a read-only audit and identified dropped bundled offer dismissibility metadata; no files changed.
- 2026-08-30 — Coordinator reserved Task 174 with a bounded four-file implementation, review, and local validation scope.
- 2026-08-30 — Linnaeus the 4th implemented the four-file change: default-true `WaypointOffer.isDismissible`, boolean decoder preservation, conditional close control, and bundled/synthetic widget coverage.
- 2026-08-30 — Ptolemy the 4th independently accepted the source with no High or Medium findings; its only Low finding was stale task-record status, which the coordinator corrected.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed` over the four paths (4 formatted, 0 changed); scoped `flutter analyze` over the four paths (no issues); the named bundled offer test (`+1`); and `flutter test test/waypoint_app_test.dart` (`61` tests passed). The initial analyzer invocation contained a coordinator path typo and was not counted; the corrected command passed. No device, simulator, Docker, AWS, or unrelated test validation was run.
