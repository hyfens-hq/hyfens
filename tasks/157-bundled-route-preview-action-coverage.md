# Task 157 — Bundled route-preview action coverage

Status: [x] Completed

## Goal

Connect the existing bundled `watch_route_preview` action to the Discover video
preview so its verified local asset, title, and play label are exercised by the
demo app without introducing a generic action engine.

## Scope and Non-goals

Scope:

- select the existing decoded `watch_route_preview` video action in Discover;
- pass its usable asset path, title, and play label to the existing video
  preview widget;
- retain the widget's current defaults when the action is absent or unusable;
- expose the source-driven play label as the preview control's tooltip/semantic
  label;
- add exactly one real zero-latency bundled-source widget test for the source-
  driven asset, title, and label.

Non-goals:

- changing `actions.json`, video assets, action decoding/model contracts,
  generic action registries, planner/share-note behavior, player lifecycle,
  native playback guarantees, or other surfaces;
- adding dependencies, changing permissions, device/simulator testing, Docker,
  AWS, hosting, deployment, or external-service work;
- adding tests outside the owned app test file or broad UI refactoring.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these three paths:

- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_video_preview.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 156;
- existing `actions.json` `watch_route_preview` record and registered route
  preview video asset;
- existing `WaypointTestAction.assetPath`/`submitLabel`, Discover page, video
  preview widget, local AlphaX/demo transport, and widget-test seam.

## Assumptions

- the checked-in `watch_route_preview` payload is the source of truth and will
  not be edited;
- an action is usable only when it is the expected video action and its needed
  strings are non-empty; absent or unusable data follows existing widget
  defaults;
- the current video controller initialization, play/pause behavior, and
  unavailable fallback remain unchanged;
- the worker owns only the three paths listed above and must preserve
  unrelated shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the bundled route-preview action, existing decoder/model fields,
  Discover video construction, video widget defaults, and test seam.
- [x] Thread a usable decoded route-preview action into the existing video
  preview with safe defaults and source-driven control labeling.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, fallback
  behavior, lifecycle preservation, UI semantics, determinism, and scope
  compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `lib/waypoint/presentation/widgets/waypoint_video_preview.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same three paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its route preview action"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: format reported three files and
  zero changes; scoped `flutter analyze` reported no issues; the named
  route-preview test passed; and the full changed app widget test passed all
  forty-eight tests.
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the declared three-file write set and
final observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  — SHA-256 `1a0a54704ba1710b61ebb28d9a7c918c4d276ef19d9d068d280a2ae6f244a1f9`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_video_preview.dart`
  — SHA-256 `a8c172c8f4f72116e342fe9ce4577337efbbbfed00dedd5b4816a165e0bb184c`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `1a3664b100d82c3a3b9e58e24bbcd12b17448460c129c4b5d2851bbc9d776b0b`.

The app test contains 48 `testWidgets` declarations, including exactly one
Task-157-named case. The implementation worker reported no other paths
changed. The missing Git `HEAD` remains an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The bundled `watch_route_preview` action now drives the existing
Discover video preview's exact local asset, title, and play label while
preserving defaults, controller lifecycle, play/pause behavior, and unavailable
fallbacks. The strict reviewer returned ACCEPT with no verified findings, and
the coordinator's final changed-scope validation passed. No fixture payload,
dependency, platform, device, deployment, AWS, hosting, or external-service
behavior changed.

## References

- `tasks/156-bundled-discover-collections-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/actions.json:18-23`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_test_action.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:161-170`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:310-315`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart:146-175`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_video_preview.dart`
- `fixtures/flutter_conformance_app/test/waypoint_video_preview_test.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Fermat the 3rd performed a read-only audit and found that the
  shipped `watch_route_preview` action is loaded and decoded but Discover still
  constructs a hard-coded video preview. The audit found no files edited and
  proposed this bounded three-path package.
- 2026-08-29: Boole the 3rd implemented the three-path package, adding safe
  source-driven asset/title/play-label inputs and exactly one real zero-latency
  bundled-source widget test. Its first named-test attempt exposed a semantics
  handle teardown leak; the worker disposed that test handle explicitly and
  did not claim a post-fix rerun.
- 2026-08-29: Anscombe the 3rd performed an independent strict fact-based
  review and returned ACCEPT. It verified exact action-field flow, unusable
  action rejection, default compatibility, lifecycle preservation, tooltip and
  semantics behavior, test cleanup, and three-file scope. Its named test
  passed after the teardown correction; no blocking finding was reported.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with three files unchanged, scoped analysis exited 0
  with no issues, the named route-preview test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all forty-eight tests passing.
