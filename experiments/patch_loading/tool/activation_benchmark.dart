import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';

const _samples = 15;
const _warmups = 2;
const _seed = 22082603;

Future<void> main(List<String> arguments) async {
  final runStartedAtUtc = DateTime.now().toUtc().toIso8601String();
  final outputPath = arguments.isEmpty
      ? '../instrumentation/tool/performance/results/task22-activation-raw.json'
      : arguments.single;
  final root = Directory.current.absolute;
  final scratch = Directory('${root.path}/.dart_tool/task22_activation');
  final lockFile = File('${root.path}/.dart_tool/task22_activation.lock')
    ..createSync(recursive: true);
  final lock = lockFile.openSync(mode: FileMode.write);
  try {
    lock.lockSync(FileLock.exclusive);
  } on FileSystemException {
    lock.closeSync();
    stderr.writeln('Task 22 activation output root is already locked');
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
    final instrumentationRoot = Directory(
      '${root.parent.path}/instrumentation',
    );
    final releaseFile = File(
      '${instrumentationRoot.path}/fixture/performance_app.dart',
    );
    final patchSourceFile = File(
      '${instrumentationRoot.path}/fixture/performance_hot_patch.dart',
    );
    final releaseSource = releaseFile.readAsStringSync();
    final transformed = E0SourceTransformer().transform(
      source: releaseSource,
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/performance_app.dart',
      appId: 'dev.hyfens.instrumentation-performance',
      releaseId: 'task22-host-aot-1',
      buildFingerprint: 'task22-host-aot-build-1',
    );
    final patchBytes = E0PatchCompiler().compile(
      source: patchSourceFile.readAsStringSync(),
      manifest: transformed.manifest,
      functionName: 'hotLeaf',
    );
    final patchFile = File('${scratch.path}/hot.e0.json')
      ..writeAsBytesSync(patchBytes);
    final seed = List<int>.generate(32, (index) => index + 1);
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final envelopeBytes = await E1SignedPatchEnvelope.sign(
      patchBytes: patchBytes,
      keyId: 'task22-key',
      privateKeySeed: seed,
    );
    final envelopeFile = File('${scratch.path}/hot.e1.signed.json')
      ..writeAsBytesSync(envelopeBytes);
    final executable = File('${scratch.path}/activation_worker');
    final build = await _compile(executable);
    final manifest = transformed.manifest;
    final functions = <String, int>{
      for (final function in manifest.functions) function.id: function.slot,
    };
    final signatures = <String, String>{
      for (final function in manifest.functions)
        function.id: function.signature.encode(),
    };
    final receivers = <String, String>{
      for (final function in manifest.functions)
        function.id: function.receiver.encode(),
    };
    final decodedProgram = E0PatchContainer.decode(
      patchBytes,
      expectedAppId: manifest.appId,
      expectedReleaseId: manifest.releaseId,
      expectedBuildFingerprint: manifest.buildFingerprint,
      expectedFunctions: functions,
      expectedSignatures: <String, E0FunctionSignature>{
        for (final function in manifest.functions)
          function.id: function.signature,
      },
      expectedReceivers: <String, E0ReceiverDescriptor>{
        for (final function in manifest.functions)
          function.id: function.receiver,
      },
    );
    final commonArguments = <String>[
      '--envelope=${envelopeFile.path}',
      '--patch=${patchFile.path}',
      '--public-key=${base64.encode(publicKey.bytes)}',
      '--app-id=${manifest.appId}',
      '--release-id=${manifest.releaseId}',
      '--build-fingerprint=${manifest.buildFingerprint}',
      '--functions=${jsonEncode(functions)}',
      '--signatures=${jsonEncode(signatures)}',
      '--receivers=${jsonEncode(receivers)}',
    ];
    const stages = <String>[
      'read',
      'framing',
      'ed25519Verify',
      'containerDecode',
      'runtimeInstall',
      'fullActivation',
    ];
    final expectedChecksums = <String, int>{
      'read': envelopeBytes.length,
      'framing': patchBytes.length,
      'ed25519Verify': patchBytes.length,
      'containerDecode': decodedProgram.code.length,
      'runtimeInstall': patchBytes.length,
      'fullActivation': envelopeBytes.length,
    };
    for (final stage in stages) {
      for (var index = 0; index < _warmups; index++) {
        await _run(
          executable,
          stage,
          commonArguments,
          expectedChecksums[stage]!,
        );
      }
    }
    final raw = <String, List<Map<String, Object?>>>{
      for (final stage in stages) stage: <Map<String, Object?>>[],
    };
    final order = <Map<String, Object>>[];
    final random = Random(_seed);
    for (var round = 0; round < _samples; round++) {
      final shuffled = stages.toList()..shuffle(random);
      order.add(<String, Object>{'round': round, 'stages': shuffled});
      for (final stage in shuffled) {
        final output = await _run(
          executable,
          stage,
          commonArguments,
          expectedChecksums[stage]!,
        );
        raw[stage]!.add(<String, Object?>{'round': round, ...output});
      }
    }
    final result = <String, Object?>{
      'schemaVersion': 2,
      'protocol': '../instrumentation/tool/performance/PROTOCOL.md',
      'protocolAmendment': 'Amendment 1 — provenance-hardened replacement run',
      'startedAtUtc': runStartedAtUtc,
      'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'environment': await _environment(),
      'configuration': <String, Object>{
        'samples': _samples,
        'warmups': _warmups,
        'randomSeed': _seed,
        'processIsolated': true,
        'workerMode': 'Dart AOT executable',
      },
      'sampleOrder': order,
      'build': build,
      'expectedChecksums': expectedChecksums,
      'stages': <String, Object?>{
        for (final stage in stages) stage: _summary(raw[stage]!),
      },
      'artifacts': <String, Object>{
        'patch': _artifact(patchFile),
        'signedEnvelope': _artifact(envelopeFile),
        'workerExecutable': _artifact(executable),
      },
      'sourceArtifacts': _sourceArtifacts(root, instrumentationRoot),
      'limitations': <String>[
        'Each stage is timed inside a fresh AOT process; process startup is excluded.',
        'runtimeInstall includes container decode plus atomic slot publication because the runtime exposes no verified-program publish API.',
        'fullActivation covers signature verification and runtime install, but not controller filesystem persistence or health-state transitions.',
      ],
    };
    final output = File(outputPath)..createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    keyPair.destroy();
  } finally {
    lock.unlockSync();
    lock.closeSync();
  }
}

