import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

Future<Directory> _createProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-mcp-project-');
  await Directory('${root.path}/lib').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: mcp_sample
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
  await File('${root.path}/lib/main.dart').writeAsString('void main() {}\n');
  return root;
}

class _Harness {
  _Harness({required this.server, required this.input, required this.lines});

  final HyfensMcpServer server;
  final StreamController<List<int>> input;
  final StreamIterator<String> lines;

  Future<Map<String, Object?>> request(
    int id,
    String method, {
    Map<String, Object?>? params,
  }) async {
    final message = <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };
    input.add(utf8.encode(jsonEncode(message) + '\n'));
    expect(await lines.moveNext(), isTrue);
    final value = jsonDecode(lines.current);
    return (value as Map).cast<String, Object?>();
  }

  void notify(String method, {Map<String, Object?>? params}) {
    input.add(
      utf8.encode(
        jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'method': method,
              if (params != null) 'params': params,
            }) +
            '\n',
      ),
    );
  }

  Future<void> close() async {
    if (server.isActive) await input.close();
    await server.done.timeout(const Duration(seconds: 5));
    await lines.cancel();
  }
}

Future<_Harness> _createHarness({String? profileName}) async {
  final input = StreamController<List<int>>();
  final output = StreamController<List<int>>();
  final auth = await Directory.systemTemp.createTemp('hyfens-mcp-auth-');
  final server = HyfensMcpServer(
    input: input.stream,
    output: output.sink,
    toolchain: HyfensToolchain(),
    authStorage: AuthStorage(root: auth),
    profileName: profileName,
  );
  final lines = StreamIterator<String>(
    utf8.decoder.bind(output.stream).transform(const LineSplitter()),
  );
  return _Harness(server: server, input: input, lines: lines);
}

