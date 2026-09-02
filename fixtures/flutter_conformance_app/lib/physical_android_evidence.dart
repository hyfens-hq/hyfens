import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

import 'patch_bootstrap.dart';

typedef PhysicalAndroidPriceCalculator = int Function(int quantity, int tier);
typedef PhysicalAndroidAsyncCalculator = Future<int> Function(
  int quantity,
  int tier,
);

/// Cross-feature release evidence used only when E1_ANDROID_EVIDENCE is true.
/// The host still owns the widget/capability registries; downloaded bytes only
/// select one already-compiled function slot at a time.
final class PhysicalAndroidEvidenceSession {
  PhysicalAndroidEvidenceSession._({
    required this.runId,
    required this.patchUri,
    required this._receiptUri,
    required this._stateFile,
    required this._stage,
    required this._multiFunction,
    this._usbPatchDirectory,
    this._usbReceiptFile,
  });

  static const _stateFileName = 'hyfens-e1-android-evidence-v1.json';
  static final RegExp _runIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,80}$');
  static final RegExp _tokenPattern = RegExp(r'^[a-f0-9]{64}$');

  final String runId;
  final Uri patchUri;
  final Uri _receiptUri;
  final File _stateFile;
  final Directory? _usbPatchDirectory;
  final File? _usbReceiptFile;
  final bool _multiFunction;
  int _stage;

  static Future<PhysicalAndroidEvidenceSession?> open(
    Directory supportDirectory, {
    bool enabled = const bool.fromEnvironment('E1_ANDROID_EVIDENCE'),
    String runId = const String.fromEnvironment('E1_ANDROID_EVIDENCE_RUN_ID'),
    String serverUrl = const String.fromEnvironment(
      'E1_ANDROID_EVIDENCE_SERVER',
    ),
    String token = const String.fromEnvironment('E1_ANDROID_EVIDENCE_TOKEN'),
    bool usbMode = const bool.fromEnvironment('E1_ANDROID_USB_EVIDENCE'),
    bool multiFunction = const bool.fromEnvironment(
      'E1_ANDROID_MULTI_FUNCTION',
    ),
    Directory? usbDirectory,
  }) async {
    if (!enabled) return null;
    if (!_runIdPattern.hasMatch(runId)) {
      throw const FormatException('Invalid E1 Android evidence run ID');
    }
    Uri? server;
    if (!usbMode) {
      server = Uri.parse(serverUrl);
      if (server.scheme != 'http' ||
          !server.hasAuthority ||
          server.userInfo.isNotEmpty ||
          server.host != '127.0.0.1' ||
          (server.path.isNotEmpty && server.path != '/') ||
          server.query.isNotEmpty ||
          server.fragment.isNotEmpty) {
        throw const FormatException('Invalid E1 Android evidence server URL');
      }
      if (!_tokenPattern.hasMatch(token)) {
        throw const FormatException('Invalid E1 Android evidence bearer token');
      }
    } else if (usbDirectory == null) {
      throw const FormatException(
        'USB cross-feature evidence requires an app Documents directory',
      );
    }
    await supportDirectory.create(recursive: true);
    final usbPatchDirectory = usbDirectory == null
        ? null
        : Directory('${usbDirectory.path}/hyfens-e1');
    if (usbPatchDirectory != null) {
      await usbPatchDirectory.create(recursive: true);
    }
    final stateFileName = multiFunction
        ? 'hyfens-e1-android-multi-v1.json'
        : _stateFileName;
    final stateFile = File('${supportDirectory.path}/$stateFileName');
    var stage = 0;
    var matchingRun = false;
    if (await stateFile.exists()) {
      try {
        final state = jsonDecode(await stateFile.readAsString());
        if (state is Map<String, Object?> && state['runId'] == runId) {
          final storedStage = state['stage'];
          if (storedStage is int && storedStage >= 0 && storedStage <= 2) {
            stage = storedStage;
            matchingRun = true;
          }
        }
      } on Object {
        // A malformed evidence marker starts a fresh harness run.
      }
    }
    if (!matchingRun) {
      final patchDirectory = Directory('${supportDirectory.path}/hyfens-e1');
      if (await patchDirectory.exists()) {
        await patchDirectory.delete(recursive: true);
      }
      if (usbPatchDirectory != null && await usbPatchDirectory.exists()) {
        await usbPatchDirectory.delete(recursive: true);
        await usbPatchDirectory.create(recursive: true);
      }
      await _writeState(stateFile, runId, 0);
    }
    final base = usbMode
        ? Uri.parse('http://127.0.0.1:18080/usb/')
        : server!.replace(path: '/$token/');
    return PhysicalAndroidEvidenceSession._(
      runId: runId,
      patchUri: base.resolve(
        multiFunction ? 'multi-1.v1.patch' : 'business-1.e1.signed.json',
      ),
      receiptUri: base.resolve('evidence'),
      stateFile: stateFile,
      stage: stage,
      multiFunction: multiFunction,
      usbPatchDirectory: usbPatchDirectory,
      usbReceiptFile: usbPatchDirectory == null
          ? null
          : File('${usbPatchDirectory.path}/receipts.jsonl'),
    );
  }

  Future<void> run(
    E1PatchController patches,
    PhysicalAndroidPriceCalculator calculatePrice,
    PhysicalAndroidAsyncCalculator calculateAsyncPrice,
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
            calculateAsyncPrice: calculateAsyncPrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
            expectedAsyncPrice: 540,
          );
          await _activateAndReport(
            'business-patch',
            patches,
            calculatePrice,
            calculateAsyncPrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 450,
            expectedAsyncPrice: 450,
            patchName: 'business-1.e1.signed.json',
          );
          await _activateAndReport(
            'async-patch',
            patches,
            calculatePrice,
            calculateAsyncPrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 540,
            expectedAsyncPrice: 481,
            patchName: 'async-2.e1.signed.json',
          );
          await _activateAndReport(
            'ui-patch',
            patches,
            calculatePrice,
            calculateAsyncPrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 540,
            expectedAsyncPrice: 540,
            patchName: 'ui-3.e1.signed.json',
          );
          await _activateAndReport(
            'riverpod-patch',
            patches,
            calculatePrice,
            calculateAsyncPrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 450,
            expectedAsyncPrice: 450,
            patchName: 'business-4.e1.signed.json',
          );
          _stage = 1;
          await _writeState(_stateFile, runId, _stage);
          await _report('restart-required-1', patches, calculatePrice, true);
          return;
        case 1:
          await _assertAndReport(
            stageName: 'riverpod-persisted',
            patches: patches,
            calculatePrice: calculatePrice,
            calculateAsyncPrice: calculateAsyncPrice,
            expectedMode: E1PatchMode.patch,
            expectedPrice: 450,
            expectedAsyncPrice: 450,
          );
          final invalidAccepted = await _activatePatch(
            patches,
            'invalid-signature.e1.signed.json',
          );
          if (invalidAccepted ||
              patches.status.phase != 'rejected' ||
              calculatePrice(6, 1) != 450) {
            throw StateError('invalid signature did not retain Riverpod patch');
          }
          await _report('invalid-rejected', patches, calculatePrice, true);
          if (!await patches.rollback()) {
            throw StateError('manual rollback failed');
          }
          await _assertAndReport(
            stageName: 'rolled-back',
            patches: patches,
            calculatePrice: calculatePrice,
            calculateAsyncPrice: calculateAsyncPrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
            expectedAsyncPrice: 540,
          );
          final staleAccepted = await _activatePatch(
            patches,
            'business-4.e1.signed.json',
          );
          if (staleAccepted ||
              patches.status.phase != 'rejected' ||
              patches.status.mode != E1PatchMode.base ||
              patches.durableState.highWaterSequence != 4 ||
              calculatePrice(6, 1) != 540) {
            throw StateError(
              'direct stale bytes were not rejected after rollback',
            );
          }
          await _report('stale-rejected', patches, calculatePrice, true);
          _stage = 2;
          await _writeState(_stateFile, runId, _stage);
          await _report('restart-required-2', patches, calculatePrice, true);
          return;
        case 2:
          await _assertAndReport(
            stageName: 'rollback-persisted',
            patches: patches,
            calculatePrice: calculatePrice,
            calculateAsyncPrice: calculateAsyncPrice,
            expectedMode: E1PatchMode.base,
            expectedPrice: 540,
            expectedAsyncPrice: 540,
          );
          await _report('complete', patches, calculatePrice, true);
          return;
      }
    } on Object catch (error, stackTrace) {
      stderr.writeln('E1_ANDROID_EVIDENCE_FAILURE $error\n$stackTrace');
      try {
        await _report(
          'failure',
          patches,
          calculatePrice,
          false,
          error: '$error',
        );
      } on Object catch (reportError) {
        stderr.writeln('E1_ANDROID_EVIDENCE_REPORT_FAILURE $reportError');
      }
    }
  }

  Future<void> _runMultiFunction(
    E1PatchController patches,
    PhysicalAndroidPriceCalculator calculatePrice,
    PhysicalAndroidAsyncCalculator calculateAsyncPrice,
  ) async {
    switch (_stage) {
      case 0:
        await _assertAndReport(
          stageName: 'multi-base',
          patches: patches,
          calculatePrice: calculatePrice,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          expectedAsyncPrice: 540,
        );
        await _activateAndReport(
          'multi-function-patch',
          patches,
          calculatePrice,
          calculateAsyncPrice,
          expectedMode: E1PatchMode.patch,
          expectedPrice: 450,
          expectedAsyncPrice: 481,
          expectedUiPatched: true,
          patchName: 'multi-1.v1.patch',
        );
        _stage = 1;
        await _writeState(_stateFile, runId, _stage);
        await _report(
          'multi-restart-required-1',
          patches,
          calculatePrice,
          true,
        );
        return;
      case 1:
        await _assertAndReport(
          stageName: 'multi-persisted',
          patches: patches,
          calculatePrice: calculatePrice,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedMode: E1PatchMode.patch,
          expectedPrice: 450,
          expectedAsyncPrice: 481,
          expectedUiPatched: true,
        );
        final invalidAccepted = await _activatePatch(
          patches,
          'multi-invalid.v1.patch',
        );
        if (invalidAccepted ||
            patches.status.phase != 'rejected' ||
            calculatePrice(6, 1) != 450 ||
            await calculateAsyncPrice(6, 1) != 481 ||
            !_isUiPatched) {
          throw StateError(
            'invalid multi-function artifact did not retain active batch',
          );
        }
        await _report(
          'multi-invalid-rejected',
          patches,
          calculatePrice,
          true,
          asyncPrice: await calculateAsyncPrice(6, 1),
          uiPatched: _isUiPatched,
        );
        if (!await patches.rollback()) {
          throw StateError('multi-function rollback failed');
        }
        await _assertAndReport(
          stageName: 'multi-rolled-back',
          patches: patches,
          calculatePrice: calculatePrice,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          expectedAsyncPrice: 540,
        );
        _stage = 2;
        await _writeState(_stateFile, runId, _stage);
        await _report(
          'multi-restart-required-2',
          patches,
          calculatePrice,
          true,
        );
        return;
      case 2:
        await _assertAndReport(
          stageName: 'multi-rollback-persisted',
          patches: patches,
          calculatePrice: calculatePrice,
          calculateAsyncPrice: calculateAsyncPrice,
          expectedMode: E1PatchMode.base,
          expectedPrice: 540,
          expectedAsyncPrice: 540,
        );
        await _report('multi-complete', patches, calculatePrice, true);
        return;
    }
  }

  Future<void> _activateAndReport(
    String stageName,
    E1PatchController patches,
    PhysicalAndroidPriceCalculator calculatePrice,
    PhysicalAndroidAsyncCalculator calculateAsyncPrice, {
    required E1PatchMode expectedMode,
    required int expectedPrice,
    required int expectedAsyncPrice,
    bool expectedUiPatched = false,
    required String patchName,
  }) async {
    final activated = await _activatePatch(patches, patchName);
    if (!activated || !await patches.markHealthy()) {
      throw StateError(
        '$stageName activation failed: ${patches.status.detail}',
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    await _assertAndReport(
      stageName: stageName,
      patches: patches,
      calculatePrice: calculatePrice,
      calculateAsyncPrice: calculateAsyncPrice,
      expectedMode: expectedMode,
      expectedPrice: expectedPrice,
      expectedAsyncPrice: expectedAsyncPrice,
      expectedUiPatched: expectedUiPatched,
    );
  }

  Future<void> _assertAndReport({
    required String stageName,
    required E1PatchController patches,
    required PhysicalAndroidPriceCalculator calculatePrice,
    required PhysicalAndroidAsyncCalculator calculateAsyncPrice,
    required E1PatchMode expectedMode,
    required int expectedPrice,
    required int expectedAsyncPrice,
    bool expectedUiPatched = false,
  }) async {
    final actualPrice = calculatePrice(6, 1);
    final actualAsyncPrice = await calculateAsyncPrice(6, 1);
    final uiPatched =
        E0PatchRuntime.lookup(e1PricingCardBuildSlot)?.signature ==
        e0WidgetBuildSignature;
    if (patches.status.mode != expectedMode ||
        actualPrice != expectedPrice ||
        actualAsyncPrice != expectedAsyncPrice ||
        (stageName == 'ui-patch' && !uiPatched) ||
        (expectedUiPatched && !uiPatched)) {
      throw StateError(
        '$stageName mismatch: mode=${patches.status.mode.name} '
        'price=$actualPrice async=$actualAsyncPrice',
      );
    }
    await _report(
      stageName,
      patches,
      calculatePrice,
      true,
      asyncPrice: actualAsyncPrice,
      uiPatched: uiPatched,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  }

  bool get _isUiPatched =>
      E0PatchRuntime.lookup(e1PricingCardBuildSlot)?.signature ==
      e0WidgetBuildSignature;

  Future<void> _report(
    String stageName,
    E1PatchController patches,
    PhysicalAndroidPriceCalculator calculatePrice,
    bool succeeded, {
    int? asyncPrice,
    bool uiPatched = false,
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
    E1PatchController patches,
    String patchName,
  ) async {
    final directory = _usbPatchDirectory;
    if (directory != null) {
      final file = File('${directory.path}/$patchName');
      for (var attempt = 0; attempt < 240; attempt++) {
        if (await file.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!await file.exists()) {
        throw StateError('USB-staged patch is missing: ${file.path}');
      }
      return patches.activateBytes(await file.readAsBytes());
    }
    return patches.downloadAndActivate(uri: patchUri.resolve(patchName));
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
