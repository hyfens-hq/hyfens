import 'dart:convert';
import 'dart:io';

const int _schemaVersion = 1;
const String _benchmarkId = 'ios-dispatch-throughput';
const int _protocolVersion = 1;
const int _callCount = 10000000;
const int _warmups = 2;
const int _timedSamples = 15;
const String _durationUnit = 'nanoseconds';
const String _percentile = 'nearest-rank p95; rank=ceil(0.95*n), one-indexed';
const String _checksumDefinition = 'sum of every returned int modulo 2^31';
const int _checksumMask = 0x7fffffff;

const List<_VariantExpectation> _variants = <_VariantExpectation>[
  _VariantExpectation(
    id: 'stock_direct_callable',
    label: 'stock/direct callable',
    path: 'stock/direct callable',
    mode: 'stock/direct',
    callableKind: 'fixture-local uninstrumented callable',
    runtimeLookup: 'not-applicable',
    expectedResult: 540,
  ),
  _VariantExpectation(
    id: 'instrumented_unpatched',
    label: 'instrumented-unpatched',
    path: 'transformed calculatePrice callable -> E0 lookup miss -> original body',
    mode: 'instrumented-unpatched',
    callableKind: 'transformed calculatePrice callable',
    runtimeLookup: 'miss',
    expectedResult: 540,
  ),
  _VariantExpectation(
    id: 'active_patch',
    label: 'active-patch',
    path: 'transformed calculatePrice callable -> E0 lookup hit -> E0PatchRuntime.invoke',
    mode: 'active-patch',
    callableKind: 'transformed calculatePrice callable',
    runtimeLookup: 'hit',
    expectedResult: 450,
  ),
];

const String _usage =
    '''Usage: dart run benchmarks/ios_dispatch_throughput_reducer.dart [options]

Offline reducer and validator for a coordinator-captured iOS dispatch report.
It never builds, installs, launches, or changes a device.

  --input=PATH   Read and validate a raw report JSON file.
  --output=PATH  Write the reduced report JSON to PATH; otherwise stdout.
  --self-check   Run deterministic valid and invalid report checks.
  --help         Show this usage text.
''';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    if (options.selfCheck) {
      _runSelfCheck();
      stdout.writeln('ios_dispatch_throughput_reducer self-check: PASS');
      return;
    }
    if (options.inputPath == null) {
      throw const FormatException(
        'Provide --input=PATH, --self-check, or --help',
      );
    }
    final decoded = jsonDecode(await File(options.inputPath!).readAsString());
    final reduced = _reduce(_asMap(decoded, r'$'));
    final encoded = const JsonEncoder.withIndent('  ').convert(reduced);
    if (options.outputPath == null) {
      stdout.writeln(encoded);
    } else {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString('$encoded\n');
      stdout.writeln('Wrote ${output.absolute.path}');
    }
  } on FormatException catch (error) {
    stderr.writeln('iOS dispatch report rejected: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('iOS dispatch report I/O failed: $error');
    exitCode = 74;
  }
}

final class _Options {
  const _Options({
    required this.help,
    required this.selfCheck,
    required this.inputPath,
    required this.outputPath,
  });

  final bool help;
  final bool selfCheck;
  final String? inputPath;
  final String? outputPath;

  factory _Options.parse(List<String> arguments) {
    var help = false;
    var selfCheck = false;
    String? inputPath;
    String? outputPath;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--self-check') {
        selfCheck = true;
      } else if (argument.startsWith('--input=')) {
        inputPath = _optionValue(argument, '--input=');
      } else if (argument.startsWith('--output=')) {
        outputPath = _optionValue(argument, '--output=');
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    final modes = <bool>[selfCheck, inputPath != null].where((x) => x).length;
    if (modes > 1) {
      throw const FormatException('Choose only one of --self-check or --input');
    }
    if (selfCheck && outputPath != null) {
      throw const FormatException(
        '--self-check cannot be combined with --output',
      );
    }
    if (help && (modes != 0 || outputPath != null)) {
      throw const FormatException(
        '--help cannot be combined with another option',
      );
    }
    return _Options(
      help: help,
      selfCheck: selfCheck,
      inputPath: inputPath,
      outputPath: outputPath,
    );
  }
}

