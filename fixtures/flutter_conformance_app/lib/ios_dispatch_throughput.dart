import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

typedef IosDispatchPriceCalculator = int Function(int quantity, int tier);

const bool iosDispatchThroughputEnabled = bool.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT',
);

const int iosDispatchThroughputSchemaVersion = 1;
const int _protocolVersion = 1;
const int _callCount = 10000000;
const int _warmupCount = 2;
const int _sampleCount = 15;
const int _checksumMask = 0x7fffffff;
const String _benchmarkId = 'ios-dispatch-throughput';
const String _benchmarkDirectoryName = 'hyfens-e1-ios-dispatch-throughput';
const String _patchFileName = 'active-patch.v1.patch';
const String _readyFileName = 'ready.v1.json';
const String _reportFileName = 'report.v1.json';
const String _timerName = 'Stopwatch.monotonic';
const String _timerBoundary = 'repeated dispatch loop only';
const String _durationUnit = 'nanoseconds';
final int _stopwatchFrequency = Stopwatch().frequency;
const String _percentileDefinition =
    'nearest-rank p95; rank=ceil(0.95*n), one-indexed';

const String _runId = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_RUN_ID',
);
const String _deviceUdid = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_DEVICE_UDID',
);
const String _coreDeviceId = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_CORE_DEVICE_ID',
);
const String _developmentTeam = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_DEVELOPMENT_TEAM',
);
const String _buildConfiguration = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_BUILD_CONFIGURATION',
);
const String _buildTarget = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_BUILD_TARGET',
);
const String _transport = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_TRANSPORT',
);
const String _sourceSha256 = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_SOURCE_SHA256',
);
const String _patchSha256 = String.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_PATCH_SHA256',
);
const int _patchSequence = int.fromEnvironment(
  'E1_IOS_DISPATCH_THROUGHPUT_PATCH_SEQUENCE',
);

const _VariantDefinition _stockVariant = _VariantDefinition(
  id: 'stock_direct_callable',
  label: 'stock/direct callable',
  path: 'stock/direct callable',
  mode: 'stock/direct',
  callableKind: 'fixture-local uninstrumented callable',
  expectedResult: 540,
);
const _VariantDefinition _instrumentedUnpatchedVariant = _VariantDefinition(
  id: 'instrumented_unpatched',
  label: 'instrumented-unpatched',
  path:
      'transformed calculatePrice callable -> E0 lookup miss -> original body',
  mode: 'instrumented-unpatched',
  callableKind: 'transformed calculatePrice callable',
  expectedResult: 540,
);
const _VariantDefinition _activePatchVariant = _VariantDefinition(
  id: 'active_patch',
  label: 'active-patch',
  path: 'transformed calculatePrice callable -> E0 lookup hit -> E0PatchRuntime.invoke',
  mode: 'active-patch',
  callableKind: 'transformed calculatePrice callable',
  expectedResult: 450,
);
const List<_VariantDefinition> _variantDefinitions = <_VariantDefinition>[
  _stockVariant,
  _instrumentedUnpatchedVariant,
  _activePatchVariant,
];

const List<String> _skippedClaims = <String>[
  'simulator performance',
  'network or LAN delivery performance',
  'AWS or hosted deployment',
  'Android performance',
  'RSS or heap attribution',
  'thermal, battery, power, or soak behavior',
  'Flutter frame or first-frame performance',
  'production or App Store performance',
];

/// This control stays in this fixture-only library, which is not part of the
/// single-file release overlay used by the physical runner. It therefore
/// remains an ordinary direct callable while [calculatePrice] is transformed.
int iosDispatchStockDirect(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 80;
  if (quantity < 5) return quantity * 100;
  return quantity * 90;
}

