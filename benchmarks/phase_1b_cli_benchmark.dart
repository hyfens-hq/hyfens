import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _fixtureRelativePath = 'fixtures/flutter_toolchain_app';
const _cliRelativePath = 'cli/bin/tool.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.write(_usage);
    return;
  }

  final repo = Directory.current.absolute;
  final fixture = Directory(_join(repo.path, _fixtureRelativePath));
  final cli = File(_join(repo.path, _cliRelativePath));
  if (!fixture.existsSync() || !cli.existsSync()) {
    throw StateError(
      'Run this benchmark from the repository root: ${repo.path}',
    );
  }

  final runStartedAtUtc = DateTime.now().toUtc().toIso8601String();
  final temporaryProject = await Directory.systemTemp.createTemp(
    'hyfens-phase1b-cli-',
  );
  String? finalPatchPath;
  try {
    await _copyDirectory(
      fixture,
      temporaryProject,
      skip: const {'.tool', 'build'},
    );
    final preparation = <String, Object?>{};
    if (!options.skipPubGet) {
      preparation['pubGet'] = (await _runProcess('flutter', const [
        'pub',
        'get',
      ], workingDirectory: temporaryProject)).toJson(includeOutput: false);
    } else {
      preparation['pubGet'] = <String, Object?>{'status': 'SKIPPED'};
    }

    final environment = await _environment();
    final stages = <String, Object?>{};

    final doctor = await _sampleJsonStage(
      name: 'discoveryDoctor',
      description:
          'Public doctor boundary: project discovery plus environment checks.',
      command: const ['doctor'],
      project: temporaryProject,
      options: options,
    );
    stages['discoveryDoctor'] = doctor.toJson();

    final keyGeneration = await _runToolJson(const [
      'keys',
      'generate',
    ], project: temporaryProject);
    final key = keyGeneration.json;

    final coldRelease = await _runToolJson(const [
      'release',
      'android',
      '--metadata-only',
    ], project: temporaryProject);
    final releaseId = _requiredString(coldRelease.json, 'releaseId');
    final releaseMetadata = await _sampleJsonStage(
      name: 'releaseMetadataWarm',
      description: 'Idempotent metadata-only Android release baseline.',
      command: const ['release', 'android', '--metadata-only'],
      project: temporaryProject,
      options: options,
    );
    stages['releaseMetadata'] = <String, Object?>{
      'cold': coldRelease.toJson(),
      'warm': releaseMetadata.toJson(),
      'releaseId': releaseId,
    };

    final mainFile = File(_join(temporaryProject.path, 'lib/main.dart'));
    _applyPatchableFixtureChange(mainFile);

    final analyze = await _sampleJsonStage(
      name: 'analyze',
      description: 'Public change analysis against the metadata-only release.',
      command: <String>['analyze', '--release', releaseId],
      project: temporaryProject,
      options: options,
    );
    stages['analyze'] = analyze.toJson();

    final patch = await _sampleJsonStage(
      name: 'patch',
      description: 'Public compile/format/sign/self-verify patch path.',
      command: <String>['patch', '--release', releaseId],
      project: temporaryProject,
      options: options,
      onSample: (run) {
        finalPatchPath = _requiredString(run.json, 'output');
      },
    );
    stages['patch'] = patch.toJson();

    final patchPath = finalPatchPath;
    if (patchPath == null) {
      throw StateError('Patch benchmark produced no artifact path');
    }

    final format = await _sampleTextStage(
      name: 'formatInspection',
      description: 'Public inspect boundary: Patch Format v1 decode/display re-encoding.',
      command: <String>['inspect', patchPath],
      project: temporaryProject,
      options: options,
      expectedText: 'Patch Format v1',
    );
    stages['formatInspection'] = format.toJson();

    final verify = await _sampleJsonStage(
      name: 'verify',
      description:
          'Public digest/signature/release compatibility verification.',
      command: <String>['verify', patchPath, '--release', releaseId],
      project: temporaryProject,
      options: options,
    );
    stages['verify'] = verify.toJson();

    final result = <String, Object?>{
      'schemaVersion': 1,
      'benchmark': <String, Object?>{
        'name': 'phase-1b-cli-public-boundary',
        'startedAtUtc': runStartedAtUtc,
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'samples': options.samples,
        'warmups': options.warmups,
        'fixture': _fixtureRelativePath,
        'commandRunner': 'dart run cli/bin/tool.dart',
        'timing':
            'host wall-clock process duration, including dart run startup',
      },
      'environment': environment,
      'preparation': preparation,
      'keyGeneration': <String, Object?>{
        'status': 'PREPARATION_ONLY',
        'result': key['result'],
        'keyId': key['keyId'],
      },
      'stages': stages,
      'unavailable': <String, Object?>{
        'standaloneSign': 'The public CLI exposes signing only inside tool patch; no standalone sign command exists.',
        'flutterBuild': 'This run measures release metadata only. No Flutter APK/IPA build timing is included.',
        'physicalDevice': 'No Android/iOS device runtime, network delivery, activation, or memory measurement is included.',
        'adjacentSdk': 'No adjacent Flutter/Dart SDK installation was selected for this run; see the compatibility report.',
      },
      'limitations': <String>[
        'Samples run in one temporary copy of the fixture; patch samples intentionally advance the local patch sequence.',
        'The process boundary includes Dart CLI startup and excludes no subprocess work performed by the public command.',
        'Wall-clock values are host measurements, not device or end-user latency budgets.',
        'No RSS, CPU-counter, thermal, network, or filesystem-cache normalization is attempted.',
      ],
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(result);
    if (options.outputPath == null) {
      stdout.writeln(encoded);
    } else {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString('$encoded\n');
      stdout.writeln('Wrote ${output.absolute.path}');
    }
    if (options.keepWorkspace) {
      stdout.writeln('Temporary project retained at ${temporaryProject.path}');
      finalPatchPath = null;
    }
  } finally {
    if (!options.keepWorkspace && temporaryProject.existsSync()) {
      await temporaryProject.delete(recursive: true);
    }
  }
}

