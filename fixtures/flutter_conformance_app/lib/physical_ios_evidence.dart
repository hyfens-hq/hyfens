import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'patch_bootstrap.dart';

typedef PhysicalIosPriceCalculator = int Function(int quantity, int tier);
typedef PhysicalIosAsyncCalculator = Future<int> Function(
  int quantity,
  int tier,
);

/// A compile-time-gated physical-device evidence path.
///
/// Normal builds omit this behavior because [open] returns `null` unless the
/// explicit `E1_IOS_EVIDENCE` dart define is true. The harness uses the same
/// signed controller as the UI. It normally uses a local HTTP server; the
/// USB mode stages the same signed bytes in the app Documents container so a
/// USB-connected device does not need a network route back to the host.
final class PhysicalIosEvidenceSession {
  PhysicalIosEvidenceSession._({
    required this.runId,
    required this.patchUri,
    required this._receiptUri,
    required this._stateFile,
    required this._stage,
    required this._multiFunction,
    this._usbPatchFile,
    this._usbInvalidPatchFile,
    this._usbReceiptFile,
  });

  static const _stateFileName = 'hyfens-e1-ios-evidence-v1.json';
  static const _patchDirectoryName = 'hyfens-e1';
  static final RegExp _runIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,80}$');
  static final RegExp _tokenPattern = RegExp(r'^[a-f0-9]{64}$');

  final String runId;
  final Uri patchUri;
  final Uri _receiptUri;
  final File _stateFile;
  final File? _usbPatchFile;
  final File? _usbInvalidPatchFile;
  final File? _usbReceiptFile;
  final bool _multiFunction;
  int _stage;

  int get stage => _stage;

  static Future<PhysicalIosEvidenceSession?> open(
    Directory supportDirectory, {
    bool enabled = const bool.fromEnvironment('E1_IOS_EVIDENCE'),
    String runId = const String.fromEnvironment('E1_IOS_EVIDENCE_RUN_ID'),
    String serverUrl = const String.fromEnvironment('E1_IOS_EVIDENCE_SERVER'),
    String token = const String.fromEnvironment('E1_IOS_EVIDENCE_TOKEN'),
    bool usbMode = const bool.fromEnvironment('E1_IOS_USB_EVIDENCE'),
    bool multiFunction = const bool.fromEnvironment('E1_IOS_MULTI_FUNCTION'),
    Directory? usbDirectory,
  }) async {
    if (!enabled) return null;
    if (!_runIdPattern.hasMatch(runId)) {
      throw const FormatException('Invalid E1 iOS evidence run ID');
    }
    Uri? server;
    if (!usbMode) {
      server = Uri.parse(serverUrl);
      if ((server.scheme != 'http' && server.scheme != 'https') ||
          !server.hasAuthority ||
          server.userInfo.isNotEmpty ||
          !_isLocalAddress(server.host) ||
          (server.path.isNotEmpty && server.path != '/') ||
          server.query.isNotEmpty ||
          server.fragment.isNotEmpty) {
        throw const FormatException('Invalid E1 iOS evidence server URL');
      }
      if (!_tokenPattern.hasMatch(token)) {
        throw const FormatException('Invalid E1 iOS evidence bearer token');
      }
    } else if (usbDirectory == null) {
      throw const FormatException(
        'USB iOS evidence requires an app Documents directory',
      );
    }

    await supportDirectory.create(recursive: true);
    final usbPatchDirectory = usbDirectory == null
        ? null
        : Directory('${usbDirectory.path}/$_patchDirectoryName');
    if (usbPatchDirectory != null) {
      await usbPatchDirectory.create(recursive: true);
    }
    final stateFileName = multiFunction
        ? 'hyfens-e1-ios-multi-v1.json'
        : _stateFileName;
    final stateFile = File('${supportDirectory.path}/$stateFileName');
    var stage = 0;
    var matchingRun = false;
    if (await stateFile.exists()) {
      try {
        final state = jsonDecode(await stateFile.readAsString());
        if (state is Map<String, Object?> && state['runId'] == runId) {
          final storedStage = state['stage'];
          if (storedStage is int && storedStage >= 0 && storedStage <= 3) {
            stage = storedStage;
            matchingRun = true;
          }
        }
      } on Object {
        // A malformed test-harness marker starts a fresh evidence run. The E1
        // controller's own fail-closed durable state remains independently
        // validated in production code.
      }
    }
    if (!matchingRun) {
      final patchDirectory = Directory(
        '${supportDirectory.path}/$_patchDirectoryName',
      );
      if (await patchDirectory.exists()) {
        await patchDirectory.delete(recursive: true);
      }
      if (usbPatchDirectory != null && await usbPatchDirectory.exists()) {
        await usbPatchDirectory.delete(recursive: true);
        await usbPatchDirectory.create(recursive: true);
      }
      stage = 0;
      await _writeState(stateFile, runId, stage);
    }

    final base = usbMode
        ? Uri.parse('http://127.0.0.1:18080/usb/')
        : server!.replace(path: '/$token/');
    final usbPatchName = multiFunction
        ? 'multi-1.v1.patch'
        : 'patch.e1.signed.json';
    final usbInvalidPatchName = multiFunction
        ? 'multi-invalid.v1.patch'
        : 'invalid-signature.e1.signed.json';
    final usbPatchFile = usbPatchDirectory == null
        ? null
        : File('${usbPatchDirectory.path}/$usbPatchName');
    final usbInvalidPatchFile = usbPatchDirectory == null
        ? null
        : File('${usbPatchDirectory.path}/$usbInvalidPatchName');
    final usbReceiptFile = usbPatchDirectory == null
        ? null
        : File('${usbPatchDirectory.path}/receipts.jsonl');
    return PhysicalIosEvidenceSession._(
      runId: runId,
      patchUri: base.resolve(
        multiFunction ? 'multi-1.v1.patch' : 'patch.e1.signed.json',
      ),
      receiptUri: base.resolve('evidence'),
      stateFile: stateFile,
      stage: stage,
      multiFunction: multiFunction,
      usbPatchFile: usbPatchFile,
      usbInvalidPatchFile: usbInvalidPatchFile,
      usbReceiptFile: usbReceiptFile,
    );
  }

  static bool _isLocalAddress(String host) {
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 169 && bytes[1] == 254) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return address.address == InternetAddress.loopbackIPv6.address ||
        (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
  }

  Future<void> run(
    E1PatchController patches,
    PhysicalIosPriceCalculator calculatePrice,
    PhysicalIosAsyncCalculator calculateAsyncPrice,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    try {
      if (_multiFunction) {
        await _runMultiFunction(patches, calculatePrice, calculateAsyncPrice);
        return;
      }
      switch (_stage) {
        case 0:
          await _assertAndReport(
            stageName: 'base',
            patches: patches,
            calculatePrice: calculatePrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
          );
          final activated = await _activatePatch(patches);
          if (!activated) {
            throw StateError(
              'signed patch activation failed: ${patches.status.detail}',
            );
          }
          final healthy = await patches.markHealthy();
          if (!healthy) {
            throw StateError('signed patch health confirmation failed');
          }
          await _assertAndReport(
            stageName: 'patch-active',
            patches: patches,
            calculatePrice: calculatePrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 450,
          );
          await _advanceAndReport(1, patches, calculatePrice);
          return;
        case 1:
          await _assertAndReport(
            stageName: 'patch-persisted',
            patches: patches,
            calculatePrice: calculatePrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 450,
          );
          final invalidAccepted = await _activatePatch(patches, invalid: true);
          if (invalidAccepted ||
              patches.status.phase != 'rejected' ||
              patches.status.mode != E1PatchMode.patch ||
              calculatePrice(6, 1) != 450) {
            throw StateError(
              'invalid signature rejection did not retain patch',
            );
          }
          await _report('invalid-rejected', patches, calculatePrice, true);
          final rolledBack = await patches.rollback();
          if (!rolledBack) throw StateError('manual rollback failed');
          await _assertAndReport(
            stageName: 'rolled-back',
            patches: patches,
            calculatePrice: calculatePrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
          );
          final staleAccepted = await _activatePatch(patches, stale: true);
          if (staleAccepted ||
              patches.status.phase != 'rejected' ||
              patches.status.mode != E1PatchMode.base ||
              patches.durableState.highWaterSequence != 1 ||
              calculatePrice(6, 1) != 540) {
            throw StateError(
              'direct stale bytes were not rejected after rollback',
            );
          }
          await _report('stale-rejected', patches, calculatePrice, true);
          await _advanceAndReport(2, patches, calculatePrice);
          return;
        case 2:
          await _assertAndReport(
            stageName: 'rollback-persisted',
            patches: patches,
            calculatePrice: calculatePrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
          );
          await _advanceAndReport(3, patches, calculatePrice);
          return;
        case 3:
          await _report('complete', patches, calculatePrice, true);
          return;
      }
    } on Object catch (error, stackTrace) {
      stderr.writeln('E1_IOS_EVIDENCE_FAILURE $error\n$stackTrace');
      try {
        await _report(
          'failure',
          patches,
          calculatePrice,
          false,
          error: '$error',
        );
      } on Object catch (reportError) {
        stderr.writeln('E1_IOS_EVIDENCE_REPORT_FAILURE $reportError');
      }
    }
  }

  Future<void> _runMultiFunction(
    E1PatchController patches,
    PhysicalIosPriceCalculator calculatePrice,
    PhysicalIosAsyncCalculator calculateAsyncPrice,
  ) async {
    switch (_stage) {
      case 0:
        await _assertAndReport(
          stageName: 'multi-base',
          patches: patches,
          calculatePrice: calculatePrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedAsyncPrice: 540,
        );
        final activated = await _activatePatch(patches);
        if (!activated || !await patches.markHealthy()) {
          throw StateError(
            'multi-function patch activation failed: ${patches.status.detail}',
          );
        }
        await _assertAndReport(
          stageName: 'multi-function-patch',
          patches: patches,
          calculatePrice: calculatePrice,
          expectedMode: E1PatchMode.patch,
          expectedPrice: 450,
          expectedUiPatched: true,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedAsyncPrice: 481,
        );
        await _advanceAndReport(1, patches, calculatePrice);
        return;
      case 1:
        await _assertAndReport(
          stageName: 'multi-persisted',
          patches: patches,
          calculatePrice: calculatePrice,
          expectedMode: E1PatchMode.patch,
          expectedPrice: 450,
          expectedUiPatched: true,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedAsyncPrice: 481,
        );
        final invalidAccepted = await _activatePatch(patches, invalid: true);
        if (invalidAccepted ||
            patches.status.phase != 'rejected' ||
            patches.status.mode != E1PatchMode.patch ||
            calculatePrice(6, 1) != 450 ||
            await calculateAsyncPrice(6, 1) != 481 ||
            !_isUiPatched) {
          throw StateError(
            'invalid multi-function artifact did not retain the batch',
          );
        }
        await _report(
          'multi-invalid-rejected',
          patches,
          calculatePrice,
          true,
          uiPatched: _isUiPatched,
          asyncPrice: await calculateAsyncPrice(6, 1),
        );
        if (!await patches.rollback()) {
          throw StateError('multi-function rollback failed');
        }
        await _assertAndReport(
          stageName: 'multi-rolled-back',
          patches: patches,
          calculatePrice: calculatePrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedAsyncPrice: 540,
        );
        await _advanceAndReport(2, patches, calculatePrice);
        return;
      case 2:
        await _assertAndReport(
          stageName: 'multi-rollback-persisted',
          patches: patches,
          calculatePrice: calculatePrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedAsyncPrice: 540,
        );
        await _advanceAndReport(3, patches, calculatePrice);
        return;
      case 3:
        await _report(
          'multi-complete',
          patches,
          calculatePrice,
          true,
          asyncPrice: await calculateAsyncPrice(6, 1),
        );
        return;
    }
  }

  Future<void> _assertAndReport({
    required String stageName,
    required E1PatchController patches,
    required PhysicalIosPriceCalculator calculatePrice,
    required E1PatchMode expectedMode,
    required int expectedPrice,
    PhysicalIosAsyncCalculator? calculateAsyncPrice,
    int? expectedAsyncPrice,
    bool expectedUiPatched = false,
  }) async {
    final actualPrice = calculatePrice(6, 1);
    final actualAsyncPrice = calculateAsyncPrice == null
        ? null
        : await calculateAsyncPrice(6, 1);
    final uiPatched = _isUiPatched;
    if (patches.status.mode != expectedMode ||
        actualPrice != expectedPrice ||
        (expectedAsyncPrice != null &&
            actualAsyncPrice != expectedAsyncPrice) ||
        (expectedUiPatched && !uiPatched)) {
      throw StateError(
        '$stageName mismatch: mode=${patches.status.mode.name} price=$actualPrice',
      );
    }
    await _report(
      stageName,
      patches,
      calculatePrice,
      true,
      uiPatched: uiPatched,
      asyncPrice: actualAsyncPrice,
    );
  }

  bool get _isUiPatched =>
      E0PatchRuntime.lookup(e1PricingCardBuildSlot)?.signature ==
      e0WidgetBuildSignature;

  Future<void> _advanceAndReport(
    int nextStage,
    E1PatchController patches,
    PhysicalIosPriceCalculator calculatePrice,
  ) async {
    _stage = nextStage;
    await _writeState(_stateFile, runId, nextStage);
    await _report(
      nextStage == 3 ? 'complete' : 'restart-required-$nextStage',
      patches,
      calculatePrice,
      true,
    );
  }

  Future<void> _report(
    String stageName,
    E1PatchController patches,
    PhysicalIosPriceCalculator calculatePrice,
    bool succeeded, {
    bool uiPatched = false,
    int? asyncPrice,
    String? error,
  }) async {
    final payload = utf8.encode(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'runId': runId,
        'stage': stageName,
        'processId': pid,
        'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'appId': e1AppId,
        'releaseId': e1ReleaseId,
        'buildFingerprint': e1BuildFingerprint,
        'functionId': e1CalculatePriceId,
        'quantity': 6,
        'tier': 1,
        'price': calculatePrice(6, 1),
        'asyncPrice': asyncPrice,
        'uiPatched': uiPatched,
        'succeeded': succeeded,
        'error': error,
        'status': patches.status.toJson(),
        'highWaterSequence': patches.durableState.highWaterSequence,
      }),
    );
    final usbReceiptFile = _usbReceiptFile;
    if (usbReceiptFile != null) {
      await usbReceiptFile.parent.create(recursive: true);
      await usbReceiptFile.writeAsString(
        '${utf8.decode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(_receiptUri);
      request.headers.contentType = ContentType.json;
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      if (response.statusCode != HttpStatus.noContent) {
        throw HttpException(
          'evidence server returned HTTP ${response.statusCode}',
          uri: _receiptUri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _activatePatch(
    E1PatchController patches, {
    bool invalid = false,
    bool stale = false,
  }) async {
    if (invalid && stale) {
      throw ArgumentError('invalid and stale patch modes are exclusive');
    }
    final file = invalid ? _usbInvalidPatchFile : _usbPatchFile;
    if (file != null) {
      for (var attempt = 0; attempt < 240; attempt++) {
        if (await file.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!await file.exists()) {
        throw StateError('USB-staged patch is missing: ${file.path}');
      }
      return patches.activateBytes(await file.readAsBytes());
    }
    return patches.downloadAndActivate(
      uri: invalid
          ? patchUri.resolve(
              _multiFunction
                  ? 'multi-invalid.v1.patch'
                  : 'invalid-signature.e1.signed.json',
            )
          : null,
    );
  }

  static Future<void> _writeState(File file, String runId, int stage) async {
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode(<String, Object>{'runId': runId, 'stage': stage}),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
