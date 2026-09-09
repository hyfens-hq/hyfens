import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

const _applicationId = 'dev.hyfens.phase1d.performance';
const _releaseId =
    'sha256:1111111111111111111111111111111111111111111111111111111111111111';
const _buildFingerprint = 'phase1d-host-build-1';
const _maxScaleFunctions = 50;
const _bridgeExtensionType = patchFormatV1E0BridgeExtensionType;
const _signingKeyId = 'phase1d-host-benchmark';
const _signingSeed = <int>[
  0x9d,
  0x61,
  0xb1,
  0x9d,
  0xef,
  0xfd,
  0x5a,
  0x60,
  0xba,
  0x84,
  0x4a,
  0xf4,
  0x92,
  0xec,
  0x2c,
  0xc4,
  0x44,
  0x49,
  0xc5,
  0x69,
  0x7b,
  0x32,
  0x69,
  0x19,
  0x70,
  0x3b,
  0xac,
  0x03,
  0x1c,
  0xae,
  0x7f,
  0x60,
];

final _phase1dImmediate = E0AsyncCapabilityDescriptor(
  id: 'phase1d.host.immediate',
  sourceName: 'phase1dImmediate',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);

const _applicationSource = '''
int calculatePrice(int unitPrice, int quantity) {
  var total = unitPrice * quantity;
  if (quantity >= 10) {
    total = total - 50;
  }
  return total;
}

bool isEligible(int age, bool verified, int spend) {
  if (age < 18) return false;
  if (!verified) return false;
  return spend >= 100;
}

List<int> transformValues(List<int> values) {
  final List<int> output = <int>[];
  for (final int value in values) {
    if (value > 0) output.add(value * 2);
  }
  return output;
}

int recomputeTotal(List<int> values, int threshold) {
  var total = 0;
  for (final int value in values) {
    if (value > threshold) total += value;
  }
  return total;
}

String routeDecision(bool authenticated, bool entitled) {
  if (!authenticated) return '/login';
  if (entitled) return '/offers';
  return '/home';
}

external Future<int> phase1dImmediate(int value);

Future<int> boundedAsync(int amount) async {
  final int result = await phase1dImmediate(amount);
  return result + 5;
}

void main(List<String> arguments) {}
''';

const _patchSources = <String, String>{
  'calculatePrice': '''
int calculatePrice(int unitPrice, int quantity) {
  var total = unitPrice * quantity;
  if (quantity >= 10) {
    total = total - 50;
  }
  return total;
}
''',
  'isEligible': '''
bool isEligible(int age, bool verified, int spend) {
  if (age < 18) return false;
  if (!verified) return false;
  return spend >= 100;
}
''',
  'transformValues': '''
List<int> transformValues(List<int> values) {
  final List<int> output = <int>[];
  for (final int value in values) {
    if (value > 0) output.add(value * 2);
  }
  return output;
}
''',
  'recomputeTotal': '''
int recomputeTotal(List<int> values, int threshold) {
  var total = 0;
  for (final int value in values) {
    if (value > threshold) total += value;
  }
  return total;
}
''',
  'routeDecision': '''
String routeDecision(bool authenticated, bool entitled) {
  if (!authenticated) return '/login';
  if (entitled) return '/offers';
  return '/home';
}
''',
  'boundedAsync': '''
external Future<int> phase1dImmediate(int value);

Future<int> boundedAsync(int amount) async {
  final int result = await phase1dImmediate(amount);
  return result + 5;
}
''',
};

