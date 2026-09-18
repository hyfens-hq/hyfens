import 'dart:convert';
import 'dart:io';

const _schemaVersion = 1;
const _defaultDispatchIterations = 10000000;
const _defaultSamples = 15;
const _defaultWarmups = 2;
const _evidenceLabels = <String>{
  'MEASURED',
  'DIRECTIONAL',
  'DERIVED',
  'NOT MEASURED',
};
const _dispatchVariants = <String>[
  'directNativeAot',
  'instrumentedUnpatched',
  'instrumentedPatchedInterpreted',
];
const _startupVariants = <String>[
  'stock',
  'instrumentedBase',
  'instrumentedActivePatch',
];

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options.help) {
      stdout.write(_usage);
      return;
    }
    if (options.selfCheck) {
      _runSelfCheck();
      stdout.writeln('phase_1c_android_measurement self-check: PASS');
      return;
    }
    if (options.templatePath != null) {
      await _writeJson(options.templatePath!, _template());
      stdout.writeln('Wrote ${File(options.templatePath!).absolute.path}');
      return;
    }
    final inputPath = options.inputPath;
    if (inputPath == null) {
      throw const FormatException(
        'Provide --input=PATH, --template=PATH, --self-check, or --help',
      );
    }
    final input = _jsonMap(
      jsonDecode(await File(inputPath).readAsString()),
      r'$ root',
    );
    final report = _buildReport(input);
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    if (options.outputPath == null) {
      stdout.writeln(encoded);
    } else {
      await _writeJson(options.outputPath!, report);
      stdout.writeln('Wrote ${File(options.outputPath!).absolute.path}');
    }
  } on FormatException catch (error) {
    stderr.writeln('Measurement report rejected: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Measurement report I/O failed: $error');
    exitCode = 74;
  }
}

const _usage =
    '''Usage: dart run benchmarks/phase_1c_android_measurement.dart [options]

The harness is an offline reducer/validator for a coordinator-captured Android
measurement JSON file. It never invokes adb, builds, installs, or changes a
device. Capture raw marker/logcat and dumpsys evidence separately, normalize it
to the input shape, then run:

  --input=PATH       Read a raw capture JSON file.
  --output=PATH      Write the reduced report JSON to PATH (otherwise stdout).
  --template=PATH    Write a NOT MEASURED input template to PATH.
  --self-check       Run deterministic reducer checks without a device.
  --help             Show this help.

Protocol defaults: 10,000,000 dispatch iterations, 2 untimed process warmups,
15 timed samples, nearest-rank p95, and no outlier removal.
''';

final class _Options {
  const _Options({
    required this.help,
    required this.selfCheck,
    required this.inputPath,
    required this.outputPath,
    required this.templatePath,
  });

  final bool help;
  final bool selfCheck;
  final String? inputPath;
  final String? outputPath;
  final String? templatePath;

  factory _Options.parse(List<String> arguments) {
    var help = false;
    var selfCheck = false;
    String? inputPath;
    String? outputPath;
    String? templatePath;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--self-check') {
        selfCheck = true;
      } else if (argument.startsWith('--input=')) {
        inputPath = _nonEmptyOption(argument, '--input=');
      } else if (argument.startsWith('--output=')) {
        outputPath = _nonEmptyOption(argument, '--output=');
      } else if (argument.startsWith('--template=')) {
        templatePath = _nonEmptyOption(argument, '--template=');
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    final modes = <bool>[
      selfCheck,
      inputPath != null,
      templatePath != null,
    ].where((value) => value).length;
    if (modes > 1) {
      throw const FormatException(
        'Choose only one of --self-check, --input, or --template',
      );
    }
    if (help && modes != 0) {
      throw const FormatException('--help cannot be combined with a mode');
    }
    return _Options(
      help: help,
      selfCheck: selfCheck,
      inputPath: inputPath,
      outputPath: outputPath,
      templatePath: templatePath,
    );
  }
}

String _nonEmptyOption(String argument, String prefix) {
  final value = argument.substring(prefix.length);
  if (value.isEmpty) throw FormatException('$prefix requires a path');
  return value;
}