const _usage =
    '''Usage: dart run benchmarks/phase_1b_cli_benchmark.dart [options]

Runs public Phase 1B CLI commands against a temporary copy of the Flutter
toolchain fixture. The benchmark never writes the checked-in fixture.

Options:
  --samples=N       Timed samples per warm stage (default: 7)
  --warmups=N       Untimed warmups per stage (default: 1)
  --output=PATH     Write the JSON report to PATH instead of stdout
  --skip-pub-get    Reuse the copied fixture package configuration
  --keep-workspace  Retain the temporary project for inspection
  --help            Show this help
''';

final class _Options {
  const _Options({
    required this.samples,
    required this.warmups,
    required this.outputPath,
    required this.skipPubGet,
    required this.keepWorkspace,
    required this.help,
  });

  final int samples;
  final int warmups;
  final String? outputPath;
  final bool skipPubGet;
  final bool keepWorkspace;
  final bool help;

  factory _Options.parse(List<String> arguments) {
    var samples = 7;
    var warmups = 1;
    String? outputPath;
    var skipPubGet = false;
    var keepWorkspace = false;
    var help = false;
    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--skip-pub-get') {
        skipPubGet = true;
      } else if (argument == '--keep-workspace') {
        keepWorkspace = true;
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
      } else if (argument.startsWith('--output=')) {
        outputPath = argument.substring('--output='.length);
        if (outputPath.isEmpty) throw FormatException('output path is empty');
      } else {
        throw FormatException('Unknown option: $argument');
      }
    }
    return _Options(
      samples: samples,
      warmups: warmups,
      outputPath: outputPath,
      skipPubGet: skipPubGet,
      keepWorkspace: keepWorkspace,
      help: help,
    );
  }
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