final _workloads = <_Workload>[
  _Workload(
    name: 'pricing',
    category: 'pricing/business calculation',
    functionName: 'calculatePrice',
    arguments: <Object?>[540, 7],
    expected: 3780,
    frequencyClass: 'medium-frequency',
  ),
  _Workload(
    name: 'eligibility',
    category: 'branch-heavy eligibility/rules',
    functionName: 'isEligible',
    arguments: <Object?>[24, true, 300],
    expected: true,
    frequencyClass: 'medium-frequency',
  ),
  _Workload(
    name: 'collectionTransform',
    category: 'collection transformation',
    functionName: 'transformValues',
    arguments: <Object?>[
      <int>[1, -2, 3, 4],
    ],
    expected: <int>[2, 6, 8],
    frequencyClass: 'medium-frequency',
  ),
  _Workload(
    name: 'stateRecompute',
    category: 'state/Notifier recomputation model',
    functionName: 'recomputeTotal',
    arguments: <Object?>[
      <int>[5, 12, 19, 3],
      10,
    ],
    expected: 31,
    frequencyClass: 'medium-frequency',
  ),
  _Workload(
    name: 'routeDecision',
    category: 'GoRouter decision model',
    functionName: 'routeDecision',
    arguments: <Object?>[true, false],
    expected: '/home',
    frequencyClass: 'low-frequency',
  ),
  _Workload(
    name: 'boundedAsync',
    category: 'bounded async business operation',
    functionName: 'boundedAsync',
    arguments: <Object?>[540],
    expected: 545,
    isAsync: true,
    frequencyClass: 'low-frequency',
  ),
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.write(_usage);
    return;
  }
  if (options.selfCheck) {
    await _runSelfCheck();
    stdout.writeln('phase_1d_performance_benchmark self-check: PASS');
    return;
  }

  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final application = _buildApplicationFixture();
  if (options.stage2Attribution) {
    final report = await _runStage2Attribution(
      application,
      options,
      startedAtUtc,
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    if (options.outputPath == null) {
      stdout.writeln(encoded);
    } else {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString('$encoded\n');
      stdout.writeln('Wrote ${output.absolute.path}');
    }
    return;
  }
  final applicationReport = await _runApplicationWorkloads(
    application,
    options,
  );
  final profileReport = _runInterpreterProfile(application, options);
  final scalingReport = await _runPatchSizeScaling(options);
  final report = <String, Object?>{
    'schemaVersion': 1,
    'benchmark': <String, Object?>{
      'name': 'phase-1d-host-performance-and-patch-scaling',
      'startedAtUtc': startedAtUtc,
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'samples': options.samples,
      'warmups': options.warmups,
      'applicationIterations': options.iterations,
      'profileIterations': options.profileIterations,
      'sizeCounts': options.sizeCounts,
      'runner': 'dart run benchmarks/phase_1d_performance_benchmark.dart',
      'timing': 'host wall-clock Dart timings; application and profile samples are in-process; patch scaling stages are in-process host timings',
      'fixture': 'inline bounded pure-Dart supported-subset fixture',
    },
    'environment': <String, Object?>{
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'processors': Platform.numberOfProcessors,
    },
    'applicationWorkloads': applicationReport,
    'interpretedProfile': profileReport,
    'patchSizeScaling': scalingReport,
    'unavailable': <String, Object?>{
      'physicalAndroid': 'NOT RUN: this benchmark does not build, install, or measure an Android device.',
      'physicalIos': 'NOT RUN: this benchmark does not build, install, or measure an iOS device.',
      'flutterEngineAndFirstFrame':
          'NOT RUN: the fixture is pure Dart and does not initialize Flutter.',
      'internalInterpreterCounters': 'NOT RUN: the existing public runtime has no per-stage hooks for instruction decode, frame/value allocation, budget, source-map, or capability attribution.',
      'networkAndFilesystem': 'NOT RUN: no delivery, durable storage, or controller lifecycle is exercised.',
    },
    'limitations': <String>[
      'Application and profile measurements are host-only directional evidence, not device latency budgets.',
      'Direct workload timings and interpreted timings include the same result-check checksum loop but are not process-isolated.',
      'The profile separates public slot lookup, public runtime invocation, and direct interpreter entry; it does not attribute time to private interpreter stages.',
      'Patch scaling compiles one supported function per E0 container and packs those containers into the existing Patch Format v1 E0 bridge. It is not a claim about a future multi-function source compiler.',
      'Process RSS snapshots, when present in scaling samples, are noisy whole-process observations and are not interpreter-only memory attribution.',
    ],
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  if (options.outputPath == null) {
    stdout.writeln(encoded);
  } else {
    final output = File(options.outputPath!);
    await output.parent.create(recursive: true);
    await output.writeAsString('$encoded\n');
    stdout.writeln('Wrote ${output.absolute.path}');
  }
}

const _usage =
    '''Usage: dart run benchmarks/phase_1d_performance_benchmark.dart [options]

Runs bounded host-only Phase 1D application-workload, public-layer profile,
and Patch Format v1 E0-bridge patch-size measurements. It does not initialize
Flutter, use a device, use a controller, or write checked-in files.

Options:
  --samples=N                 Timed samples per stage (default: 5)
  --warmups=N                 Untimed warmups per stage (default: 1)
  --iterations=N              Calls per application sample (default: 1000)
  --profile-iterations=N      Calls per profile sample (default: 10000)
  --size-counts=LIST          Comma-separated function counts up to 50 (default: 1,5,20,50)
  --output=PATH               Write JSON to PATH instead of stdout
  --stage2-attribution        Run the opt-in private-stage attribution profile only
  --self-check                Validate fixture, compilation, bridge, and batch install
  --help                      Show this help
''';

final class _Options {
  const _Options({
    required this.samples,
    required this.warmups,
    required this.iterations,
    required this.profileIterations,
    required this.sizeCounts,
    required this.outputPath,
    required this.stage2Attribution,
    required this.selfCheck,
    required this.help,
  });

  final int samples;
  final int warmups;
  final int iterations;
  final int profileIterations;
  final List<int> sizeCounts;
  final String? outputPath;
  final bool stage2Attribution;
  final bool selfCheck;
  final bool help;

  factory _Options.parse(List<String> arguments) {
    var samples = 5;
    var warmups = 1;
    var iterations = 1000;
    var profileIterations = 10000;
    var sizeCounts = const <int>[1, 5, 20, 50];
    String? outputPath;
    var stage2Attribution = false;
    var selfCheck = false;
    var help = false;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--self-check') {
        selfCheck = true;
      } else if (argument == '--stage2-attribution') {
        stage2Attribution = true;
      } else if (argument.startsWith('--samples=')) {
        samples = _positiveInt(
          argument.substring('--samples='.length),
          'samples',
        );
      } else if (argument.startsWith('--warmups=')) {
        warmups = _nonNegativeInt(
          argument.substring('--warmups='.length),
          'warmups',
        );
      } else if (argument.startsWith('--iterations=')) {
        iterations = _positiveInt(
          argument.substring('--iterations='.length),
          'iterations',
        );
      } else if (argument.startsWith('--profile-iterations=')) {
        profileIterations = _positiveInt(
          argument.substring('--profile-iterations='.length),
          'profile-iterations',
        );
      } else if (argument.startsWith('--size-counts=')) {
        final value = argument.substring('--size-counts='.length);
        sizeCounts =
            value
                .split(',')
                .where((item) => item.isNotEmpty)
                .map((item) => _positiveInt(item, 'size-counts'))
                .toSet()
                .toList()
              ..sort();
        if (sizeCounts.isEmpty) {
          throw const FormatException('size-counts must not be empty');
        }
        if (sizeCounts.any((count) => count > _maxScaleFunctions)) {
          throw FormatException(
            'size-counts cannot exceed $_maxScaleFunctions functions',
          );
        }
      } else if (argument.startsWith('--output=')) {
        outputPath = argument.substring('--output='.length);
        if (outputPath.isEmpty) {
          throw const FormatException('output path is empty');
        }
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    return _Options(
      samples: samples,
      warmups: warmups,
      iterations: iterations,
      profileIterations: profileIterations,
      sizeCounts: sizeCounts,
      outputPath: outputPath,
      stage2Attribution: stage2Attribution,
      selfCheck: selfCheck,
      help: help,
    );
  }
}

final class _Workload {
  _Workload({
    required this.name,
    required this.category,
    required this.functionName,
    required List<Object?> arguments,
    required this.expected,
    required this.frequencyClass,
    this.isAsync = false,
  }) : arguments = List<Object?>.unmodifiable(arguments);

  final String name;
  final String category;
  final String functionName;
  final List<Object?> arguments;
  final Object? expected;
  final bool isAsync;
  final String frequencyClass;
}

final class _ApplicationFixture {
  const _ApplicationFixture({required this.manifest, required this.programs});

  final E0ReleaseManifest manifest;
  final Map<String, E0PatchProgram> programs;
}

void _configureApplicationCapability() {
  E0PatchRuntime.configureCapabilities(
    E0CapabilityAuthority(
      shipped: <E0AsyncCapabilityDescriptor>[_phase1dImmediate],
      registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
        E0CapabilityRegistration(
          _phase1dImmediate,
          (arguments) => Future<Object?>.value(arguments.single! as int),
        ),
      ]),
    ),
  );
}

