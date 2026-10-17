import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:hyfens_control_plane/control_plane.dart' as cp;
import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

const _applicationId = 'com.example.transferred';
const _source = '''
void main() {}

int calculate(int left, int right) {
  return left + right;
}
''';

void main() {
  late Directory root;
  late Directory project;
  late AuthStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyfens-handover-');
    project = Directory('${root.path}/project');
    await Directory('${project.path}/lib').create(recursive: true);
    await File('${project.path}/lib/main.dart').writeAsString(_source);
    await File('${project.path}/pubspec.yaml').writeAsString('''
name: handover_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
    await File('${project.path}/pubspec.lock').writeAsString('packages: {}\n');
    await Directory('${project.path}/.dart_tool').create();
    await File('${project.path}/.dart_tool/package_config.json').writeAsString(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'handover_app',
            'rootUri': project.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
    );
    await Directory('${project.path}/android/app').create(recursive: true);
    await File('${project.path}/android/app/build.gradle').writeAsString(
      'android { defaultConfig { applicationId "$_applicationId" } }\n',
    );
    await File('${project.path}/tool.yaml').writeAsString(
      '# Retain the project-specific policy and formatting.\n'
      '${const ToolConfig(applicationId: _applicationId, exclude: <String>['lib/generated/**', 'lib/ignored/**']).encode()}',
    );
    await ToolStore(
      const ProjectDiscovery().discover(projectPath: project.path),
    ).ensure();
    await writeHyfensBinding(
      File('${project.path}/hyfens.yaml'),
      binding: const HyfensProjectBinding(
        profile: 'original',
        organizationId: 'org_original',
        applicationId: 'app_original',
        environmentId: 'env_original',
        runtimeApplicationId: _applicationId,
      ),
    );
    storage = AuthStorage(root: Directory('${root.path}/auth'));
    await storage.writeNamedProfile(
      CliProfile(
        name: 'recipient',
        endpoint: Uri.parse('https://recipient.example/'),
        managed: false,
        organizationId: 'org_recipient',
        applicationId: 'app_recipient',
        environmentId: 'env_recipient',
      ),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<Map<String, Object?>> run(List<String> arguments) async {
    final outputFile = File('${root.path}/stdout');
    final output = outputFile.openWrite();
    final error = File('${root.path}/stderr').openWrite();
    try {
      await HyfensCommandRunner(
        authStorage: storage,
        out: output,
        err: error,
      ).run(<String>['--project', project.path, ...arguments, '--json']);
    } finally {
      await output.close();
      await error.close();
    }
    return jsonDecode(await outputFile.readAsString()) as Map<String, Object?>;
  }

  test(
    'rebind changes only the account binding and dry-run writes nothing',
    () async {
      await File('${project.path}/.tool/keys/private.key')
          .writeAsString('key sentinel');
      await Directory('${project.path}/.tool/patches/baseline').create();
      await File('${project.path}/.tool/patches/baseline/sequence.json')
          .writeAsString('{"sequence":7}');
      await File('${project.path}/.tool/releases/baseline.json')
          .writeAsString('baseline sentinel');
      final before = await _snapshot(project);

      final plan = await run(<String>['init', '--rebind', '--dry-run']);
      expect(plan['result'], 'REBIND_PLANNED');
      expect(await _snapshot(project), before);
      expect((plan['previousBinding']! as Map)['organization'], 'org_original');
      expect((plan['binding']! as Map)['organization'], 'org_recipient');

      final result = await run(<String>['init', '--rebind']);
      expect(result['result'], 'PROJECT_REBOUND');
      final after = await _snapshot(project);
      expect(after.remove('hyfens.yaml'), isNot(before.remove('hyfens.yaml')));
      expect(after, before);
      final binding = HyfensProjectBinding.load(
        File('${project.path}/hyfens.yaml'),
      )!;
      expect(binding.profile, 'recipient');
      expect(binding.applicationId, 'app_recipient');
      expect(binding.environmentId, 'env_recipient');
      expect(binding.runtimeApplicationId, _applicationId);
    },
  );

  test('rebind refuses a changed platform identity without writing', () async {
    await File('${project.path}/android/app/build.gradle').writeAsString(
      'android { defaultConfig { applicationId "com.example.different" } }\n',
    );
    final before = await _snapshot(project);
    await expectLater(run(<String>['init', '--rebind']), _failure('H1205'));
    expect(await _snapshot(project), before);
  });

  test(
    'rebind requires an initialized project and complete destination',
    () async {
      await storage.writeNamedProfile(
        CliProfile(
          name: 'recipient',
          endpoint: Uri.parse('https://recipient.example/'),
          managed: false,
          organizationId: 'org_recipient',
        ),
      );
      final before = await _snapshot(project);
      await expectLater(run(<String>['init', '--rebind']), _failure('H1207'));
      expect(await _snapshot(project), before);
      await File('${project.path}/hyfens.yaml').delete();
      final uninitialized = await _snapshot(project);
      await expectLater(run(<String>['init', '--rebind']), _failure('H1206'));
      expect(await _snapshot(project), uninitialized);
    },
  );

  test(
    'rebind refuses malformed configuration and force combination',
    () async {
      await File('${project.path}/tool.yaml')
          .writeAsString('version: 1\ninstrumentation: false\n');
      final before = await _snapshot(project);
      await expectLater(run(<String>['init', '--rebind']), _failure('T1203'));
      await expectLater(
        run(<String>['init', '--rebind', '--force']),
        throwsA(isA<UsageException>()),
      );
      expect(await _snapshot(project), before);
    },
  );

  test('recipient deploys its new baseline and receives patches with its own credentials', () async {
    final service = cp.ControlPlaneService(
      store: cp.FileControlPlaneStore(Directory('${root.path}/server')),
    );
    Future<cp.BootstrapResult> provision(String name) => service.bootstrap(
      organizationName: name,
      runtimeApplicationId: _applicationId,
      platformId: 'android-arm64-release',
      environmentName: 'production',
    );
    final original = await provision('Original');
    final recipient = await provision('Recipient');
    final server = await cp.ControlPlaneHttpServer(service).bind();
    addTearDown(() => server.close(force: true));
    final endpoint = Uri.parse('http://127.0.0.1:${server.port}/');
    Future<void> select(String name, cp.BootstrapResult account) async {
      await storage.writeNamedProfile(
        CliProfile(
          name: name,
          endpoint: endpoint,
          managed: false,
          organizationId: account.organization.id,
          applicationId: account.application.id,
          environmentId: account.environment.id,
        ),
      );
      await storage.writeSession(
        AuthSession(accessToken: account.controlCredential.token),
        endpoint: endpoint,
      );
    }

    final tool = HyfensToolchain();
    await tool.generateKeys(projectPath: project.path);
    final originalRelease = await tool.release(
      target: 'android',
      projectPath: project.path,
      metadataOnly: true,
    );
    final source = File('${project.path}/lib/main.dart');
    await source.writeAsString(
      _source.replaceFirst('left + right', 'left - right'),
    );
    await tool.patch(
      projectPath: project.path,
      releaseId: originalRelease.releaseId,
    );
    await select('original', original);
    expect(
      (await run(<String>[
        'deploy',
        '--release',
        originalRelease.releaseId,
      ]))['result'],
      'DEPLOYED',
    );

    await select('recipient', recipient);
    final before = await _snapshot(project);
    await run(<String>['init', '--rebind']);
    final after = await _snapshot(project);
    before.remove('hyfens.yaml');
    after.remove('hyfens.yaml');
    expect(after, before);

    // Model the normal store version increment before the recipient release.
    final pubspec = File('${project.path}/pubspec.yaml');
    await pubspec.writeAsString(
      (await pubspec.readAsString()).replaceFirst('1.0.0+1', '1.0.1+2'),
    );
    await source.writeAsString(_source);
    final release = await tool.release(
      target: 'android',
      projectPath: project.path,
      metadataOnly: true,
    );
    expect(release.applicationId, originalRelease.applicationId);
    expect(release.releaseId, isNot(originalRelease.releaseId));
    await source.writeAsString(
      _source.replaceFirst('left + right', 'left * right'),
    );
    final patch = await tool.patch(
      projectPath: project.path,
      releaseId: release.releaseId,
    );
    final deployed = await run(<String>[
      'deploy',
      '--release',
      release.releaseId,
    ]);
    expect(deployed['result'], 'DEPLOYED');
    expect(deployed['environmentId'], recipient.environment.id);

    final request = cp.UpdateCheckRequest(
      applicationId: recipient.application.id,
      environmentId: recipient.environment.id,
      runtimeApplicationId: _applicationId,
      runtimeReleaseId: release.releaseId,
      runtimeCompatibilityVersion: release.manifest.runtimeCompatibilityVersion,
      patchFormatVersion: release.manifest.patchFormatVersion,
      highWaterSequence: 0,
    );
    final update = await service.updateCheck(
      token: recipient.deliveryCredential.token,
      request: request,
    );
    expect(update.decision, 'PATCH_AVAILABLE');
    final payload = await service.fetchArtifact(
      token: recipient.deliveryCredential.token,
      artifactId: deployed['artifactId']! as String,
      applicationId: recipient.application.id,
      environmentId: recipient.environment.id,
    );
    expect(payload.bytes, await patch.output.readAsBytes());
    await expectLater(
      service.updateCheck(
        token: original.deliveryCredential.token,
        request: request,
      ),
      throwsA(
        isA<cp.ControlPlaneException>().having(
          (error) => error.statusCode,
          'status',
          404,
        ),
      ),
    );
    await storage.writeSession(
      AuthSession(accessToken: original.controlCredential.token),
      endpoint: endpoint,
    );
    await expectLater(
      run(<String>['deploy', '--release', release.releaseId]),
      _failure('NOT_FOUND'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Matcher _failure(String code) => throwsA(
  isA<ToolFailure>().having(
    (error) => error.diagnostics.single.code,
    'code',
    code,
  ),
);

Future<Map<String, List<int>>> _snapshot(Directory directory) async {
  final files = <String, List<int>>{};
  await for (final entry in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entry is File) {
      files[entry.path.substring(directory.path.length + 1)] = await entry
          .readAsBytes();
    }
  }
  return files;
}
