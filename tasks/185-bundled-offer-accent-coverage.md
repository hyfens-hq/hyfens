# Task 185 — Bundled offer accent coverage

Status: [x] Completed

## Goal

Prove that the bundled offer accent value is decoded and applied to the rendered offer banner background.

## Scope and Non-goals

Scope:

- Extend the existing real bundled time-limited-offer widget test with an exact keyed banner `BoxDecoration.color` assertion.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, offer action, dismissibility, expiry behavior, copy, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `test/waypoint_app_test.dart`.
- Do not use synthetic offer data or global/ambiguous widget lookups.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled `home.json` offer accent value.
- Existing `WaypointJsonDecoder.decodeOffer` mapping and keyed `WaypointOfferBanner` root container.
- Existing real bundled offer test and zero-latency local AlphaX/demo source.

## Assumptions

- The bundled offer accent `#E47755` is expected as `Color(0xFFE47755)` after `waypointColor` conversion.
- The `waypoint-offer-banner` key identifies the banner root `Container`, whose decoration contains the applied color.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit bundled offer accent value, decoder/UI path, existing test, and completed-task boundary.
- [x] Add the exact keyed banner color assertion to the existing bundled offer test.
- [x] Review the task-owned test diff for source fidelity, keyed scoping, and preservation of existing offer assertions.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named offer test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart

flutter analyze test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its time-limited offer"

flutter test test/waypoint_app_test.dart
```

Only `test/waypoint_app_test.dart` is in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

The real bundled offer test now proves the source accent `#E47755` reaches the keyed banner `BoxDecoration` as `Color(0xFFE47755)`, while all existing offer behavior assertions remain. No production code, fixture data, or dependencies changed.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:14-24` — bundled offer record and `#E47755` accent.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:191-204` — offer accent decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_offer_banner.dart:20-26` — keyed root container and accent application.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:213-288` — existing real bundled offer test with the banner-color assertion and prior offer coverage.
- `tasks/172-bundled-offer-planner-handoff-coverage.md` — prior offer-action coverage boundary.
- `tasks/174-bundled-offer-dismissibility-coverage.md` — prior offer-dismissibility coverage boundary.
- `tasks/184-bundled-destination-accent-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Leibniz the 4th completed a fresh read-only audit and identified unasserted bundled offer banner accent propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the source color, decoder mapping, keyed banner container, and existing real-offer test boundary.
- 2026-08-30 — Coordinator reserved Task 185 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Parfit the 4th extended the existing bundled offer test with the keyed `BoxDecoration` color assertion; worker-reported named validation passed (`+1`) and only `test/waypoint_app_test.dart` changed.
- 2026-08-30 — Chandrasekhar the 4th independently accepted the implementation with no High, Medium, or Low findings; the coordinator applied formatting before final review.
- 2026-08-30 — Fermat the 4th final strict review accepted the formatted source; two Low task-reference issues were corrected: the offer test range was updated to `213-288`, and the Task 172 filename was corrected to `tasks/172-bundled-offer-planner-handoff-coverage.md`.
- 2026-08-30 — Hilbert the 4th performed the final strict review and accepted with no High, Medium, or Low findings after the reference corrections.
- 2026-08-30 — Coordinator direct scope check found only `test/waypoint_app_test.dart` newer than the Task 185 record; the checkout has no usable Git `HEAD`, so scope provenance is based on direct file inspection.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` (`Formatted 1 file (0 changed)`); `flutter analyze test/waypoint_app_test.dart` (`No issues found`); named offer test (`+1`); and `flutter test test/waypoint_app_test.dart` (`68` tests passed). No device, simulator, Docker, AWS, hosting, or unrelated test validation was run.