String _optionValue(String argument, String prefix) {
  final value = argument.substring(prefix.length);
  if (value.isEmpty) throw FormatException('$prefix requires a value');
  return value;
}

Map<String, Object?> _reduce(Map<String, Object?> report) {
  _validateReport(report);
  final identity = _requiredMap(report, 'identity', r'$');
  final protocol = _requiredMap(report, 'protocol', r'$');
  final variants = _requiredList(report, 'variants', r'$');
  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'benchmarkId': _benchmarkId,
    'status': _requiredString(report, 'status', r'$'),
    'identity': <String, Object?>{
      'runId': _requiredString(identity, 'runId', r'$.identity'),
      'appId': _requiredString(identity, 'appId', r'$.identity'),
      'releaseId': _requiredString(identity, 'releaseId', r'$.identity'),
      'buildFingerprint': _requiredString(
        identity,
        'buildFingerprint',
        r'$.identity',
      ),
      'buildConfiguration': _requiredString(
        identity,
        'buildConfiguration',
        r'$.identity',
      ),
      'buildTarget': _requiredString(identity, 'buildTarget', r'$.identity'),
      'transport': _requiredString(identity, 'transport', r'$.identity'),
      'deviceUdid': _requiredString(identity, 'deviceUdid', r'$.identity'),
      'coreDeviceId': _requiredString(identity, 'coreDeviceId', r'$.identity'),
      'developmentTeam': _requiredString(
        identity,
        'developmentTeam',
        r'$.identity',
      ),
      'sourceSha256': _requiredString(identity, 'sourceSha256', r'$.identity'),
      'patchSha256': _requiredString(identity, 'patchSha256', r'$.identity'),
      'patchSequence': _requiredInt(identity, 'patchSequence', r'$.identity'),
      'reportRelativePath': _requiredString(
        identity,
        'reportRelativePath',
        r'$.identity',
      ),
    },
    'protocol': <String, Object?>{
      'callCount': _requiredInt(protocol, 'callCount', r'$.protocol'),
      'warmups': _requiredInt(protocol, 'warmups', r'$.protocol'),
      'timedSamples': _requiredInt(protocol, 'timedSamples', r'$.protocol'),
      'durationUnit': _requiredString(protocol, 'durationUnit', r'$.protocol'),
      'percentile': _requiredString(protocol, 'percentile', r'$.protocol'),
    },
    'variants': [
      for (var index = 0; index < variants.length; index++)
        _reducedVariant(_asMap(variants[index], r'$.variants[$index]')),
    ],
    'validation': <String, Object?>{
      'accepted': true,
      'checkedVariants': _variants.length,
      'checkedTimedSamples': _timedSamples,
      'checkedWarmups': _warmups,
    },
  };
}

Map<String, Object?> _reducedVariant(Map<String, Object?> variant) {
  final stats = variant['statistics'];
  return <String, Object?>{
    'id': _requiredString(variant, 'id', r'$.variants[]'),
    'label': _requiredString(variant, 'label', r'$.variants[]'),
    'status': _requiredString(variant, 'status', r'$.variants[]'),
    'expectedResult': _requiredInt(variant, 'expectedResult', r'$.variants[]'),
    'warmups': _requiredMap(variant, 'warmups', r'$.variants[]')['completed'],
    'sampleCount': _requiredList(variant, 'samples', r'$.variants[]').length,
    if (stats is Map) 'statistics': stats,
  };
}