final class _ProcessRun {
  const _ProcessRun({
    required this.executable,
    required this.arguments,
    required this.exitCode,
    required this.elapsedMicros,
    required this.stdout,
    required this.stderr,
  });

  final String executable;
  final List<String> arguments;
  final int exitCode;
  final int elapsedMicros;
  final String stdout;
  final String stderr;

  Map<String, Object?> toJson({required bool includeOutput}) =>
      <String, Object?>{
        'executable': executable,
        'arguments': arguments,
        'exitCode': exitCode,
        'elapsedMicros': elapsedMicros,
        if (includeOutput) 'stdout': stdout,
        if (includeOutput) 'stderr': stderr,
      };
}

Future<_ProcessRun> _runProcess(
  String executable,
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  final timer = Stopwatch()..start();
  late final ProcessResult result;
  try {
    result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
    );
  } on Object catch (error) {
    timer.stop();
    throw StateError(
      'Failed to run $executable ${arguments.join(' ')}: $error',
    );
  }
  timer.stop();
  return _ProcessRun(
    executable: executable,
    arguments: List.unmodifiable(arguments),
    exitCode: result.exitCode,
    elapsedMicros: timer.elapsedMicroseconds,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  );
}

Future<_ToolRun> _runToolJson(
  List<String> command, {
  required Directory project,
}) async {
  final args = <String>[
    'run',
    _cliRelativePath,
    ...command,
    '--json',
    '--project',
    project.path,
  ];
  final process = await _runProcess(
    Platform.resolvedExecutable,
    args,
    workingDirectory: Directory.current.absolute,
  );
  if (process.exitCode != 0) {
    throw StateError(_failureText(process));
  }
  final output = process.stdout.trim();
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw StateError('Expected JSON object from ${command.join(' ')}: $output');
  }
  return _ToolRun(process: process, json: decoded);
}

Future<_ToolRun> _runToolText(
  List<String> command, {
  required Directory project,
}) async {
  final args = <String>[...command, '--project', project.path];
  final process = await _runProcess(Platform.resolvedExecutable, <String>[
    'run',
    _cliRelativePath,
    ...args,
  ], workingDirectory: Directory.current.absolute);
  if (process.exitCode != 0) {
    throw StateError(_failureText(process));
  }
  return _ToolRun(process: process, json: const <String, Object?>{});
}

String _failureText(_ProcessRun process) =>
    '${process.executable} ${process.arguments.join(' ')} exited ${process.exitCode}\n'
    '${process.stdout}\n${process.stderr}';

final class _ToolRun {
  const _ToolRun({required this.process, required this.json});

  final _ProcessRun process;
  final Map<String, Object?> json;

  Map<String, Object?> toJson() => <String, Object?>{
    'elapsedMicros': process.elapsedMicros,
    'exitCode': process.exitCode,
    'stdoutBytes': utf8.encode(process.stdout).length,
    'stderrBytes': utf8.encode(process.stderr).length,
  };
}

final class _StageResult {
  _StageResult({
    required this.name,
    required this.description,
    required this.command,
    required this.samples,
    required this.warmups,
  });

  final String name;
  final String description;
  final List<_ToolRun> samples;
  final List<String> command;
  final int warmups;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'command': command,
    'warmups': warmups,
    'summary': _summary(samples.map((sample) => sample.process.elapsedMicros)),
    'samples': [for (final sample in samples) sample.toJson()],
  };
}

Future<_StageResult> _sampleJsonStage({
  required String name,
  required String description,
  required List<String> command,
  required Directory project,
  required _Options options,
  void Function(_ToolRun run)? onSample,
}) async {
  for (var index = 0; index < options.warmups; index++) {
    final run = await _runToolJson(command, project: project);
    onSample?.call(run);
  }
  final samples = <_ToolRun>[];
  for (var index = 0; index < options.samples; index++) {
    final run = await _runToolJson(command, project: project);
    samples.add(run);
    onSample?.call(run);
  }
  return _StageResult(
    name: name,
    description: description,
    command: command,
    samples: samples,
    warmups: options.warmups,
  );
}

