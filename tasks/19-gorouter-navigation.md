# Task 19 — GoRouter navigation interoperability

Status: [x] Completed

## Goal
Prove patched ordinary Dart route-selection logic and investigate route-builder behavior using GoRouter.

## Scope and Non-goals
Scope: route A/B decision, existing router/subscriptions, optional route builder, capability-based navigation, rollback, and mounted state. Non-goals: native deep-link declarations, manifests, plist schemes, or new routes requiring native configuration.

## Owner
Flutter navigation specialist; coordinator integrates.

## Dependencies
Tasks 14, 16–17.

## Assumptions
Pure Dart routing decisions can be patched independently from native deep-link registration.

## Work Items
- [x] Add minimal deterministic GoRouter fixture.
- [x] Patch route decision and verify existing router behavior.
- [x] Investigate builder patching and capability navigation.
- [x] Classify native/store-release boundaries explicitly.
- [x] Review and validate focused widget/integration tests.

## Validation
Planned: initial redirect and post-activation navigation, push/pop, rollback, unknown route/capability rejection, mounted state continuity, and native-boundary assertions. Exit: ordinary route selection works or a concrete blocker is recorded.

Focused results (2026-08-22):

- `flutter pub get` in `fixtures/flutter_conformance_app`: passed; resolved
  go_router 17.5.0.
- `flutter analyze lib/navigation_fixture.dart test/fixtures/navigation_patch.dart`:
  passed with no issues.
- `dart analyze test/flutter_gorouter_overlay_v10_test.dart` in
  `experiments/instrumentation`: passed with no issues.
- `dart test test/flutter_gorouter_overlay_v10_test.dart` in
  `experiments/instrumentation`: passed. The outer test ran two generated
  Flutter widget tests through the actual transformed and signed patch path.
- Official pub.dev metadata identifies 17.5.0 as current with Dart `^3.10.0`
  and Flutter `>=3.38.0`; its tagged source contains the BSD 3-Clause license.
- Physical Android/iOS release execution was not run; no native declarations
  were changed.

## Next Action
Begin Task 20's bounded BLoC/Cubit compatibility experiment.

## Blockers
None; Tasks 14, 16, and 17 are complete.

## Outcome
The resolved go_router 17.5.0 Dart library files stayed
byte-identical while an actual transformed, signed route decision changed
`/decision/2` from compiled destination A to B on ordinary navigation.
Activation alone did not refresh the mounted route; malformed-input rejection
retained B, and rollback restored A on the next navigation. Builder closure
replacement and patch-driven navigation capability remain unproved.

## References
- `docs/research/navigation-interoperability.md`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 18 completed with a documented provider-cache invalidation condition.
- 2026-08-22: Pinned compatible go_router 17.5.0 and added a deterministic
  transformed/signed A/B redirect fixture. Focused generated Flutter test passed;
  coordinator review remains.
- 2026-08-22: Review added explicit router-listener and redirect-counter checks,
  distinguished unmatched-route error state from the compiled rejection route,
  narrowed integrity/rejection claims, and reran the focused test successfully.
- 2026-08-22: Completed after independent review found no remaining blocker/high issue and coordinator integrated the bounded result and accepted limitations.
