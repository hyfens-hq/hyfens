library hyfens_flutter_integration;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'src/control_plane_delivery.dart';
import 'src/install_receipts.dart';
import 'src/installation_key.dart';
import 'src/runtime_attestation.dart';
import 'src/runtime_storage.dart';

export 'src/control_plane_delivery.dart';
export 'src/install_receipts.dart'
    show
        HyfensInstallReceiptException,
        HyfensInstallReceiptMode,
        HyfensInstallReceipts;
export 'src/runtime_attestation.dart';

/// The generated-release lifecycle boundary used by the local Phase 1B
/// workflow.
///
/// The source instrumenter emits one call to [start] in the application's
/// existing `main` function. The application remains ordinary Dart source;
/// release metadata, function maps, and the trusted public key are supplied
/// by the build overlay. The controller owns verification, persistence,
/// candidate health, and bounded runtime installation.
final class HyfensFlutterIntegration {
  HyfensFlutterIntegration._();

  static const Duration defaultPollInterval = Duration(seconds: 2);
  static final Set<E1PatchController> _controllers = <E1PatchController>{};
  static final Set<Timer> _pollers = <Timer>{};
  static final Set<E1PatchController> _pollsInFlight = <E1PatchController>{};
  static final Map<E1PatchController, HyfensInstallReceipts> _receiptClients =
      {};
  static const Duration _localControlRequestTimeout = Duration(seconds: 8);
  static const int _maxRollbackControlBytes = 16 * 1024;
  static String? _activeBootstrapKey;

  /// Starts the local development lifecycle without delaying the application's
  /// first frame. A failed local poll leaves the AOT base active and is
  /// retried on the next interval.
  static void start({
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    required Map<String, String> signatures,
    required Map<String, String> receivers,
    Map<String, String> functionNames = const <String, String>{},
    Map<String, String> functionUris = const <String, String>{},
    required String keyId,
    required List<int> publicKey,
    required Uri patchUri,
    HyfensControlPlaneConfiguration? controlPlane,
    Duration pollInterval = defaultPollInterval,
  }) {
    final functionContexts = _functionContexts(
      functionNames: functionNames,
      functionUris: functionUris,
    );
    final bootstrapKey = _bootstrapKey(
      appId: appId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      functions: functions,
      signatures: signatures,
      receivers: receivers,
      functionNames: functionNames,
      functionUris: functionUris,
      keyId: keyId,
      publicKey: publicKey,
      patchUri: patchUri,
      controlPlane: controlPlane,
    );
    final active = _activeBootstrapKey;
    if (active != null) {
      if (active != bootstrapKey) {
        stderr.writeln(
          'HYFENS_PATCH bootstrap ignored: a different runtime is already active',
        );
      }
      return;
    }
    _activeBootstrapKey = bootstrapKey;
    E0PatchRuntime.markGeneratedIntegrationStarted();
    _configureDiagnostics(functionContexts);
    unawaited(
      _start(
        bootstrapKey: bootstrapKey,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
        functionContexts: functionContexts,
        keyId: keyId,
        publicKey: publicKey,
        patchUri: patchUri,
        controlPlane: controlPlane,
        pollInterval: pollInterval,
      ),
    );
  }

  static void _writeRuntimeDiagnostic(String message) {
    // The message is already bounded and redacted by E0RuntimeFault. Use the
    // Flutter/Dart stdout path because release Android builds surface print()
    // records through logcat reliably, while stderr is not consistently
    // forwarded by the embedding.
    print('HYFENS_PATCH runtime fault: $message');
  }

  static Map<String, E0RuntimeFunctionContext> _functionContexts({
    required Map<String, String> functionNames,
    required Map<String, String> functionUris,
  }) {
    if (functionNames.keys
            .toSet()
            .difference(functionUris.keys.toSet())
            .isNotEmpty ||
        functionUris.keys
            .toSet()
            .difference(functionNames.keys.toSet())
            .isNotEmpty) {
      throw const FormatException(
        'Runtime function context names and URIs must have the same keys',
      );
    }
    return <String, E0RuntimeFunctionContext>{
      for (final entry in functionNames.entries)
        entry.key: E0RuntimeFunctionContext(
          functionId: entry.key,
          functionName: entry.value,
          logicalUri: functionUris[entry.key]!,
        )..validate(),
    };
  }

