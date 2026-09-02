# Flutter E1 conformance fixture

This is a minimal mobile app with stock Flutter 3.47/Dart 3.13 Android and iOS
hosts. The
checked-in `lib/main.dart` contains an ordinary, multi-branch top-level
`calculatePrice(int, int)` used directly by a `StatefulWidget`. It has no patch
annotation, per-function API, or patch widget.

The only explicit integration is `lib/patch_bootstrap.dart`, which initializes
the app-local E1 lifecycle after Flutter bindings are available. A build script
generates an ephemeral instrumented copy of `main.dart`; the checked-in source is
hash-checked before and after generation. Activation rebuilds the existing state
object, so its integer counter, `TextEditingController` value/selection, and
`ScrollController` offset remain intact while the guarded function begins
executing E0 data bytecode. Fast focused Flutter tests use a guard-equivalent
injected calculator, while an ephemeral-overlay test imports and executes the
actual transformed `app.dart`. Both compare exact State, controller, and keyed
Element identity through real signed activation, invalid-patch rejection, and
rollback. Removing and reconstructing the tree is the explicit tree-remount
control and creates fresh State and controllers; it is not an application or
process restart. No physical-device result is claimed by these tests.

The iOS evidence mode is compile-time gated and inactive in ordinary builds.
It uses a local HTTP server only to deliver the signed test envelope and return
machine-readable receipts. The host is restricted to private/local IP space,
endpoints use a random per-run bearer path, and iOS declares only the narrower
`NSAllowsLocalNetworking` ATS exception. Cleartext LAN transport is still not
confidential or on-path authenticated and is not a production networking policy.

The screen exposes local patch activation, deliberate invalid-patch rejection,
and manual rollback so a physical-device run can capture UI and log evidence.
See `experiments/patch_loading/README.md` for security and language-subset limits.

The fixture also contains an ordinary `PricingCard extends StatelessWidget` and
the Task 16 host factory registry. Focused tests generate an ephemeral transformed
copy, install a widget patch, and pump that guarded class as real Flutter widgets.
No `PatchView`, annotation, reflection, raw `BuildContext`, or guest callback
crosses the boundary. The signed E1 controller reapplies the release-owned
factory registry across every reset, while the download flow continues to target
`calculatePrice`. This proves mounted StatefulWidget preservation; it does not
claim State layout migration or arbitrary StatefulWidget method patching.

## Riverpod interoperability boundary

The fixture pins the hosted `flutter_riverpod` dependency to 3.4.2. A
`ProviderScope`, `NotifierProvider<PricingInputNotifier, PricingInput>`, derived
`Provider<int>`, and `ConsumerWidget` form a small pricing graph. The production
`ConformanceApp` is only wrapped in `ProviderScope`; `RiverpodPricingPanel` is a
focused conformance harness, not a claim that the production screen was migrated
to Riverpod. A provider subscription created before activation continues to
observe values after signed activation, invalid patch rejection, and rollback;
the container, provider, sync notifier, and input state retain identity. The
transformed-overlay test checks that the locally resolved `flutter_riverpod` and
`riverpod` source trees do not change during the test. That before/after check
does not establish the pristine provenance of the package-cache contents.

Activation and rollback are not Riverpod dependencies. An already-cached derived
provider therefore remains stale until an ordinary watched input changes or the
host explicitly calls `ref.invalidate`/`container.invalidate`. Tests prove both
options and do not claim automatic cache refresh. A bounded `AsyncNotifier`
awaits a host `Future`, then calls the same guarded ordinary calculator; its
loading, data, host-failure error, and recovery transitions preserve the existing
subscription and notifier where Riverpod semantics allow. This is not support
for patching Riverpod internals, generated providers, arbitrary provider
callbacks, or `AsyncNotifier.build` itself; broad framework patching remains
unsupported.