Future<void> _writeJson(String path, Map<String, Object?> value) async {
  final output = File(path);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

Map<String, Object?> _buildReport(Map<String, Object?> input) {
  final schemaVersion = _requiredInt(input, 'schemaVersion', r'$ root');
  if (schemaVersion != _schemaVersion) {
    throw FormatException(
      'schemaVersion must be $_schemaVersion, got $schemaVersion',
    );
  }
  final context =
      _optionalMap(input, 'context', r'$ root') ?? <String, Object?>{};
  final dispatchInput = _requiredMap(input, 'dispatch', r'$ root');
  final startupInput = _requiredMap(input, 'startup', r'$ root');
  final memoryInput = _requiredMap(input, 'memory', r'$ root');
  final apkInput = _requiredMap(input, 'apk', r'$ root');

  final dispatch = <String, Object?>{
    for (final variant in _dispatchVariants)
      variant: _dispatchReport(
        _requiredMap(dispatchInput, variant, r'$.dispatch'),
        variant,
      ),
  };
  final startup = <String, Object?>{
    for (final variant in _startupVariants)
      variant: _startupReport(
        _requiredMap(startupInput, variant, r'$.startup'),
        variant,
      ),
  };
  final memory = <String, Object?>{
    for (final point in const ['ready', 'postDispatch'])
      point: _memoryPointReport(
        _requiredMap(memoryInput, point, r'$.memory'),
        point,
      ),
  };
  final apk = _apkReport(apkInput);

  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'report': <String, Object?>{
      'status': _reportStatus(<Map<String, Object?>>[
        ...dispatch.values.whereType<Map<String, Object?>>(),
        ...startup.values.whereType<Map<String, Object?>>(),
        ...memory.values.whereType<Map<String, Object?>>(),
        apk,
      ]),
      'evidenceLabels': _evidenceLabels.toList(growable: false),
      'context': context,
      'protocol': <String, Object?>{
        'dispatchIterations': _defaultDispatchIterations,
        'warmups': _defaultWarmups,
        'samples': _defaultSamples,
        'percentile': 'nearest-rank p95; index ceil(0.95*n)-1',
        'outlierPolicy': 'retain every sample; discard none',
        'dispatchTimer': 'monotonic Stopwatch around the identical hotLeaf loop; process startup and patch loading excluded',
        'startupTimer': 'adb shell am start -W after force-stop; TotalTime primary and WaitTime secondary',
        'memoryCommand': 'adb shell dumpsys meminfo <package>; capture TOTAL PSS and TOTAL RSS at named point',
        'apkBytes': 'exact bytes of the comparable local APK files; active patch reuses the instrumented APK',
      },
      'dispatch': _withDispatchComparisons(dispatch),
      'startup': _withStartupComparisons(startup),
      'memory': _withMemoryComparisons(memory),
      'apk': apk,
      'inputStatus': input['status'] ?? 'RAW_CAPTURE',
    },
  };
}

String _reportStatus(List<Map<String, Object?>> reports) {
  final labels = <String>{};
  void collect(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'evidence' && entry.value is String) {
          labels.add(entry.value as String);
        } else {
          collect(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) collect(item);
    }
  }

  for (final report in reports) collect(report);
  if (labels.isNotEmpty && labels.every((label) => label == 'NOT MEASURED')) {
    return 'NOT MEASURED';
  }
  if (labels.contains('MEASURED')) return 'MEASURED_WITH_LIMITATIONS';
  if (labels.contains('DIRECTIONAL')) return 'DIRECTIONAL_ONLY';
  if (labels.contains('DERIVED')) return 'DERIVED_ONLY';
  return 'PREPARED';
}

Map<String, Object?> _dispatchReport(
  Map<String, Object?> input,
  String pathName,
) {
  final evidence = _evidence(input, pathName);
  final iterations =
      _optionalInt(input, 'iterations', pathName) ?? _defaultDispatchIterations;
  final warmups = _optionalInt(input, 'warmups', pathName) ?? _defaultWarmups;
  final samples = _sampleRecords(input, 'samples', pathName);
  if (iterations <= 0 || warmups < 0) {
    throw FormatException('$pathName iterations/warmups are invalid');
  }
  _checkSampleCount(
    evidence: evidence,
    actual: samples.length,
    pathName: pathName,
  );
  final elapsed = <int>[
    for (var index = 0; index < samples.length; index++)
      _requiredInt(
        samples[index],
        'elapsedMicros',
        '$pathName.samples[$index]',
      ),
  ];
  return <String, Object?>{
    'evidence': evidence,
    'iterations': iterations,
    'warmups': warmups,
    'sampleCount': elapsed.length,
    'samplesElapsedMicros': elapsed,
    if (elapsed.isNotEmpty) 'summary': _stats(elapsed, 'microseconds'),
    if (elapsed.isNotEmpty)
      'perIterationNanoseconds': _stats(<num>[
        for (final value in elapsed) value * 1000 / iterations,
      ], 'nanosecondsPerIteration'),
  };
}

