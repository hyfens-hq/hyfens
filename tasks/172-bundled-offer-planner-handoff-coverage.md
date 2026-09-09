# Task 172 — Bundled offer planner handoff coverage

Status: [x] Completed

## Goal

When the bundled offer declares `action: "open_planner"`, pass the existing validated planner action metadata to the planning sheet opened by the offer CTA, while retaining fallback behavior for offers without a supported action.

## Scope and Non-goals

Scope:

- Add an optional action id to `WaypointOffer` and decode it from the existing offer payload.
- Extend the bundled offer CTA path to pass the already decoded, validated `open_planner` action only when the offer action id matches exactly.
- Update the existing real zero-latency bundled offer test to tap the CTA and assert the three source-driven planner strings.

Non-goals:

- Do not edit JSON/assets, the transport, repository, planning-sheet implementation, planner fields/state, generic action routing, offer expiry/dismissal behavior, or other screens.
- Do not change the hero handoff completed by Task 169 or fallback callers.
- No new dependency, device/simulator work, Docker/AWS/hosting work, deployment, or unrelated test-file changes.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing bundled `home.json` offer action and `actions.json` `open_planner` action metadata.
- Task 169's optional planner-sheet action metadata API and validated Discover action lookup.
- Existing `WaypointOffer`, decoder, Discover page, planning sheet, and zero-latency test transport.
- No new dependency.

## Assumptions

- The offer action id is optional and must match `open_planner` exactly before propagation.
- Unsupported, missing, malformed, or absent offer action metadata opens the existing planning sheet with fallback copy.
- The existing `bundled local demo renders its time-limited offer` test is extended in place; no second bundled offer widget test is added.
- Existing synthetic offer-flow tests continue to use the fallback path because their payload has no supported action metadata.

## Work Items

- [x] Audit bundled offer/action source, model, decoder, Discover CTA, planning-sheet API, tests, and completed-task boundary.
- [x] Add optional offer action-id data and decode it safely.
- [x] Pass only the exact validated `open_planner` action from the offer CTA.
- [x] Extend the existing bundled offer widget test with the three exact planner-copy assertions.
- [x] Review the combined four-path diff for correctness and scope.
- [x] Run scoped format, analysis, named test, and affected app test file validation.
- [x] Obtain strict independent review; no blocking findings were reported.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/domain/waypoint_offer.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/domain/waypoint_offer.dart \
  lib/waypoint/data/waypoint_json_decoder.dart \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "bundled local demo renders its time-limited offer"

flutter test test/waypoint_app_test.dart
```

Only the four task-owned production/test files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test files are required.

Coordinator results on 2026-08-30:

- `dart format --output=none --set-exit-if-changed` on the four task-owned files: passed; 4 files formatted, 0 changed.
- `flutter analyze` on the four task-owned files: passed; no issues found.
- Named test `bundled local demo renders its time-limited offer`: passed; 1 test.
- `flutter test test/waypoint_app_test.dart`: passed; 60 tests.
- Widget test declaration count remained 60; the existing bundled offer test was extended in place.

Task-owned file hashes after validation (SHA-256):

- `lib/waypoint/domain/waypoint_offer.dart`: `4f789265a0ea080c3d8bf7ed7699ad06eba27f1ec49bc08bd09806370cd75a6e`
- `lib/waypoint/data/waypoint_json_decoder.dart`: `a0e52adea189f2668b8b523f9b1fd6187b4e6676817e1f04e7ddef9415edd230`
- `lib/waypoint/presentation/screens/waypoint_discover_page.dart`: `90e5a310e3bb97653a20d5450b893ff11f6effcda7a1769f317b15920fb32e0b`
- `test/waypoint_app_test.dart`: `beb8c1e6fa73a6d51d29eb67ef7dcbd0bf67e4ad21b43a79e67caea4103d8e28`

## Next Action

Reserve Task 173 and audit the next uncovered bundled local conformance gap, excluding completed Tasks 150–172.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit four-path scope.

## Outcome

Completed. The bundled offer CTA now conditionally forwards the validated `open_planner` action metadata, while unsupported or missing actions retain the existing fallback. No blocker remains.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:14-23` — bundled offer action `open_planner`.
- `fixtures/flutter_conformance_app/assets/data/actions.json:5-10` — matching planner title, subtitle, and submit label.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_offer.dart` — current offer contract without action id.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart` — current offer decoder.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart` — current offer CTA and validated planner action lookup.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart` — existing bundled offer test and fallback offer-flow test.
- `tasks/169-bundled-open-planner-action-copy-coverage.md` — completed hero propagation boundary.
- `tasks/171-bundled-permission-action-copy-coverage.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Russell the 4th completed a read-only audit and identified the bundled offer CTA's dropped `open_planner` metadata; no files changed.
- 2026-08-30 — Coordinator reserved Task 172 with a bounded four-file implementation, review, and local validation scope.
- 2026-08-30 — Descartes the 4th implemented the four-path conditional offer handoff and reported formatting, analysis, the named offer test, and 60 affected app tests passing.
- 2026-08-30 — Dewey the 4th independently reviewed the actual source and returned ACCEPT with no findings; coordinator validation remained pending.
- 2026-08-30 — Coordinator validation passed: format unchanged, scoped analysis clean, the named bundled offer test passed, and all 60 tests in `waypoint_app_test.dart` passed. Task completed.
