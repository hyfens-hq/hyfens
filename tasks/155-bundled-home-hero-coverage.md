# Task 155 — Bundled home hero coverage

Status: [x] Completed

## Goal

Decode and render the bundled home greeting and hero on the initial Discover
surface so the demo app exercises the real local home content and its existing
planning action.

## Scope and Non-goals

Scope:

- add a typed home-hero model for the existing bundled fields: eyebrow, title,
  subtitle, image asset, video asset, action, and action label;
- add optional greeting and hero data to `WaypointHomeData` and decode the
  existing `home.json` fields;
- render the decoded greeting and hero eyebrow/title/subtitle/image on
  Discover using existing presentation components and the bundled asset;
- connect only the existing `open_planner` hero action to the existing planning
  sheet;
- add exactly one real-source widget test using zero-latency local AlphaX
  transport that asserts the bundled hero content and opens the planning sheet.

Non-goals:

- changing `home.json`, assets, video playback, action infrastructure,
  repository/API/transport behavior, persistence, permissions, Settings,
  Saved, Activity, Trips, documents, share-note behavior, or other routes;
- adding generic hero/action registries, new dependencies, device/simulator,
  Docker, AWS, hosting, deployment, or external-service work;
- adding tests outside the changed app test file or broad UI refactoring;
- breaking the existing Discover surface when optional hero data is absent.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these five paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_hero.dart`
  (new);
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

## Dependencies

- completed Tasks 150–154;
- existing `home.json` hero and greeting payload;
- existing `WaypointHomeData`, `WaypointJsonDecoder`,
  `WaypointAssetArtwork`, `WaypointSurface`, `showWaypointPlanningSheet`,
  Discover screen, local AlphaX transport, and widget-test override seam.

## Assumptions

- the existing bundled hero payload is the source of truth and must not be
  edited;
- hero data is optional for compatibility with minimal or older home payloads;
- only the known `open_planner` action is wired, and it invokes the existing
  planning sheet without a generic action engine;
- the worker owns only the five paths listed in the write set and must not
  revert unrelated edits in this shared checkout;
- any existing hardcoded Discover copy assertion that conflicts with the
  intentional source-driven hero must be updated only within the one new/owned
  app test file and only to reflect the bundled payload.

## Work Items

- [x] Audit the bundled home payload, current model/decoder, Discover UI,
  existing asset widgets, planning action, and test seam.
- [x] Add the typed optional greeting/hero model data and decoder mapping.
- [x] Render the bundled hero content and existing planning handoff on
  Discover with optional-data fallback.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, fallback
  compatibility, action behavior, layout, determinism, and scope compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_home_hero.dart`
  `lib/waypoint/domain/waypoint_home_data.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze`
  `lib/waypoint/domain/waypoint_home_hero.dart`
  `lib/waypoint/domain/waypoint_home_data.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its home hero"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: formatting reported five files
  and zero changes; scoped analysis reported no issues; the named regression
  test passed; and the full changed app widget test passed all forty-six
  tests.
- no unrelated test files, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the intended five-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_hero.dart`
  — SHA-256 `cd94e4eccfa7268d926119c25d4fef70ef3edc0865d33fa6401f10ec8a9b1e59`;
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
  — SHA-256 `81dfde2f8581ce09cf70df182916d3133ddc82439a042c4c225012200e9033f9`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `2d94c9b1dd154d7dc86c308c3c493cf538ed4b3879be09eae44332e74f8cb8c5`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  — SHA-256 `895aa868a78655107e8d73bdbb7be7526186bb7172f42158311b6e0f98f0188b`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `8e9845aed54f92fbd64a77aea226afb9e3ea014a235c94106fcd1dfc505ccaae`.

The app test contains 46 `testWidgets` declarations, including exactly one
Task-155-named case. No temporary `DEBUG-T155` diagnostics remain. The worker
reported no other implementation paths changed; the missing Git baseline is
retained as an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The bundled home greeting and hero now survive the local
AlphaX/decoder path into Discover, including the existing `open_planner` handoff
and bundled artwork. Optional hero data retains the prior Discover copy path.
The initial full-file regression caused by shared asset-bundle state was
reproduced, fixed with a test-only cache reset before the following real-source
test, and revalidated. No fixture, dependency, platform, device, deployment,
AWS, hosting, or external-service behavior changed.

## References

- `tasks/150-bundled-saved-state-widget-coverage.md`
- `tasks/151-bundled-activity-stream-widget-coverage.md`
- `tasks/152-trip-document-detail-coverage.md`
- `tasks/153-settings-share-trip-note-action.md`
- `tasks/154-bundled-secondary-trip-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:4-16`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_asset_artwork.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Averroes the 3rd performed a read-only audit after Task 154 and
  found that the bundled `home.json` greeting and hero fields are loaded by the
  local transport but are not represented by the home model, decoded, or
  rendered; Discover uses hardcoded copy instead. The audit proposed this
  bounded five-path model/decoder/UI/test package and no files were edited
  during the audit.
- 2026-08-29: Curie the 3rd implemented the five-path package and reported the
  named hero test passing. The initial full app-widget run exposed a timeout
  in the following real-source Saved test at its unbounded `pumpAndSettle`;
  the implementation was not accepted while that regression remained.
- 2026-08-29: The coordinator built a red-capable minimized loop containing
  the hero test followed by the Saved test. It reproduced the same timeout,
  with the Saved test still on `WaypointLoadingPage` and 23 active skeleton
  callbacks. The Saved test passed in isolation. A single-variable probe adding
  `rootBundle.clear()` before that following real-source setup made the
  minimized loop pass. The temporary `[DEBUG-T155]` diagnostic was removed;
  the cache reset remains as the verified test-isolation correction.
- 2026-08-29: After removing the diagnostic, the coordinator reran the full
  changed app widget file and all forty-six tests passed. Strict review and
  final format/analyze/named-test validation remain pending.
- 2026-08-29: Bacon the 3rd performed a strict read-only review and returned
  ACCEPT. No verified correctness, fallback, action, UI, lifecycle, test,
  scope, dependency, or debug-residue findings were reported. It confirmed
  that the `rootBundle.clear()` correction is justified by the recorded red
  and green minimized loops. The checkout's missing Git `HEAD` remains an
  explicit provenance limitation.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with five files unchanged, scoped analysis exited 0
  with no issues, the named hero test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all forty-six tests passing.