_ApplicationFixture _buildApplicationFixture() {
  final transformed = E0SourceTransformer().transform(
    source: _applicationSource,
    packageName: 'phase1d_fixture',
    logicalLibraryPath: 'lib/application_workload.dart',
    appId: _applicationId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    capabilities: <E0AsyncCapabilityDescriptor>[_phase1dImmediate],
  );
  final manifest = transformed.manifest;
  final tables = _releaseTables(manifest);
  final programs = <String, E0PatchProgram>{};
  final bytePrograms = <List<int>>[];
  for (final workload in _workloads) {
    final bytes = E0PatchCompiler().compile(
      source: _patchSources[workload.functionName]!,
      manifest: manifest,
      functionName: workload.functionName,
      patchSequence: 1,
    );
    bytePrograms.add(bytes);
    final program = E0PatchContainer.decode(
      bytes,
      expectedAppId: _applicationId,
      expectedReleaseId: _releaseId,
      expectedBuildFingerprint: _buildFingerprint,
      expectedFunctions: tables.functions,
      expectedSignatures: tables.decodedSignatures,
      expectedReceivers: tables.decodedReceivers,
    );
    programs[workload.functionName] = program;
  }
  E0PatchRuntime.reset();
  _configureApplicationCapability();
  final installed = E0PatchRuntime.installBatchBytes(
    bytePrograms,
    appId: _applicationId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    functions: tables.functions,
    signatures: tables.signatures,
    receivers: tables.receivers,
  );
  if (!installed) {
    throw StateError(
      'Application fixture batch install failed: ${E0PatchRuntime.lastRejection}',
    );
  }
  return _ApplicationFixture(manifest: manifest, programs: programs);
}

Future<Map<String, Object?>> _runApplicationWorkloads(
  _ApplicationFixture fixture,
  _Options options,
) async {
  final report = <String, Object?>{
    'evidence': 'DIRECTIONAL',
    'samples': options.samples,
    'warmups': options.warmups,
    'iterations': options.iterations,
    'workloads': <String, Object?>{},
  };
  final workloads = report['workloads']! as Map<String, Object?>;
  for (final workload in _workloads) {
    final program = fixture.programs[workload.functionName]!;
    final directCheck = workload.isAsync
        ? await _directAsyncValue(workload)
        : _directValue(workload);
    final patchedCheck = workload.isAsync
        ? await _patchedAsyncValue(program, workload.arguments)
        : _patchedValue(program, workload.arguments);
    _expectEqual(
      directCheck,
      workload.expected,
      '${workload.name} direct semantic result',
    );
    _expectEqual(
      patchedCheck,
      workload.expected,
      '${workload.name} patched semantic result',
    );

    final expectedChecksum = _repeatFingerprint(
      workload.expected,
      options.iterations,
    );
    late final Map<String, Object?> direct;
    late final Map<String, Object?> patched;
    if (workload.isAsync) {
      direct = await _sampleAsync(
        operation: () =>
            _runDirectAsyncLoop(workload, options.iterations, expectedChecksum),
        samples: options.samples,
        warmups: options.warmups,
        iterationsPerSample: options.iterations,
      );
      patched = await _sampleAsync(
        operation: () => _runPatchedAsyncLoop(
          program,
          workload.arguments,
          options.iterations,
          expectedChecksum,
        ),
        samples: options.samples,
        warmups: options.warmups,
        iterationsPerSample: options.iterations,
      );
    } else {
      direct = _sampleSync(
        operation: () =>
            _runDirectSyncLoop(workload, options.iterations, expectedChecksum),
        samples: options.samples,
        warmups: options.warmups,
        iterationsPerSample: options.iterations,
      );
      patched = _sampleSync(
        operation: () => _runPatchedSyncLoop(
          program,
          workload.arguments,
          options.iterations,
          expectedChecksum,
        ),
        samples: options.samples,
        warmups: options.warmups,
        iterationsPerSample: options.iterations,
      );
    }
    final directMedian = direct['median']! as num;
    final patchedMedian = patched['median']! as num;
    workloads[workload.name] = <String, Object?>{
      'category': workload.category,
      'frequencyClass': workload.frequencyClass,
      'functionName': workload.functionName,
      'async': workload.isAsync,
      'expectedResult': workload.expected,
      'direct': direct,
      'patchedInterpreted': patched,
      'comparison': <String, Object?>{
        'evidence': 'DERIVED',
        'patchedToDirectMedian': patchedMedian / directMedian,
        'directMedianMicros': directMedian,
        'patchedMedianMicros': patchedMedian,
      },
      'runtimeCounters': <String, Object?>{
        'patchedArgumentListAllocations':
            E0PatchRuntime.patchedArgumentListAllocations,
        'meaning':
            'public invoke/invokeAsync call counter, not heap attribution',
      },
    };
  }
  return report;
}

Map<String, Object?> _runInterpreterProfile(
  _ApplicationFixture fixture,
  _Options options,
) {
  final workload = _workloads.first;
  final program = fixture.programs[workload.functionName]!;
  final args = workload.arguments;
  final expected = workload.expected;
  final expectedChecksum = _repeatFingerprint(
    expected,
    options.profileIterations,
  );
  final beforeAllocations = E0PatchRuntime.patchedArgumentListAllocations;
  final stages = <String, Object?>{
    'slotLookup': _sampleSync(
      operation: () {
        var checksum = 0;
        for (var index = 0; index < options.profileIterations; index++) {
          final found = E0PatchRuntime.lookup(program.slot);
          if (found == null)
            throw StateError('Profile slot lookup returned null');
          checksum ^= found.code.length;
        }
        if (checksum == -1) throw StateError('Unreachable profile checksum');
      },
      samples: options.samples,
      warmups: options.warmups,
      iterationsPerSample: options.profileIterations,
    ),
    'directInterpreterExecuteValues': _sampleSync(
      operation: () {
        var checksum = 0;
        for (var index = 0; index < options.profileIterations; index++) {
          final value = E0Interpreter.executeValues(program, args);
          checksum = (checksum + _fingerprint(value)) & 0x7fffffff;
        }
        if (checksum != expectedChecksum) {
          throw StateError('Direct interpreter profile checksum mismatch');
        }
      },
      samples: options.samples,
      warmups: options.warmups,
      iterationsPerSample: options.profileIterations,
    ),
    'publicRuntimeInvoke': _sampleSync(
      operation: () => _runPatchedSyncLoop(
        program,
        args,
        options.profileIterations,
        expectedChecksum,
      ),
      samples: options.samples,
      warmups: options.warmups,
      iterationsPerSample: options.profileIterations,
    ),
    'lookupAndPublicRuntimeInvoke': _sampleSync(
      operation: () {
        var checksum = 0;
        for (var index = 0; index < options.profileIterations; index++) {
          final found = E0PatchRuntime.lookup(program.slot);
          if (found == null)
            throw StateError('Combined profile lookup returned null');
          final result = _patchedValue(found, args);
          checksum = (checksum + _fingerprint(result)) & 0x7fffffff;
        }
        if (checksum != expectedChecksum) {
          throw StateError('Combined profile checksum mismatch');
        }
      },
      samples: options.samples,
      warmups: options.warmups,
      iterationsPerSample: options.profileIterations,
    ),
  };
  final interpreter =
      stages['directInterpreterExecuteValues']! as Map<String, Object?>;
  final invoke = stages['publicRuntimeInvoke']! as Map<String, Object?>;
  final lookupAndInvoke =
      stages['lookupAndPublicRuntimeInvoke']! as Map<String, Object?>;
  final interpreterMedian = interpreter['median']! as num;
  final invokeMedian = invoke['median']! as num;
  final combinedMedian = lookupAndInvoke['median']! as num;
  return <String, Object?>{
    'evidence': 'DIRECTIONAL',
    'profileFunction': workload.functionName,
    'profileIterations': options.profileIterations,
    'stages': stages,
    'derivedLayerDeltas': <String, Object?>{
      'evidence': 'DERIVED',
      'publicInvokeMinusDirectInterpreterMedianMicros':
          invokeMedian - interpreterMedian,
      'lookupAndInvokeMinusPublicInvokeMedianMicros':
          combinedMedian - invokeMedian,
    },
    'runtimeCounters': <String, Object?>{
      'patchedArgumentListAllocationsDuringProfile':
          E0PatchRuntime.patchedArgumentListAllocations - beforeAllocations,
      'meaning': 'one increment per public invoke/invokeAsync entry; not heap attribution',
    },
    'unavailable': <String, Object?>{
      'instructionDecode': 'NOT RUN: no public per-opcode timing hook exists in the current runtime.',
      'frameAndValueAllocation':
          'NOT RUN: no public allocation counter or stage hook exists.',
      'budgetAccounting': 'NOT RUN: the profile uses default valid budgets and cannot isolate their checks.',
      'diagnosticSourceMapChecks': 'NOT RUN: no runtime fault was induced and no private diagnostic timing hook exists.',
      'capabilityChecks':
          'NOT RUN: the selected workload has no capability requirement.',
    },
  };
}