Future<_StageResult> _sampleTextStage({
  required String name,
  required String description,
  required List<String> command,
  required Directory project,
  required _Options options,
  required String expectedText,
}) async {
  Future<_ToolRun> run() async {
    final result = await _runToolText(command, project: project);
    if (!result.process.stdout.contains(expectedText)) {
      throw StateError(
        'Expected "$expectedText" from ${command.join(' ')}:\n'
        '${result.process.stdout}',
      );
    }
    return result;
  }

  for (var index = 0; index < options.warmups; index++) {
    await run();
  }
  final samples = <_ToolRun>[];
  for (var index = 0; index < options.samples; index++) {
    samples.add(await run());
  }
  return _StageResult(
    name: name,
    description: description,
    command: command,
    samples: samples,
    warmups: options.warmups,
  );
}

Map<String, Object?> _summary(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw StateError('Cannot summarize zero samples');
  final median = sorted[sorted.length ~/ 2];
  final p95Index = max(0, (sorted.length * 0.95).ceil() - 1);
  final mean = sorted.reduce((left, right) => left + right) / sorted.length;
  return <String, Object?>{
    'unit': 'microseconds',
    'median': median,
    'p95': sorted[p95Index],
    'minimum': sorted.first,
    'maximum': sorted.last,
    'mean': mean,
    'count': sorted.length,
  };
}

String _requiredString(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String || result.isEmpty) {
    throw StateError('Expected non-empty string field "$key": $value');
  }
  return result;
}

void _applyPatchableFixtureChange(File mainFile) {
  final source = mainFile.readAsStringSync();
  const before = '''int displayCount(int value) {
  return value;
}''';
  const after = '''int displayCount(int value) {
  return value + 1;
}''';
  if (!source.contains(before)) {
    throw StateError(
      'Fixture displayCount body no longer matches benchmark input',
    );
  }
  mainFile.writeAsStringSync(source.replaceFirst(before, after));
}

Future<void> _copyDirectory(
  Directory source,
  Directory destination, {
  required Set<String> skip,
}) async {
  await destination.create(recursive: true);
  final entries = source.listSync(followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entity in entries) {
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
    if (skip.contains(name)) continue;
    final target = FileSystemEntity.typeSync(entity.path, followLinks: false);
    final destinationPath = _join(destination.path, name);
    if (target == FileSystemEntityType.directory) {
      await _copyDirectory(
        Directory(entity.path),
        Directory(destinationPath),
        skip: skip,
      );
    } else if (target == FileSystemEntityType.file) {
      await File(entity.path).copy(destinationPath);
    } else {
      throw StateError('Unsupported fixture entry: ${entity.path}');
    }
  }
}

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) return '$left$right';
  return '$left${Platform.pathSeparator}$right';
}

Future<Map<String, Object?>> _environment() async {
  final flutter = await _runProcess('flutter', const [
    '--version',
  ], workingDirectory: Directory.current.absolute);
  final dart = await _runProcess(Platform.resolvedExecutable, const [
    '--version',
  ], workingDirectory: Directory.current.absolute);
  final uname = await _runProcess('uname', const [
    '-m',
  ], workingDirectory: Directory.current.absolute);
  return <String, Object?>{
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'architecture': uname.stdout.trim(),
    'dartExecutable': Platform.resolvedExecutable,
    'dartVersionOutput': dart.stdout.trim().isEmpty
        ? dart.stderr.trim()
        : dart.stdout.trim(),
    'flutterVersionOutput': flutter.stdout.trim(),
    'flutterExecutable': (await _which('flutter')) ?? 'unresolved',
    'workingDirectory': Directory.current.absolute.path,
  };
}

Future<String?> _which(String executable) async {
  final result = await Process.run('which', <String>[executable]);
  if (result.exitCode != 0) return null;
  final value = result.stdout.toString().trim();
  return value.isEmpty ? null : value;
}
