import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:path_provider/path_provider.dart';
import 'package:conformance/ios_dispatch_throughput.dart';
import 'package:conformance/physical_ios_evidence.dart';
import 'package:conformance/waypoint/app/waypoint_bootstrap.dart';
import 'package:conformance/waypoint/application/waypoint_providers.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';
import 'package:conformance/waypoint/data/waypoint_repository.dart';
import 'package:conformance/waypoint/presentation/waypoint_app.dart';

import 'patch_bootstrap.dart';

import 'package:conformance/physical_android_evidence.dart';

int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 80;
  if (quantity < 5) return quantity * 100;
  return quantity * 90;
}

/// Fixture-only receipt for the generated authenticated control-plane run.
/// The ordinary app does not enable this loop unless the release was built
/// with a control-plane URL; it provides a USB-readable observation of the
/// instrumented function changing without exposing runtime credentials.
Future<void> _writeControlPlaneEvidence(Directory documentsDirectory) async {
  final file = File(
    '${documentsDirectory.path}/hyfens-control-plane-result.json',
  );
  try {
    for (var attempt = 0; attempt < 120; attempt++) {
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'attempt': attempt,
        'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'price': calculatePrice(6, 1),
      };
      final encoded = jsonEncode(payload);
      await file.writeAsString(encoded, flush: true);
      // Release APKs are not debuggable, so the physical Android evidence
      // reader uses logcat rather than `run-as` to observe this fixture-only
      // receipt. No credential or control-plane response is logged.
      // ignore: avoid_print
      print('HYFENS_CONTROL_PLANE_RECEIPT $encoded');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } on Object {
    // The receipt is an optional fixture observation; app behavior remains
    // governed by the runtime's fail-closed delivery path.
  }
}

/// Ordinary async application code used by the physical cross-feature run.
/// The release implementation remains normal Dart; only a replacement body
/// is interpreted when an async patch is active.
Future<int> calculateAsyncPrice(int quantity, int tier) async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
  return calculatePrice(quantity, tier);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final automaticIntegration = E0PatchRuntime.generatedIntegrationStarted;
  final iosEvidence = await PhysicalIosEvidenceSession.open(
    supportDirectory,
    usbDirectory: documentsDirectory,
  );
  final androidEvidence = await PhysicalAndroidEvidenceSession.open(
    supportDirectory,
  );
  if (const String.fromEnvironment('HYFENS_CONTROL_PLANE_URL').isNotEmpty) {
    unawaited(_writeControlPlaneEvidence(documentsDirectory));
  }
  final patches = createPatchController(
    supportDirectory,
    patchUri: iosEvidence?.patchUri,
  );
  // The checked-in fixture retains a manual E1 controller for archived
  // evidence runs. Automatic CLI releases inject the generated integration
  // bootstrap before this body; initializing both controllers would reset the
  // same process-global E0 registry from one controller under the other.
  if (!automaticIntegration) {
    await patches.initialize();
  }
  late final WaypointDataSource waypointSource;
  try {
    waypointSource = await createWaypointDataSource();
  } on Object catch (error) {
    waypointSource = WaypointUnavailableDataSource(error);
  }
  runApp(
    ProviderScope(
      overrides: [
        waypointRepositoryProvider.overrideWithValue(
          WaypointRepository(waypointSource),
        ),
      ],
      child: const WaypointApp(),
    ),
  );
  if (iosDispatchThroughputEnabled) {
    await WidgetsBinding.instance.endOfFrame;
    unawaited(
      runIosDispatchThroughput(
        documentsDirectory: documentsDirectory,
        patches: patches,
        instrumentedCallable: calculatePrice,
        appId: e1AppId,
        releaseId: e1ReleaseId,
        buildFingerprint: e1BuildFingerprint,
        functionId: e1CalculatePriceId,
        functionSlot: e1CalculatePriceSlot,
      ),
    );
  }
  if (iosEvidence case final evidence?) {
    await WidgetsBinding.instance.endOfFrame;
    unawaited(evidence.run(patches, calculatePrice, calculateAsyncPrice));
  }
  if (androidEvidence case final evidence?) {
    await WidgetsBinding.instance.endOfFrame;
    unawaited(evidence.run(patches, calculatePrice, calculateAsyncPrice));
  }
}

typedef PriceCalculator = int Function(int quantity, int tier);

/// The deliberately small Riverpod state consumed by [quotedPriceProvider].
final class PricingInput {
  const PricingInput({required this.quantity, required this.tier});

  final int quantity;
  final int tier;
}

