# Task 168 — Bundled destination emoji rendering

Status: [x] Completed

## Goal

Preserve each bundled destination's optional emoji and render it as a small
non-interactive identity badge in the shared destination card.

## Scope and Non-goals

Scope:

- add an optional `emoji` field to `WaypointDestination` and preserve it in
  `copyWith`;
- decode nonblank bundled `emoji` strings;
- render the exact value in the existing destination-card image stack,
  positioned away from the save button;
- add exactly one real zero-latency bundled-source widget test asserting the
  five shipped emoji values.

Non-goals:

- changing JSON/assets, transport, repository, Saved state, search/filter
  behavior, destination detail, navigation, dependencies, support fixtures,
  platform files, devices, simulators, Docker, AWS, hosting, deployment, or
  external services;
- changing card semantics, save controls, card taps, existing metadata,
  artwork, layout outside the badge, or tests outside the owned app test file;
- adding a new widget file, emoji parser, or fallback glyph.

## Owner

Implementation: GPT-5.6 Luna Max, max reasoning, priority/fast execution.
Coordination and integration: Codex. A separate strict fact-based reviewer is
assigned after implementation.

## Write Set

The implementation owns exactly these four paths:

- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart`;
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart`;
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart`.

The coordinator owns this task record and its later evidence updates.

## Dependencies

- completed Task 167;
- existing bundled `home.json` and `discover.json` places;
- existing destination model/decoder, shared `WaypointDestinationCard`,
  Discover/Saved card usage, and bundled AlphaX/demo test seam.

## Assumptions

- exact nonblank Unicode values in the bundled payload are the source of truth:
  `⌂`, `✦`, `✧`, `◇`, and `○`;
- missing or blank emoji remains `null` and renders no placeholder;
- the shared destination card is the correct presentation seam for both
  Discover and Saved;
- existing card semantics, save interaction, tap behavior, and metadata remain
  unchanged;
- the worker owns only the four paths listed above and must preserve unrelated
  shared-checkout edits;
- validation uses only the changed app scope and local bundled data.

## Work Items

- [x] Audit bundled emoji values, local merge, model/decoder, shared card,
  Saved reuse, tests, and prior task exclusions.
- [x] Add optional typed emoji decoding and `copyWith` preservation.
- [x] Render a small non-interactive exact-value card badge without overlapping
  the save control.
- [x] Add exactly one real bundled-source regression test for all five values.
- [x] Review the combined task-owned diff for source fidelity, compatibility,
  layout, semantics, interactions, and scope.
- [x] Run only formatting, scoped analysis, the named test, and the full
  changed app widget test file.
- [x] Obtain strict fact-based review and fix only verified blocking findings.
- [x] Record validation evidence, outcome, and the next source-based
  instruction.

## Validation

Planned affected-file validation only, from
`fixtures/flutter_conformance_app`:

- `dart format --output=none --set-exit-if-changed`
  `lib/waypoint/domain/waypoint_destination.dart`
  `lib/waypoint/data/waypoint_json_decoder.dart`
  `lib/waypoint/presentation/widgets/waypoint_destination_card.dart`
  `test/waypoint_app_test.dart`;
- `flutter analyze` on the same four paths;
- `flutter test test/waypoint_app_test.dart --plain-name`
  `"bundled local demo renders destination emojis"`;
- `flutter test test/waypoint_app_test.dart`;
- no unrelated tests, devices, simulators, Docker, AWS, or hosted-service
  checks.

Coordinator validation results:

- `dart format --output=none --set-exit-if-changed` on the four owned paths:
  passed; 4 files inspected, 0 changed.
- `flutter analyze` on the four owned paths: passed with no issues.
- `flutter test test/waypoint_app_test.dart --plain-name "bundled local demo
  renders destination emojis"`: passed, 1 test.
- `flutter test test/waypoint_app_test.dart`: passed, all 59 tests.
- Carver the 3rd independently reviewed the combined diff and returned
  `ACCEPT`; no blocking findings were identified.
- No unrelated tests or device, simulator, Docker, AWS, or hosted-service
  checks were run.

Scope Manifest (coordinator capture after validation; repository has no
usable Git `HEAD` for a baseline comparison):

- `lib/waypoint/domain/waypoint_destination.dart` —
  `6a8a580427e8786b7f7d464ec28a77fb4b10e1f45731b77a80dfeb0d5ab7db4e`
- `lib/waypoint/data/waypoint_json_decoder.dart` —
  `e4fb6a6ce6d5a670937afdb290fed1cb4f9a4c2c1a8f578870edb50ad59c704b`
- `lib/waypoint/presentation/widgets/waypoint_destination_card.dart` —
  `b407beb23edfbc237a2e787792024b4bfb0567fea6592626b5d22c56c08b4958`
- `test/waypoint_app_test.dart` —
  `91a2ad681a2af2a2a206c650d45b7c55bcc3be6a15841cd429d12d8527157cc6`
- Test declaration count in the owned app test file: `59`.

## Next Action

Perform the next read-only audit for the highest-value local, non-AWS gap,
excluding completed Tasks 150–168 and preserving the same bounded validation
policy.

## Blockers

None known.

## Outcome

Implemented optional bundled destination emoji propagation and passive lower-left
badges in the shared destination card. The real bundled-source test verifies
all five exact Unicode values in their card contexts. Independent strict review
returned `ACCEPT`, and coordinator validation passed all 59 app tests. No JSON,
dependency, platform, device, deployment, or AWS work was introduced.

## References

- `tasks/167-bundled-trip-document-icon-coverage.md`
- `tasks/159-bundled-destination-distance-coverage.md`
- `fixtures/flutter_conformance_app/assets/data/home.json:69-99`
- `fixtures/flutter_conformance_app/assets/data/discover.json:15-59`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_data_source.dart:286-318`
- `fixtures/flutter_conformance_app/lib/waypoint/domain/waypoint_destination.dart:11-58`
- `fixtures/flutter_conformance_app/lib/waypoint/data/waypoint_json_decoder.dart:106-123`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/widgets/waypoint_destination_card.dart:37-117`
- `fixtures/flutter_conformance_app/lib/waypoint/presentation/screens/waypoint_saved_page.dart:41-60`
- `fixtures/flutter_conformance_app/test/waypoint_app_test.dart:220-248,519-564`

## History

- 2026-08-30: Jason the 3rd performed a read-only audit. It found five exact
  `emoji` values in the bundled destination payloads with no model, decoder,
  card, or test usage; the shared card is also reused by Saved. The audit
  proposed this bounded four-path package; no files were changed or tested.
- 2026-08-30: Heisenberg the 3rd implemented the bounded four-path package and
  reported the planned checks passing with 59 app tests.
- 2026-08-30: Carver the 3rd independently reviewed the combined diff and
  returned `ACCEPT`; optional model/decoder flow, passive badge placement,
  preserved interactions, exact five-value coverage, and scope were factually
  verified.
- 2026-08-30: Coordinator ran the planned format, scoped analysis, named test,
  and full app test. All passed; the task was marked completed with the scope
  manifest above.
