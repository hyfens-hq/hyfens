import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

const _defaultIterations = 10000000;
const _defaultSamples = 15;
const _defaultWarmups = 2;
const _randomSeed = 22082601;

Future<void> main(List<String> arguments) async {
  final runStartedAtUtc = DateTime.now().toUtc().toIso8601String();
  final options = _Options.parse(arguments);
  final root = Directory.current.absolute;
  final scratch = Directory('${root.path}/.dart_tool/task22_performance');
  final lockFile = File('${root.path}/.dart_tool/task22_performance.lock')
    ..createSync(recursive: true);
  final lock = lockFile.openSync(mode: FileMode.write);
  try {
    lock.lockSync(FileLock.exclusive);
  } on FileSystemException {
    lock.closeSync();
    stderr.writeln('Task 22 performance output root is already locked');
    exitCode = 73;
    return;
  }
  try {
    final competingBuilds = await _competingBuilds();
    if (competingBuilds.isNotEmpty) {
      throw StateError(
        'Another Dart/Flutter build process is active:\n'
        '${competingBuilds.join('\n')}',
      );
    }
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    scratch.createSync(recursive: true);

    final fixture = File('${root.path}/fixture/performance_app.dart');
    final fixtureHash = _hashFile(fixture);
    final overlay = E0SourceTransformer().transform(
      source: fixture.readAsStringSync(),
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/performance_app.dart',
      appId: 'dev.hyfens.instrumentation-performance',
      releaseId: 'task22-host-aot-1',
      buildFingerprint: 'task22-host-aot-build-1',
    );
    final overlayDirectory = Directory('${scratch.path}/overlay')
      ..createSync(recursive: true);
    File('${overlayDirectory.path}/app.dart').writeAsStringSync(overlay.source);
    File('${overlayDirectory.path}/manifest.json')
        .writeAsStringSync(overlay.manifest.encode());
    File('${overlayDirectory.path}/source-map.json')
        .writeAsStringSync(overlay.offsetMap.encode());
    if (_hashFile(fixture) != fixtureHash) {
      throw StateError('Performance fixture changed during overlay generation');
    }
    final hotPatch = E0PatchCompiler().compile(
      source: File('${root.path}/fixture/performance_hot_patch.dart')
          .readAsStringSync(),
      manifest: overlay.manifest,
      functionName: 'hotLeaf',
    );
    final unrelatedPatch = E0PatchCompiler().compile(
      source: File('${root.path}/fixture/performance_unrelated_patch.dart')
          .readAsStringSync(),
      manifest: overlay.manifest,
      functionName: 'unrelatedLeaf',
    );
    final hotPatchFile = File('${scratch.path}/hot.e0.json')
      ..writeAsBytesSync(hotPatch);
    final unrelatedPatchFile = File('${scratch.path}/unrelated.e0.json')
      ..writeAsBytesSync(unrelatedPatch);
    final stock = File('${scratch.path}/stock');
    final instrumented = File('${scratch.path}/instrumented');
    final lookup = File('${scratch.path}/lookup');
    final builds = <Map<String, Object?>>[
      await _compile(fixture, stock),
      await _compile(File('${scratch.path}/overlay/app.dart'), instrumented),
      await _compile(
        File('${root.path}/fixture/performance_lookup_app.dart'),
        lookup,
        packageConfig: File('${root.path}/.dart_tool/package_config.json'),
      ),
    ];

    final functions = <String, int>{
      for (final function in overlay.manifest.functions)
        function.id: function.slot,
    };
    final signatures = <String, String>{
      for (final function in overlay.manifest.functions)
        function.id: function.signature.encode(),
    };
    final receivers = <String, String>{
      for (final function in overlay.manifest.functions)
        function.id: function.receiver.encode(),
    };
    final hotSlot = overlay.manifest.functions
        .singleWhere((function) => function.name == 'hotLeaf')
        .slot;
    final unrelatedSlot = overlay.manifest.functions
        .singleWhere((function) => function.name == 'unrelatedLeaf')
        .slot;
    final primaryVariants = <String, _Variant>{
      'stock': _Variant(stock.path, <String>[
        '--iterations=${options.iterations}',
      ], const _Semantics(hot: 7, unrelated: 6)),
      'instrumentedUnpatched': _Variant(instrumented.path, <String>[
        '--iterations=${options.iterations}',
      ], const _Semantics(hot: 7, unrelated: 6)),
      'instrumentedUnrelatedPatch': _Variant(instrumented.path, <String>[
        '--iterations=${options.iterations}',
        '--e0-patch=${unrelatedPatchFile.path}',
      ], const _Semantics(hot: 7, unrelated: 1005)),
      'patchedInterpreted': _Variant(instrumented.path, <String>[
        '--iterations=${options.iterations}',
        '--e0-patch=${hotPatchFile.path}',
      ], const _Semantics(hot: 19, unrelated: 6)),
    };
    final stockChecksum = _expectedHotChecksum(
      options.iterations,
      patched: false,
    );
    final patchedChecksum = _expectedHotChecksum(
      options.iterations,
      patched: true,
    );
    final primary = await _sampleMatrix(
      primaryVariants,
      samples: options.samples,
      warmups: options.warmups,
      seed: _randomSeed,
      validate: (name, output) {
        final expected = primaryVariants[name]!.semantics;
        if (output['hotDirect'] != expected.hot ||
            output['hotTearOff'] != expected.hot ||
            output['unrelated'] != expected.unrelated) {
          throw StateError('Semantic mismatch for $name: $output');
        }
        final expectedChecksum = name == 'patchedInterpreted'
            ? patchedChecksum
            : stockChecksum;
        if (output['checksum'] != expectedChecksum) {
          throw StateError(
            'Workload checksum mismatch for $name: '
            'expected $expectedChecksum, got ${output['checksum']}',
          );
        }
      },
    );

    final lookupArguments = <String>[
      '--iterations=${options.iterations}',
      '--patch=${unrelatedPatchFile.path}',
      '--app-id=${overlay.manifest.appId}',
      '--release-id=${overlay.manifest.releaseId}',
      '--build-fingerprint=${overlay.manifest.buildFingerprint}',
      '--functions=${jsonEncode(functions)}',
      '--signatures=${jsonEncode(signatures)}',
      '--receivers=${jsonEncode(receivers)}',
    ];
    final lookupVariants = <String, _Variant>{
      'denseLookupMissActiveTable': _Variant(lookup.path, <String>[
        ...lookupArguments,
        '--slot=$hotSlot',
      ], const _Semantics(hot: 0, unrelated: 0)),
      'denseLookupHit': _Variant(lookup.path, <String>[
        ...lookupArguments,
        '--slot=$unrelatedSlot',
      ], const _Semantics(hot: 0, unrelated: 0)),
    };
    final lookupResults = await _sampleMatrix(
      lookupVariants,
      samples: options.samples,
      warmups: options.warmups,
      seed: _randomSeed + 1,
      validate: (name, output) {
        final expectedHits = name == 'denseLookupHit' ? options.iterations : 0;
        final expectedChecksum = expectedHits ^ options.iterations;
        if (output['hits'] != expectedHits ||
            output['checksum'] != expectedChecksum) {
          throw StateError('Lookup semantic mismatch for $name: $output');
        }
      },
    );

    final startupVariants = <String, _Variant>{
      'stock': _Variant(stock.path, const <String>[
        '--iterations=0',
      ], const _Semantics(hot: 7, unrelated: 6)),
      'instrumentedUnpatched': _Variant(instrumented.path, const <String>[
        '--iterations=0',
      ], const _Semantics(hot: 7, unrelated: 6)),
    };
    final startup = await _sampleStartupMatrix(
      startupVariants,
      samples: options.samples,
      warmups: options.warmups,
      seed: _randomSeed + 2,
    );

    final stockStats = primary['variants']! as Map<String, Object?>;
    final stockMedian =
        (stockStats['stock']! as Map<String, Object?>)['medianElapsedMicros']!
            as num;
    final unpatchedMedian =
        (stockStats['instrumentedUnpatched']!
                as Map<String, Object?>)['medianElapsedMicros']!
            as num;
    final stockNs = stockMedian * 1000 / options.iterations;
    final unpatchedNs = unpatchedMedian * 1000 / options.iterations;
    final gate = <String, Object>{
      'maximumAddedNanosecondsPerCall': 10,
      'maximumRelativeToStock': 5,
      'stockNanosecondsPerCall': stockNs,
      'instrumentedUnpatchedNanosecondsPerCall': unpatchedNs,
      'addedNanosecondsPerCall': unpatchedNs - stockNs,
      'relativeToStock': unpatchedMedian / stockMedian,
      'passesAddedNanoseconds': unpatchedNs - stockNs <= 10,
      'passesRelative': unpatchedMedian / stockMedian <= 5,
      'passes':
          unpatchedNs - stockNs <= 10 && unpatchedMedian / stockMedian <= 5,
    };
    final environment = await _environment();
    final result = <String, Object?>{
      'schemaVersion': 2,
      'protocol': 'tool/performance/PROTOCOL.md',
      'protocolAmendment': 'Amendment 1 — provenance-hardened replacement run',
      'startedAtUtc': runStartedAtUtc,
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'environment': environment,
      'configuration': <String, Object>{
        'iterations': options.iterations,
        'samples': options.samples,
        'warmups': options.warmups,
        'randomSeed': _randomSeed,
        'protocolDefaultsUsed': options.isProtocolDefault,
        'resourceReductionReason': options.resourceReductionReason,
      },
      'hotLeafGate': gate,
      'builds': builds,
      'hotLeaf': primary,
      'lookup': lookupResults,
      'startupAndPeakRss': startup,
      'artifacts': <String, Object>{
        'stockExecutable': _artifact(stock),
        'instrumentedExecutable': _artifact(instrumented),
        'lookupExecutable': _artifact(lookup),
        'hotPatch': _artifact(hotPatchFile),
        'unrelatedPatch': _artifact(unrelatedPatchFile),
        'originalFixture': _artifact(fixture),
        'transformedFixture': _artifact(
          File('${scratch.path}/overlay/app.dart'),
        ),
        'manifest': _artifact(File('${scratch.path}/overlay/manifest.json')),
      },
      'sourceArtifacts': _sourceArtifacts(root),
      'limitations': <String>[
        'Host macOS AOT only; no physical-device measurements.',
        'Startup is external wall time to process completion; the single JSON output line is not independently timestamped.',
        if (Platform.operatingSystem != 'macos')
          'Peak RSS omitted because macOS /usr/bin/time -l was unavailable.',
        'No cached-flag or generation alternative was implemented, so no alternative lookup result is reported.',
      ],
    };
    final output = File(options.outputPath)..createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    if (gate['passes'] != true) exitCode = 1;
  } finally {
    lock.unlockSync();
    lock.closeSync();
  }
}