final class PricingInputNotifier extends Notifier<PricingInput> {
  @override
  PricingInput build() => const PricingInput(quantity: 6, tier: 1);

  void incrementQuantity() {
    state = PricingInput(quantity: state.quantity + 1, tier: state.tier);
  }

  void toggleTier() {
    state = PricingInput(
      quantity: state.quantity,
      tier: state.tier == 1 ? 2 : 1,
    );
  }
}

final NotifierProvider<PricingInputNotifier, PricingInput>
pricingInputProvider = NotifierProvider<PricingInputNotifier, PricingInput>(
  PricingInputNotifier.new,
);

/// Host-owned invalidation signal used by the physical evidence fixture. It
/// does not grant guest code provider access; the mounted host increments it
/// after a patch status transition so existing consumers recompute normally.
final class PatchTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final NotifierProvider<PatchTickNotifier, int> patchTickProvider =
    NotifierProvider<PatchTickNotifier, int>(PatchTickNotifier.new);

final Provider<PriceCalculator> priceCalculatorProvider =
    Provider<PriceCalculator>((ref) => calculatePrice);

/// A normal derived provider. It intentionally has no patch-status dependency:
/// cached values change only when Riverpod sees an input change or a host
/// explicitly invalidates this provider.
final Provider<int> quotedPriceProvider = Provider<int>((ref) {
  ref.watch(patchTickProvider);
  final input = ref.watch(pricingInputProvider);
  final calculate = ref.watch(priceCalculatorProvider);
  return calculate(input.quantity, input.tier);
});

typedef PricingHostWait = Future<void> Function();

final Provider<PricingHostWait> pricingHostWaitProvider =
    Provider<PricingHostWait>(
      (ref) =>
          () => Future<void>.delayed(Duration.zero),
    );

/// Bounded async interoperability evidence. Riverpod owns this notifier and
/// its loading/data transitions; only the ordinary calculator it calls is in
/// the supported patch surface.
final class AsyncPricingNotifier extends AsyncNotifier<int> {
  @override
  FutureOr<int> build() {
    ref.watch(patchTickProvider);
    final input = ref.watch(pricingInputProvider);
    final calculate = ref.watch(priceCalculatorProvider);
    final waitForHost = ref.read(pricingHostWaitProvider);
    return () async {
      await waitForHost();
      return calculate(input.quantity, input.tier);
    }();
  }
}

final AsyncNotifierProvider<AsyncPricingNotifier, int>
asyncQuotedPriceProvider = AsyncNotifierProvider<AsyncPricingNotifier, int>(
  AsyncPricingNotifier.new,
);

/// A focused Riverpod surface used by conformance and transformed-overlay tests.
class RiverpodPricingApp extends StatelessWidget {
  const RiverpodPricingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: MaterialApp(home: Scaffold(body: RiverpodPricingPanel())),
    );
  }
}

class RiverpodPricingPanel extends ConsumerWidget {
  const RiverpodPricingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = ref.watch(pricingInputProvider);
    final price = ref.watch(quotedPriceProvider);
    final asyncPrice = ref.watch(asyncQuotedPriceProvider);
    final asyncPriceText = switch (asyncPrice) {
      AsyncData<int>(:final value) => 'riverpod async price: $value',
      AsyncError<int>(:final error) => 'riverpod async error: $error',
      _ => 'riverpod async price: loading',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'riverpod quantity: ${input.quantity}',
          key: const Key('riverpod-quantity'),
        ),
        Text('riverpod tier: ${input.tier}', key: const Key('riverpod-tier')),
        Text('riverpod price: $price', key: const Key('riverpod-price')),
        Text(asyncPriceText, key: const Key('riverpod-async-price')),
        FilledButton(
          key: const Key('riverpod-increment'),
          onPressed: () =>
              ref.read(pricingInputProvider.notifier).incrementQuantity(),
          child: const Text('Increase Riverpod quantity'),
        ),
        FilledButton.tonal(
          key: const Key('riverpod-tier-toggle'),
          onPressed: () => ref.read(pricingInputProvider.notifier).toggleTier(),
          child: const Text('Toggle Riverpod tier'),
        ),
      ],
    );
  }
}

/// The deliberately small state owned by [BlocPricingCubit].
final class BlocPricingState {
  const BlocPricingState({
    required this.quantity,
    required this.tier,
    required this.price,
  });

  final int quantity;
  final int tier;
  final int price;
}

/// BLoC owns this instance, stream, and state. Its ordinary inputs call only
/// the app-owned pricing function that is inside the supported patch surface.
final class BlocPricingCubit extends Cubit<BlocPricingState> {
  BlocPricingCubit()
    : super(
        BlocPricingState(quantity: 6, tier: 1, price: calculatePrice(6, 1)),
      );