  static void _configureDiagnostics(
    Map<String, E0RuntimeFunctionContext> functionContexts,
  ) {
    E0PatchRuntime.configureFunctionContexts(functionContexts);
    E0PatchRuntime.configureDiagnosticSink(_writeRuntimeDiagnostic);
  }

  static Future<void> _start({
    required String bootstrapKey,
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    required Map<String, String> signatures,
    required Map<String, String> receivers,
    required Map<String, E0RuntimeFunctionContext> functionContexts,
    required String keyId,
    required List<int> publicKey,
    required Uri patchUri,
    HyfensControlPlaneConfiguration? controlPlane,
    required Duration pollInterval,
  }) async {
    try {
      final storage = await runtimeStorageDirectory(
        appId: appId,
        releaseId: releaseId,
      );
      final controller = E1PatchController(
        storageDirectory: storage,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
        patchUri: patchUri,
        trustedPublicKeys: <String, E1TrustedPublicKey>{
          keyId: E1TrustedPublicKey(keyId: keyId, bytes: publicKey),
        },
      );
      _controllers.add(controller);
      try {
        await controller.initialize();
        _configureDiagnostics(functionContexts);
        await _poll(controller, patchUri, functionContexts, controlPlane);
        if (pollInterval <= Duration.zero) return;
        final timer = Timer.periodic(pollInterval, (_) {
          unawaited(
            _poll(controller, patchUri, functionContexts, controlPlane),
          );
        });
        _pollers.add(timer);
      } on Object {
        _controllers.remove(controller);
        _receiptClients.remove(controller);
        try {
          await controller.close();
        } on Object catch (cleanupError, cleanupStack) {
          stderr.writeln(
            'HYFENS_PATCH bootstrap cleanup failed: $cleanupError',
          );
          stderr.writeln(cleanupStack);
        }
        rethrow;
      }
    } on Object catch (error, stackTrace) {
      if (_activeBootstrapKey == bootstrapKey) _activeBootstrapKey = null;
      stderr.writeln('HYFENS_PATCH bootstrap failed: $error');
      stderr.writeln(stackTrace);
    }
  }

  static String _bootstrapKey({
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    required Map<String, String> signatures,
    required Map<String, String> receivers,
    required Map<String, String> functionNames,
    required Map<String, String> functionUris,
    required String keyId,
    required List<int> publicKey,
    required Uri patchUri,
    HyfensControlPlaneConfiguration? controlPlane,
  }) {
    String mapMaterial<T>(Map<String, T> values) {
      final entries = values.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return entries.map((entry) => '${entry.key}=${entry.value}').join(';');
    }

    return <String>[
      appId,
      releaseId,
      buildFingerprint,
      mapMaterial(functions),
      mapMaterial(signatures),
      mapMaterial(receivers),
      mapMaterial(functionNames),
      mapMaterial(functionUris),
      keyId,
      publicKey.join(','),
      patchUri.toString(),
      if (controlPlane case final configuration?)
        <String>[
          configuration.baseUrl.toString(),
          configuration.applicationId,
          configuration.environmentId,
          configuration.platformId,
          '${configuration.runtimeCompatibilityVersion}',
          '${configuration.patchFormatVersion}',
          configuration.receiptMode.name,
        ].join('\u0001'),
    ].join('\u0000');
  }

