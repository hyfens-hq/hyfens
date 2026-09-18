import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test(
    'hyfens executable exposes canonical help and version identity',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final help = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/hyfens.dart',
        '--help',
      ], workingDirectory: Directory.current.path);
      expect(help.exitCode, 0, reason: '${help.stdout}\n${help.stderr}');
      expect(help.stdout.toString(), contains('Usage: hyfens'));
      expect(help.stdout.toString(), contains('profile'));
      expect(help.stdout.toString(), contains('login'));

      final version = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/hyfens.dart',
        '--version',
      ], workingDirectory: Directory.current.path);
      expect(
        version.exitCode,
        0,
        reason: '${version.stdout}\n${version.stderr}',
      );
      expect(version.stdout.toString().trim(), startsWith('hyfens '));
    },
  );

  test(
    'tool executable exposes a stable version command',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/tool.dart',
        '--version',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout.toString().trim(), startsWith('0.1.0-phase1c.'));
      expect(
        result.stderr.toString().trim(),
        endsWith('tool is deprecated; use hyfens'),
      );
    },
  );

  test(
    'mcp announces startup on stderr and leaves stdout for protocol traffic',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        'bin/hyfens.dart',
        'mcp',
      ], workingDirectory: Directory.current.path);
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exit = await process.exitCode;

      expect(exit, 0, reason: '$stdout\n$stderr');
      expect(stdout, isEmpty);
      expect(stderr, contains(hyfensMcpStartupMessage));
    },
  );

  test(
    'tool deploy is registered without persisting credentials',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/tool.dart',
        'deploy',
        '--help',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout.toString(), contains('self-hosted control plane'));
      expect(result.stdout.toString(), contains('--token'));
      expect(result.stdout.toString(), contains('--ca-cert'));
    },
  );

  test(
    'hyfens patch rejects an unsupported platform selector',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/hyfens.dart',
        'patch',
        'web',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, 64, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr.toString(),
        contains('patch accepts only android or ios'),
      );
    },
  );
}