Future<Map<String, Object?>> _runStage2Attribution(
  _ApplicationFixture fixture,
  _Options options,
  String startedAtUtc,
) async {
  final workloads = <String, Object?>{};
  for (final workload in _workloads) {
    final program = fixture.programs[workload.functionName]!;
    final expectedChecksum = _repeatFingerprint(
      workload.expected,
      options.iterations,
    );
    final unprofiled = workload.isAsync
        ? await _sampleDirectAsyncInterpreter(
            program,
            workload.arguments,
            workload.expected,
            options,
            profile: false,
          )
        : _sampleDirectSyncInterpreter(
            program,
            workload.arguments,
            workload.expected,
            options,
            profile: false,
          );
    final profiled = workload.isAsync
        ? await _sampleDirectAsyncInterpreter(
            program,
            workload.arguments,
            workload.expected,
            options,
            profile: true,
          )
        : _sampleDirectSyncInterpreter(
            program,
            workload.arguments,
            workload.expected,
            options,
            profile: true,
          );
    final public = workload.isAsync
        ? await _sampleAsync(
            operation: () => _runPatchedAsyncLoop(
              program,
              workload.arguments,
              options.iterations,
              expectedChecksum,
            ),
            samples: options.samples,
            warmups: options.warmups,
            iterationsPerSample: options.iterations,
          )
        : _sampleSync(
            operation: () => _runPatchedSyncLoop(
              program,
              workload.arguments,
              options.iterations,
              expectedChecksum,
            ),
            samples: options.samples,
            warmups: options.warmups,
            iterationsPerSample: options.iterations,
          );
    final offMedian = unprofiled['timing']! as Map<String, Object?>;
    final onMedian = profiled['timing']! as Map<String, Object?>;
    final offMicros = offMedian['median']! as num;
    final onMicros = onMedian['median']! as num;
    final elapsed = profiled['profile']! as Map<String, Object?>;
    final elapsedMicros =
        elapsed['elapsedMicrosPerSample']! as Map<String, num>;
    final outerLoopMicros = elapsedMicros['opcodeDecodeDispatch'] ?? 0;
    final prePostMicros = _sumStageMicros(elapsedMicros, const <String>[
      'argumentBinding',
      'valueAllocationConversion',
      'frameCreation',
      'returnConversion',
    ]);
    final residualMicros = onMicros - outerLoopMicros - prePostMicros;
    final nestedMicros = _sumStageMicros(elapsedMicros, const <String>[
      'capabilityValidation',
      'capabilityCall',
      'asyncContinuationSchedule',
      'asyncContinuationResume',
      'diagnosticSourceMapLookup',
    ]);
    workloads[workload.name] = <String, Object?>{
      'category': workload.category,
      'frequencyClass': workload.frequencyClass,
      'functionName': workload.functionName,
      'async': workload.isAsync,
      'expectedResult': workload.expected,
      'unprofiledDirectInterpreter': unprofiled,
      'profiledDirectInterpreter': profiled,
      'publicInterpretedTotal': public,
      'profilerOverhead': <String, Object?>{
        'evidence': 'DERIVED',
        'medianMultiplier': offMicros == 0 ? null : onMicros / offMicros,
        'medianFraction': offMicros == 0 ? null : (onMicros / offMicros) - 1,
        'unprofiledMedianMicros': offMicros,
        'profiledMedianMicros': onMicros,
      },
      'attribution': <String, Object?>{
        'evidence': 'DERIVED',
        'outerOpcodeLoopMicros': outerLoopMicros,
        'prePostStageMicros': prePostMicros,
        'nestedObservationMicros': nestedMicros,
        'residualMicros': residualMicros,
        'residualFractionOfProfiledMedian': onMicros == 0
            ? null
            : residualMicros / onMicros,
        'methodology': 'opcodeDecodeDispatch is an outer interval. Pre/post stages are summed separately. Nested observations are reported separately and are not added to the outer interval.',
      },
    };
  }
  return <String, Object?>{
    'schemaVersion': 2,
    'benchmark': <String, Object?>{
      'name': 'phase-0b-stage2-private-interpreter-attribution',
      'startedAtUtc': startedAtUtc,
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'samples': options.samples,
      'warmups': options.warmups,
      'iterations': options.iterations,
      'runner': 'dart run benchmarks/phase_1d_performance_benchmark.dart --stage2-attribution',
      'productionPathProfileNull': true,
    },
    'environment': <String, Object?>{
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'processors': Platform.numberOfProcessors,
    },
    'workloads': workloads,
    'decision': 'ATTRIBUTION STILL INSUFFICIENT',
    'decisionBasis': <String>[
      'The opt-in sink now measures function entry, argument/value conversion, frame creation, opcode-loop time, capability validation/call time, async continuation scheduling/resume, return conversion, and fault-path diagnostic hooks.',
      'The sink is not present on production dispatch paths and does not change patch authority or patch bytes when disabled.',
      'The result still cannot attribute Dart source-map lookup, host allocation, AOT guard cost, Flutter frame cost, or per-call site identity; device and release-mode measurements remain required.',
    ],
    'unavailable': <String, Object?>{
      'aotDispatchAndFlutterFrame':
          'NOT RUN: this is a host pure-Dart interpreter benchmark.',
      'sourceMapLookupOnHealthyPath':
          'NOT RUN: no runtime fault is induced by the valid workloads.',
      'heapAllocation': 'NOT RUN: elapsed conversion stages are not heap allocation counters.',
    },
  };
}