void _validateReport(Map<String, Object?> report) {
  _expectInt(report, 'schemaVersion', _schemaVersion, r'$');
  _expectString(report, 'benchmarkId', _benchmarkId, r'$');
  _expectInt(report, 'protocolVersion', _protocolVersion, r'$');
  final status = _requiredString(report, 'status', r'$');
  if (status != 'MEASURED' && status != 'NOT_MEASURED') {
    throw FormatException('\$.status must be MEASURED or NOT_MEASURED');
  }
  final identity = _requiredMap(report, 'identity', r'$');
  _validateIdentity(identity);
  final protocol = _requiredMap(report, 'protocol', r'$');
  _validateProtocol(protocol);
  final timerFrequency = _requiredInt(
    protocol,
    'timerFrequency',
    r'$.protocol',
  );
  final workload = _requiredMap(report, 'workload', r'$');
  _validateWorkload(workload);
  final patch = _requiredMap(report, 'patch', r'$');
  _validatePatch(patch, identity, status);
  _validateController(_requiredMap(report, 'controller', r'$'));
  _validateClaimBoundary(_requiredMap(report, 'claimBoundary', r'$'));

  final rawVariants = _requiredList(report, 'variants', r'$');
  if (rawVariants.length != _variants.length) {
    throw FormatException(
      '\$.variants must contain exactly ${_variants.length} entries',
    );
  }
  var measuredCount = 0;
  for (var index = 0; index < _variants.length; index++) {
    final variant = _asMap(rawVariants[index], r'$.variants[$index]');
    _validateVariant(
      variant,
      _variants[index],
      index,
      timerFrequency: timerFrequency,
    );
    if (variant['status'] == 'MEASURED') measuredCount++;
  }
  if ((status == 'MEASURED' && measuredCount != _variants.length) ||
      (status == 'NOT_MEASURED' && measuredCount == _variants.length)) {
    throw const FormatException('root status does not match variant statuses');
  }
  final failure = report['failure'];
  if (status == 'MEASURED' && failure != null) {
    throw const FormatException('\$.failure must be null for MEASURED reports');
  }
  if (status == 'NOT_MEASURED' &&
      (failure is! String || failure.trim().isEmpty)) {
    throw const FormatException(
      '\$.failure must contain text for NOT_MEASURED reports',
    );
  }
}

void _validateIdentity(Map<String, Object?> identity) {
  final nonEmpty = <String>[
    'runId',
    'appId',
    'releaseId',
    'buildFingerprint',
    'buildConfiguration',
    'buildTarget',
    'transport',
    'deviceUdid',
    'coreDeviceId',
    'developmentTeam',
    'sourceSha256',
    'patchSha256',
    'reportRelativePath',
  ];
  for (final key in nonEmpty) {
    if (_requiredString(identity, key, r'$.identity').trim().isEmpty) {
      throw FormatException('\$.identity.$key must not be empty');
    }
  }
  _expectString(identity, 'appId', 'dev.hyfens.conformance', r'$.identity');
  _expectString(identity, 'releaseId', 'android-e1-release-1', r'$.identity');
  _expectString(
    identity,
    'buildFingerprint',
    'conformance-build-1',
    r'$.identity',
  );
  _expectString(identity, 'buildConfiguration', 'Release', r'$.identity');
  _expectString(identity, 'buildTarget', 'device', r'$.identity');
  _expectString(identity, 'transport', 'usb', r'$.identity');
  final runId = _requiredString(identity, 'runId', r'$.identity');
  if (!RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(runId)) {
    throw const FormatException('\$.identity.runId has invalid characters');
  }
  _expectString(
    identity,
    'reportRelativePath',
    'hyfens-e1-ios-dispatch-throughput/$runId/report.v1.json',
    r'$.identity',
  );
  for (final key in const ['sourceSha256', 'patchSha256']) {
    final digest = _requiredString(identity, key, r'$.identity');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw FormatException(
        '\$.identity.$key must be a lowercase SHA-256 digest',
      );
    }
  }
  final patchSequence = _requiredInt(identity, 'patchSequence', r'$.identity');
  if (patchSequence <= 0) {
    throw const FormatException('\$.identity.patchSequence must be positive');
  }
  final deviceUdid = _requiredString(identity, 'deviceUdid', r'$.identity');
  final coreDeviceId = _requiredString(identity, 'coreDeviceId', r'$.identity');
  if (!RegExp(r'^[A-Fa-f0-9-]{20,64}$').hasMatch(deviceUdid) ||
      !RegExp(r'^[A-Fa-f0-9-]{20,64}$').hasMatch(coreDeviceId)) {
    throw const FormatException('\$.identity device identifiers are invalid');
  }
  if (!RegExp(r'^[A-Z0-9]{10}$')
      .hasMatch(_requiredString(identity, 'developmentTeam', r'$.identity'))) {
    throw const FormatException('\$.identity.developmentTeam is invalid');
  }
}

