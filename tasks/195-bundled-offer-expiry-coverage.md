# Task 195 — Bundled offer expiry coverage

Status: [x] Completed

## Goal

Prove that the real bundled time-limited offer expiry reaches the rendered offer widget and supports its active-state gate.

## Scope and Non-goals

Scope:

- Extend the existing real bundled time-limited offer widget test with one exact `WaypointOffer.expiresAt` assertion from the rendered banner.

Non-goals:

- Do not change production code, JSON/assets, models, decoder, repository, offer visibility logic, dismissibility, action, accent, planner behavior, navigation, dependencies, or infrastructure.
- Do not add a new test declaration or test file; do not change tests outside `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.
- Do not use synthetic offer data or infer expiry from current wall-clock visibility.
- No device, simulator, Docker, AWS, hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Bundled offer `expiresAt` value in `home.json`.
- Existing `WaypointJsonDecoder.decodeOffer` parsing and `WaypointOfferBanner` widget payload.
- Existing real zero-latency bundled time-limited offer test with banner key, content, action, and cleanup.

## Assumptions

- The bundled `2030-06-30T23:59:59Z` value is represented by the decoded widget as `DateTime.utc(2030, 6, 30, 23, 59, 59)`.
- The existing `waypoint-offer-banner` key uniquely identifies the rendered bundled offer widget.
- Validation targets only the changed app test file.

## Work Items

- [x] Audit the bundled expiry value, decoder/model/rendering path, existing coverage, and completed-task boundary.
- [x] Add one exact rendered-offer expiry assertion to the existing time-limited offer test.
- [x] Review the task-owned test diff for source fidelity, correct widget payload access, and preservation of existing assertions.
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

Audit the next uncovered local fixture capability and reserve the next task only after direct source and test evidence identifies a bounded gap.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit test-only scope.

## Outcome

Completed as a test-only extension of the existing real bundled time-limited offer test. The test now reads the rendered `WaypointOfferBanner.offer.expiresAt` and verifies the exact UTC expiry from the bundled payload, while preserving the existing banner, action, navigation, and cleanup assertions. No production, fixture, dependency, device, simulator, Docker, AWS, hosting, or deployment work was required.

Validation passed from `fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed test/waypoint_app_test.dart` — `Formatted 1 file (0 changed)`.
- `flutter analyze test/waypoint_app_test.dart` — `No issues found!`.
- Named offer selector — `+1: All tests passed!`.
- `flutter test test/waypoint_app_test.dart` — `+68: All tests passed!`.

The repository has no usable Git `HEAD`; review and scope evidence therefore used direct file inspection and the explicit single-file ownership boundary. No unrelated test files were validated.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:14-20` — bundled time-limited offer expiry.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:190-203` — offer expiry parsing and model construction.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_offer.dart:1-22` — expiry field and active-state predicate.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:72-75,158-161` — expiry-gated offer rendering.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_offer_banner.dart:6-20` — rendered offer widget payload/key.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:213-288` — existing real bundled time-limited offer test.
- `tasks/174-bundled-offer-dismissibility-coverage.md` — prior offer visibility/control coverage boundary.
- `tasks/185-bundled-offer-accent-coverage.md` — prior offer accent coverage boundary.
- `tasks/194-bundled-checklist-third-detail-coverage.md` — immediately preceding disposition-only local task.

## History

- 2026-08-30 — Hypatia the 4th completed a focused read-only scan and identified unasserted bundled offer expiry propagation; no files changed.
- 2026-08-30 — Coordinator directly verified the expiry source, parser/model, active-state gate, rendered widget payload, existing test seam, and coverage boundary.
- 2026-08-30 — Coordinator reserved Task 195 with a bounded single-file test implementation, review, and local validation scope.
- 2026-08-30 — Copernicus the 4th added the exact rendered `WaypointOffer.expiresAt` assertion in `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`; the named offer test passed.
- 2026-08-30 — Einstein the 4th completed the strict review with `ACCEPT — no findings`, verifying UTC source fidelity, typed widget scope, preserved assertions, and task references.
- 2026-08-30 — Coordinator completed the declared scoped validation: format clean, analyzer clean, named offer test passed, and the affected app test file passed all 68 tests.