Map<String, Object?> _sampleDirectSyncInterpreter(
  E0PatchProgram program,
  List<Object?> arguments,
  Object? expected,
  _Options options, {
  required bool profile,
}) {
  void run(E0InterpreterProfileSink? sink) {
    var checksum = 0;
    for (var index = 0; index < options.iterations; index++) {
      final result = E0Interpreter.executeValues(
        program,
        arguments,
        profile: sink,
      );
      _expectEqual(
        result,
        expected,
        '${program.functionId} attribution result',
      );
      checksum = (checksum + _fingerprint(result)) & 0x7fffffff;
    }
    if (checksum != _repeatFingerprint(expected, options.iterations)) {
      throw StateError('Attribution checksum mismatch');
    }
  }

  for (var index = 0; index < options.warmups; index++) {
    run(profile ? E0InterpreterProfileSink() : null);
  }
  final times = <int>[];
  final profiles = <Map<String, Object?>>[];
  for (var index = 0; index < options.samples; index++) {
    final sink = profile ? E0InterpreterProfileSink() : null;
    final watch = Stopwatch()..start();
    run(sink);
    watch.stop();
    times.add(watch.elapsedMicroseconds);
    if (sink != null) profiles.add(sink.toJson());
  }
  return <String, Object?>{
    'timing': <String, Object?>{
      'unit': 'microseconds',
      'iterationsPerSample': options.iterations,
      ..._statistics(times),
      'samples': times,
    },
    'profile': _aggregateProfileReports(profiles),
  };
}

Future<Map<String, Object?>> _sampleDirectAsyncInterpreter(
  E0PatchProgram program,
  List<Object?> arguments,
  Object? expected,
  _Options options, {
  required bool profile,
}) async {
  Future<void> run(E0InterpreterProfileSink? sink) async {
    var checksum = 0;
    for (var index = 0; index < options.iterations; index++) {
      final result = await E0AsyncInterpreter.execute(
        program,
        arguments,
        profile: sink,
        onRuntimeFault: (_) {},
      );
      _expectEqual(
        result,
        expected,
        '${program.functionId} attribution result',
      );
      checksum = (checksum + _fingerprint(result)) & 0x7fffffff;
    }
    if (checksum != _repeatFingerprint(expected, options.iterations)) {
      throw StateError('Async attribution checksum mismatch');
    }
  }

  for (var index = 0; index < options.warmups; index++) {
    await run(profile ? E0InterpreterProfileSink() : null);
  }
  final times = <int>[];
  final profiles = <Map<String, Object?>>[];
  for (var index = 0; index < options.samples; index++) {
    final sink = profile ? E0InterpreterProfileSink() : null;
    final watch = Stopwatch()..start();
    await run(sink);
    watch.stop();
    times.add(watch.elapsedMicroseconds);
    if (sink != null) profiles.add(sink.toJson());
  }
  return <String, Object?>{
    'timing': <String, Object?>{
      'unit': 'microseconds',
      'iterationsPerSample': options.iterations,
      ..._statistics(times),
      'samples': times,
    },
    'profile': _aggregateProfileReports(profiles),
  };
}

Map<String, Object?> _aggregateProfileReports(
  List<Map<String, Object?>> reports,
) {
  final counts = <String, int>{};
  final elapsed = <String, int>{};
  for (final report in reports) {
    final reportCounts = report['counts']! as Map<String, int>;
    final reportElapsed = report['elapsedMicros']! as Map<String, int>;
    for (final entry in reportCounts.entries) {
      counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
    }
    for (final entry in reportElapsed.entries) {
      elapsed[entry.key] = (elapsed[entry.key] ?? 0) + entry.value;
    }
  }
  final elapsedPerSample = <String, num>{
    for (final entry in elapsed.entries)
      entry.key: reports.isEmpty ? 0 : entry.value / reports.length,
  };
  return <String, Object?>{
    'enabled': reports.isNotEmpty,
    'sampleCount': reports.length,
    'counts': counts,
    'elapsedMicros': elapsed,
    'elapsedMicrosPerSample': elapsedPerSample,
  };
}

num _sumStageMicros(Map<String, num> values, List<String> stages) =>
    stages.fold(0, (sum, stage) => sum + (values[stage] ?? 0));

Future<Map<String, Object?>> _runPatchSizeScaling(_Options options) async {
  final source = _scaleSource(_maxScaleFunctions);
  final transformed = E0SourceTransformer().transform(
    source: source,
    packageName: 'phase1d_scale_fixture',
    logicalLibraryPath: 'lib/scale.dart',
    appId: _applicationId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
  );
  final manifest = transformed.manifest;
  final byName = <String, E0FunctionManifest>{
    for (final function in manifest.functions) function.name: function,
  };
  final names = byName.keys.toList()..sort();
  final tables = _releaseTables(manifest);
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_signingSeed);
  final publicKey = (await keyPair.extractPublicKey()).bytes;
  final scaleReports = <String, Object?>{};
  try {
    for (final count in options.sizeCounts) {
      final selected = [for (final name in names.take(count)) byName[name]!]
        ..sort((left, right) => left.id.compareTo(right.id));
      final raw = <_ScaleMeasurement>[];
      for (var warmup = 0; warmup < options.warmups; warmup++) {
        await _measureScale(
          selected: selected,
          manifest: manifest,
          tables: tables,
          algorithm: algorithm,
          keyPair: keyPair,
          publicKey: publicKey,
          retain: false,
        );
      }
      for (var sample = 0; sample < options.samples; sample++) {
        raw.add(
          await _measureScale(
            selected: selected,
            manifest: manifest,
            tables: tables,
            algorithm: algorithm,
            keyPair: keyPair,
            publicKey: publicKey,
            retain: true,
          ),
        );
      }
      final firstArtifact = raw.first.artifactBytes;
      final artifactDeterministic = raw.every(
        (measurement) => _sameBytes(measurement.artifactBytes, firstArtifact),
      );
      scaleReports['$count'] = <String, Object?>{
        'evidence': 'DERIVED',
        'functionCount': count,
        'selectedSlots': raw.first.selectedSlots,
        'compileMicros': _statistics(
          raw.map((measurement) => measurement.compileMicros).toList(),
        ),
        'artifactBuildMicros': _statistics(
          raw.map((measurement) => measurement.artifactBuildMicros).toList(),
        ),
        'verifyMicros': _statistics(
          raw.map((measurement) => measurement.verifyMicros).toList(),
        ),
        'activationMicros': _statistics(
          raw.map((measurement) => measurement.activationMicros).toList(),
        ),
        'artifactBytes': firstArtifact.length,
        'e0ProgramBytes': raw.first.e0ProgramBytes,
        'bridgePayloadBytes': raw.first.bridgePayloadBytes,
        'releaseManifestBytes': raw.first.releaseManifestBytes,
        'derivedRuntimeMetadataBytes': raw.first.runtimeMetadataBytes,
        'deterministicArtifactBytes': artifactDeterministic,
        'rssSnapshots': <String, Object?>{
          'evidence': 'DIRECTIONAL',
          'beforeBytes': [
            for (final measurement in raw) measurement.rssBeforeBytes,
          ],
          'afterBytes': [
            for (final measurement in raw) measurement.rssAfterBytes,
          ],
          'meaning':
              'whole-process snapshots; not runtime metadata attribution',
        },
        'samples': [for (final measurement in raw) measurement.toJson()],
      };
    }
  } finally {
    keyPair.destroy();
    E0PatchRuntime.reset();
  }
  return <String, Object?>{
    'evidence': 'DERIVED',
    'samples': options.samples,
    'warmups': options.warmups,
    'fixtureFunctionCount': manifest.functions.length,
    'format': 'Patch Format v1 with one E0 container per selected function',
    'counts': scaleReports,
    'unavailable': <String, Object?>{
      'deviceCompileAndActivation':
          'NOT RUN: all compile, verify, and activation timings are host-only.',
      'controllerActivation': 'NOT RUN: the controller and durable lifecycle are intentionally out of scope for this benchmark.',
      'memoryAttribution': 'NOT RUN: only noisy whole-process RSS snapshots and derived serialized metadata byte counts are available.',
    },
  };
}