void main() {
  test(
    'initialize and tools/list expose the bounded SDK-backed catalog',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.close);

      final initialized = await harness.request(
        1,
        'initialize',
        params: <String, Object?>{
          'protocolVersion': '2025-11-25',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{
            'name': 'mcp-test',
            'version': '1.0.0',
          },
        },
      );
      final initializeResult = (initialized['result']! as Map)
          .cast<String, Object?>();
      final serverInfo = (initializeResult['serverInfo']! as Map)
          .cast<String, Object?>();
      expect(serverInfo['name'], 'hyfens');
      expect(serverInfo['version'], '0.1.1');
      expect(
        ((initializeResult['capabilities']! as Map)['tools'] as Map)
            .containsKey('listChanged'),
        isTrue,
      );

      harness.notify('notifications/initialized', params: <String, Object?>{});
      final listed = await harness.request(2, 'tools/list');
      final tools = ((listed['result']! as Map)['tools']! as List)
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      final names = tools.map((tool) => tool['name']).toSet();
      expect(
        names,
        containsAll(<String>{
          'status',
          'doctor',
          'profile_list',
          'profile_current',
          'profile_get',
          'project_init',
          'release_create',
          'release_inspect',
          'patch_create',
          'patch_verify',
          'patch_inspect',
          'deploy',
          'rollback',
          'control_plane_discovery',
        }),
      );
      final deploy = tools.firstWhere((tool) => tool['name'] == 'deploy');
      expect(deploy['description'], contains('UNSUPPORTED CAPABILITY'));
    },
  );

  test(
    'adapter maps local read and mutation services without absolute paths',
    () async {
      final project = await _createProject();
      final auth = await Directory.systemTemp.createTemp('hyfens-mcp-auth-');
      addTearDown(() async {
        await project.delete(recursive: true);
        await auth.delete(recursive: true);
      });
      final adapter = HyfensMcpAdapter(
        toolchain: HyfensToolchain(),
        authStorage: AuthStorage(root: auth),
      );

      final status = await adapter.status(projectPath: project.path);
      expect(status['result'], 'NOT_INITIALIZED');
      expect(jsonEncode(status), isNot(contains(project.path)));

      final init = await adapter.projectInit(
        projectPath: project.path,
        dryRun: true,
      );
      expect(init['dryRun'], isTrue);
      final initProject = (init['project']! as Map).cast<String, Object?>();
      expect(initProject['root'], '<project>');
      expect(jsonEncode(init), isNot(contains(project.path)));
    },
  );

  test(
    'profile metadata is host-bound and redacts all session material',
    () async {
      final authRoot = await Directory.systemTemp.createTemp(
        'hyfens-mcp-auth-',
      );
      addTearDown(() => authRoot.delete(recursive: true));
      final storage = AuthStorage(root: authRoot);
      final alpha = ControlPlaneProfile(
        name: 'alpha',
        endpoint: Uri.parse('http://127.0.0.1:43111/p2'),
        managed: false,
        organizationId: 'org-alpha',
        applicationId: 'app-alpha',
        environmentId: 'env-alpha',
      );
      final beta = ControlPlaneProfile(
        name: 'beta',
        endpoint: Uri.parse('http://127.0.0.1:43112/p2'),
        managed: false,
        organizationId: 'org-beta',
      );
      await storage.writeNamedProfile(alpha);
      await storage.writeNamedProfile(beta, makeActive: false);
      await storage.writeNamedProfile(
        CliProfile(
          name: managedCloudProfileName,
          endpoint: Uri.parse(managedCloudApiBase),
          managed: true,
        ),
        makeActive: false,
      );
      await storage.writeSession(
        const AuthSession(
          accessToken: 'alpha-access-secret',
          sessionToken: 'alpha-refresh-secret',
        ),
        endpoint: alpha.endpoint,
      );
      await storage.writeSession(
        const AuthSession(accessToken: 'beta-access-secret'),
        endpoint: beta.endpoint,
      );
      final adapter = HyfensMcpAdapter(
        toolchain: HyfensToolchain(),
        authStorage: storage,
        defaultProfileName: 'alpha',
      );

      final result = await adapter.profileList();
      final encoded = jsonEncode(result);
      expect(encoded, isNot(contains('alpha-access-secret')));
      expect(encoded, isNot(contains('alpha-refresh-secret')));
      expect(encoded, isNot(contains('beta-access-secret')));
      final profiles = (result['profiles']! as List)
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      final alphaResult = profiles.firstWhere(
        (item) => item['name'] == 'alpha',
      );
      final authResult = (alphaResult['auth']! as Map).cast<String, Object?>();
      expect(authResult['host_bound'], isTrue);
      expect(authResult['status'], 'LOGGED_IN');
      expect(encoded, isNot(contains('api.hyfens.com')));
    },
  );

  test('deploy returns an honest capability error without acting', () async {
    final auth = await Directory.systemTemp.createTemp('hyfens-mcp-auth-');
    addTearDown(() => auth.delete(recursive: true));
    final adapter = HyfensMcpAdapter(
      toolchain: HyfensToolchain(),
      authStorage: AuthStorage(root: auth),
    );

    expect(adapter.deploy, throwsA(isA<Exception>()));
  });

  test(
    'invalid paths and shutdown use structured errors and clean close',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.close);

      await harness.request(
        1,
        'initialize',
        params: <String, Object?>{
          'protocolVersion': '2025-11-25',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{'name': 'mcp-test', 'version': '1'},
        },
      );
      harness.notify('notifications/initialized');
      final invalid = await harness.request(
        2,
        'tools/call',
        params: <String, Object?>{
          'name': 'status',
          'arguments': <String, Object?>{'project_path': 'bad\npath'},
        },
      );
      final invalidResult = (invalid['result']! as Map).cast<String, Object?>();
      expect(invalidResult['isError'], isTrue);
      final invalidStructured = (invalidResult['structuredContent']! as Map)
          .cast<String, Object?>();
      expect(
        ((invalidStructured['error']! as Map).cast<String, Object?>())['code'],
        'MCP_INVALID_PATH',
      );

      final shutdown = await harness.request(3, 'shutdown');
      expect(shutdown['result'], isA<Map>());
      await harness.server.done.timeout(const Duration(seconds: 5));
      expect(harness.server.isActive, isFalse);
    },
  );
}