void _validateProtocol(Map<String, Object?> protocol) {
  _expectInt(protocol, 'callCount', _callCount, r'$.protocol');
  _expectInt(protocol, 'warmups', _warmups, r'$.protocol');
  _expectInt(protocol, 'timedSamples', _timedSamples, r'$.protocol');
  _expectString(protocol, 'durationUnit', _durationUnit, r'$.protocol');
  _expectString(protocol, 'percentile', _percentile, r'$.protocol');
  _expectString(protocol, 'timer', 'Stopwatch.monotonic', r'$.protocol');
  _expectString(
    protocol,
    'timerBoundary',
    'repeated dispatch loop only',
    r'$.protocol',
  );
  final frequency = _requiredInt(protocol, 'timerFrequency', r'$.protocol');
  if (frequency <= 0)
    throw const FormatException('\$.protocol.timerFrequency must be positive');
  _expectString(protocol, 'checksum', _checksumDefinition, r'$.protocol');
}

void _validateWorkload(Map<String, Object?> workload) {
  final functionId = _requiredString(workload, 'functionId', r'$.workload');
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(functionId)) {
    throw const FormatException('\$.workload.functionId is invalid');
  }
  if (_requiredInt(workload, 'functionSlot', r'$.workload') < 0) {
    throw const FormatException('\$.workload.functionSlot must be nonnegative');
  }
  final input = _requiredMap(workload, 'input', r'$.workload');
  _expectInt(input, 'quantity', 6, r'$.workload.input');
  _expectInt(input, 'tier', 1, r'$.workload.input');
  final expected = _requiredMap(workload, 'expectedResults', r'$.workload');
  for (final variant in _variants) {
    _expectInt(
      expected,
      variant.id,
      variant.expectedResult,
      r'$.workload.expectedResults',
    );
  }
}

void _validatePatch(
  Map<String, Object?> patch,
  Map<String, Object?> identity,
  String reportStatus,
) {
  _expectString(patch, 'format', 'Patch Format v1', r'$.patch');
  _expectString(patch, 'fileName', 'active-patch.v1.patch', r'$.patch');
  _expectString(
    patch,
    'sha256',
    _requiredString(identity, 'patchSha256', r'$.identity'),
    r'$.patch',
  );
  _expectInt(
    patch,
    'sequence',
    _requiredInt(identity, 'patchSequence', r'$.identity'),
    r'$.patch',
  );
  final bytes = patch['bytes'];
  if (bytes != null && (bytes is! int || bytes <= 0)) {
    throw const FormatException(
      '\$.patch.bytes must be null or a positive integer',
    );
  }
  _requiredBool(patch, 'activateBytesSucceeded', r'$.patch');
  _requiredBool(patch, 'markHealthySucceeded', r'$.patch');
  if (reportStatus == 'MEASURED') {
    if (bytes is! int || bytes <= 0) {
      throw const FormatException(
        '\$.patch.bytes must be positive for MEASURED reports',
      );
    }
    _expectBool(patch, 'activateBytesSucceeded', true, r'$.patch');
    _expectBool(patch, 'markHealthySucceeded', true, r'$.patch');
  }
}

void _validateController(Map<String, Object?> controller) {
  _requiredMap(controller, 'status', r'$.controller');
  _requiredString(controller, 'lifecycleState', r'$.controller');
  _requiredInt(controller, 'highWaterSequence', r'$.controller');
  _requiredBool(controller, 'recoveryNeeded', r'$.controller');
}