Future<_ScaleMeasurement> _measureScale({
  required List<E0FunctionManifest> selected,
  required E0ReleaseManifest manifest,
  required _ReleaseTables tables,
  required DartEd25519 algorithm,
  required SimpleKeyPair keyPair,
  required List<int> publicKey,
  required bool retain,
}) async {
  final compileWatch = Stopwatch()..start();
  final programBytesById = <String, Uint8List>{};
  for (final function in selected) {
    programBytesById[function.id] = E0PatchCompiler().compile(
      source: _scalePatchSource(function.name),
      manifest: manifest,
      functionName: function.name,
      patchSequence: 1,
    );
  }
  compileWatch.stop();

  final artifactWatch = Stopwatch()..start();
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _applicationId,
    releaseId: _releaseId,
    patchId: 'phase1d-size-${selected.length}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      for (final function in selected)
        PatchFunctionEntry(
          id: function.id,
          slot: function.slot,
          signatureDigest: 'sha256:${function.signatureDigest}',
        ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('hyfens-e0-bridge-v1')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _signingKeyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(
        type: _bridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode(<String, Object?>{
            'bridgeVersion': 1,
            'encoding': PatchFormatV1E0Bridge.encoding,
            'functions': <String, String>{
              for (final function in selected)
                function.id: base64.encode(programBytesById[function.id]!),
            },
          }),
        ),
      ),
    ],
  );
  final sealed = await PatchFormatV1.sealAsync(draft, (bytes) async {
    return (await algorithm.sign(bytes, keyPair: keyPair)).bytes;
  });
  final artifactBytes = PatchFormatV1.encode(sealed);
  artifactWatch.stop();

  final verifyWatch = Stopwatch()..start();
  final decoded = PatchFormatV1.decode(artifactBytes);
  final valid = await algorithm.verify(
    PatchFormatV1.signingBytes(decoded),
    signature: Signature(
      decoded.signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (!valid) throw StateError('Patch Format v1 signature verification failed');
  final bridge = PatchFormatV1E0Bridge.decode(decoded);
  final programBytes = <List<int>>[];
  for (final function in selected) {
    final bytes = bridge[function.id];
    if (bytes == null)
      throw StateError('Missing bridge bytes for ${function.id}');
    E0PatchContainer.decode(
      bytes,
      expectedAppId: _applicationId,
      expectedReleaseId: _releaseId,
      expectedBuildFingerprint: _buildFingerprint,
      expectedFunctions: tables.functions,
      expectedSignatures: tables.decodedSignatures,
      expectedReceivers: tables.decodedReceivers,
    );
    programBytes.add(bytes);
  }
  verifyWatch.stop();

  E0PatchRuntime.reset();
  final rssBefore = ProcessInfo.currentRss;
  final activationWatch = Stopwatch()..start();
  final installed = E0PatchRuntime.installBatchBytes(
    programBytes,
    appId: _applicationId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
    functions: tables.functions,
    signatures: tables.signatures,
    receivers: tables.receivers,
  );
  activationWatch.stop();
  final rssAfter = ProcessInfo.currentRss;
  if (!installed) {
    throw StateError(
      'Patch batch activation failed: ${E0PatchRuntime.lastRejection}',
    );
  }
  for (final function in selected) {
    if (E0PatchRuntime.lookup(function.slot) == null) {
      throw StateError('Patch batch did not activate slot ${function.slot}');
    }
  }
  final manifestBytes = utf8.encode(manifest.encode()).length;
  final tableBytes = utf8
      .encode(
        jsonEncode(<String, Object?>{
          'functions': tables.functions,
          'signatures': tables.signatures,
          'receivers': tables.receivers,
        }),
      )
      .length;
  final bridgePayloadBytes = decoded.extensions
      .singleWhere((extension) => extension.type == _bridgeExtensionType)
      .payload
      .length;
  return _ScaleMeasurement(
    functionCount: selected.length,
    selectedSlots: <int>[for (final function in selected) function.slot],
    compileMicros: compileWatch.elapsedMicroseconds,
    artifactBuildMicros: artifactWatch.elapsedMicroseconds,
    verifyMicros: verifyWatch.elapsedMicroseconds,
    activationMicros: activationWatch.elapsedMicroseconds,
    artifactBytes: artifactBytes,
    e0ProgramBytes: programBytes.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    ),
    bridgePayloadBytes: bridgePayloadBytes,
    releaseManifestBytes: manifestBytes,
    runtimeMetadataBytes: manifestBytes + tableBytes,
    rssBeforeBytes: rssBefore,
    rssAfterBytes: rssAfter,
    retain: retain,
  );
}