Map<String, Object?> _startupReport(
  Map<String, Object?> input,
  String pathName,
) {
  final evidence = _evidence(input, pathName);
  final warmups = _optionalInt(input, 'warmups', pathName) ?? _defaultWarmups;
  final samples = _sampleRecords(input, 'samples', pathName);
  if (warmups < 0) throw FormatException('$pathName warmups are invalid');
  _checkSampleCount(
    evidence: evidence,
    actual: samples.length,
    pathName: pathName,
  );
  final total = <int>[];
  final wait = <int>[];
  for (var index = 0; index < samples.length; index++) {
    final samplePath = '$pathName.samples[$index]';
    total.add(_requiredInt(samples[index], 'totalTimeMs', samplePath));
    wait.add(_requiredInt(samples[index], 'waitTimeMs', samplePath));
  }
  return <String, Object?>{
    'evidence': evidence,
    'warmups': warmups,
    'sampleCount': total.length,
    'samples': samples,
    if (total.isNotEmpty) 'totalTimeMs': _stats(total, 'milliseconds'),
    if (wait.isNotEmpty) 'waitTimeMs': _stats(wait, 'milliseconds'),
  };
}

Map<String, Object?> _memoryPointReport(
  Map<String, Object?> input,
  String pointName,
) {
  final result = <String, Object?>{'measurementPoint': pointName};
  for (final variant in _startupVariants) {
    final entry = _requiredMap(input, variant, r'$.memory');
    final evidence = _evidence(entry, '$pointName.$variant');
    final warmups =
        _optionalInt(entry, 'warmups', '$pointName.$variant') ??
        _defaultWarmups;
    final samples = _sampleRecords(entry, 'samples', '$pointName.$variant');
    if (warmups < 0) {
      throw FormatException('$pointName.$variant warmups are invalid');
    }
    _checkSampleCount(
      evidence: evidence,
      actual: samples.length,
      pathName: '$pointName.$variant',
    );
    final pss = <int>[];
    final rss = <int>[];
    for (var index = 0; index < samples.length; index++) {
      final samplePath = '$pointName.$variant.samples[$index]';
      pss.add(_requiredInt(samples[index], 'totalPssKiB', samplePath));
      final rssValue = _optionalInt(samples[index], 'totalRssKiB', samplePath);
      if (rssValue != null) rss.add(rssValue);
    }
    result[variant] = <String, Object?>{
      'evidence': evidence,
      'warmups': warmups,
      'sampleCount': samples.length,
      'samples': samples,
      if (pss.isNotEmpty) 'totalPssKiB': _stats(pss, 'KiB'),
      if (rss.isNotEmpty) 'totalRssKiB': _stats(rss, 'KiB'),
      if (samples.isNotEmpty && rss.isEmpty) 'rssEvidence': 'NOT MEASURED',
    };
  }
  return result;
}