void _validateClaimBoundary(Map<String, Object?> boundary) {
  _expectString(
    boundary,
    'scope',
    'one named physical iOS device over USB',
    r'$.claimBoundary',
  );
  final skipped = _requiredList(boundary, 'skipped', r'$.claimBoundary');
  if (skipped.isEmpty || skipped.any((item) => item is! String)) {
    throw const FormatException('\$.claimBoundary.skipped must contain text');
  }
}

void _validateVariant(
  Map<String, Object?> variant,
  _VariantExpectation expectation,
  int index, {
  required int timerFrequency,
}) {
  final path = r'$.variants[' + index.toString() + ']';
  _expectString(variant, 'id', expectation.id, path);
  _expectString(variant, 'label', expectation.label, path);
  _expectString(variant, 'path', expectation.path, path);
  _expectString(variant, 'mode', expectation.mode, path);
  _expectInt(variant, 'expectedResult', expectation.expectedResult, path);
  final status = _requiredString(variant, 'status', path);
  if (status != 'MEASURED' && status != 'NOT_MEASURED') {
    throw FormatException('$path.status is invalid');
  }
  final failure = variant['failure'];
  final warmups = _requiredMap(variant, 'warmups', path);
  _expectInt(warmups, 'requested', _warmups, '$path.warmups');
  _expectBool(warmups, 'timed', false, '$path.warmups');
  final warmupChecksums = _requiredList(warmups, 'checksums', '$path.warmups');
  final samples = _requiredList(variant, 'samples', path);
  final statistics = variant['statistics'];
  final demonstration = _requiredMap(variant, 'demonstration', path);
  if (status == 'NOT_MEASURED') {
    if (failure is! String || failure.trim().isEmpty) {
      throw FormatException('$path.failure must contain text');
    }
    _expectInt(warmups, 'completed', 0, '$path.warmups');
    if (warmupChecksums.isNotEmpty ||
        samples.isNotEmpty ||
        statistics != null) {
      throw FormatException('$path NOT_MEASURED must have no measurements');
    }
    return;
  }
  if (failure != null) throw FormatException('$path.failure must be null');
  _expectString(
    demonstration,
    'callableKind',
    expectation.callableKind,
    '$path.demonstration',
  );
  final active = expectation.id == 'active_patch';
  final stock = expectation.id == 'stock_direct_callable';
  _expectString(
    demonstration,
    'controllerMode',
    active ? 'patch' : 'base',
    '$path.demonstration',
  );
  _expectNullableBool(
    demonstration,
    'lookupBefore',
    stock ? null : !active,
    '$path.demonstration',
  );
  _expectNullableBool(
    demonstration,
    'lookupAfter',
    stock ? null : active,
    '$path.demonstration',
  );
  _expectString(
    demonstration,
    'runtimeLookup',
    expectation.runtimeLookup,
    '$path.demonstration',
  );
  _expectBool(
    demonstration,
    'patchActivationSucceeded',
    active,
    '$path.demonstration',
  );
  _expectBool(
    demonstration,
    'healthConfirmationSucceeded',
    active,
    '$path.demonstration',
  );
  _expectNullableString(
    demonstration,
    'patchFormat',
    active ? 'Patch Format v1' : null,
    '$path.demonstration',
  );
  _expectInt(warmups, 'completed', _warmups, '$path.warmups');
  if (warmupChecksums.length != _warmups) {
    throw FormatException(
      '$path.warmups.checksums must contain $_warmups entries',
    );
  }
  final expectedChecksum = _expectedChecksum(expectation.expectedResult);
  for (
    var warmupIndex = 0;
    warmupIndex < warmupChecksums.length;
    warmupIndex++
  ) {
    _expectValueInt(
      warmupChecksums[warmupIndex],
      expectedChecksum,
      '$path.warmups.checksums[$warmupIndex]',
    );
  }
  if (samples.length != _timedSamples) {
    throw FormatException('$path.samples must contain $_timedSamples entries');
  }
  final elapsed = <int>[];
  for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
    elapsed.add(
      _validateSample(
        _asMap(samples[sampleIndex], '$path.samples[$sampleIndex]'),
        expectation,
        sampleIndex,
        expectedChecksum,
        timerFrequency,
        path,
      ),
    );
  }
  if (statistics is! Map) {
    throw FormatException('$path.statistics must be an object for MEASURED');
  }
  _validateStatistics(_asMap(statistics, '$path.statistics'), elapsed, path);
}

