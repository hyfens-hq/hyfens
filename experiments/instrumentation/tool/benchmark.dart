import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 5000000 : int.parse(arguments.single);
  final root = Directory.current;
  final scratch = Directory('${root.path}/.dart_tool/e0_benchmark');
  if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  scratch.createSync(recursive: true);
  final fixture = File('${root.path}/fixture/release_app.dart');
  final originalHash = _hash(fixture.readAsBytesSync());
  E0OverlayBuilder(E0SourceTransformer()).build(
    input: fixture,
    outputDirectory: scratch,
    packageName: 'instrumentation_fixture',
    logicalLibraryPath: 'lib/app.dart',
    appId: 'dev.hyfens.instrumentation-e0',
    releaseId: 'release-1',
    buildFingerprint: 'benchmark-build-1',
  );
  final manifest = E0ReleaseManifest.decode(
    File('${scratch.path}/manifest.json').readAsStringSync(),
  );
  final patch = E0PatchCompiler().compile(
    source: File('${root.path}/fixture/patch_app.dart').readAsStringSync(),
    manifest: manifest,
    functionName: 'calculate',
  );
  final patchFile = File('${scratch.path}/patch.e0.json')
    ..writeAsBytesSync(patch);
  if (_hash(fixture.readAsBytesSync()) != originalHash) {
    throw StateError('Original fixture changed');
  }
  final baseline = File('${scratch.path}/baseline');
  final instrumented = File('${scratch.path}/instrumented');
  await _run(<String>['compile', 'exe', fixture.path, '-o', baseline.path]);
  await _run(<String>[
    'compile',
    'exe',
    '${scratch.path}/app.dart',
    '-o',
    instrumented.path,
  ]);
  // Warm each executable once before recording seven process-isolated samples.
  await _execute(baseline.path, iterations, null);
  await _execute(instrumented.path, iterations, null);
  await _execute(instrumented.path, iterations, patchFile.path);
  final variants = <String, Map<String, Object>>{};
  for (final entry in <String, (String, String?)>{
    'baseline': (baseline.path, null),
    'instrumentedUnpatched': (instrumented.path, null),
    'patchedInterpreted': (instrumented.path, patchFile.path),
  }.entries) {
    final samples = <int>[];
    String lastOutput = '';
    for (var index = 0; index < 7; index++) {
      final result = await _execute(entry.value.$1, iterations, entry.value.$2);
      samples.add(result.$1);
      lastOutput = result.$2;
    }
    samples.sort();
    variants[entry.key] = <String, Object>{
      'medianElapsedMicros': samples[samples.length ~/ 2],
      'samplesElapsedMicros': samples,
      'lastOutput': lastOutput,
    };
  }
  final result = <String, Object>{
    'dartVersion': Platform.version.split(' ').take(4).join(' '),
    'os': Platform.operatingSystem,
    'architecture': Platform.version.contains('arm64') ? 'arm64' : 'unknown',
    'iterations': iterations,
    'baselineBytes': baseline.lengthSync(),
    'instrumentedBytes': instrumented.lengthSync(),
    'patchBytes': patch.length,
    'originalSha256': originalHash,
    'variants': variants,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}

Future<void> _run(List<String> arguments) async {
  final result = await Process.run(Platform.resolvedExecutable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

Future<(int, String)> _execute(
  String executable,
  int iterations,
  String? patch,
) async {
  final arguments = <String>[
    '--iterations=$iterations',
    if (patch != null) '--e0-patch=$patch',
  ];
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  final output = (result.stdout as String).trim();
  final match = RegExp(r'elapsedMicros=(\d+)').firstMatch(output);
  if (match == null) throw StateError('Missing timing: $output');
  return (int.parse(match.group(1)!), output);
}

String _hash(List<int> bytes) {
  return sha256.convert(bytes).toString();
}