Future<Map<String, Object?>> _compile(File output) async {
  final arguments = <String>[
    'compile',
    'exe',
    'tool/performance_activation_worker.dart',
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

Future<Map<String, Object?>> _run(
  File executable,
  String stage,
  List<String> commonArguments,
  int expectedChecksum,
) async {
  final arguments = <String>['--stage=$stage', ...commonArguments];
  final startedAtUtc = DateTime.now().toUtc().toIso8601String();
  final result = await Process.run(executable.path, arguments);
  final completedAtUtc = DateTime.now().toUtc().toIso8601String();
  if (result.exitCode != 0) {
    throw ProcessException(
      executable.path,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final decoded = jsonDecode((result.stdout as String).trim());
  if (decoded is! Map<String, Object?> ||
      decoded['stage'] != stage ||
      decoded['elapsedMicros'] is! int ||
      decoded['checksum'] != expectedChecksum) {
    throw StateError('Invalid $stage output: ${result.stdout}');
  }
  return <String, Object?>{
    ...decoded,
    'process': _processRecord(
      executable.path,
      arguments,
      result.exitCode,
      startedAtUtc,
      completedAtUtc,
    ),
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> samples) {
  final values =
      samples.map((sample) => sample['elapsedMicros']! as int).toList()..sort();
  final median = _median(values);
  final deviations = values.map((value) => (value - median).abs()).toList()
    ..sort();
  return <String, Object?>{
    'medianElapsedMicros': median,
    'p95ElapsedMicros': values[(0.95 * values.length).ceil() - 1],
    'madElapsedMicros': _median(deviations),
    'minimumElapsedMicros': values.first,
    'maximumElapsedMicros': values.last,
    'samples': samples,
  };
}

num _median(List<num> sorted) {
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

Map<String, Object> _artifact(File file) => <String, Object>{
  'path': file.path,
  'bytes': file.lengthSync(),
  'sha256': sha256.convert(file.readAsBytesSync()).toString(),
};

List<Map<String, Object>> _sourceArtifacts(
  Directory root,
  Directory instrumentationRoot,
) {
  final files = <File>[
    File('${root.path}/tool/activation_benchmark.dart'),
    File('${root.path}/tool/performance_activation_worker.dart'),
    File('${root.path}/pubspec.yaml'),
    File('${root.path}/pubspec.lock'),
    File('${root.path}/.dart_tool/package_config.json'),
    File('${instrumentationRoot.path}/fixture/performance_app.dart'),
    File('${instrumentationRoot.path}/fixture/performance_hot_patch.dart'),
    File('${instrumentationRoot.path}/pubspec.yaml'),
    File('${instrumentationRoot.path}/pubspec.lock'),
    File('${instrumentationRoot.path}/.dart_tool/package_config.json'),
    ...Directory('${root.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
    ...Directory('${instrumentationRoot.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ]..sort((left, right) => left.path.compareTo(right.path));
  if (files.any((file) => !file.existsSync())) {
    throw StateError('A declared activation source artifact is missing');
  }
  return files.map(_artifact).toList(growable: false);
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
      .where((line) => !line.contains('activation_benchmark.dart'))
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
