import 'dart:convert';
import 'dart:io';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

Future<Directory> createServerProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-server-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create();
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: server_app
version: 1.0.0
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
  await File('${root.path}/pubspec.lock').writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left + right;
}
''');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'server_app',
          'rootUri': root.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  return root;
}

void main() {
  test(
    'local server exposes health and refuses non-loopback binding',
    () async {
      final root = await createServerProject();
      addTearDown(() => root.delete(recursive: true));
      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final service = PatchDevelopmentServer(project: project);
      final bound = await service.bind(port: 0);
      final subscription = bound.listen(service.handleRequest);
      addTearDown(() async {
        await subscription.cancel();
        await bound.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${bound.port}/health'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(body), <String, Object?>{
        'result': 'READY',
        'service': 'hyfens-local-patch-server',
      });
      expect(
        () => service.bind(host: '0.0.0.0', port: 0),
        throwsA(isA<ToolFailure>()),
      );
    },
  );

  test('local server returns an exact-release patch artifact', () async {
    final root = await createServerProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    await tool.generateKeys(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left - right;
}
''');
    final patch = await tool.patch(
      projectPath: root.path,
      releaseId: release.releaseId,
    );
    final service = PatchDevelopmentServer(
      project: const ProjectDiscovery().discover(projectPath: root.path),
      releaseId: release.releaseId,
    );
    final bound = await service.bind(port: 0);
    final subscription = bound.listen(service.handleRequest);
    addTearDown(() async {
      await subscription.cancel();
      await bound.close(force: true);
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final checkRequest = await client.getUrl(
      Uri.http('127.0.0.1:${bound.port}', '/v1/check', <String, String>{
        'release': release.releaseId,
        'sequence': '0',
      }),
    );
    final checkResponse = await checkRequest.close();
    expect(checkResponse.statusCode, HttpStatus.ok);
    expect(
      jsonDecode(await checkResponse.transform(utf8.decoder).join()),
      <String, Object?>{
        'formatVersion': patchFormatV1,
        'patchId': patch.artifact.patchId,
        'result': 'PATCH_AVAILABLE',
        'releaseId': release.releaseId,
        'runtimeVersion': patchFormatRuntimeCompatibilityV1,
        'sequence': 1,
      },
    );

    final patchRequest = await client.getUrl(
      Uri.http('127.0.0.1:${bound.port}', '/v1/patch', <String, String>{
        'release': release.releaseId,
      }),
    );
    final patchResponse = await patchRequest.close();
    expect(patchResponse.statusCode, HttpStatus.ok);
    expect(
      await patchResponse.fold<List<int>>(<int>[], (all, chunk) {
        all.addAll(chunk);
        return all;
      }),
      patch.output.readAsBytesSync(),
    );
  });

  test(
    'local server serves only a trusted release-bound rollback control',
    () async {
      final root = await createServerProject();
      addTearDown(() => root.delete(recursive: true));
      final tool = HyfensToolchain();
      await tool.init(projectPath: root.path);
      await tool.generateKeys(projectPath: root.path);
      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final store = ToolStore(project);
      final config = ToolConfig.load(project.configFile);
      final privateKey = const KeyStore().readPrivate(
        store.resolveConfiguredPath(config.privateKeyPath, allowExternal: true),
      );
      await store.patchDirectory(release.releaseId).create(recursive: true);
      final control = await RollbackControlCommand.sign(
        applicationId: release.applicationId,
        releaseId: release.releaseId,
        highWaterSequence: 0,
        highWaterDigest: null,
        keyId: privateKey.keyId,
        signer: privateKey.sign,
      );
      await store
          .rollbackControl(release.releaseId)
          .writeAsString(control.encode());

      final service = PatchDevelopmentServer(
        project: project,
        releaseId: release.releaseId,
      );
      final bound = await service.bind(port: 0);
      final subscription = bound.listen(service.handleRequest);
      addTearDown(() async {
        await subscription.cancel();
        await bound.close(force: true);
      });
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.http('127.0.0.1:${bound.port}', '/v1/control', <String, String>{
          'release': release.releaseId,
        }),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      expect(await response.transform(utf8.decoder).join(), control.encode());

      await store.rollbackControl(release.releaseId).writeAsString('{}');
      final rejectedRequest = await client.getUrl(
        Uri.http('127.0.0.1:${bound.port}', '/v1/control', <String, String>{
          'release': release.releaseId,
        }),
      );
      final rejectedResponse = await rejectedRequest.close();
      expect(rejectedResponse.statusCode, HttpStatus.noContent);
    },
  );
}