Map<String, Object?> _apkReport(Map<String, Object?> input) {
  final result = <String, Object?>{};
  for (final name in const ['stock', 'instrumented', 'activePatch', 'patch']) {
    final entry = _requiredMap(input, name, r'$.apk');
    final evidence = _evidence(entry, 'apk.$name');
    final bytes = _optionalInt(entry, 'bytes', 'apk.$name');
    if (bytes != null && bytes < 0) {
      throw FormatException('apk.$name bytes cannot be negative');
    }
    result[name] = <String, Object?>{
      'evidence': evidence,
      'bytes': bytes,
      if (entry['sha256'] != null)
        'sha256': _requiredString(entry, 'sha256', 'apk.$name'),
      if (entry['comparableBuildKey'] != null)
        'comparableBuildKey': _requiredString(
          entry,
          'comparableBuildKey',
          'apk.$name',
        ),
      if (entry['sameAs'] != null)
        'sameAs': _requiredString(entry, 'sameAs', 'apk.$name'),
    };
  }
  final stock = result['stock']! as Map<String, Object?>;
  final instrumented = result['instrumented']! as Map<String, Object?>;
  final stockBytes = stock['bytes'];
  final instrumentedBytes = instrumented['bytes'];
  final stockKey = stock['comparableBuildKey'];
  final instrumentedKey = instrumented['comparableBuildKey'];
  if (stockBytes is int &&
      instrumentedBytes is int &&
      stockKey is String &&
      stockKey.isNotEmpty &&
      stockKey == instrumentedKey) {
    final absolute = instrumentedBytes - stockBytes;
    result['comparison'] = <String, Object?>{
      'evidence': 'DERIVED',
      'stockBytes': stockBytes,
      'instrumentedBytes': instrumentedBytes,
      'absoluteGrowthBytes': absolute,
      'percentageGrowth': absolute * 100 / stockBytes,
      'comparableBuildKey': stockKey,
      'interpretation': 'same fixture/toolchain/mode/ABI comparison; this is not a universal size claim',
    };
  } else {
    result['comparison'] = <String, Object?>{
      'evidence': 'NOT MEASURED',
      'reason': 'stock and instrumented APK bytes plus one identical non-empty comparableBuildKey are required',
    };
  }
  return result;
}

Map<String, Object?> _withDispatchComparisons(Map<String, Object?> dispatch) {
  final result = <String, Object?>{};
  final direct = dispatch['directNativeAot']! as Map<String, Object?>;
  for (final variant in _dispatchVariants) {
    final entry = Map<String, Object?>.from(
      dispatch[variant]! as Map<String, Object?>,
    );
    if (variant != 'directNativeAot') {
      entry['comparisonToDirect'] = _dispatchComparison(
        direct,
        entry,
        'directNativeAot',
      );
    }
    if (variant == 'instrumentedPatchedInterpreted') {
      final unpatched =
          dispatch['instrumentedUnpatched']! as Map<String, Object?>;
      entry['comparisonToInstrumentedUnpatched'] = _dispatchComparison(
        unpatched,
        entry,
        'instrumentedUnpatched',
      );
    }
    result[variant] = entry;
  }
  return result;
}

Map<String, Object?> _dispatchComparison(
  Map<String, Object?> baseline,
  Map<String, Object?> candidate,
  String baselineName,
) {
  final baselineStats = baseline['perIterationNanoseconds'];
  final candidateStats = candidate['perIterationNanoseconds'];
  if (baselineStats is! Map<String, Object?> ||
      candidateStats is! Map<String, Object?>) {
    return <String, Object?>{
      'evidence': 'NOT MEASURED',
      'baseline': baselineName,
      'reason': 'both variants require measured samples',
    };
  }
  final baselineMedian = baselineStats['median'];
  final candidateMedian = candidateStats['median'];
  final baselineP95 = baselineStats['p95'];
  final candidateP95 = candidateStats['p95'];
  if (baselineMedian is! num ||
      candidateMedian is! num ||
      baselineP95 is! num ||
      candidateP95 is! num ||
      baselineMedian <= 0 ||
      baselineP95 <= 0) {
    return <String, Object?>{
      'evidence': 'NOT MEASURED',
      'baseline': baselineName,
      'reason': 'baseline statistics are unavailable or non-positive',
    };
  }
  return <String, Object?>{
    'evidence': 'DERIVED',
    'baseline': baselineName,
    'medianAbsoluteDeltaNanosecondsPerCall': candidateMedian - baselineMedian,
    'medianRelativeToBaseline': candidateMedian / baselineMedian,
    'medianRelativeOverheadPercent':
        (candidateMedian / baselineMedian - 1) * 100,
    'p95AbsoluteDeltaNanosecondsPerCall': candidateP95 - baselineP95,
    'p95RelativeToBaseline': candidateP95 / baselineP95,
    'p95RelativeOverheadPercent': (candidateP95 / baselineP95 - 1) * 100,
  };
}

Map<String, Object?> _withStartupComparisons(Map<String, Object?> startup) {
  final result = <String, Object?>{};
  final stock = startup['stock']! as Map<String, Object?>;
  for (final variant in _startupVariants) {
    final entry = Map<String, Object?>.from(
      startup[variant]! as Map<String, Object?>,
    );
    if (variant != 'stock') {
      entry['comparisonToStock'] = _startupComparison(stock, entry);
    }
    result[variant] = entry;
  }
  return result;
}

