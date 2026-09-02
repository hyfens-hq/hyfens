import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

Future<Directory> createProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-project-');
  await Directory('${root.path}/lib/generated').create(recursive: true);
  await Directory('${root.path}/android/app').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: sample_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  uses-material-design: true
dependencies: {}
''');
  await File('${root.path}/pubspec.lock').writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await File('${root.path}/android/app/build.gradle').writeAsString(
    'android { namespace "com.example.sample"; applicationId "com.example.sample" }',
  );
  await File('${root.path}/lib/main.dart').writeAsString('void main() {}\n');
  await File('${root.path}/lib/generated/model.dart')
      .writeAsString('void generated() {}\n');
  await Directory('${root.path}/.dart_tool').create();
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object>{
          'name': 'sample_app',
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
  test('accepts the server canonical S256 browser auth method', () {
    final document = DiscoveryDocument.fromJson(<String, Object?>{
      'product': 'hyfens',
      'api_version': 'v1',
      'auth_methods': <String>['authorization_code_pkce_s256'],
      'capabilities': <String, Object?>{},
    });

    expect(document.supportsBrowserPkce, isTrue);
  });

  test('does not treat the legacy deployment prefix as an API version', () {
    expect(
      () => DiscoveryDocument.fromJson(<String, Object?>{
        'product': 'hyfens',
        'api_version': 'p2',
        'auth_methods': <String>['authorization_code_pkce_s256'],
        'capabilities': <String, Object?>{},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'discovers project root, application ID, graph, and source policy',
    () async {
      final root = await createProject();
      addTearDown(() => root.delete(recursive: true));
      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final graph = const ProjectGraphLoader().load(project);
      final sources = const SourceDiscoverer().discover(
        project,
        graph,
        const ToolConfig(),
      );

      expect(project.packageName, 'sample_app');
      expect(project.applicationId, 'com.example.sample');
      expect(graph.fingerprint, hasLength(64));
      expect(
        sources.selected.map((item) => item.libraryUri),
        contains('package:sample_app/main.dart'),
      );
      expect(
        sources.skipped.any((item) => item.kind == SourceKind.generatedDart),
        isTrue,
      );
    },
  );

  test('finds a project when invoked from a child directory', () async {
    final root = await createProject();
    addTearDown(() => root.delete(recursive: true));
    final child = Directory('${root.path}/lib/generated');
    final project = const ProjectDiscovery().discover(start: child);
    expect(project.root.path, root.absolute.path);
  });

  test('graph identity excludes checkout-specific absolute paths', () async {
    final first = await createProject();
    final second = await createProject();
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));

    final firstGraph = const ProjectGraphLoader().load(
      const ProjectDiscovery().discover(projectPath: first.path),
    );
    final secondGraph = const ProjectGraphLoader().load(
      const ProjectDiscovery().discover(projectPath: second.path),
    );

    expect(firstGraph.fingerprint, secondGraph.fingerprint);
    expect(firstGraph.toJson().toString(), isNot(contains(first.path)));
    expect(secondGraph.toJson().toString(), isNot(contains(second.path)));
  });

  test(
    'discovers selected local packages with stable collision-free paths',
    () async {
      final root = await createProject();
      final packageRoot = await Directory.systemTemp.createTemp(
        'hyfens-local-package-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => packageRoot.delete(recursive: true));
      await Directory('${packageRoot.path}/lib').create(recursive: true);
      await File('${packageRoot.path}/pubspec.yaml').writeAsString('''
name: local_models
version: 1.2.3
environment:
  sdk: ^3.13.0
''');
      await File('${packageRoot.path}/lib/model.dart')
          .writeAsString('int modelValue() => 7;\n');
      await File('${root.path}/pubspec.lock').writeAsString('''
packages:
  local_models:
    dependency: "direct main"
    description:
      path: ${packageRoot.path}
      relative: true
    source: path
    version: 1.2.3
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
      final packageConfig = File('${root.path}/.dart_tool/package_config.json');
      final raw =
          jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
      final packages = (raw['packages']! as List<Object?>).toList();
      packages.add(<String, Object?>{
        'name': 'local_models',
        'rootUri': packageRoot.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      });
      await packageConfig.writeAsString(
        jsonEncode(<String, Object?>{...raw, 'packages': packages}),
      );

      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final graph = const ProjectGraphLoader().load(project);
      final sources = const SourceDiscoverer().discover(
        project,
        graph,
        const ToolConfig(),
      );
      final local = sources.units.singleWhere(
        (item) => item.libraryUri == 'package:local_models/model.dart',
      );
      expect(local.kind, SourceKind.localPackage);
      expect(local.selected, isTrue);
      expect(local.relativeTo(project), 'package:local_models/lib/model.dart');
      expect(graph.byName('local_models')!.source, PackageSourceType.path);
    },
  );
}
