import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:patch_loading_e1/src/key_lifecycle.dart';

const _authoritySeed = <int>[
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
final _oldPatchSeed = List<int>.filled(32, 0x21);
final _newPatchSeed = List<int>.filled(32, 0x42);
final _recoverySeed = List<int>.filled(32, 0x63);

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.write(_usage);
    return;
  }
  _assertPackageInvocation();

  final startedAt = DateTime.now().toUtc();
  final initial = await _initialState();
  final addCommand = await _addCommand(initial);
  final addCommandBytes = addCommand.encodeBytes();
  final restoredState = await initial.apply(addCommandBytes);
  final startupStateBytes = initial.encodeBytes();
  final startupCommandBytes = addCommandBytes.length;
  final artifact = E1VerifiedArtifactIdentity(
    keyId: 'new-patch',
    sequence: 1,
    digest: 'a' * 64,
  );
  final initialLedger = E1ArtifactReplayLedger.empty(
    releaseId: initial.releaseId,
  );
  final acceptedLedger = initialLedger
      .admitNewArtifact(lifecycle: restoredState, artifact: artifact)
      .ledger;

  final startup = await _sampleAsync(
    name: 'startupRestoreAndCommandApply',
    description: 'Decode a checksummed lifecycle snapshot and verify/apply one signed rotation command.',
    options: options,
    operation: () async {
      final decoded = E1KeyLifecycleState.decode(startupStateBytes);
      final applied = await decoded.apply(addCommandBytes);
      if (applied.stateDigest != restoredState.stateDigest) {
        throw StateError(
          'Startup lifecycle state digest changed across restore',
        );
      }
    },
  );

  final dispatch = _sampleSync(
    name: 'dispatchAdmission',
    description: 'Post-verification key-state and high-water admission checks for a repeated dispatch candidate.',
    options: options,
    operation: () {
      var admitted = 0;
      for (var index = 0; index < options.dispatchIterations; index++) {
        final decision = acceptedLedger.admitNewArtifact(
          lifecycle: restoredState,
          artifact: artifact,
        );
        if (decision.status == E1ArtifactAdmissionStatus.idempotent) {
          admitted++;
        }
      }
      if (admitted != options.dispatchIterations) {
        throw StateError('Dispatch admission did not remain idempotent');
      }
    },
  );

  final metadata = _sampleSync(
    name: 'metadataSerialization',
    description: 'Canonical lifecycle and bounded artifact-ledger metadata serialization.',
    options: options,
    operation: () {
      final stateBytes = restoredState.encodeBytes();
      final ledgerBytes = utf8.encode(acceptedLedger.canonicalJson);
      if (stateBytes.isEmpty || ledgerBytes.isEmpty) {
        throw StateError('Lifecycle metadata unexpectedly serialized empty');
      }
    },
  );

  final report = <String, Object?>{
    'schemaVersion': 1,
    'benchmark': <String, Object?>{
      'name': 'phase-1c-key-lifecycle-host',
      'startedAtUtc': startedAt.toIso8601String(),
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'samples': options.samples,
      'warmups': options.warmups,
      'dispatchIterations': options.dispatchIterations,
      'runner': 'dart run --packages=.dart_tool/package_config.json ../../benchmarks/phase_1c_runtime_benchmark.dart',
      'timing':
          'host wall-clock synchronous/asynchronous Dart model operations',
    },
    'environment': <String, Object?>{
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'processors': Platform.numberOfProcessors,
      'hostProcessRssBytes': <String, Object?>{
        'after': ProcessInfo.currentRss,
        'meaning':
            'process snapshot only; not an attribution to lifecycle metadata',
      },
    },
    'fixture': <String, Object?>{
      'applicationId': initial.applicationId,
      'releaseId': initial.releaseId,
      'initialKeyCount': initial.keys.length,
      'rotatedKeyCount': restoredState.keys.length,
      'rememberedArtifactCount': acceptedLedger.artifacts.length,
      'startupStateBytes': startupStateBytes.length,
      'rotationCommandBytes': startupCommandBytes,
      'restoredStateBytes': restoredState.encodeBytes().length,
      'artifactLedgerMetadataBytes': acceptedLedger.metadataBytes,
      'maxKeys': E1KeyLifecycleLimits.maxKeys,
      'maxRememberedArtifacts': E1KeyLifecycleLimits.maxRememberedArtifacts,
    },
    'stages': <String, Object?>{
      'startupRestoreAndCommandApply': startup,
      'dispatchAdmission': dispatch,
      'metadataSerialization': metadata,
    },
    'unavailable': <String, Object?>{
      'physicalAndroid': 'No Android device startup, dispatch, RSS/PSS, frame-time, or thermal measurement was performed by this host benchmark.',
      'physicalIos': 'No iOS device startup, dispatch, RSS/PSS, frame-time, or thermal measurement was performed by this host benchmark.',
      'flutterEngineAttribution': 'The benchmark does not initialize Flutter or measure engine first-frame behavior.',
      'networkAndFilesystem': 'No network delivery or durable filesystem fault-injection timing is included.',
    },
    'limitations': <String>[
      'The lifecycle model is a pure Dart standalone policy seam; existing E1 signature/runtime verification remains outside these timings.',
      'Dispatch samples repeat an idempotent candidate to isolate admission overhead; they do not represent a Flutter frame or a full controller queue.',
      'Process RSS is a noisy whole-process snapshot and is not a memory delta for this model.',
      'Use the same SDK family, host class, sample count, and warmup policy for comparisons.',
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

const _usage = '''Usage: dart run --packages=.dart_tool/package_config.json ../../benchmarks/phase_1c_runtime_benchmark.dart [options]

Runs the bounded key-lifecycle model on the host. Run it from
experiments/patch_loading so the package's pinned cryptography dependency is
used. No Flutter project, device, network, or checked-in file is modified.

Options:
  --samples=N                 Timed samples per stage (default: 5)
  --warmups=N                 Untimed warmups per stage (default: 1)
  --dispatch-iterations=N     Repeated admission checks per dispatch sample (default: 10000)
  --output=PATH               Write JSON to PATH instead of stdout
  --help                      Show this help
''';

final class _Options {
  const _Options({
    required this.samples,
    required this.warmups,
    required this.dispatchIterations,
    required this.outputPath,
    required this.help,
  });

  final int samples;
  final int warmups;
  final int dispatchIterations;
  final String? outputPath;
  final bool help;

  factory _Options.parse(List<String> arguments) {
    var samples = 5;
    var warmups = 1;
    var dispatchIterations = 10000;
    String? outputPath;
    var help = false;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
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
      } else if (argument.startsWith('--dispatch-iterations=')) {
        dispatchIterations = _positiveInt(
          argument.substring('--dispatch-iterations='.length),
          'dispatch-iterations',
        );
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
      dispatchIterations: dispatchIterations,
      outputPath: outputPath,
      help: help,
    );
  }
}

Future<Map<String, Object?>> _sampleAsync({
  required String name,
  required String description,
  required _Options options,
  required Future<void> Function() operation,
}) async {
  for (var index = 0; index < options.warmups; index++) {
    await operation();
  }
  final samples = <int>[];
  for (var index = 0; index < options.samples; index++) {
    final timer = Stopwatch()..start();
    await operation();
    timer.stop();
    samples.add(timer.elapsedMicroseconds);
  }
  return <String, Object?>{
    'name': name,
    'description': description,
    'unit': 'microseconds',
    'warmups': options.warmups,
    'summary': _summary(samples),
    'samples': samples,
  };
}

Map<String, Object?> _sampleSync({
  required String name,
  required String description,
  required _Options options,
  required void Function() operation,
}) {
  for (var index = 0; index < options.warmups; index++) {
    operation();
  }
  final samples = <int>[];
  for (var index = 0; index < options.samples; index++) {
    final timer = Stopwatch()..start();
    operation();
    timer.stop();
    samples.add(timer.elapsedMicroseconds);
  }
  return <String, Object?>{
    'name': name,
    'description': description,
    'unit': 'microseconds',
    'warmups': options.warmups,
    'summary': _summary(samples),
    'samples': samples,
  };
}

Map<String, Object?> _summary(List<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    throw StateError('Cannot summarize zero samples');
  }
  final p95Index = max(0, (sorted.length * 0.95).ceil() - 1);
  return <String, Object?>{
    'count': sorted.length,
    'median': sorted[sorted.length ~/ 2],
    'p95': sorted[p95Index],
    'minimum': sorted.first,
    'maximum': sorted.last,
    'mean': sorted.reduce((left, right) => left + right) / sorted.length,
  };
}