  void incrementQuantity() {
    final quantity = state.quantity + 1;
    emit(
      BlocPricingState(
        quantity: quantity,
        tier: state.tier,
        price: calculatePrice(quantity, state.tier),
      ),
    );
  }

  void toggleTier() {
    final tier = state.tier == 1 ? 2 : 1;
    emit(
      BlocPricingState(
        quantity: state.quantity,
        tier: tier,
        price: calculatePrice(state.quantity, tier),
      ),
    );
  }
}

/// Test/evidence counter for the mounted [BlocBuilder].
final class BlocPricingLifecycle {
  int buildCount = 0;
}

/// A focused BLoC surface that accepts an existing Cubit instance.
final class BlocPricingApp extends StatelessWidget {
  const BlocPricingApp({
    super.key,
    required this.cubit,
    required this.lifecycle,
  });

  final BlocPricingCubit cubit;
  final BlocPricingLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BlocPricingCubit>.value(
      value: cubit,
      child: MaterialApp(
        home: Scaffold(body: BlocPricingPanel(lifecycle: lifecycle)),
      ),
    );
  }
}

final class BlocPricingPanel extends StatelessWidget {
  const BlocPricingPanel({super.key, required this.lifecycle});

  final BlocPricingLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BlocPricingCubit, BlocPricingState>(
      builder: (context, state) {
        lifecycle.buildCount++;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'bloc quantity: ${state.quantity}',
              key: const Key('bloc-quantity'),
            ),
            Text('bloc tier: ${state.tier}', key: const Key('bloc-tier')),
            Text('bloc price: ${state.price}', key: const Key('bloc-price')),
            FilledButton(
              key: const Key('bloc-increment'),
              onPressed: context.read<BlocPricingCubit>().incrementQuantity,
              child: const Text('Increase BLoC quantity'),
            ),
            FilledButton.tonal(
              key: const Key('bloc-tier-toggle'),
              onPressed: context.read<BlocPricingCubit>().toggleTier,
              child: const Text('Toggle BLoC tier'),
            ),
          ],
        );
      },
    );
  }
}

/// Test/evidence surface for Flutter-owned mounted-state identity.
///
/// Patching changes guarded function behavior only. It does not migrate the
/// layout of a [State] object or authorize arbitrary StatefulWidget methods.
final class PriceScreenLifecycle {
  int initStateCount = 0;
  int disposeCount = 0;
  int buildCount = 0;
  PriceScreenState? currentState;

  void _attach(PriceScreenState state) {
    initStateCount++;
    currentState = state;
  }

  void _detach(PriceScreenState state) {
    disposeCount++;
    if (identical(currentState, state)) currentState = null;
  }
}

class ConformanceApp extends StatelessWidget {
  ConformanceApp({
    super.key,
    required this.patches,
    PriceScreenLifecycle? lifecycle,
    this.priceCalculator = calculatePrice,
  }) : lifecycle = lifecycle ?? PriceScreenLifecycle();

  final E1PatchController patches;
  final PriceScreenLifecycle lifecycle;
  final PriceCalculator priceCalculator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyfens E1',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: PriceScreen(
        key: const ValueKey<String>('price-screen'),
        patches: patches,
        lifecycle: lifecycle,
        priceCalculator: priceCalculator,
      ),
    );
  }
}

class PriceScreen extends StatefulWidget {
  const PriceScreen({
    super.key,
    required this.patches,
    required this.lifecycle,
    required this.priceCalculator,
  });

  final E1PatchController patches;
  final PriceScreenLifecycle lifecycle;
  final PriceCalculator priceCalculator;

  @override
  State<PriceScreen> createState() => PriceScreenState();
}

class PricingCard extends StatelessWidget {
  const PricingCard({super.key, required this.featured, required this.plan});

  final bool featured;
  final String plan;

  @override
  Widget build(BuildContext context) {
    // Explicit receiver syntax is required by the experiment's syntax-only
    // release descriptor; this is still ordinary Flutter source.
    // ignore: unnecessary_this
    if (this.featured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ignore: unnecessary_this
          Text('BASE ${this.plan}', style: const TextStyle(fontSize: 18)),
          const Text('ordinary StatelessWidget.build'),
          const ElevatedButton(onPressed: null, child: Text('Base action')),
        ],
      );
    }
    // ignore: unnecessary_this
    return Text('BASE ${this.plan}');
  }
}