Map<String, Object?> _startupComparison(
  Map<String, Object?> baseline,
  Map<String, Object?> candidate,
) {
  final baselineTotal = baseline['totalTimeMs'];
  final candidateTotal = candidate['totalTimeMs'];
  if (baselineTotal is! Map<String, Object?> ||
      candidateTotal is! Map<String, Object?> ||
      baselineTotal['median'] is! num ||
      candidateTotal['median'] is! num ||
      (baselineTotal['median']! as num) <= 0) {
    return <String, Object?>{
      'evidence': 'NOT MEASURED',
      'reason': 'stock and candidate TotalTime samples are required',
    };
  }
  final baselineMedian = baselineTotal['median']! as num;
  final candidateMedian = candidateTotal['median']! as num;
  return <String, Object?>{
    'evidence': 'DERIVED',
    'medianAbsoluteDeltaMs': candidateMedian - baselineMedian,
    'medianRelativeToStock': candidateMedian / baselineMedian,
    'medianRelativeOverheadPercent':
        (candidateMedian / baselineMedian - 1) * 100,
    'interpretation': 'am start -W launch timing; not a first-frame or end-to-end user latency claim',
  };
}

Map<String, Object?> _withMemoryComparisons(Map<String, Object?> memory) {
  final result = <String, Object?>{};
  for (final point in const ['ready', 'postDispatch']) {
    final input = memory[point]! as Map<String, Object?>;
    final output = <String, Object?>{};
    final stock = input['stock']! as Map<String, Object?>;
    for (final variant in _startupVariants) {
      final entry = Map<String, Object?>.from(
        input[variant]! as Map<String, Object?>,
      );
      if (variant != 'stock') {
        entry['comparisonToStock'] = _memoryComparison(stock, entry);
      }
      output[variant] = entry;
    }
    output['measurementPoint'] = input['measurementPoint'];
    result[point] = output;
  }
  return result;
}

Map<String, Object?> _memoryComparison(
  Map<String, Object?> baseline,
  Map<String, Object?> candidate,
) {
  final pss = _memoryMetricComparison(
    baseline['totalPssKiB'],
    candidate['totalPssKiB'],
  );
  final rss = _memoryMetricComparison(
    baseline['totalRssKiB'],
    candidate['totalRssKiB'],
  );
  return <String, Object?>{
    'evidence': pss['evidence'] == 'DERIVED' || rss['evidence'] == 'DERIVED'
        ? 'DERIVED'
        : 'NOT MEASURED',
    'totalPssKiB': pss,
    'totalRssKiB': rss,
    'interpretation': 'whole-process dumpsys meminfo snapshots; no interpreter-only attribution',
  };
}

Map<String, Object?> _memoryMetricComparison(
  Object? baseline,
  Object? candidate,
) {
  if (baseline is! Map<String, Object?> ||
      candidate is! Map<String, Object?> ||
      baseline['median'] is! num ||
      candidate['median'] is! num) {
    return <String, Object?>{'evidence': 'NOT MEASURED'};
  }
  final baselineMedian = baseline['median']! as num;
  final candidateMedian = candidate['median']! as num;
  return <String, Object?>{
    'evidence': 'DERIVED',
    'medianAbsoluteDelta': candidateMedian - baselineMedian,
    'medianRelativeToStock': baselineMedian == 0
        ? null
        : candidateMedian / baselineMedian,
  };
}

Map<String, Object?> _stats(List<num> values, String unit) {
  if (values.isEmpty)
    throw const FormatException('Cannot summarize zero samples');
  final sorted = values.toList()..sort();
  final p95Index = (sorted.length * 0.95).ceil() - 1;
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  final deviations = <num>[for (final value in sorted) (value - median).abs()]
    ..sort();
  final mad = deviations.length.isOdd
      ? deviations[deviations.length ~/ 2]
      : (deviations[deviations.length ~/ 2 - 1] +
                deviations[deviations.length ~/ 2]) /
            2;
  return <String, Object?>{
    'unit': unit,
    'count': sorted.length,
    'median': median,
    'p95': sorted[p95Index],
    'minimum': sorted.first,
    'maximum': sorted.last,
    'mad': mad,
  };
}

String _evidence(Map<String, Object?> input, String pathName) {
  final value = input['evidence'];
  if (value is! String || !_evidenceLabels.contains(value)) {
    throw FormatException(
      '$pathName.evidence must be one of ${_evidenceLabels.join(', ')}',
    );
  }
  return value;
}