/// Runs the opt-in physical-device dispatch protocol and writes its report to
/// the USB-readable app Documents directory. The caller supplies the
/// transformed release callable and the already-created public E1 controller;
/// no runtime or compiler hooks are introduced here.
Future<void> runIosDispatchThroughput({
  required Directory documentsDirectory,
  required E1PatchController patches,
  required IosDispatchPriceCalculator instrumentedCallable,
  required String appId,
  required String releaseId,
  required String buildFingerprint,
  required String functionId,
  required int functionSlot,
}) async {
  final directoryRunId = _runIdPattern.hasMatch(_runId)
      ? _runId
      : 'invalid-run-id';
  final reportDirectory = Directory(
    '${documentsDirectory.path}/$_benchmarkDirectoryName/$directoryRunId',
  );
  final reportFile = File('${reportDirectory.path}/$_reportFileName');
  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final results = <String, Map<String, Object?>>{};
  final patchEvidence = <String, Object?>{
    'format': 'Patch Format v1',
    'fileName': _patchFileName,
    'sha256': _patchSha256,
    'sequence': _patchSequence,
    'bytes': null,
    'activateBytesSucceeded': false,
    'markHealthySucceeded': false,
  };
  String? failure;

  try {
    _validateConfiguration(
      appId: appId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      functionId: functionId,
      functionSlot: functionSlot,
    );
    if (await reportDirectory.exists()) {
      throw StateError(
        'benchmark report directory already exists for run $_runId',
      );
    }
    await reportDirectory.create(recursive: true);
    await _writeReadyMarker(reportDirectory);

    await _prepareBase(patches, functionSlot);
    results[_stockVariant.id] = await _measureVariant(
      definition: _stockVariant,
      callable: iosDispatchStockDirect,
      patches: patches,
      functionSlot: functionSlot,
      requiresUnpatchedSlot: false,
      requiresActivePatch: false,
    );
    results[_instrumentedUnpatchedVariant.id] = await _measureVariant(
      definition: _instrumentedUnpatchedVariant,
      callable: instrumentedCallable,
      patches: patches,
      functionSlot: functionSlot,
      requiresUnpatchedSlot: true,
      requiresActivePatch: false,
    );

    final patchFile = File('${reportDirectory.path}/$_patchFileName');
    final patchBytes = await _waitForPatch(patchFile);
    patchEvidence['bytes'] = patchBytes.length;
    final activated = await patches.activateBytes(patchBytes);
    patchEvidence['activateBytesSucceeded'] = activated;
    if (!activated) {
      throw StateError(
        'Patch Format v1 activation failed: ${patches.status.detail}',
      );
    }
    final healthy = await patches.markHealthy();
    patchEvidence['markHealthySucceeded'] = healthy;
    if (!healthy) {
      throw StateError(
        'Patch Format v1 health confirmation failed: ${patches.status.detail}',
      );
    }
    _requireActivePatch(patches, functionSlot);
    results[_activePatchVariant.id] = await _measureVariant(
      definition: _activePatchVariant,
      callable: instrumentedCallable,
      patches: patches,
      functionSlot: functionSlot,
      requiresUnpatchedSlot: false,
      requiresActivePatch: true,
    );
  } on Object catch (error) {
    failure = _boundedError(error);
  }

  final missingReason = failure ?? 'variant was not reached';
  for (final definition in _variantDefinitions) {
    results.putIfAbsent(
      definition.id,
      () => _notMeasuredVariant(definition, missingReason),
    );
  }
  final orderedResults = <Map<String, Object?>>[
    for (final definition in _variantDefinitions) results[definition.id]!,
  ];
  final allMeasured = orderedResults.every(
    (result) => result['status'] == 'MEASURED',
  );
  final report = <String, Object?>{
    'schemaVersion': iosDispatchThroughputSchemaVersion,
    'benchmarkId': _benchmarkId,
    'protocolVersion': _protocolVersion,
    'status': allMeasured ? 'MEASURED' : 'NOT_MEASURED',
    'failure': allMeasured ? null : failure ?? 'one or more variants failed',
    'startedAtUtc': startedAtUtc,
    'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'identity': <String, Object?>{
      'runId': _runId,
      'appId': appId,
      'releaseId': releaseId,
      'buildFingerprint': buildFingerprint,
      'buildConfiguration': _buildConfiguration,
      'buildTarget': _buildTarget,
      'transport': _transport,
      'deviceUdid': _deviceUdid,
      'coreDeviceId': _coreDeviceId,
      'developmentTeam': _developmentTeam,
      'sourceSha256': _sourceSha256,
      'patchSha256': _patchSha256,
      'patchSequence': _patchSequence,
      'patchFileName': _patchFileName,
      'reportRelativePath':
          '$_benchmarkDirectoryName/$directoryRunId/$_reportFileName',
    },
    'protocol': <String, Object?>{
      'callCount': _callCount,
      'warmups': _warmupCount,
      'timedSamples': _sampleCount,
      'timer': _timerName,
      'timerBoundary': _timerBoundary,
      'timerFrequency': _stopwatchFrequency,
      'durationUnit': _durationUnit,
      'percentile': _percentileDefinition,
      'checksum': 'sum of every returned int modulo 2^31',
    },
    'workload': <String, Object?>{
      'functionId': functionId,
      'functionSlot': functionSlot,
      'input': <String, int>{'quantity': 6, 'tier': 1},
      'expectedResults': <String, int>{
        _stockVariant.id: _stockVariant.expectedResult,
        _instrumentedUnpatchedVariant.id:
            _instrumentedUnpatchedVariant.expectedResult,
        _activePatchVariant.id: _activePatchVariant.expectedResult,
      },
    },
    'patch': patchEvidence,
    'controller': _controllerEvidence(patches),
    'claimBoundary': <String, Object?>{
      'scope': 'one named physical iOS device over USB',
      'skipped': _skippedClaims,
    },
    'variants': orderedResults,
  };

  try {
    await _writeReport(reportFile, report);
    // ignore: avoid_print
    print('E1_IOS_DISPATCH_THROUGHPUT_REPORT ${reportFile.path}');
  } on Object catch (error) {
    stderr.writeln(
      'E1_IOS_DISPATCH_THROUGHPUT_REPORT_FAILURE ${_boundedError(error)}',
    );
  }
}

