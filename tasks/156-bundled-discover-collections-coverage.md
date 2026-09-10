# Task 156 — Bundled Discover collections coverage

Status: [x] Completed

## Goal

Preserve the two bundled Discover collection records through the local
AlphaX/demo data path and render their source-driven title, subtitle, and
existing artwork on Discover with a real local regression test.

## Scope and Non-goals

Scope:

- add a typed collection model in its own file;
- preserve `discover.json` collection records in the local demo payload;
- decode collections into `WaypointHomeData`;
- render one non-navigating Discover collection section using the existing
  artwork component;
- add exactly one real bundled-source widget test proving `First light` and
  `Warm colours` appear.

Non-goals:

- changing `discover.json`, assets, categories, search suggestions, collection
  navigation, collection actions, backend/server behavior, permissions,
  Settings, Saved, Activity, Trips, documents, share-note behavior, or any
  completed Task 150–155 surface;
- new dependencies, generic collection registries, device/simulator testing,
  Docker, AWS, hosting, deployment, or external-service work;
- tests outside the owned app test file or broad UI refactoring.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these six paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_discover_collection.dart`
  (new);
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Tasks 150–155;
- existing `discover.json` collection records and registered SVG assets;
- existing `WaypointHomeData`, `WaypointJsonDecoder`, local AlphaX/demo
  transport, `WaypointAssetArtwork`, Discover screen, and widget-test seam.

## Assumptions

- the checked-in bundled collection payload is the source of truth and will not
  be edited;
- collection data is optional for compatibility with minimal or older home
  payloads;
- the section is display-only because the payload exposes no verified
  collection action contract;
- the worker owns only the six paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit the bundled collection payload, transport, model, decoder, UI, and
  existing local test seam.
- [x] Add the typed collection model and thread collections through local
  transport, home data, and decoding.
- [x] Render the source-driven collection section with existing artwork.
- [x] Add exactly one real bundled-source widget regression test.
- [x] Review the combined task-owned diff for payload fidelity, fallback
  compatibility, layout, determinism, and scope compliance.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_discover_collection.dart`
  `lib/waypoint/domain/waypoint_home_data.dart`
  `lib/waypoint/data/waypoint_data_source.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same six paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders its Discover collections"`;
- `flutter test test/waypoint_app_test.dart`;
- Coordinator final validation on 2026-08-29: format reported six files and
  zero changes; scoped `flutter analyze` reported no issues; the named
  collection test passed; and the full changed app widget test passed all
  forty-seven tests.
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

## Scope Manifest

This checkout has no valid Git `HEAD`, so Git cannot provide historical diff
provenance. The coordinator records the declared six-file write set and final
observations directly:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_discover_collection.dart`
  — SHA-256 `a3eaf54e265a8badde416b8c202251450c86d0faa341809afa82709266ae6174`;
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
  — SHA-256 `be395ed7b50d879edc22224ad33bfab3d88f647102695f97ac23b6c1cfe61517`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart`
  — SHA-256 `871d8f7b5d27c36935f8bf40d560f6c0ab7b1739619797d88f3336659b55656a`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
  — SHA-256 `b8725195ace8532ad9154b94855782063be720918ebba08bfbb112d2bbd0891b`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
  — SHA-256 `89d17379761ea39ae69f4690d4ae0ba816347b2b7d83b29bd9d50e0b8a284cda`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`
  — SHA-256 `c3cd05078fb9c911ea1e603449c6d263c5874775c99db77d4fb03ace7236cf54`.

The app test contains 47 `testWidgets` declarations, including exactly one
Task-156-named case. The implementation worker reported no other paths
changed. The missing Git `HEAD` remains an explicit provenance limitation.

## Next Action

Start a fresh read-only source audit for the next uncovered local conformance
gap, then reserve the next task number before assigning implementation.

## Blockers

None known.

## Outcome

Accepted. The two shipped Discover collection records now survive the local
AlphaX/demo transport and JSON decoder into typed home data, render with their
exact title, subtitle, and existing artwork, and are covered by one real
bundled-source widget test. The strict reviewer returned ACCEPT with no
verified findings. No fixture payload, dependency, platform, device,
deployment, AWS, hosting, or external-service behavior changed.

## References

- `tasks/155-bundled-home-hero-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/discover.json:11-14`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:302-326`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_home_data.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_discover_page.dart`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_asset_artwork.dart`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`

## History

- 2026-08-29: Noether the 3rd performed a read-only audit and found that the
  two bundled Discover collections are loaded from `discover.json` only as
  discarded data; they are not modeled, decoded, rendered, or covered by a
  real local-source widget test. The audit found no files edited and proposed
  this bounded six-path package.
- 2026-08-29: Darwin the 3rd implemented the six-path package, preserving the
  shipped fields and adding exactly one real bundled-source widget test. The
  worker reported format, scoped analysis, and the named test passing; its
  attempted full-file run was interrupted and therefore unclaimed.
- 2026-08-29: Pauli the 3rd performed an independent strict fact-based review
  and returned ACCEPT. It verified the source field path, local transport
  injection, typed decoding, visible non-interactive rendering, exact artwork
  assertions, and six-file scope. The review noted that its named-test run was
  interrupted and required coordinator rerun; no blocking finding was
  reported.
- 2026-08-29: Coordinator reran the planned changed-file validation after
  review: format exited 0 with six files unchanged, scoped analysis exited 0
  with no issues, the named collection test exited 0, and the full
  `waypoint_app_test.dart` file exited 0 with all forty-seven tests passing.