int _validateSample(
  Map<String, Object?> sample,
  _VariantExpectation expectation,
  int zeroBasedIndex,
  int expectedChecksum,
  int timerFrequency,
  String variantPath,
) {
  final path = '$variantPath.samples[$zeroBasedIndex]';
  _expectInt(sample, 'sampleIndex', zeroBasedIndex + 1, path);
  _expectInt(sample, 'callCount', _callCount, path);
  final elapsedTicks = _requiredInt(sample, 'elapsedTicks', path);
  final elapsedNanoseconds = _requiredInt(sample, 'elapsedNanoseconds', path);
  if (elapsedTicks < 0 || elapsedNanoseconds < 0) {
    throw FormatException('$path elapsed durations must be nonnegative');
  }
  if (_ticksToNanoseconds(elapsedTicks, timerFrequency) != elapsedNanoseconds) {
    throw FormatException(
      '$path elapsedNanoseconds does not match elapsedTicks',
    );
  }
  _expectInt(sample, 'checksum', expectedChecksum, path);
  _expectInt(sample, 'expectedChecksum', expectedChecksum, path);
  _expectInt(sample, 'result', expectation.expectedResult, path);
  _expectInt(sample, 'expectedResult', expectation.expectedResult, path);
  return elapsedNanoseconds;
}

int _ticksToNanoseconds(int ticks, int frequency) {
  final wholeSeconds = ticks ~/ frequency;
  final remainder = ticks % frequency;
  return wholeSeconds * 1000000000 + (remainder * 1000000000) ~/ frequency;
}

void _validateStatistics(
  Map<String, Object?> statistics,
  List<int> elapsed,
  String path,
) {
  final sorted = List<int>.from(elapsed)..sort();
  final p95Rank = (sorted.length * 95 + 99) ~/ 100;
  _expectInt(statistics, 'count', elapsed.length, '$path.statistics');
  _expectInt(
    statistics,
    'medianNanoseconds',
    sorted[sorted.length ~/ 2],
    '$path.statistics',
  );
  _expectInt(
    statistics,
    'p95Nanoseconds',
    sorted[p95Rank - 1],
    '$path.statistics',
  );
  _expectInt(statistics, 'p95Rank', p95Rank, '$path.statistics');
  _expectInt(
    statistics,
    'minimumNanoseconds',
    sorted.first,
    '$path.statistics',
  );
  _expectInt(statistics, 'maximumNanoseconds', sorted.last, '$path.statistics');
  _expectInt(statistics, 'outliersDiscarded', 0, '$path.statistics');
}

int _expectedChecksum(int expectedResult) =>
    (expectedResult * _callCount) & _checksumMask;