Future<void> _prepareBase(E1PatchController patches, int functionSlot) async {
  if (!await patches.rollback()) {
    throw StateError('base reset failed: ${patches.status.detail}');
  }
  if (patches.status.mode != E1PatchMode.base ||
      E0PatchRuntime.lookup(functionSlot) != null) {
    throw StateError(
      'instrumented-unpatched path cannot be demonstrated: '
      'mode=${patches.status.mode.name} slotPresent=${E0PatchRuntime.lookup(functionSlot) != null}',
    );
  }
}

void _requireActivePatch(E1PatchController patches, int functionSlot) {
  final program = E0PatchRuntime.lookup(functionSlot);
  if (patches.status.mode != E1PatchMode.patch ||
      patches.status.phase != 'healthy' ||
      program == null) {
    throw StateError(
      'active-patch path cannot be demonstrated: '
      'phase=${patches.status.phase} mode=${patches.status.mode.name} '
      'slotPresent=${program != null}',
    );
  }
}

Future<List<int>> _waitForPatch(File patchFile) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    if (await patchFile.exists()) {
      final bytes = await patchFile.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
      throw StateError('staged Patch Format v1 artifact is empty');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('staged Patch Format v1 artifact is missing');
}

Future<void> _writeReadyMarker(Directory reportDirectory) async {
  final marker = File('${reportDirectory.path}/$_readyFileName');
  await marker.writeAsString(
    '${jsonEncode(<String, Object?>{'schemaVersion': iosDispatchThroughputSchemaVersion, 'benchmarkId': _benchmarkId, 'runId': _runId, 'patchFileName': _patchFileName, 'reportFileName': _reportFileName})}\n',
    flush: true,
  );
}