class PriceScreenState extends State<PriceScreen> {
  int quantity = 6;
  int tier = 1;
  bool busy = false;
  late final TextEditingController noteController;
  late final ScrollController scrollController;
  StreamSubscription<E1PatchStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    noteController = TextEditingController(text: 'draft')
      ..selection = const TextSelection.collapsed(offset: 5);
    scrollController = ScrollController();
    widget.lifecycle._attach(this);
    _listenToPatchStatus();
  }

  @override
  void didUpdateWidget(covariant PriceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.patches, widget.patches)) {
      _statusSubscription?.cancel();
      _listenToPatchStatus();
    }
  }

  void _listenToPatchStatus() {
    ProviderContainer? container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on StateError {
      // Standalone widget tests may intentionally omit a ProviderScope.
    }
    _statusSubscription = widget.patches.statuses.listen((_) {
      if (mounted) setState(() {});
      container?.read(patchTickProvider.notifier).bump();
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    noteController.dispose();
    scrollController.dispose();
    widget.lifecycle._detach(this);
    super.dispose();
  }

  Future<void> _run(
    Future<bool> Function() operation, {
    bool confirmHealth = false,
  }) async {
    setState(() => busy = true);
    final succeeded = await operation();
    if (!mounted) return;
    setState(() => busy = false);
    if (succeeded && confirmHealth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.patches.markHealthy();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.lifecycle.buildCount++;
    final status = widget.patches.status;
    final price = widget.priceCalculator(quantity, tier);
    return Scaffold(
      appBar: AppBar(title: const Text('Hyfens E1 conformance')),
      body: ListView(
        key: const ValueKey<String>('price-screen-scroll'),
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'lifecycle: init=${widget.lifecycle.initStateCount} '
            'dispose=${widget.lifecycle.disposeCount} '
            'build=${widget.lifecycle.buildCount}',
            key: const ValueKey<String>('lifecycle'),
          ),
          Text(
            status.mode == E1PatchMode.base ? 'BASE AOT' : 'PATCH ACTIVE',
            key: const Key('mode'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text('status: ${status.phase}', key: const Key('status')),
          Text(status.detail, key: const Key('detail')),
          const SizedBox(height: 24),
          Text('quantity: $quantity', key: const Key('quantity')),
          Text('tier: $tier', key: const Key('tier-value')),
          Text(
            'price: $price',
            key: const Key('price'),
            style: Theme.of(context).textTheme.displaySmall,
          ),
          TextField(
            key: const ValueKey<String>('draft-input'),
            controller: noteController,
            decoration: const InputDecoration(labelText: 'Local draft'),
          ),
          PricingCard(featured: tier == 2, plan: 'Pro'),
          if (const bool.fromEnvironment('E1_ANDROID_EVIDENCE') ||
              const bool.fromEnvironment(
                'E1_IOS_EXPANDED_EVIDENCE',
              )) ...<Widget>[
            const Divider(height: 36),
            const Text('Riverpod physical evidence'),
            const RiverpodPricingPanel(),
          ],
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(
                key: const Key('increment'),
                onPressed: busy ? null : () => setState(() => quantity++),
                child: const Text('Increase quantity'),
              ),
              FilledButton.tonal(
                key: const Key('tier'),
                onPressed: busy
                    ? null
                    : () => setState(() => tier = tier == 1 ? 2 : 1),
                child: const Text('Toggle tier'),
              ),
            ],
          ),
          const Divider(height: 36),
          FilledButton(
            key: const Key('activate'),
            onPressed: busy
                ? null
                : () => _run(
                    widget.patches.downloadAndActivate,
                    confirmHealth: true,
                  ),
            child: const Text('Download and activate local patch'),
          ),
          OutlinedButton(
            key: const Key('invalid'),
            onPressed: busy
                ? null
                : () => _run(
                    () => widget.patches.downloadAndActivate(
                      uri: widget.patches.patchUri.resolve('invalid.e0.json'),
                    ),
                  ),
            child: const Text('Attempt invalid patch'),
          ),
          OutlinedButton(
            key: const Key('rollback'),
            onPressed: busy ? null : () => _run(widget.patches.rollback),
            child: const Text('Manual rollback'),
          ),
          if (status.patchBytes case final bytes?) Text('patch bytes: $bytes'),
          if (status.downloadMicros case final micros?)
            Text('download: $micros us'),
          if (status.verificationMicros case final micros?)
            Text('verification: $micros us'),
          if (status.loadMicros case final micros?) Text('load: $micros us'),
          const SizedBox(height: 320),
        ],
      ),
    );
  }
}