int _expectedHotChecksum(int iterations, {required bool patched}) {
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    final a = index % 31 - 15;
    final b = index % 17;
    final value = a < 0
        ? b - a
        : patched
        ? a == b
              ? a * 10
              : a * b + 7
        : a + b;
    checksum ^= value;
  }
  return checksum;
}

Future<Map<String, Object?>> _sampleMatrix(
  Map<String, _Variant> variants, {
  required int samples,
  required int warmups,
  required int seed,
  required void Function(String name, Map<String, Object?> output) validate,
}) async {
  for (final entry in variants.entries) {
    for (var index = 0; index < warmups; index++) {
      final output = await _execute(entry.value);
      validate(entry.key, output);
    }
  }
  final raw = <String, List<Map<String, Object?>>>{
    for (final name in variants.keys) name: <Map<String, Object?>>[],
  };
  final order = <Map<String, Object>>[];
  final random = Random(seed);
  for (var round = 0; round < samples; round++) {
    final names = variants.keys.toList()..shuffle(random);
    order.add(<String, Object>{'round': round, 'variants': names});
    for (final name in names) {
      final output = await _execute(variants[name]!);
      validate(name, output);
      raw[name]!.add(<String, Object?>{
        'round': round,
        'elapsedMicros': output['elapsedMicros'],
        'checksum': output['checksum'],
        'output': output,
      });
    }
  }
  return <String, Object?>{
    'sampleOrder': order,
    'variants': <String, Object?>{
      for (final name in variants.keys)
        name: _summarize(
          raw[name]!,
          raw[name]!.map((sample) => sample['elapsedMicros']! as int).toList(),
        ),
    },
  };
}

