# Task 20 — BLoC/Cubit compatibility

Status: [x] Completed

## Goal
Obtain bounded ecosystem evidence that patched Cubit/event-state logic preserves existing subscriptions and state.

## Scope and Non-goals
Scope: one minimal Cubit or BLoC case after Riverpod, existing subscriptions, branch behavior, state preservation, and rollback. Non-goals: duplicating Riverpod coverage or broad BLoC APIs.

## Owner
Flutter ecosystem specialist; coordinator integrates.

## Dependencies
Task 18; shared runtime/UI/state gates.

## Assumptions
If dispatch is framework-agnostic, a small Cubit proof should not need special runtime semantics.

## Work Items
- [x] Add minimal fixture only after Riverpod result.
- [x] Patch one app-owned business branch reached by an ordinary Cubit input.
- [x] Verify existing subscription, mounted builder, and state continuity.
- [x] Stop after the Cubit lifecycle result; broader BLoC APIs add no
  demonstrated new risk in this bounded proof.
- [x] Review and validate focused tests.

## Validation
Planned: focused bloc/widget tests for pre/post activation, existing listener behavior, rollback, and failure retention. Exit: one credible compatibility proof or documented redundancy/blocker.

Focused results (2026-08-22):

- `flutter pub get` in `fixtures/flutter_conformance_app`: passed; resolved the
  exact pins `flutter_bloc 9.1.1` and `bloc 9.2.1`.
- `flutter analyze lib/main.dart` in the fixture: passed with no issues.
- `dart analyze test/flutter_stateful_overlay_v10_test.dart` in
  `experiments/instrumentation`: passed with no issues.
- `dart test test/flutter_stateful_overlay_v10_test.dart` in
  `experiments/instrumentation`: passed. The outer test generated the real
  transformed fixture and its signed-E1 Flutter suite; the added Cubit case
  retained instance, stream, state, provider lookup, and mounted builder across
  activation, malformed-input rejection, and rollback.
- Task-owned self-review and Markdown trailing-whitespace check passed;
  coordinator review remains.

## Next Action
Begin Task 21's package-preserving pure-Dart dependency overlay experiment.

## Blockers
None; Task 18 and the shared runtime/UI/state gates are complete.

## Outcome
Compatible for the tested synchronous Cubit flow, with patch
activation and rollback explicitly producing no Cubit emission or builder
rebuild. The next ordinary Cubit input observes the active implementation while
retaining current state. Event-based Bloc and broader package APIs remain
unproved.

## References
- `tasks/18-riverpod-interoperability.md`
- `docs/research/bloc-interoperability.md`
- `fixtures/flutter_conformance_app/lib/main.dart`
- `experiments/instrumentation/test/flutter_stateful_overlay_v10_test.dart`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Tasks 18 and 19 completed with explicit reactive-cache and navigation-refresh boundaries.
- 2026-08-22: Pinned compatible bloc/flutter_bloc releases and added a bounded
  actual-transformed signed-E1 Cubit lifecycle proof. Focused generated Flutter
  tests passed; coordinator review remains.
- 2026-08-22: Completed after independent adversarial review found no blocker/high issue and reran the transformed signed test successfully. Broader BLoC APIs remain explicit limitations.