Map<String, Object?> _asMap(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path has a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _requiredMap(
  Map<String, Object?> map,
  String key,
  String path,
) => _asMap(_required(map, key, path), '$path.$key');

List<Object?> _requiredList(Map<String, Object?> map, String key, String path) {
  final value = _required(map, key, path);
  if (value is! List) {
    throw FormatException('$path.$key must be an array');
  }
  return List<Object?>.from(value);
}

String _requiredString(Map<String, Object?> map, String key, String path) {
  final value = _required(map, key, path);
  if (value is! String) throw FormatException('$path.$key must be a string');
  return value;
}

int _requiredInt(Map<String, Object?> map, String key, String path) {
  final value = _required(map, key, path);
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

bool _requiredBool(Map<String, Object?> map, String key, String path) {
  final value = _required(map, key, path);
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

Object? _required(Map<String, Object?> map, String key, String path) {
  if (!map.containsKey(key)) throw FormatException('$path.$key is required');
  return map[key];
}

void _expectString(
  Map<String, Object?> map,
  String key,
  String expected,
  String path,
) {
  final actual = _requiredString(map, key, path);
  if (actual != expected) {
    throw FormatException('$path.$key must be $expected, got $actual');
  }
}

void _expectInt(
  Map<String, Object?> map,
  String key,
  int expected,
  String path,
) {
  final actual = _requiredInt(map, key, path);
  if (actual != expected) {
    throw FormatException('$path.$key must be $expected, got $actual');
  }
}

void _expectBool(
  Map<String, Object?> map,
  String key,
  bool expected,
  String path,
) {
  final actual = _requiredBool(map, key, path);
  if (actual != expected) {
    throw FormatException('$path.$key must be $expected, got $actual');
  }
}

void _expectNullableBool(
  Map<String, Object?> map,
  String key,
  bool? expected,
  String path,
) {
  if (!map.containsKey(key) || map[key] != expected) {
    throw FormatException('$path.$key must be $expected');
  }
}

void _expectNullableString(
  Map<String, Object?> map,
  String key,
  String? expected,
  String path,
) {
  if (!map.containsKey(key) || map[key] != expected) {
    throw FormatException('$path.$key must be $expected');
  }
}

void _expectValueInt(Object? actual, int expected, String path) {
  if (actual is! int || actual != expected) {
    throw FormatException('$path must be $expected, got $actual');
  }
}

void _runSelfCheck() {
  final valid = _selfCheckReport();
  _reduce(valid);

  final badChecksum = _deepCopy(valid);
  final badChecksumVariants = badChecksum['variants']! as List<Object?>;
  final badChecksumFirst = badChecksumVariants[0]! as Map<String, Object?>;
  final badChecksumSamples = badChecksumFirst['samples']! as List<Object?>;
  final badChecksumSample = badChecksumSamples[0]! as Map<String, Object?>;
  badChecksumSample['checksum'] = 1;
  _expectRejected(badChecksum, 'checksum mismatch');

  final badStats = _deepCopy(valid);
  final badStatsVariants = badStats['variants']! as List<Object?>;
  final badStatsThird = badStatsVariants[2]! as Map<String, Object?>;
  final badStatsStatistics =
      badStatsThird['statistics']! as Map<String, Object?>;
  badStatsStatistics['p95Rank'] = 1;
  _expectRejected(badStats, 'p95 rank mismatch');

  final badStatus = _deepCopy(valid);
  badStatus['status'] = 'NOT_MEASURED';
  _expectRejected(badStatus, 'root status mismatch');
}

void _expectRejected(Map<String, Object?> report, String description) {
  try {
    _reduce(report);
  } on FormatException {
    return;
  }
  throw StateError('self-check expected rejection: $description');
}

Map<String, Object?> _selfCheckReport() {
  final identity = <String, Object?>{
    'runId': 'self-check-20260828',
    'appId': 'dev.hyfens.conformance',
    'releaseId': 'android-e1-release-1',
    'buildFingerprint': 'conformance-build-1',
    'buildConfiguration': 'Release',
    'buildTarget': 'device',
    'transport': 'usb',
    'deviceUdid': '000080200015288E03002E',
    'coreDeviceId': 'CC5119BA-1DBD-54D2-AD8C-1F15FC5E5B6F',
    'developmentTeam': 'CYT7A4VAZ3',
    'sourceSha256': List<String>.filled(64, 'a').join(),
    'patchSha256': List<String>.filled(64, 'b').join(),
    'patchSequence': 1,
    'patchFileName': 'active-patch.v1.patch',
    'reportRelativePath':
        'hyfens-e1-ios-dispatch-throughput/self-check-20260828/report.v1.json',
  };
  final protocol = <String, Object?>{
    'callCount': _callCount,
    'warmups': _warmups,
    'timedSamples': _timedSamples,
    'timer': 'Stopwatch.monotonic',
    'timerBoundary': 'repeated dispatch loop only',
    'timerFrequency': 1000000000,
    'durationUnit': _durationUnit,
    'percentile': _percentile,
    'checksum': _checksumDefinition,
  };
  final variants = <Object?>[
    for (final variant in _variants) _selfCheckVariant(variant),
  ];
  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'benchmarkId': _benchmarkId,
    'protocolVersion': _protocolVersion,
    'status': 'MEASURED',
    'failure': null,
    'identity': identity,
    'protocol': protocol,
    'workload': <String, Object?>{
      'functionId': 'sha256:${List<String>.filled(64, 'c').join()}',
      'functionSlot': 1,
      'input': <String, int>{'quantity': 6, 'tier': 1},
      'expectedResults': <String, int>{
        for (final variant in _variants) variant.id: variant.expectedResult,
      },
    },
    'patch': <String, Object?>{
      'format': 'Patch Format v1',
      'fileName': 'active-patch.v1.patch',
      'sha256': List<String>.filled(64, 'b').join(),
      'sequence': 1,
      'bytes': 128,
      'activateBytesSucceeded': true,
      'markHealthySucceeded': true,
    },
    'controller': <String, Object?>{
      'status': <String, Object?>{},
      'lifecycleState': 'running',
      'highWaterSequence': 1,
      'recoveryNeeded': false,
    },
    'claimBoundary': <String, Object?>{
      'scope': 'one named physical iOS device over USB',
      'skipped': <String>['simulator performance', 'AWS or hosted deployment'],
    },
    'variants': variants,
  };
}

Map<String, Object?> _selfCheckVariant(_VariantExpectation expectation) {
  final checksum = _expectedChecksum(expectation.expectedResult);
  final samples = <Object?>[
    for (var index = 1; index <= _timedSamples; index++)
      <String, Object?>{
        'sampleIndex': index,
        'callCount': _callCount,
        'elapsedTicks': index * 10,
        'elapsedNanoseconds': index * 10,
        'checksum': checksum,
        'expectedChecksum': checksum,
        'result': expectation.expectedResult,
        'expectedResult': expectation.expectedResult,
      },
  ];
  final elapsed = <int>[
    for (var index = 1; index <= _timedSamples; index++) index * 10,
  ];
  final sorted = List<int>.from(elapsed)..sort();
  return <String, Object?>{
    'id': expectation.id,
    'label': expectation.label,
    'path': expectation.path,
    'mode': expectation.mode,
    'expectedResult': expectation.expectedResult,
    'status': 'MEASURED',
    'failure': null,
    'demonstration': <String, Object?>{
      'callableKind': expectation.callableKind,
      'controllerMode': expectation.id == 'active_patch' ? 'patch' : 'base',
      'lookupBefore': expectation.id == 'stock_direct_callable'
          ? null
          : expectation.id == 'instrumented_unpatched',
      'lookupAfter': expectation.id == 'stock_direct_callable'
          ? null
          : expectation.id == 'active_patch',
      'runtimeLookup': expectation.runtimeLookup,
      'patchActivationSucceeded': expectation.id == 'active_patch',
      'healthConfirmationSucceeded': expectation.id == 'active_patch',
      'patchFormat': expectation.id == 'active_patch'
          ? 'Patch Format v1'
          : null,
    },
    'warmups': <String, Object?>{
      'requested': _warmups,
      'completed': _warmups,
      'timed': false,
      'checksums': <int>[checksum, checksum],
    },
    'samples': samples,
    'statistics': <String, Object?>{
      'count': _timedSamples,
      'medianNanoseconds': sorted[sorted.length ~/ 2],
      'p95Nanoseconds': sorted[sorted.length - 1],
      'p95Rank': _timedSamples,
      'minimumNanoseconds': sorted.first,
      'maximumNanoseconds': sorted.last,
      'outliersDiscarded': 0,
    },
  };
}

Map<String, Object?> _deepCopy(Map<String, Object?> source) =>
    _asMap(jsonDecode(jsonEncode(source)), r'$');

final class _VariantExpectation {
  const _VariantExpectation({
    required this.id,
    required this.label,
    required this.path,
    required this.mode,
    required this.callableKind,
    required this.runtimeLookup,
    required this.expectedResult,
  });

  final String id;
  final String label;
  final String path;
  final String mode;
  final String callableKind;
  final String runtimeLookup;
  final int expectedResult;
}
