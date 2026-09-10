# Task 18 — Riverpod interoperability

Status: [x] Completed

## Goal
Prove one realistic Riverpod flow using patched business/Notifier logic and an existing ConsumerWidget.

## Scope and Non-goals
Scope: Provider, Notifier or AsyncNotifier, ConsumerWidget build, existing subscriptions, UI update, and state behavior. Non-goals: modifying Riverpod or broad package coverage.

## Owner
Flutter ecosystem specialist; coordinator integrates.

## Dependencies
Tasks 12, 16–17.

## Assumptions
Transparent method/function dispatch can interoperate with Riverpod lifecycle and subscriptions.

## Work Items
- [x] Add minimal deterministic Riverpod fixture.
- [x] Patch pricing/provider logic and observe existing ConsumerWidget.
- [x] Test Notifier/AsyncNotifier case as supported by async evidence.
- [x] Record state/subscription limitations and failures.
- [x] Review and validate focused widget/integration tests.

## Validation
Planned: provider container and widget tests, activation while subscribed, async success/error where available, rollback, listener count/state continuity, and unsupported diagnostics. Exit: at least one realistic pricing flow works without modifying Riverpod.

## Next Action
Begin Task 19's focused GoRouter route-decision experiment.

## Blockers
None; Tasks 12, 16, and 17 are complete.

## Outcome
Riverpod 3.4.2 Provider, Notifier input, AsyncNotifier result, subscriptions,
and a mounted ConsumerWidget retained identity/state through signed activation,
invalid rejection, and rollback. Ordinary dependency changes and explicit
invalidation recomputed through the active guard. Patch activation alone did
not invalidate cached provider values, so interoperability is PARTIAL.

## References
- `docs/research/riverpod-interoperability.md`
- `docs/dart-support-matrix.md`
- `fixtures/flutter_conformance_app/test/riverpod_interop_test.dart`
- `experiments/instrumentation/test/flutter_stateful_overlay_v10_test.dart`

## History
- 2026-08-22: Package number reserved serially.
- 2026-08-22: Started after Task 17 passed independent adversarial re-review.
- 2026-08-22: Completed after implementation, independent review, fixture analysis, eleven combined fixture tests, instrumentation analysis, and the actual transformed Flutter overlay test passed. Accepted limits are documented in the research result.
