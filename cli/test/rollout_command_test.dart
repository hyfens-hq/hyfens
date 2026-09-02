import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

const _internalHashOne =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _internalHashTwo =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test('rollout command is registered with exactly three subcommands', () {
    final runner = HyfensCommandRunner();
    final rollout = runner.commands['rollout'];
    expect(rollout, isNotNull);
    final output = rollout!.usage;
    expect(output, contains('create'));
    expect(output, contains('inspect'));
    expect(output, contains('transition'));
    expect(output, isNot(contains('deploy')));
  });

  test(
    'rollout commands send the exact request boundary and redact human output',
    () async {
      final requests = <_CapturedRequest>[];
      final server = await HttpServer.bind('127.0.0.1', 0);
      final subscription = server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        final source = utf8.decode(bytes);
        final body = source.isEmpty ? null : jsonDecode(source);
        requests.add(
          _CapturedRequest(
            method: request.method,
            path: request.uri.path,
            organizationId: request.uri.queryParameters['organization_id'],
            authorization: request.headers.value('authorization'),
            idempotencyKey: request.headers.value('idempotency-key'),
            body: body,
          ),
        );
        final responseBody =
            request.method == 'POST' && request.uri.path == '/v1/rollouts'
            ? _snapshot(state: 'DRAFT', revision: 1, currentRevision: 1)
            : request.method == 'GET'
            ? _snapshot(state: 'DRAFT', revision: 1, currentRevision: 1)
            : _snapshot(state: 'READY', revision: 2, currentRevision: 2);
        final encoded = utf8.encode(jsonEncode(responseBody));
        request.response
          ..statusCode =
              request.method == 'POST' && request.uri.path == '/v1/rollouts'
              ? 201
              : 200
          ..headers.contentType = ContentType.json
          ..headers.contentLength = encoded.length
          ..add(encoded);
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final endpoint = 'http://127.0.0.1:${server.port}';
      const token = 'rollout-cli-secret';
      const organizationId = 'org_cli';
      final create = await _runTool(<String>[
        'rollout',
        'create',
        '--endpoint',
        endpoint,
        '--token',
        token,
        '--organization-id',
        organizationId,
        '--application-id',
        'app_cli',
        '--environment-id',
        'env_cli',
        '--platform-id',
        'plt_android',
        '--release-id',
        'rel_cli',
        '--patch-id',
        'pat_cli',
        '--percentage-basis-points',
        '0',
        '--cohort-kind',
        'internal',
        '--internal-installation-hash',
        _internalHashOne,
        '--internal-installation-hash',
        _internalHashTwo,
        '--idempotency-key',
        'cli-create-key',
        '--json',
      ]);
      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final createResponse = _snapshot(
        state: 'DRAFT',
        revision: 1,
        currentRevision: 1,
      );
      expect(jsonDecode(create.stdout.toString()), createResponse);

      final inspect = await _runTool(<String>[
        'rollout',
        'inspect',
        '--endpoint',
        endpoint,
        '--token',
        token,
        '--organization-id',
        organizationId,
        '--rollout-id',
        'rol_cli',
        '--json',
      ]);
      expect(
        inspect.exitCode,
        0,
        reason: '${inspect.stdout}\n${inspect.stderr}',
      );
      expect(jsonDecode(inspect.stdout.toString()), createResponse);

      final transition = await _runTool(<String>[
        'rollout',
        'transition',
        '--endpoint',
        endpoint,
        '--token',
        token,
        '--organization-id',
        organizationId,
        '--rollout-id',
        'rol_cli',
        '--action',
        'ready',
        '--expected-revision',
        '1',
        '--reason',
        'stage internal rollout',
        '--idempotency-key',
        'cli-transition-key',
      ]);
      expect(
        transition.exitCode,
        0,
        reason: '${transition.stdout}\n${transition.stderr}',
      );
      final humanOutput = transition.stdout.toString();
      expect(humanOutput, contains('Rollout ID: rol_cli'));
      expect(humanOutput, contains('State:      READY'));
      expect(humanOutput, contains('Revision:   2'));
      expect(humanOutput, contains('Target:'));
      expect(humanOutput, contains('Policy:'));
      expect(humanOutput, isNot(contains(token)));
      expect(humanOutput, isNot(contains(_internalHashOne)));

      expect(requests, hasLength(3));
      expect(requests[0].method, 'POST');
      expect(requests[0].path, '/v1/rollouts');
      expect(requests[0].authorization, 'Bearer $token');
      expect(requests[0].idempotencyKey, 'cli-create-key');
      expect(requests[0].body, <String, Object?>{
        'organization_id': organizationId,
        'application_id': 'app_cli',
        'environment_id': 'env_cli',
        'platform_id': 'plt_android',
        'release_id': 'rel_cli',
        'patch_id': 'pat_cli',
        'percentage_basis_points': 0,
        'cohort_kind': 'internal',
        'internal_installation_hashes': <String>[
          _internalHashOne,
          _internalHashTwo,
        ],
      });
      expect(requests[1].method, 'GET');
      expect(requests[1].path, '/v1/rollouts/rol_cli');
      expect(requests[1].organizationId, organizationId);
      expect(requests[1].authorization, 'Bearer $token');
      expect(requests[1].idempotencyKey, isNull);
      expect(requests[2].method, 'POST');
      expect(requests[2].path, '/v1/rollouts/rol_cli/actions');
      expect(requests[2].authorization, 'Bearer $token');
      expect(requests[2].idempotencyKey, 'cli-transition-key');
      expect(requests[2].body, <String, Object?>{
        'action': 'ready',
        'expected_revision': 1,
        'reason': 'stage internal rollout',
        'organization_id': organizationId,
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('rollout uses one unambiguous stored profile session', () async {
    final storageRoot = await Directory.systemTemp.createTemp(
      'hyfens-rollout-auth-',
    );
    final outputRoot = await Directory.systemTemp.createTemp(
      'hyfens-rollout-output-',
    );
    addTearDown(() async {
      await storageRoot.delete(recursive: true);
      await outputRoot.delete(recursive: true);
    });
    final server = await HttpServer.bind('127.0.0.1', 0);
    final requests = <_CapturedRequest>[];
    final subscription = server.listen((request) async {
      requests.add(
        _CapturedRequest(
          method: request.method,
          path: request.uri.path,
          organizationId: request.uri.queryParameters['organization_id'],
          authorization: request.headers.value('authorization'),
          idempotencyKey: request.headers.value('idempotency-key'),
          body: null,
        ),
      );
      final encoded = utf8.encode('{}');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..headers.contentLength = encoded.length
        ..add(encoded);
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    final storage = AuthStorage(root: storageRoot);
    await storage.writeProfile(
      Profile(
        endpoint: endpoint,
        profiles: const <ProfileScope>[
          ProfileScope(
            name: 'demo',
            organizationId: 'org_cli',
            applicationId: 'app_cli',
            environmentId: 'env_cli',
            role: 'owner',
          ),
        ],
      ),
    );
    await storage.writeSession(
      const AuthSession(
        accessToken: 'stored-control-access',
        sessionToken: 'stored-session',
      ),
    );
    final stdoutFile = File('${outputRoot.path}/stdout');
    final stderrFile = File('${outputRoot.path}/stderr');
    final stdout = stdoutFile.openWrite();
    final stderr = stderrFile.openWrite();
    try {
      await HyfensCommandRunner(
        authStorage: storage,
        out: stdout,
        err: stderr,
      ).run(<String>[
        'rollout',
        'inspect',
        '--rollout-id',
        'rol_cli',
        '--json',
      ]);

      final explicitStdout = File('${outputRoot.path}/explicit-stdout')
          .openWrite();
      final explicitStderr = File('${outputRoot.path}/explicit-stderr')
          .openWrite();
      try {
        await HyfensCommandRunner(
          authStorage: storage,
          out: explicitStdout,
          err: explicitStderr,
        ).run(<String>[
          'rollout',
          'inspect',
          '--rollout-id',
          'rol_cli',
          '--token',
          'explicit-control-token',
          '--json',
        ]);
      } finally {
        await explicitStdout.close();
        await explicitStderr.close();
      }
    } finally {
      await stdout.close();
      await stderr.close();
    }
    expect(requests, hasLength(2));
    expect(requests[0].path, '/v1/rollouts/rol_cli');
    expect(requests[0].organizationId, 'org_cli');
    expect(requests[0].authorization, 'Bearer stored-control-access');
    expect(requests[1].path, '/v1/rollouts/rol_cli');
    expect(requests[1].authorization, 'Bearer explicit-control-token');
  });
}

Future<ProcessResult> _runTool(List<String> arguments) {
  final current = Directory.current;
  final workingDirectory = File('${current.path}/bin/tool.dart').existsSync()
      ? current.path
      : '${current.path}/cli';
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/tool.dart',
    ...arguments,
  ], workingDirectory: workingDirectory);
}

Map<String, Object?> _snapshot({
  required String state,
  required int revision,
  required int currentRevision,
}) => <String, Object?>{
  'rollout': <String, Object?>{
    'id': 'rol_cli',
    'organizationId': 'org_cli',
    'currentRevision': currentRevision,
    'state': state,
    'createdAt': '2026-08-28T00:00:00.000Z',
  },
  'revision': <String, Object?>{
    'id': 'rvr_cli_$revision',
    'rolloutId': 'rol_cli',
    'organizationId': 'org_cli',
    'revision': revision,
    'previousRevision': revision == 1 ? null : revision - 1,
    'state': state,
    'target': <String, Object?>{
      'organizationId': 'org_cli',
      'applicationId': 'app_cli',
      'environmentId': 'env_cli',
      'platformId': 'plt_android',
      'releaseId': 'rel_cli',
      'runtimeReleaseId': 'runtime-rel-cli',
      'patchId': 'pat_cli',
      'runtimePatchId': 'runtime-pat-cli',
      'artifactId': 'art_cli',
      'sha256': 'sha256:${'0' * 64}',
      'sequence': 1,
    },
    'policy': <String, Object?>{
      'cohortKind': 'internal',
      'percentageBasisPoints': 0,
      'salt': 'private-salt',
      'internalInstallationHashes': <String>[
        _internalHashOne,
        _internalHashTwo,
      ],
      'exposureMode': 'deterministic_re_evaluate',
    },
    'actorId': 'cred_cli',
    'reason': revision == 1 ? 'created' : 'stage internal rollout',
    'pausedFromState': null,
    'createdAt': '2026-08-28T00:00:00.000Z',
  },
  'history': <Object?>[],
  'request_id': 'server-request',
};

final class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.organizationId,
    required this.authorization,
    required this.idempotencyKey,
    required this.body,
  });

  final String method;
  final String path;
  final String? organizationId;
  final String? authorization;
  final String? idempotencyKey;
  final Object? body;
}
