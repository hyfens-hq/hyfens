# Task 176 — Bundled hero video-asset fallback

Status: [x] Completed

## Goal

Use the decoded home hero `videoAsset` for the Discover video preview when no usable route-preview action is available, while preserving route-action precedence and the video widget's existing default.

## Scope and Non-goals

Scope:

- Extend the existing Discover video asset selection to use a nonblank hero video asset after a usable route-preview action and before the widget default.
- Add one synthetic local widget test with no route-preview action and a distinct hero asset, using the existing fake video platform to verify the selected asset.

Non-goals:

- Do not edit JSON/assets, home-hero/domain/decoder/repository contracts, video playback lifecycle, action decoding, route-preview behavior, Settings media preview, planner/offer/permission behavior, dependencies, or infrastructure.
- Do not change video titles/play labels, playback controls, unavailable handling, or the widget's fallback asset.
- Do not add generic action routing or video configuration abstractions, and do not change completed task files.
- No device, simulator, Docker, AWS, online hosting, or deployment work is required.

## Owner

- Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast mode.
- Coordination and integration: Codex.
- Strict review: independent GPT-5.6 Luna Max reviewer, max reasoning, priority/fast mode.

## Dependencies

- Existing decoded `WaypointHomeHero.videoAsset` field.
- Existing `_findRoutePreviewAction` validation and route-action asset precedence.
- Existing `WaypointVideoPreview` optional asset path/default.
- Existing fake `VideoPlayerPlatform` and local test-source override.

## Assumptions

- A usable route-preview action remains first priority; an absent or unusable action falls back to a nonblank hero video asset; when neither exists, passing `null` preserves `WaypointVideoPreview`'s current default.
- The synthetic test can use `WaypointTestDataSource` with the existing payload plus a hero and an empty actions list, without changing production JSON/assets.
- The existing bundled route-preview test remains the evidence for route-action precedence; the new test focuses only on the hero fallback with a distinct asset path.
- Only the Discover screen and existing app test file are changed.

## Work Items

- [x] Audit hero payload/model/decoder, Discover video construction, route-action selection, widget default, fake video platform, existing tests, and completed-task boundary.
- [x] Add route-action → hero asset → widget-default selection and the synthetic no-action hero-asset test within the two-file scope.
- [x] Review the combined two-path diff for precedence, fallback, lifecycle preservation, scope, and test adequacy.
- [x] Obtain strict independent review and fix any blocking findings.
- [x] Run scoped format, analysis, the named hero-fallback test, and the affected app test file.
- [x] Record evidence, outcome, and the next local audit instruction.

## Validation

Run from `fixtures/flutter_conformance_app` after implementation and review:

```sh
dart format --output=none --set-exit-if-changed \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter analyze \
  lib/waypoint/presentation/screens/waypoint_discover_page.dart \
  test/waypoint_app_test.dart

flutter test test/waypoint_app_test.dart --plain-name \
  "uses the home hero video asset when route preview action is unavailable"

flutter test test/waypoint_app_test.dart
```

Only the two task-owned files are in validation scope. No device, simulator, Docker, AWS, hosting, or unrelated test validation is required.

## Next Action

Audit the next uncovered local fixture capability and reserve the next task number before implementation.

## Blockers

None. The repository has no usable Git `HEAD`; review must use direct file evidence and the explicit two-file scope.

## Outcome

Discover now selects a usable route-preview action asset first, then a nonblank decoded home-hero video asset, then preserves the video widget default through `null`. A synthetic local no-action test proves the hero fallback with the existing fake video platform; existing route-preview behavior remains covered.

## References

- `fixtures/flutter_conformance_app/assets/data/home.json:4-12` — bundled hero `videoAsset`.
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_hero.dart:2-18` — typed hero video asset.
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:43-53` — hero video asset decoding.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:61,171-179` — route action lookup and current video construction.
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_video_preview.dart:10-35` — optional asset path and existing default.
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:544-602` — existing fake video platform and route-action asset coverage.
- `tasks/155-bundled-home-hero-coverage.md` — prior task explicitly excluded video playback.
- `tasks/157-bundled-route-preview-action-coverage.md` — existing route-action precedence path.
- `tasks/175-bundled-local-destination-description-search.md` — immediately preceding completed local coverage task.

## History

- 2026-08-30 — Faraday the 4th completed a read-only audit and identified the dropped hero video-asset fallback; no files changed.
- 2026-08-30 — Coordinator reserved Task 176 with a bounded two-file implementation, review, and local validation scope.
- 2026-08-30 — Averroes the 4th implemented the two-file fallback and synthetic no-route-action test; worker-reported scoped checks passed.
- 2026-08-30 — Hume the 4th independently accepted the implementation with no High, Medium, or Low findings and verified existing route-preview coverage remained intact.
- 2026-08-30 — Coordinator validation passed: scoped `dart format --output=none --set-exit-if-changed` over the two paths (2 formatted, 0 changed); scoped `flutter analyze` over the two paths (no issues); named hero-fallback test (`+1`); and `flutter test test/waypoint_app_test.dart` (`64` tests passed). No device, simulator, Docker, AWS, or unrelated test validation was run.