final class _ScaleMeasurement {
  const _ScaleMeasurement({
    required this.functionCount,
    required this.selectedSlots,
    required this.compileMicros,
    required this.artifactBuildMicros,
    required this.verifyMicros,
    required this.activationMicros,
    required this.artifactBytes,
    required this.e0ProgramBytes,
    required this.bridgePayloadBytes,
    required this.releaseManifestBytes,
    required this.runtimeMetadataBytes,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.retain,
  });

  final int functionCount;
  final List<int> selectedSlots;
  final int compileMicros;
  final int artifactBuildMicros;
  final int verifyMicros;
  final int activationMicros;
  final List<int> artifactBytes;
  final int e0ProgramBytes;
  final int bridgePayloadBytes;
  final int releaseManifestBytes;
  final int runtimeMetadataBytes;
  final int rssBeforeBytes;
  final int rssAfterBytes;
  final bool retain;

  Map<String, Object?> toJson() => <String, Object?>{
    'functionCount': functionCount,
    'selectedSlots': selectedSlots,
    'compileMicros': compileMicros,
    'artifactBuildMicros': artifactBuildMicros,
    'verifyMicros': verifyMicros,
    'activationMicros': activationMicros,
    'artifactBytes': artifactBytes.length,
    'e0ProgramBytes': e0ProgramBytes,
    'bridgePayloadBytes': bridgePayloadBytes,
    'releaseManifestBytes': releaseManifestBytes,
    'derivedRuntimeMetadataBytes': runtimeMetadataBytes,
    'rssBeforeBytes': rssBeforeBytes,
    'rssAfterBytes': rssAfterBytes,
    'retainedMeasurement': retain,
  };
}

Future<void> _runSelfCheck() async {
  _expect(_statistics(<int>[1, 2, 3, 4, 5])['median'] == 3, 'median');
  _expect(_statistics(<int>[1, 2, 3, 4, 5])['p95'] == 5, 'p95');
  final fixture = _buildApplicationFixture();
  final pricing = fixture.programs['calculatePrice']!;
  final result = _patchedValue(pricing, <Object?>[540, 7]);
  _expect(result == 3780, 'application patch result');

  final scaleSource = _scaleSource(1);
  final transformed = E0SourceTransformer().transform(
    source: scaleSource,
    packageName: 'phase1d_self_check',
    logicalLibraryPath: 'lib/scale.dart',
    appId: _applicationId,
    releaseId: _releaseId,
    buildFingerprint: _buildFingerprint,
  );
  final function = transformed.manifest.functions.single;
  final tables = _releaseTables(transformed.manifest);
  final programBytes = E0PatchCompiler().compile(
    source: _scalePatchSource(function.name),
    manifest: transformed.manifest,
    functionName: function.name,
  );
  final keyPair = await DartEd25519().newKeyPairFromSeed(_signingSeed);
  try {
    final artifact = await _makeArtifact(
      function: function,
      programBytes: programBytes,
      algorithm: DartEd25519(),
      keyPair: keyPair,
    );
    final decoded = PatchFormatV1.decode(artifact);
    final bridge = PatchFormatV1E0Bridge.decode(decoded);
    _expect(bridge.length == 1, 'bridge function count');
    E0PatchRuntime.reset();
    _expect(
      E0PatchRuntime.installBatchBytes(
        <List<int>>[bridge.values.single],
        appId: _applicationId,
        releaseId: _releaseId,
        buildFingerprint: _buildFingerprint,
        functions: tables.functions,
        signatures: tables.signatures,
        receivers: tables.receivers,
      ),
      'batch install',
    );
  } finally {
    keyPair.destroy();
    E0PatchRuntime.reset();
  }
}

Future<List<int>> _makeArtifact({
  required E0FunctionManifest function,
  required List<int> programBytes,
  required DartEd25519 algorithm,
  required SimpleKeyPair keyPair,
}) async {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _applicationId,
    releaseId: _releaseId,
    patchId: 'phase1d-self-check',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: function.id,
        slot: function.slot,
        signatureDigest: 'sha256:${function.signatureDigest}',
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('hyfens-e0-bridge-v1')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _signingKeyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(
        type: _bridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode(<String, Object?>{
            'bridgeVersion': 1,
            'encoding': PatchFormatV1E0Bridge.encoding,
            'functions': <String, String>{
              function.id: base64.encode(programBytes),
            },
          }),
        ),
      ),
    ],
  );
  final sealed = await PatchFormatV1.sealAsync(draft, (bytes) async {
    return (await algorithm.sign(bytes, keyPair: keyPair)).bytes;
  });
  return PatchFormatV1.encode(sealed);
}

_ReleaseTables _releaseTables(E0ReleaseManifest manifest) => _ReleaseTables(
  functions: <String, int>{
    for (final function in manifest.functions) function.id: function.slot,
  },
  signatures: <String, String>{
    for (final function in manifest.functions)
      function.id: function.signature.encode(),
  },
  receivers: <String, String>{
    for (final function in manifest.functions)
      function.id: function.receiver.encode(),
  },
);

final class _ReleaseTables {
  const _ReleaseTables({
    required this.functions,
    required this.signatures,
    required this.receivers,
  });

  final Map<String, int> functions;
  final Map<String, String> signatures;
  final Map<String, String> receivers;

  Map<String, E0FunctionSignature> get decodedSignatures =>
      <String, E0FunctionSignature>{
        for (final entry in signatures.entries)
          entry.key: E0FunctionSignature.decode(entry.value),
      };

  Map<String, E0ReceiverDescriptor> get decodedReceivers =>
      <String, E0ReceiverDescriptor>{
        for (final entry in receivers.entries)
          entry.key: E0ReceiverDescriptor.decode(entry.value),
      };
}

String _scaleSource(int count) {
  final buffer = StringBuffer();
  for (var index = 0; index < count; index++) {
    buffer
      ..writeln(
        'int phase1dScaleFunction${index.toString().padLeft(2, '0')}(int value) {',
      )
      ..writeln('  return value + ${index + 1};')
      ..writeln('}')
      ..writeln();
  }
  buffer.writeln('void main(List<String> arguments) {}');
  return buffer.toString();
}

String _scalePatchSource(String functionName) {
  final index = int.parse(functionName.substring(functionName.length - 2));
  return 'int $functionName(int value) { return value + ${index + 1}; }';
}

Object? _directValue(_Workload workload) {
  final args = workload.arguments;
  return switch (workload.functionName) {
    'calculatePrice' => _directCalculatePrice(args[0]! as int, args[1]! as int),
    'isEligible' => _directEligibility(
      args[0]! as int,
      args[1]! as bool,
      args[2]! as int,
    ),
    'transformValues' => _directTransform(args[0]! as List<int>),
    'recomputeTotal' => _directRecompute(
      args[0]! as List<int>,
      args[1]! as int,
    ),
    'routeDecision' => _directRoute(args[0]! as bool, args[1]! as bool),
    'boundedAsync' => throw StateError('Async workload passed to sync helper'),
    _ => throw StateError('Unknown workload ${workload.functionName}'),
  };
}

