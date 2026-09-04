import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

const _publicCommandPaths = <List<String>>[
  <String>['version'],
  <String>['doctor'],
  <String>['status'],
  <String>['mcp'],
  <String>['login'],
  <String>['logout'],
  <String>['profile'],
  <String>['profile', 'list'],
  <String>['profile', 'show'],
  <String>['profile', 'use'],
  <String>['profile', 'remove'],
  <String>['profile', 'current'],
  <String>['auth'],
  <String>['auth', 'login'],
  <String>['auth', 'status'],
  <String>['auth', 'logout'],
  <String>['init'],
  <String>['analyze'],
  <String>['release'],
  <String>['patch'],
  <String>['rollback'],
  <String>['cleanup'],
  <String>['inspect'],
  <String>['verify'],
  <String>['keys'],
  <String>['keys', 'generate'],
  <String>['keys', 'inspect'],
  <String>['serve'],
  <String>['deploy'],
  <String>['rollout'],
  <String>['rollout', 'create'],
  <String>['rollout', 'inspect'],
  <String>['rollout', 'transition'],
  <String>['bundle'],
  <String>['bundle', 'export'],
  <String>['bundle', 'verify'],
  <String>['bundle', 'import'],
  <String>['bundle', 'admit'],
];

void main() {
  test('canonical root help aliases share one usage surface', () async {
    final results = <_CliResult>[];
    for (final arguments in const <List<String>>[
      <String>['--help'],
      <String>['-h'],
      <String>['help'],
    ]) {
      results.add(await _runCli(arguments));
    }

    for (final result in results) {
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, isEmpty);
      expect(result.stdout, contains('Usage: hyfens'));
      expect(result.stdout, contains('version'));
      expect(result.stdout, contains('profile'));
      expect(result.stdout, contains('mcp'));
      expect(result.stdout, contains('Examples:'));
      expect(result.stdout, contains('Documentation:'));
    }
    expect(results[1].stdout, results[0].stdout);
    expect(results[2].stdout, results[0].stdout);
  });

  test('MCP help explains the stdio and profile contract', () async {
    final result = await _runCli(const <String>['mcp', '--help']);

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stderr, isEmpty);
    expect(result.stdout, contains('stdio'));
    expect(result.stdout, contains('--profile'));
    expect(result.stdout, contains('--debug'));
    expect(result.stdout, contains('active host-bound profile'));
    expect(result.stdout, contains('hyfens login'));
    expect(result.stdout, contains('stderr'));
  });

  group('command-level help', () {
    for (final path in _publicCommandPaths) {
      final name = path.join(' ');
      test('prints help for $name', () async {
        final result = await _runCli(<String>[...path, '--help']);

        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stderr, isEmpty);
        expect(result.stdout, contains('Usage: hyfens $name'));
      });
    }
  });

  test(
    'version flag, short flag, and command share canonical output',
    () async {
      for (final arguments in const <List<String>>[
        <String>['--version'],
        <String>['-v'],
        <String>['version'],
      ]) {
        final result = await _runCli(arguments);

        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stderr, isEmpty);
        expect(result.stdout.trim(), 'hyfens $hyfensToolVersion');
      }
    },
  );

  test('release and patch help expose flavor entrypoint options', () async {
    final release = await _runCli(const <String>['release', '--help']);
    final patch = await _runCli(const <String>['patch', '--help']);

    expect(release.exitCode, 0, reason: release.stderr);
    expect(release.stdout, contains('--flavor'));
    expect(release.stdout, contains('--entrypoint'));
    expect(patch.exitCode, 0, reason: patch.stderr);
    expect(patch.stdout, contains('--flavor'));
    expect(patch.stdout, contains('--entrypoint'));
  });

  test(
    'unknown command suggests a close match and fails with usage status',
    () async {
      final result = await _runCli(const <String>['statuz']);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        contains('Could not find a command named "statuz"'),
      );
      expect(result.stderr, contains('Did you mean one of these?'));
      expect(result.stderr, contains('status'));
    },
  );

  test(
    'deprecated tool delegates help and version to the shared runner',
    () async {
      final rootHelp = await _runCli(const <String>[
        '--help',
      ], deprecatedToolShim: true);
      expect(rootHelp.exitCode, 0, reason: rootHelp.stderr);
      expect(rootHelp.stdout, contains('Usage: hyfens'));
      expect(rootHelp.stdout, contains('mcp'));
      expect(rootHelp.stderr, 'tool is deprecated; use hyfens\n');

      final help = await _runCli(const <String>[
        'help',
        'status',
      ], deprecatedToolShim: true);
      expect(help.exitCode, 0, reason: help.stderr);
      expect(help.stdout, contains('Usage: hyfens status'));
      expect(help.stdout.split('Usage:').length - 1, 1);
      expect(help.stderr, 'tool is deprecated; use hyfens\n');

      final version = await _runCli(const <String>[
        'version',
      ], deprecatedToolShim: true);
      expect(version.exitCode, 0, reason: version.stderr);
      expect(version.stdout.trim(), hyfensToolVersion);
      expect(version.stderr, 'tool is deprecated; use hyfens\n');
    },
  );
}

final class _CliResult {
  const _CliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<_CliResult> _runCli(
  List<String> arguments, {
  bool deprecatedToolShim = false,
}) async {
  final directory = await Directory.systemTemp.createTemp('hyfens-cli-help-');
  final stdoutFile = File('${directory.path}/stdout');
  final stderrFile = File('${directory.path}/stderr');
  final output = stdoutFile.openWrite();
  final errors = stderrFile.openWrite();
  final previousExitCode = exitCode;
  var resultExitCode = 0;
  exitCode = 0;
  try {
    await runHyfensCli(
      arguments,
      deprecatedToolShim: deprecatedToolShim,
      out: output,
      err: errors,
    );
    resultExitCode = exitCode;
  } finally {
    exitCode = previousExitCode;
    await output.close();
    await errors.close();
  }
  try {
    return _CliResult(
      exitCode: resultExitCode,
      stdout: await stdoutFile.readAsString(),
      stderr: await stderrFile.readAsString(),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