Future<Map<String, Object?>> _sampleStartupMatrix(
  Map<String, _Variant> variants, {
  required int samples,
  required int warmups,
  required int seed,
}) async {
  for (final variant in variants.values) {
    for (var index = 0; index < warmups; index++) {
      await _executeExternal(variant);
    }
  }
  final raw = <String, List<Map<String, Object?>>>{
    for (final name in variants.keys) name: <Map<String, Object?>>[],
  };
  final order = <Map<String, Object>>[];
  final random = Random(seed);
  for (var round = 0; round < samples; round++) {
    final names = variants.keys.toList()..shuffle(random);
    order.add(<String, Object>{'round': round, 'variants': names});
    for (final name in names) {
      final sample = await _executeExternal(variants[name]!);
      raw[name]!.add(<String, Object?>{'round': round, ...sample});
    }
  }
  return <String, Object?>{
    'sampleOrder': order,
    'rssUnit': Platform.operatingSystem == 'macos' ? 'bytes' : null,
    'variants': <String, Object?>{
      for (final name in variants.keys)
        name: <String, Object?>{
          ..._summarize(
            raw[name]!,
            raw[name]!
                .map((sample) => sample['wallElapsedMicros']! as int)
                .toList(),
            elapsedKey: 'wallElapsedMicros',
          ),
          if (raw[name]!.every((sample) => sample['peakRssBytes'] is int))
            'peakRss': _statistics(
              raw[name]!
                  .map((sample) => sample['peakRssBytes']! as int)
                  .toList(),
            ),
        },
    },
  };
}