Future<Map<String, Object?>> _measureVariant({
  required _VariantDefinition definition,
  required IosDispatchPriceCalculator callable,
  required E1PatchController patches,
  required int functionSlot,
  required bool requiresUnpatchedSlot,
  required bool requiresActivePatch,
}) async {
  final warmupChecksums = <int>[];
  final samples = <Map<String, Object?>>[];
  try {
    if (requiresUnpatchedSlot) {
      if (patches.status.mode != E1PatchMode.base ||
          E0PatchRuntime.lookup(functionSlot) != null) {
        throw StateError('unpatched runtime proof failed before warmups');
      }
    }
    if (requiresActivePatch) _requireActivePatch(patches, functionSlot);
    final expectedChecksum = _expectedChecksum(definition.expectedResult);
    for (var warmup = 0; warmup < _warmupCount; warmup++) {
      final checksum = _runLoop(callable, definition.expectedResult);
      if (checksum != expectedChecksum) {
        throw StateError(
          '${definition.id} warmup checksum mismatch: '
          'got=$checksum expected=$expectedChecksum',
        );
      }
      warmupChecksums.add(checksum);
    }
    for (var sampleIndex = 1; sampleIndex <= _sampleCount; sampleIndex++) {
      final watch = Stopwatch()..start();
      final checksum = _runLoop(callable, definition.expectedResult);
      watch.stop();
      if (checksum != expectedChecksum) {
        throw StateError(
          '${definition.id} sample checksum mismatch: '
          'got=$checksum expected=$expectedChecksum',
        );
      }
      final elapsedTicks = watch.elapsedTicks;
      samples.add(<String, Object?>{
        'sampleIndex': sampleIndex,
        'callCount': _callCount,
        'elapsedTicks': elapsedTicks,
        'elapsedNanoseconds': _ticksToNanoseconds(elapsedTicks),
        'checksum': checksum,
        'expectedChecksum': expectedChecksum,
        'result': definition.expectedResult,
        'expectedResult': definition.expectedResult,
      });
    }
    if (requiresUnpatchedSlot && E0PatchRuntime.lookup(functionSlot) != null) {
      throw StateError('unpatched runtime proof failed after samples');
    }
    if (requiresActivePatch) _requireActivePatch(patches, functionSlot);
    return <String, Object?>{
      ..._variantMetadata(definition),
      'status': 'MEASURED',
      'failure': null,
      'demonstration': _demonstration(
        definition,
        patches,
        functionSlot,
        patchActive: requiresActivePatch,
      ),
      'warmups': <String, Object?>{
        'requested': _warmupCount,
        'completed': warmupChecksums.length,
        'timed': false,
        'checksums': warmupChecksums,
      },
      'samples': samples,
      'statistics': _statistics(samples),
    };
  } on Object catch (error) {
    return <String, Object?>{
      ..._variantMetadata(definition),
      'status': 'NOT_MEASURED',
      'failure': _boundedError(error),
      'demonstration': _demonstration(
        definition,
        patches,
        functionSlot,
        patchActive: requiresActivePatch,
      ),
      'warmups': <String, Object?>{
        'requested': _warmupCount,
        'completed': warmupChecksums.length,
        'timed': false,
        'checksums': warmupChecksums,
      },
      'samples': samples,
      'statistics': null,
    };
  }
}

Map<String, Object?> _variantMetadata(_VariantDefinition definition) =>
    <String, Object?>{
      'id': definition.id,
      'label': definition.label,
      'path': definition.path,
      'mode': definition.mode,
      'expectedResult': definition.expectedResult,
    };

Map<String, Object?> _notMeasuredVariant(
  _VariantDefinition definition,
  String reason,
) => <String, Object?>{
  ..._variantMetadata(definition),
  'status': 'NOT_MEASURED',
  'failure': reason,
  'demonstration': <String, Object?>{
    'callableKind': definition.callableKind,
    'controllerMode': null,
    'lookupBefore': null,
    'lookupAfter': null,
    'runtimeLookup': 'not-demonstrated',
    'patchActivationSucceeded': false,
    'healthConfirmationSucceeded': false,
    'patchFormat': null,
  },
  'warmups': <String, Object?>{
    'requested': _warmupCount,
    'completed': 0,
    'timed': false,
    'checksums': <int>[],
  },
  'samples': <Map<String, Object?>>[],
  'statistics': null,
};

Map<String, Object?> _demonstration(
  _VariantDefinition definition,
  E1PatchController patches,
  int functionSlot, {
  required bool patchActive,
}) {
  final lookup = E0PatchRuntime.lookup(functionSlot);
  final isStock = definition.id == _stockVariant.id;
  return <String, Object?>{
    'callableKind': definition.callableKind,
    'controllerMode': patches.status.mode.name,
    'lookupBefore': isStock ? null : !patchActive,
    'lookupAfter': isStock ? null : lookup != null,
    'runtimeLookup': isStock
        ? 'not-applicable'
        : lookup == null
        ? 'miss'
        : 'hit',
    'patchActivationSucceeded': patchActive,
    'healthConfirmationSucceeded': patchActive,
    'patchFormat': patchActive ? 'Patch Format v1' : null,
  };
}