void _checkSampleCount({
  required String evidence,
  required int actual,
  required String pathName,
}) {
  if (evidence == 'MEASURED' && actual != _defaultSamples) {
    throw FormatException(
      '$pathName requires $_defaultSamples timed samples for MEASURED; got $actual',
    );
  }
  if (evidence == 'NOT MEASURED' && actual != 0) {
    throw FormatException(
      '$pathName is NOT MEASURED but contains $actual samples',
    );
  }
}

List<Map<String, Object?>> _sampleRecords(
  Map<String, Object?> input,
  String key,
  String pathName,
) {
  final value = input[key];
  if (value is! List) throw FormatException('$pathName.$key must be a list');
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index++)
      _jsonMap(value[index], '$pathName.$key[$index]'),
  ];
}

Map<String, Object?> _template() {
  Map<String, Object?> emptySeries({int? iterations}) => <String, Object?>{
    'evidence': 'NOT MEASURED',
    if (iterations != null) 'iterations': iterations,
    'warmups': _defaultWarmups,
    'samples': <Object?>[],
  };
  Map<String, Object?> memorySeries() => <String, Object?>{
    'evidence': 'NOT MEASURED',
    'warmups': _defaultWarmups,
    'samples': <Object?>[],
  };
  return <String, Object?>{
    'schemaVersion': _schemaVersion,
    'status': 'NOT MEASURED',
    'context': <String, Object?>{
      'device': null,
      'fixture': null,
      'flutter': null,
      'dart': null,
      'buildMode': 'release',
      'abi': 'arm64-v8a',
      'package': null,
      'activity': null,
    },
    'dispatch': <String, Object?>{
      for (final variant in _dispatchVariants)
        variant: emptySeries(iterations: _defaultDispatchIterations),
    },
    'startup': <String, Object?>{
      for (final variant in _startupVariants) variant: emptySeries(),
    },
    'memory': <String, Object?>{
      for (final point in const ['ready', 'postDispatch'])
        point: <String, Object?>{
          for (final variant in _startupVariants) variant: memorySeries(),
        },
    },
    'apk': <String, Object?>{
      for (final artifact in const [
        'stock',
        'instrumented',
        'activePatch',
        'patch',
      ])
        artifact: <String, Object?>{
          'evidence': 'NOT MEASURED',
          'bytes': null,
          'sha256': null,
          'comparableBuildKey': null,
        },
    },
  };
}