Map<String, Object?> _summarize(
  List<Map<String, Object?>> raw,
  List<int> values, {
  String elapsedKey = 'elapsedMicros',
}) => <String, Object?>{
  ..._statistics(values)
      .map((key, value) => MapEntry('$key${_suffix(elapsedKey)}', value)),
  'samples': raw,
};

String _suffix(String key) => key == 'elapsedMicros'
    ? 'ElapsedMicros'
    : key == 'wallElapsedMicros'
    ? 'WallElapsedMicros'
    : key;

Map<String, num> _statistics(List<int> values) {
  final sorted = values.toList()..sort();
  final median = _median(sorted);
  final deviations = values.map((value) => (value - median).abs()).toList()
    ..sort();
  return <String, num>{
    'median': median,
    'p95': sorted[(0.95 * sorted.length).ceil() - 1],
    'mad': _median(deviations),
    'minimum': sorted.first,
    'maximum': sorted.last,
  };
}

num _median(List<num> sorted) {
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

Future<Map<String, Object?>> _execute(_Variant variant) async {
  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final result = await Process.run(variant.executable, variant.arguments);
  final completedAtUtc = DateTime.now().toUtc().toIso8601String();
  if (result.exitCode != 0) {
    throw ProcessException(
      variant.executable,
      variant.arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final decoded = jsonDecode((result.stdout as String).trim());
  if (decoded is! Map<String, Object?> || decoded['elapsedMicros'] is! int) {
    throw StateError('Invalid benchmark output: ${result.stdout}');
  }
  return <String, Object?>{
    ...decoded,
    'process': _processRecord(
      variant.executable,
      variant.arguments,
      result.exitCode,
      startedAtUtc,
      completedAtUtc,
    ),
  };
}

Future<Map<String, Object?>> _executeExternal(_Variant variant) async {
  final useTime =
      Platform.operatingSystem == 'macos' && File('/usr/bin/time').existsSync();
  final executable = useTime ? '/usr/bin/time' : variant.executable;
  final arguments = useTime
      ? <String>['-l', variant.executable, ...variant.arguments]
      : variant.arguments;
  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final watch = Stopwatch()..start();
  final result = await Process.run(executable, arguments);
  watch.stop();
  final completedAtUtc = DateTime.now().toUtc().toIso8601String();
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final output = jsonDecode((result.stdout as String).trim());
  if (output is! Map<String, Object?> ||
      output['hotDirect'] != variant.semantics.hot ||
      output['unrelated'] != variant.semantics.unrelated) {
    throw StateError('Invalid startup output: ${result.stdout}');
  }
  final rss = useTime
      ? RegExp(r'(\d+)\s+maximum resident set size')
            .firstMatch(result.stderr as String)
      : null;
  return <String, Object?>{
    'wallElapsedMicros': watch.elapsedMicroseconds,
    'peakRssBytes': rss == null ? null : int.parse(rss.group(1)!),
    'checksum': output['checksum'],
    'process': _processRecord(
      executable,
      arguments,
      result.exitCode,
      startedAtUtc,
      completedAtUtc,
    ),
  };
}

Future<Map<String, Object?>> _compile(
  File source,
  File output, {
  File? packageConfig,
}) async {
  final arguments = <String>[
    'compile',
    'exe',
    if (packageConfig != null) '--packages=${packageConfig.path}',
    source.path,
    '-o',
    output.path,
  ];
  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final result = await Process.run(Platform.resolvedExecutable, arguments);
  final completedAtUtc = DateTime.now().toUtc().toIso8601String();
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return _processRecord(
    Platform.resolvedExecutable,
    arguments,
    result.exitCode,
    startedAtUtc,
    completedAtUtc,
  );
}

Future<List<String>> _competingBuilds() async {
  final result = await Process.run('ps', const <String>[
    '-axo',
    'pid=,command=',
  ]);
  if (result.exitCode != 0) return <String>[];
  return (result.stdout as String)
      .split('\n')
      .where(
        (line) =>
            line.contains('dart compile') ||
            line.contains('flutter assemble') ||
            line.contains('gen_snapshot'),
      )
      .where((line) => !line.contains('performance_benchmark.dart'))
      .toList();
}

Future<Map<String, Object?>> _environment() async {
  Future<String?> command(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0 ? (result.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  return <String, Object?>{
    'dartVersion': Platform.version,
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'localeName': Platform.localeName,
    'numberOfProcessors': Platform.numberOfProcessors,
    'cpuModel': await command('sysctl', const <String>[
      '-n',
      'machdep.cpu.brand_string',
    ]),
    'machineArchitecture': await command('uname', const <String>['-m']),
    'kernel': await command('uname', const <String>['-srv']),
  };
}

Map<String, Object> _artifact(File file) => <String, Object>{
  'path': file.path,
  'bytes': file.lengthSync(),
  'sha256': _hashFile(file),
};

List<Map<String, Object>> _sourceArtifacts(Directory root) {
  final files = <File>[
    File('${root.path}/tool/performance_benchmark.dart'),
    File('${root.path}/fixture/performance_app.dart'),
    File('${root.path}/fixture/performance_hot_patch.dart'),
    File('${root.path}/fixture/performance_unrelated_patch.dart'),
    File('${root.path}/fixture/performance_lookup_app.dart'),
    File('${root.path}/pubspec.yaml'),
    File('${root.path}/pubspec.lock'),
    File('${root.path}/.dart_tool/package_config.json'),
    ...Directory('${root.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ]..sort((left, right) => left.path.compareTo(right.path));
  if (files.any((file) => !file.existsSync())) {
    throw StateError('A declared performance source artifact is missing');
  }
  return files.map(_artifact).toList(growable: false);
}

Map<String, Object> _processRecord(
  String executable,
  List<String> arguments,
  int exitStatus,
  String startedAtUtc,
  String completedAtUtc,
) => <String, Object>{
  'executable': executable,
  'arguments': arguments,
  'exitStatus': exitStatus,
  'startedAtUtc': startedAtUtc,
  'completedAtUtc': completedAtUtc,
};

String _hashFile(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

final class _Variant {
  const _Variant(this.executable, this.arguments, this.semantics);

  final String executable;
  final List<String> arguments;
  final _Semantics semantics;
}

final class _Semantics {
  const _Semantics({required this.hot, required this.unrelated});

  final int hot;
  final int unrelated;
}

final class _Options {
  const _Options({
    required this.iterations,
    required this.samples,
    required this.warmups,
    required this.outputPath,
    required this.resourceReductionReason,
  });

  final int iterations;
  final int samples;
  final int warmups;
  final String outputPath;
  final String resourceReductionReason;

  bool get isProtocolDefault =>
      iterations == _defaultIterations &&
      samples == _defaultSamples &&
      warmups == _defaultWarmups;

  static _Options parse(List<String> arguments) {
    var iterations = _defaultIterations;
    var samples = _defaultSamples;
    var warmups = _defaultWarmups;
    var output = 'tool/performance/results/task22-host-raw.json';
    var reductionReason = '';
    for (final argument in arguments) {
      if (argument.startsWith('--iterations=')) {
        iterations = int.parse(argument.substring('--iterations='.length));
      } else if (argument.startsWith('--samples=')) {
        samples = int.parse(argument.substring('--samples='.length));
      } else if (argument.startsWith('--warmups=')) {
        warmups = int.parse(argument.substring('--warmups='.length));
      } else if (argument.startsWith('--output=')) {
        output = argument.substring('--output='.length);
      } else if (argument.startsWith('--resource-reduction-reason=')) {
        reductionReason = argument.substring(
          '--resource-reduction-reason='.length,
        );
      } else {
        throw FormatException('Unknown argument $argument');
      }
    }
    if (iterations <= 0 || samples <= 0 || warmups < 0) {
      throw const FormatException('Iteration/sample counts must be positive');
    }
    final reduced =
        iterations < _defaultIterations ||
        samples < _defaultSamples ||
        warmups < _defaultWarmups;
    if (reduced && reductionReason.trim().isEmpty) {
      throw const FormatException(
        'Reduced protocol requires --resource-reduction-reason',
      );
    }
    return _Options(
      iterations: iterations,
      samples: samples,
      warmups: warmups,
      outputPath: output,
      resourceReductionReason: reductionReason,
    );
  }
}