  static Future<void> _poll(
    E1PatchController controller,
    Uri baseUri,
    Map<String, E0RuntimeFunctionContext> functionContexts,
    HyfensControlPlaneConfiguration? controlPlane,
  ) async {
    if (!_pollsInFlight.add(controller)) return;
    try {
      _configureDiagnostics(functionContexts);
      if (controller.recoveryNeeded) return;
      try {
        if (controlPlane case final configuration?) {
          final receipts = _receiptClientFor(controller, configuration);
          if (receipts != null) await _flushReceipts(receipts, controller);
          // A pending candidate already owns its durable admission context.
          // Retry only the existing health transition before asking for any
          // further delivery; never prepare a second admission here.
          if (controller.durableState.health == 'pending') {
            if (!await _confirmHealthy(controller)) return;
            if (receipts != null) await _flushReceipts(receipts, controller);
            return;
          }
          await HyfensControlPlaneDelivery(
            configuration,
            receipts: receipts,
          ).deliver(controller);
          _configureDiagnostics(functionContexts);
          if (controller.durableState.health == 'pending') {
            if (!await _confirmHealthy(controller)) return;
          }
          if (receipts != null) await _flushReceipts(receipts, controller);
          return;
        }
        if (controller.durableState.health == 'pending') {
          if (!await _confirmHealthy(controller)) return;
          return;
        }
        final rolledBack = await _pollRollbackControl(controller, baseUri);
        if (rolledBack) {
          _configureDiagnostics(functionContexts);
          return;
        }
        final uri = _withReleaseQuery(baseUri, controller.releaseId);
        await controller.downloadAndActivate(uri: uri);
        _configureDiagnostics(functionContexts);
        if (controller.durableState.health == 'pending') {
          await _confirmHealthy(controller);
        }
      } on Object catch (error) {
        // Local delivery is deliberately best-effort. The controller has
        // already preserved the base or last-known-good state; logging keeps
        // the failure visible without turning a missing dev server into an app
        // process failure.
        stderr.writeln('HYFENS_PATCH poll failed: $error');
      }
    } finally {
      _pollsInFlight.remove(controller);
    }
  }

  static Future<bool> _confirmHealthy(E1PatchController controller) async {
    final confirmed = await controller.markHealthy();
    if (!confirmed) {
      stderr.writeln('HYFENS_PATCH control-plane health confirmation failed');
    }
    return confirmed;
  }

  static HyfensInstallReceipts? _receiptClientFor(
    E1PatchController controller,
    HyfensControlPlaneConfiguration configuration,
  ) {
    if (configuration.receiptMode == HyfensInstallReceiptMode.disabled) {
      return null;
    }
    final existing = _receiptClients[controller];
    if (existing != null) return existing;

    final HyfensInstallReceipts? created;
    if (configuration.receiptMode == HyfensInstallReceiptMode.production) {
      final producer = configuration.attestationProducer;
      final gate = configuration.productionGate;
      if (producer == null || gate == null) return null;
      try {
        created = HyfensInstallReceipts.production(
          baseUrl: configuration.baseUrl,
          deliveryCredential: configuration.deliveryCredential,
          applicationId: configuration.applicationId,
          environmentId: configuration.environmentId,
          platformId: configuration.platformId,
          keyStore: HyfensInstallationKeyStore(),
          attestationProducer: producer,
          productionGate: gate,
          requestTimeout: configuration.requestTimeout,
        );
      } on HyfensRuntimeAttestationException {
        return null;
      }
    } else {
      created = HyfensInstallReceipts(
        baseUrl: configuration.baseUrl,
        deliveryCredential: configuration.deliveryCredential,
        applicationId: configuration.applicationId,
        environmentId: configuration.environmentId,
        platformId: configuration.platformId,
        keyStore: HyfensInstallationKeyStore(),
        requestTimeout: configuration.requestTimeout,
      );
    }
    _receiptClients[controller] = created;
    return created;
  }

  static Future<void> _flushReceipts(
    HyfensInstallReceipts receipts,
    E1PatchController controller,
  ) async {
    try {
      await receipts.flush(controller);
    } on Object {
      // Admission and durable activation are separate from receipt transport.
      // Keep the outbox intact; do not disturb an already-installed patch.
      stderr.writeln('HYFENS_PATCH receipt remains queued');
    }
  }