int _positiveInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name must be positive');
  }
  return parsed;
}

int _nonNegativeInt(String value, String name) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw FormatException('$name must be non-negative');
  }
  return parsed;
}

void _assertPackageInvocation() {
  final packageConfig = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  if (!packageConfig.existsSync()) {
    throw StateError(
      'Run from experiments/patch_loading after dart pub get: ${Directory.current.path}',
    );
  }
}

Future<E1KeyLifecycleState> _initialState() async =>
    E1KeyLifecycleState.initial(
      applicationId: 'dev.hyfens.app',
      releaseId: 'android-arm64-release',
      keys: <E1ReleaseKey>[
        await _releaseKey('authority', _authoritySeed, const {
          E1ReleaseKeyRole.authority,
          E1ReleaseKeyRole.patch,
          E1ReleaseKeyRole.rollback,
        }),
        await _releaseKey('old-patch', _oldPatchSeed, const {
          E1ReleaseKeyRole.patch,
          E1ReleaseKeyRole.rollback,
        }),
        await _releaseKey('recovery', _recoverySeed, const {
          E1ReleaseKeyRole.recovery,
        }),
      ],
    );

Future<E1KeyLifecycleCommand> _addCommand(E1KeyLifecycleState state) async =>
    E1KeyLifecycleCommand.sign(
      applicationId: state.applicationId,
      releaseId: state.releaseId,
      commandSequence: state.commandSequence + 1,
      previousStateDigest: state.stateDigest,
      operation: E1KeyLifecycleOperation.add,
      signerKeyId: 'authority',
      newKeyId: 'new-patch',
      newPublicKey: await _publicKey(_newPatchSeed),
      newRoles: const {E1ReleaseKeyRole.patch, E1ReleaseKeyRole.rollback},
      signer: (message) => _sign(_authoritySeed, message),
    );

Future<E1ReleaseKey> _releaseKey(
  String keyId,
  List<int> seed,
  Set<E1ReleaseKeyRole> roles,
) async => E1ReleaseKey(
  keyId: keyId,
  publicKeyBytes: await _publicKey(seed),
  roles: roles,
);

Future<List<int>> _publicKey(List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    return (await pair.extractPublicKey()).bytes;
  } finally {
    pair.destroy();
  }
}

Future<List<int>> _sign(List<int> seed, List<int> message) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  try {
    return (await DartEd25519().sign(message, keyPair: pair)).bytes;
  } finally {
    pair.destroy();
  }
}