Map<String, Object?> _statistics(List<Map<String, Object?>> samples) {
  final elapsed = <int>[
    for (final sample in samples) sample['elapsedNanoseconds']! as int,
  ]..sort();
  final p95Rank = (elapsed.length * 95 + 99) ~/ 100;
  return <String, Object?>{
    'count': elapsed.length,
    'medianNanoseconds': elapsed[elapsed.length ~/ 2],
    'p95Nanoseconds': elapsed[p95Rank - 1],
    'p95Rank': p95Rank,
    'minimumNanoseconds': elapsed.first,
    'maximumNanoseconds': elapsed.last,
    'outliersDiscarded': 0,
  };
}

Map<String, Object?> _controllerEvidence(E1PatchController patches) =>
    <String, Object?>{
      'status': patches.status.toJson(),
      'lifecycleState': patches.lifecycleState.name,
      'highWaterSequence': patches.durableState.highWaterSequence,
      'recoveryNeeded': patches.recoveryNeeded,
    };

int _runLoop(IosDispatchPriceCalculator callable, int expectedResult) {
  var checksum = 0;
  for (var index = 0; index < _callCount; index++) {
    final result = callable(6, 1);
    if (result != expectedResult) {
      throw StateError(
        'dispatch result mismatch: got=$result expected=$expectedResult',
      );
    }
    checksum = (checksum + result) & _checksumMask;
  }
  return checksum;
}

int _expectedChecksum(int expectedResult) =>
    (expectedResult * _callCount) & _checksumMask;

int _ticksToNanoseconds(int ticks) {
  final wholeSeconds = ticks ~/ _stopwatchFrequency;
  final remainder = ticks % _stopwatchFrequency;
  return wholeSeconds * 1000000000 +
      (remainder * 1000000000) ~/ _stopwatchFrequency;
}

void _validateConfiguration({
  required String appId,
  required String releaseId,
  required String buildFingerprint,
  required String functionId,
  required int functionSlot,
}) {
  if (!_runIdPattern.hasMatch(_runId) ||
      appId.isEmpty ||
      releaseId.isEmpty ||
      buildFingerprint.isEmpty ||
      !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(functionId) ||
      functionSlot < 0 ||
      !_sha256Pattern.hasMatch(_sourceSha256) ||
      !_sha256Pattern.hasMatch(_patchSha256) ||
      _patchSequence <= 0 ||
      _buildConfiguration != 'Release' ||
      _buildTarget != 'device' ||
      _transport != 'usb' ||
      !_deviceIdPattern.hasMatch(_deviceUdid) ||
      !_deviceIdPattern.hasMatch(_coreDeviceId) ||
      !_teamPattern.hasMatch(_developmentTeam)) {
    throw const FormatException(
      'throughput benchmark requires explicit Release/USB identity defines',
    );
  }
}

Future<void> _writeReport(File reportFile, Map<String, Object?> report) async {
  final temporary = File('${reportFile.path}.tmp');
  await temporary.writeAsString('${jsonEncode(report)}\n', flush: true);
  await temporary.rename(reportFile.path);
}

String _boundedError(Object error) {
  final message = error.toString();
  return message.length <= 400 ? message : '${message.substring(0, 397)}...';
}

final RegExp _runIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,80}$');
final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _deviceIdPattern = RegExp(r'^[A-Fa-f0-9-]{20,64}$');
final RegExp _teamPattern = RegExp(r'^[A-Z0-9]{10}$');

final class _VariantDefinition {
  const _VariantDefinition({
    required this.id,
    required this.label,
    required this.path,
    required this.mode,
    required this.callableKind,
    required this.expectedResult,
  });

  final String id;
  final String label;
  final String path;
  final String mode;
  final String callableKind;
  final int expectedResult;
}
