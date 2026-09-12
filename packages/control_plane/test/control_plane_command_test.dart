import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'artifact retention command honors a bounded limit and resumes',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-command-');
      try {
        final firstBytes = <int>[1, 2, 3];
        final secondBytes = <int>[4, 5, 6];
        final first = _artifact(id: 'artifact_command_a', bytes: firstBytes);
        final second = _artifact(id: 'artifact_command_b', bytes: secondBytes);
        final store = FileControlPlaneStore(root);
        await store.initialize();
        await store.putArtifact(first.sha256, firstBytes);
        await store.putArtifact(second.sha256, secondBytes);
        await store.createJson('artifacts', first.id, first.toJson());
        await store.createJson('artifacts', second.id, second.toJson());
        await store.close();

        final limited = await _runCommand(root, <String>[
          '--process-artifact-retention',
          '--artifact-retention-limit',
          '1',
        ]);
        _expectSuccess(limited);
        expect(limited.stdout, contains('artifact_retention_worker_limit=1'));
        expect(
          limited.stdout,
          contains('artifact_retention_worker_considered=1'),
        );
        expect(limited.stdout, contains('artifact_retention_worker_purged=1'));

        var records = await _readArtifacts(root);
        expect(
          records.where((artifact) => artifact.state == artifactPurgedState),
          hasLength(1),
        );
        expect(
          records.where(
            (artifact) => artifact.state == artifactQuarantinedState,
          ),
          hasLength(1),
        );

        final resumed = await _runCommand(root, <String>[
          '--process-artifact-retention',
        ]);
        _expectSuccess(resumed);
        expect(resumed.stdout, contains('artifact_retention_worker_purged=1'));

        records = await _readArtifacts(root);
        expect(
          records.where((artifact) => artifact.state == artifactPurgedState),
          hasLength(2),
        );
        final verification = FileControlPlaneStore(root);
        await verification.initialize();
        try {
          expect(await verification.readArtifact(first.sha256), isNull);
          expect(await verification.readArtifact(second.sha256), isNull);
        } finally {
          await verification.close();
        }

        final replay = await _runCommand(root, <String>[
          '--process-artifact-retention',
        ]);
        _expectSuccess(replay);
        expect(
          replay.stdout,
          contains('artifact_retention_worker_considered=0'),
        );
        expect(replay.stdout, contains('artifact_retention_worker_purged=0'));
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    timeout: Timeout(Duration(minutes: 2)),
  );

  test('artifact retention command fails closed outside Cloud', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-command-mode-');
    try {
      final result = await _runCommand(root, <String>[
        '--process-artifact-retention',
      ], deploymentModel: 'self_hosted');
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('--process-artifact-retention requires a Cloud deployment'),
      );
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('artifact retention command rejects unbounded limits', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-command-limit-');
    try {
      for (final value in <String>['0', '1001', 'not-a-number']) {
        final result = await _runCommand(root, <String>[
          '--process-artifact-retention',
          '--artifact-retention-limit',
          value,
        ]);
        expect(result.exitCode, isNot(0), reason: value);
        expect(
          result.stderr,
          contains(
            '--artifact-retention-limit must be an integer between 1 and 1000',
          ),
          reason: value,
        );
      }
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}

Future<ProcessResult> _runCommand(
  Directory root,
  List<String> arguments, {
  String deploymentModel = 'cloud',
}) {
  final environment = <String, String>{
    ...Platform.environment,
    'HYFENS_DEPLOYMENT_MODEL': deploymentModel,
    'HYFENS_FILE_ROOT': root.path,
  };
  for (final key in const <String>[
    'HYFENS_DATABASE_URL',
    'HYFENS_ARTIFACT_ENDPOINT',
    'HYFENS_ARTIFACT_ACCESS_KEY',
    'HYFENS_ARTIFACT_SECRET_KEY',
    'HYFENS_ARTIFACT_AUTHORIZATION',
    'HYFENS_ARTIFACT_USE_TASK_ROLE',
  ]) {
    environment.remove(key);
  }
  final packageRoot = _packageRoot();
  return Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'bin/control_plane.dart', ...arguments],
    workingDirectory: packageRoot.path,
    environment: environment,
  );
}

Directory _packageRoot() {
  var candidate = Directory.current;
  while (true) {
    if (File(p.join(candidate.path, 'bin', 'control_plane.dart'))
        .existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the control-plane package root');
    }
    candidate = parent;
  }
}

void _expectSuccess(ProcessResult result) {
  expect(
    result.exitCode,
    0,
    reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
  );
}

Future<List<ArtifactRecord>> _readArtifacts(Directory root) async {
  final store = FileControlPlaneStore(root);
  await store.initialize();
  try {
    return (await store.listJson('artifacts'))
        .map(ArtifactRecord.fromJson)
        .toList(growable: false);
  } finally {
    await store.close();
  }
}

ArtifactRecord _artifact({required String id, required List<int> bytes}) {
  return ArtifactRecord(
    id: id,
    organizationId: 'org_command',
    patchId: 'patch_command',
    sha256: sha256Digest(bytes),
    sizeBytes: bytes.length,
    contentType: 'application/octet-stream',
    state: artifactQuarantinedState,
    createdAt: DateTime.utc(2026, 9, 1),
    purgeEligibleAt: DateTime.utc(2026, 9, 2),
  );
}