Future<Object?> _directAsyncValue(_Workload workload) async {
  if (workload.functionName != 'boundedAsync') {
    throw StateError('Unknown async workload ${workload.functionName}');
  }
  return _directBoundedAsync(workload.arguments[0]! as int);
}

Object? _patchedValue(E0PatchProgram program, List<Object?> arguments) {
  final result = E0PatchRuntime.invoke(program, arguments);
  if (result.isGuestThrow) result.rethrowGuest();
  if (!result.isSuccess) {
    throw StateError(
      E0PatchRuntime.lastRejection ?? 'patched invocation failed',
    );
  }
  return result.value;
}

Future<Object?> _patchedAsyncValue(
  E0PatchProgram program,
  List<Object?> arguments,
) async {
  final future = E0PatchRuntime.invokeAsync<Object?>(program, arguments);
  if (future == null) {
    throw StateError(E0PatchRuntime.lastRejection ?? 'async invocation failed');
  }
  return future;
}

void _runDirectSyncLoop(
  _Workload workload,
  int iterations,
  int expectedChecksum,
) {
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    checksum = (checksum + _fingerprint(_directValue(workload))) & 0x7fffffff;
  }
  if (checksum != expectedChecksum) {
    throw StateError('Direct workload checksum mismatch for ${workload.name}');
  }
}

void _runPatchedSyncLoop(
  E0PatchProgram program,
  List<Object?> arguments,
  int iterations,
  int expectedChecksum,
) {
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    checksum =
        (checksum + _fingerprint(_patchedValue(program, arguments))) &
        0x7fffffff;
  }
  if (checksum != expectedChecksum) {
    throw StateError('Patched workload checksum mismatch');
  }
}

Future<void> _runDirectAsyncLoop(
  _Workload workload,
  int iterations,
  int expectedChecksum,
) async {
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    checksum =
        (checksum + _fingerprint(await _directAsyncValue(workload))) &
        0x7fffffff;
  }
  if (checksum != expectedChecksum) {
    throw StateError('Direct async workload checksum mismatch');
  }
}

Future<void> _runPatchedAsyncLoop(
  E0PatchProgram program,
  List<Object?> arguments,
  int iterations,
  int expectedChecksum,
) async {
  var checksum = 0;
  for (var index = 0; index < iterations; index++) {
    checksum =
        (checksum +
            _fingerprint(await _patchedAsyncValue(program, arguments))) &
        0x7fffffff;
  }
  if (checksum != expectedChecksum) {
    throw StateError('Patched async workload checksum mismatch');
  }
}

Map<String, Object?> _sampleSync({
  required void Function() operation,
  required int samples,
  required int warmups,
  required int iterationsPerSample,
}) {
  for (var index = 0; index < warmups; index++) {
    operation();
  }
  final values = <int>[];
  for (var index = 0; index < samples; index++) {
    final watch = Stopwatch()..start();
    operation();
    watch.stop();
    values.add(watch.elapsedMicroseconds);
  }
  return <String, Object?>{
    'unit': 'microseconds',
    'iterationsPerSample': iterationsPerSample,
    ..._statistics(values),
    'samples': values,
  };
}

Future<Map<String, Object?>> _sampleAsync({
  required Future<void> Function() operation,
  required int samples,
  required int warmups,
  required int iterationsPerSample,
}) async {
  for (var index = 0; index < warmups; index++) {
    await operation();
  }
  final values = <int>[];
  for (var index = 0; index < samples; index++) {
    final watch = Stopwatch()..start();
    await operation();
    watch.stop();
    values.add(watch.elapsedMicroseconds);
  }
  return <String, Object?>{
    'unit': 'microseconds',
    'iterationsPerSample': iterationsPerSample,
    ..._statistics(values),
    'samples': values,
  };
}

Map<String, num> _statistics(List<int> values) {
  if (values.isEmpty) throw const FormatException('No samples');
  final sorted = values.toList()..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  final deviations = sorted.map((value) => (value - median).abs()).toList()
    ..sort();
  final mad = deviations.length.isOdd
      ? deviations[deviations.length ~/ 2]
      : (deviations[deviations.length ~/ 2 - 1] +
                deviations[deviations.length ~/ 2]) /
            2;
  return <String, num>{
    'median': median,
    'p95': sorted[(sorted.length * 0.95).ceil() - 1],
    'mad': mad,
    'minimum': sorted.first,
    'maximum': sorted.last,
  };
}

int _repeatFingerprint(Object? value, int iterations) =>
    (_fingerprint(value) * iterations) & 0x7fffffff;

int _fingerprint(Object? value) {
  if (value == null) return 0;
  if (value is bool) return value ? 1 : 2;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    var result = 0;
    for (final codeUnit in value.codeUnits) result += codeUnit;
    return result;
  }
  if (value is List<Object?>) {
    var result = 0;
    for (final item in value)
      result = (result + _fingerprint(item)) & 0x7fffffff;
    return result;
  }
  throw StateError('Unsupported benchmark result ${value.runtimeType}');
}

int _directCalculatePrice(int unitPrice, int quantity) {
  var total = unitPrice * quantity;
  if (quantity >= 10) total = total - 50;
  return total;
}

bool _directEligibility(int age, bool verified, int spend) {
  if (age < 18) return false;
  if (!verified) return false;
  return spend >= 100;
}

List<int> _directTransform(List<int> values) {
  final output = <int>[];
  for (final int value in values) {
    if (value > 0) output.add(value * 2);
  }
  return output;
}

int _directRecompute(List<int> values, int threshold) {
  var total = 0;
  for (final int value in values) {
    if (value > threshold) total += value;
  }
  return total;
}

String _directRoute(bool authenticated, bool entitled) {
  if (!authenticated) return '/login';
  if (entitled) return '/offers';
  return '/home';
}

Future<int> _directBoundedAsync(int amount) async => amount + 5;

void _expectEqual(Object? actual, Object? expected, String name) {
  if (actual is List && expected is List) {
    if (actual.length != expected.length ||
        actual.asMap().entries.any(
          (entry) => entry.value != expected[entry.key],
        )) {
      throw StateError('$name: expected $expected, got $actual');
    }
    return;
  }
  if (actual != expected)
    throw StateError('$name: expected $expected, got $actual');
}

void _expect(bool condition, String name) {
  if (!condition) throw StateError('Self-check failed: $name');
}

int _positiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name must be a positive integer');
  }
  return parsed;
}

int _nonNegativeInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw FormatException('$name must be a non-negative integer');
  }
  return parsed;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