void _runSelfCheck() {
  final samples = <Object?>[
    for (var index = 0; index < _defaultSamples; index++)
      <String, Object?>{
        'elapsedMicros': 1000 + index,
        'checksum': 42,
        'pid': 9000 + index,
      },
  ];
  final startupSamples = <Object?>[
    for (var index = 0; index < _defaultSamples; index++)
      <String, Object?>{'totalTimeMs': 100 + index, 'waitTimeMs': 110 + index},
  ];
  final memorySamples = <Object?>[
    for (var index = 0; index < _defaultSamples; index++)
      <String, Object?>{
        'totalPssKiB': 80000 + index,
        'totalRssKiB': 180000 + index,
      },
  ];
  Map<String, Object?> makeDispatch(String evidence, int offset) =>
      <String, Object?>{
        'evidence': evidence,
        'iterations': _defaultDispatchIterations,
        'warmups': _defaultWarmups,
        'samples': [
          for (final sample in samples)
            <String, Object?>{
              ...(sample as Map<String, Object?>),
              'elapsedMicros': (sample['elapsedMicros']! as int) + offset,
            },
        ],
      };
  Map<String, Object?> startup(String evidence, int offset) =>
      <String, Object?>{
        'evidence': evidence,
        'warmups': _defaultWarmups,
        'samples': [
          for (final sample in startupSamples)
            <String, Object?>{
              ...(sample as Map<String, Object?>),
              'totalTimeMs': (sample['totalTimeMs']! as int) + offset,
            },
        ],
      };
  Map<String, Object?> memory(String evidence, int offset) => <String, Object?>{
    'evidence': evidence,
    'warmups': _defaultWarmups,
    'samples': [
      for (final sample in memorySamples)
        <String, Object?>{
          ...(sample as Map<String, Object?>),
          'totalPssKiB': (sample['totalPssKiB']! as int) + offset,
        },
    ],
  };
  final input = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'context': <String, Object?>{'device': 'self-check'},
    'dispatch': <String, Object?>{
      'directNativeAot': makeDispatch('MEASURED', 0),
      'instrumentedUnpatched': makeDispatch('MEASURED', 20),
      'instrumentedPatchedInterpreted': makeDispatch('MEASURED', 400),
    },
    'startup': <String, Object?>{
      'stock': startup('MEASURED', 0),
      'instrumentedBase': startup('MEASURED', 10),
      'instrumentedActivePatch': startup('MEASURED', 20),
    },
    'memory': <String, Object?>{
      for (final point in const ['ready', 'postDispatch'])
        point: <String, Object?>{
          'stock': memory('MEASURED', 0),
          'instrumentedBase': memory('MEASURED', 100),
          'instrumentedActivePatch': memory('MEASURED', 200),
        },
    },
    'apk': <String, Object?>{
      'stock': <String, Object?>{
        'evidence': 'MEASURED',
        'bytes': 100000,
        'comparableBuildKey': 'fixture|flutter|dart|release|arm64-v8a',
      },
      'instrumented': <String, Object?>{
        'evidence': 'MEASURED',
        'bytes': 106070,
        'comparableBuildKey': 'fixture|flutter|dart|release|arm64-v8a',
      },
      'activePatch': <String, Object?>{
        'evidence': 'DERIVED',
        'bytes': 106070,
        'sameAs': 'instrumented',
      },
      'patch': <String, Object?>{'evidence': 'MEASURED', 'bytes': 1798},
    },
  };
  final report = _buildReport(input);
  final reportRoot = report['report']! as Map<String, Object?>;
  final dispatch = reportRoot['dispatch']! as Map<String, Object?>;
  final patched =
      dispatch['instrumentedPatchedInterpreted']! as Map<String, Object?>;
  final direct = dispatch['directNativeAot']! as Map<String, Object?>;
  final directSummary = direct['summary']! as Map<String, Object?>;
  _expect(directSummary['median'] == 1007, 'nearest-rank median');
  _expect(directSummary['p95'] == 1014, 'nearest-rank p95');
  final comparison = patched['comparisonToDirect']! as Map<String, Object?>;
  _expect(comparison['evidence'] == 'DERIVED', 'dispatch comparison label');
  _expect(
    (comparison['medianRelativeOverheadPercent']! as num) > 0,
    'dispatch relative overhead',
  );
  final apk = reportRoot['apk']! as Map<String, Object?>;
  final apkComparison = apk['comparison']! as Map<String, Object?>;
  _expect(apkComparison['percentageGrowth'] == 6.07, 'APK growth derivation');
  final notMeasured = _buildReport(_template());
  final notMeasuredRoot = notMeasured['report']! as Map<String, Object?>;
  _expect(notMeasuredRoot['status'] == 'NOT MEASURED', 'missing-data label');

  final invalidInput = _template();
  final invalidDispatch = invalidInput['dispatch']! as Map<String, Object?>;
  final invalidDirect =
      invalidDispatch['directNativeAot']! as Map<String, Object?>;
  invalidDirect['evidence'] = 'MEASURED';
  invalidDirect['samples'] = samples.take(1).toList(growable: false);
  var rejected = false;
  try {
    _buildReport(invalidInput);
  } on FormatException {
    rejected = true;
  }
  _expect(rejected, 'measured sample-count validation');
}

void _expect(bool condition, String name) {
  if (!condition) throw StateError('Self-check failed: $name');
}

Map<String, Object?> _jsonMap(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path contains a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _requiredMap(
  Map<String, Object?> input,
  String key,
  String path,
) {
  final value = input[key];
  return _jsonMap(value, '$path.$key');
}

Map<String, Object?>? _optionalMap(
  Map<String, Object?> input,
  String key,
  String path,
) {
  final value = input[key];
  if (value == null) return null;
  return _jsonMap(value, '$path.$key');
}

String _requiredString(Map<String, Object?> input, String key, String path) {
  final value = input[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _requiredInt(Map<String, Object?> input, String key, String path) {
  final value = input[key];
  if (value is! int || value < 0) {
    throw FormatException('$path.$key must be a non-negative integer');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> input, String key, String path) {
  final value = input[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('$path.$key must be a non-negative integer or null');
  }
  return value;
}