  static Future<bool> _pollRollbackControl(
    E1PatchController controller,
    Uri patchUri,
  ) async {
    final controlUri = _withReleaseQuery(
      _controlUri(patchUri),
      controller.releaseId,
    );
    final bytes = await _downloadControl(controlUri);
    if (bytes == null) return false;
    return controller.applyRollbackControl(bytes);
  }

  static Future<List<int>?> _downloadControl(Uri uri) async {
    if (uri.scheme != 'http' || !_isLocalDevelopmentHost(uri.host)) {
      throw const FormatException(
        'E1 only permits local-development HTTP endpoints',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = _localControlRequestTimeout;
    try {
      final request =
          await client.getUrl(uri).timeout(_localControlRequestTimeout)
            ..followRedirects = false;
      final response = await request.close().timeout(
        _localControlRequestTimeout,
      );
      if (response.isRedirect) {
        throw const FormatException('rollback control redirects are disabled');
      }
      if (response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = await _readBoundedResponse(
        response,
        maxBytes: _maxRollbackControlBytes,
      ).timeout(_localControlRequestTimeout);
      return Uint8List.fromList(bytes);
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<int>> _readBoundedResponse(
    HttpClientResponse response, {
    required int maxBytes,
  }) async {
    if (response.contentLength > maxBytes) {
      throw const FormatException('response exceeds byte limit');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (chunk.length > maxBytes - builder.length) {
        throw const FormatException('response exceeds byte limit');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Uri _withReleaseQuery(Uri uri, String releaseId) {
    final query = <String, String>{
      ...uri.queryParameters,
      'release': releaseId,
    };
    return uri.replace(queryParameters: query);
  }

  static Uri _controlUri(Uri patchUri) {
    const patchSuffix = '/patch';
    final path = patchUri.path;
    final controlPath = path.endsWith(patchSuffix)
        ? '${path.substring(0, path.length - patchSuffix.length)}/control'
        : '$path/control';
    return patchUri.replace(path: controlPath, queryParameters: const {});
  }

  static bool _isLocalDevelopmentHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }
    if (host.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.type == InternetAddressType.IPv4) {
      final octets = host.split('.').map(int.parse).toList(growable: false);
      return octets[0] == 10 ||
          (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
          (octets[0] == 192 && octets[1] == 168) ||
          (octets[0] == 169 && octets[1] == 254);
    }
    final normalized = host.toLowerCase();
    return normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe80:');
  }

  /// Returns the generated call source used by tests and diagnostics.
  ///
  /// Keeping the serialization here makes the build-time source injection
  /// contract easy to inspect without exposing a mutable runtime API.
  static String invocationSource({
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    required Map<String, String> signatures,
    required Map<String, String> receivers,
    Map<String, String> functionNames = const <String, String>{},
    Map<String, String> functionUris = const <String, String>{},
    required String keyId,
    required List<int> publicKey,
    required Uri patchUri,
  }) {
    String mapInt(Map<String, int> value) {
      final entries = value.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return '<String, int>{${entries.map((entry) => '${jsonEncode(entry.key)}: ${entry.value}').join(', ')}}';
    }

    String mapString(Map<String, String> value) {
      final entries = value.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return '<String, String>{${entries.map((entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value)}').join(', ')}}';
    }

    return 'start('
        'appId: ${jsonEncode(appId)}, '
        'releaseId: ${jsonEncode(releaseId)}, '
        'buildFingerprint: ${jsonEncode(buildFingerprint)}, '
        'functions: ${mapInt(functions)}, '
        'signatures: ${mapString(signatures)}, '
        'receivers: ${mapString(receivers)}, '
        'functionNames: ${mapString(functionNames)}, '
        'functionUris: ${mapString(functionUris)}, '
        'keyId: ${jsonEncode(keyId)}, '
        'publicKey: <int>[${publicKey.join(', ')}], '
        'patchUri: Uri.parse(${jsonEncode(patchUri.toString())}),'
        'controlPlane: _hyfens_bootstrap.HyfensControlPlaneConfiguration.fromEnvironment(),'
        ');';
  }
}
