import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('automatic Flutter target discovery', () {
    test(
      'selects a basic application and lib/main.dart automatically',
      () async {
        final root = await _createApp('basic_app');
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: root.path,
        );
        final selection = project.resolveTarget(target: 'android');

        expect(selection.entrypointPath, 'lib/main.dart');
        expect(selection.flavor, isNull);
        expect(selection.confidence, DiscoveryConfidence.highConfidence);
      },
    );

    test(
      'rejects an export-only main and resolves a nested flavor target',
      () async {
        final root = await _createApp(
          'nested_flavor_app',
          android: '''
android {
  namespace = "com.example.nested"
  defaultConfig { applicationId = "com.example.nested" }
  flavorDimensions += "environment"
  productFlavors {
    create("dev") { applicationIdSuffix = ".dev" }
  }
}
''',
          main: 'export "src/flavors/dev.dart";\n',
          extraEntrypoints: <String, String>{
            'lib/src/flavors/dev.dart': 'void main() {}\n',
          },
        );
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: root.path,
        );
        expect(
          project.entrypointCandidates.map((item) => item.path),
          contains('lib/src/flavors/dev.dart'),
        );
        expect(
          project.entrypointCandidates.map((item) => item.path),
          isNot(contains('lib/main.dart')),
        );
        final selection = project.resolveTarget(target: 'android');
        expect(selection.flavor, 'dev');
        expect(selection.entrypointPath, 'lib/src/flavors/dev.dart');
        expect(
          project.applicationIdFor('android', flavor: 'dev'),
          'com.example.nested.dev',
        );
      },
    );

    test(
      'supports conventional and custom Dart targets without native flavors',
      () async {
        final root = await _createApp(
          'custom_target_app',
          main: 'export "main_dev.dart";\n',
          extraEntrypoints: <String, String>{
            'lib/main_dev.dart': 'void main() {}\n',
            'lib/main_prod.dart': 'void main() {}\n',
            'lib/bootstrap.dart': 'void main() {}\n',
          },
        );
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: root.path,
        );
        expect(
          () => project.resolveTarget(target: 'android'),
          _failureCode('T1304'),
        );
        final explicit = project.resolveTarget(
          target: 'android',
          entrypointPath: 'lib/bootstrap.dart',
        );
        expect(explicit.entrypointPath, 'lib/bootstrap.dart');
        expect(explicit.flavor, isNull);
      },
    );

    test(
      'supports a native flavor that intentionally shares lib/main.dart',
      () async {
        final root = await _createApp(
          'same_main_app',
          android: '''
android {
  namespace "com.example.same"
  defaultConfig { applicationId "com.example.same" }
  productFlavors { dev { applicationIdSuffix ".dev" } }
}
''',
        );
        addTearDown(() => root.delete(recursive: true));

        final selection = const ProjectDiscovery()
            .discover(projectPath: root.path)
            .resolveTarget(target: 'android');
        expect(selection.flavor, 'dev');
        expect(selection.entrypointPath, 'lib/main.dart');
      },
    );

    test('explicit flavor and entrypoint overrides are strongest', () async {
      final root = await _createApp(
        'override_app',
        android: '''
android {
  namespace "com.example.override"
  defaultConfig { applicationId "com.example.override" }
  productFlavors { dev { } staging { } }
}
''',
        extraEntrypoints: <String, String>{
          'lib/flavors/dev.dart': 'void main() {}\n',
          'lib/flavors/staging.dart': 'void main() {}\n',
        },
      );
      addTearDown(() => root.delete(recursive: true));

      final selection = const ProjectDiscovery()
          .discover(projectPath: root.path)
          .resolveTarget(
            target: 'android',
            flavor: 'staging',
            entrypointPath: 'lib/flavors/staging.dart',
          );
      expect(selection.confidence, DiscoveryConfidence.exact);
      expect(selection.flavor, 'staging');
      expect(selection.entrypointPath, 'lib/flavors/staging.dart');
    });
  });

  group('native platform configuration', () {
    test(
      'discovers Kotlin Android flavors and iOS schemes/configurations',
      () async {
        final root = await _createApp(
          'platform_config_app',
          android: '''
android {
  namespace = "com.example.platform"
  defaultConfig { applicationId = "com.example.platform" }
  productFlavors {
    create("dev") { applicationIdSuffix = ".dev" }
    create("prod") { }
  }
}
''',
          ios: <String, String>{
            'ios/Flutter/Flavors/dev.xcconfig': 'PRODUCT_BUNDLE_IDENTIFIER = com.example.platform.dev\nFLUTTER_TARGET = lib/main_dev.dart\n',
            'ios/Flutter/Flavors/prod.xcconfig':
                'PRODUCT_BUNDLE_IDENTIFIER = com.example.platform\n',
            'ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme':
                '<Scheme/>',
          },
          extraEntrypoints: <String, String>{
            'lib/main_dev.dart': 'void main() {}\n',
          },
        );
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: root.path,
        );
        expect(project.androidFlavors, containsAll(<String>['dev', 'prod']));
        expect(project.iosFlavors, containsAll(<String>['dev', 'prod']));
        expect(
          project.applicationIdFor('android', flavor: 'dev'),
          'com.example.platform.dev',
        );
        expect(
          project.applicationIdFor('ios', flavor: 'dev'),
          'com.example.platform.dev',
        );
        expect(project.platformEntrypoints['ios']?['dev'], 'lib/main_dev.dart');
      },
    );

    test('reports a flavor choice instead of selecting production', () async {
      final root = await _createApp(
        'ambiguous_flavor_app',
        android: '''
android {
  defaultConfig { applicationId "com.example.ambiguous" }
  productFlavors { dev { } prod { } }
}
''',
      );
      addTearDown(() => root.delete(recursive: true));

      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final failure = await _captureFailure(
        () => project.resolveTarget(target: 'android'),
      );
      expect(failure.diagnostics.single.code, 'T1304');
      expect(failure.diagnostics.single.detail, isNot(contains('selected')));
    });
  });

  group('workspace discovery', () {
    test('supports a Dart Pub Workspace without Melos', () async {
      final root = await _createPubWorkspace();
      final apps = Directory(p.join(root.path, 'apps'));
      await _createApp('mobile', parent: apps, includeNative: false);
      await _createPackage('shared_models', root);
      addTearDown(() => root.delete(recursive: true));

      final report = const ProjectDiscovery().inspect(projectPath: root.path);
      expect(report.workspaceType, WorkspaceType.pubWorkspace);
      expect(report.candidates.map((item) => item.relativePath), <String>[
        'apps/mobile',
      ]);
    });

    test(
      'finds one runnable Melos/Pub Workspace app and excludes packages',
      () async {
        final root = await _createWorkspace(<String>['mobile']);
        final apps = Directory(p.join(root.path, 'apps'));
        await _createApp('mobile', parent: apps, includeNative: false);
        await _createPackage('design_system', root);
        await _createApp(
          'example',
          parent: Directory(p.join(root.path, 'packages', 'design_system')),
          includeNative: false,
        );
        addTearDown(() => root.delete(recursive: true));

        final report = const ProjectDiscovery().inspect(projectPath: root.path);
        expect(report.workspaceType, WorkspaceType.melosAndPubWorkspace);
        expect(report.candidates.map((item) => item.relativePath), <String>[
          'apps/mobile',
        ]);
        expect(report.selected?.packageName, 'mobile');
      },
    );

    test(
      'reports multiple runnable apps and resolves from an app directory',
      () async {
        final root = await _createWorkspace(<String>['apps/*']);
        final apps = Directory(p.join(root.path, 'apps'));
        await _createApp('customer', parent: apps, includeNative: false);
        await _createApp('admin', parent: apps, includeNative: false);
        addTearDown(() => root.delete(recursive: true));

        final ambiguous = const ProjectDiscovery().inspect(
          projectPath: root.path,
        );
        expect(ambiguous.issueCode, 'T1302');
        expect(ambiguous.candidates.map((item) => item.relativePath), <String>[
          'apps/admin',
          'apps/customer',
        ]);

        final selected = const ProjectDiscovery().discover(
          start: Directory(p.join(root.path, 'apps', 'customer', 'lib')),
        );
        expect(selected.packageName, 'customer');
        expect(selected.candidateApplications, hasLength(1));
      },
    );

    test('discovery JSON does not expose absolute workspace paths', () async {
      final root = await _createWorkspace(const <String>['apps/*']);
      final apps = Directory(p.join(root.path, 'apps'));
      await _createApp('customer', parent: apps, includeNative: false);
      await _createApp('admin', parent: apps, includeNative: false);
      addTearDown(() => root.delete(recursive: true));

      final report = const ProjectDiscovery().inspect(projectPath: root.path);
      final encoded = jsonEncode(report.toJson());
      expect(encoded, isNot(contains(root.path)));
      expect(report.toJson()['repositoryRoot'], '<repository>');
      expect(report.toJson()['workspaceRoot'], '<workspace>');
    });

    test('persisted app selection is used from workspace root', () async {
      final root = await _createWorkspace(<String>['apps/*']);
      final apps = Directory(p.join(root.path, 'apps'));
      await _createApp('customer', parent: apps, includeNative: false);
      await _createApp('admin', parent: apps, includeNative: false);
      await File(p.join(apps.path, 'customer', 'hyfens.yaml')).writeAsString('''
version: 1
profile: local
project: apps/customer
''');
      addTearDown(() => root.delete(recursive: true));

      final selected = const ProjectDiscovery().discover(
        projectPath: root.path,
      );
      expect(selected.packageName, 'customer');
      expect(selected.relativeProjectPath, 'apps/customer');
    });

    test('supports an app-directory invocation in a Pub Workspace', () async {
      final root = await _createWorkspace(const <String>['apps/mobile']);
      final apps = Directory(p.join(root.path, 'apps'));
      final app = await _createApp(
        'mobile',
        parent: apps,
        includeNative: false,
      );
      addTearDown(() => root.delete(recursive: true));

      final project = const ProjectDiscovery().discover(start: app);
      expect(project.workspaceType, WorkspaceType.melosAndPubWorkspace);
      expect(project.relativeProjectPath, 'apps/mobile');
    });

    test(
      'does not retarget an explicit Flutter package to a sibling app',
      () async {
        final root = await _createWorkspace(const <String>['apps/*']);
        final apps = Directory(p.join(root.path, 'apps'));
        await _createApp('mobile', parent: apps, includeNative: false);
        final package = Directory(
          p.join(root.path, 'packages', 'design_system'),
        );
        await _createPackage('design_system', root);
        addTearDown(() => root.delete(recursive: true));

        final report = const ProjectDiscovery().inspect(
          projectPath: package.path,
        );
        expect(report.issueCode, 'T1301');
        expect(report.selected, isNull);
        expect(report.candidates, isEmpty);
      },
    );

    test(
      'does not retarget an explicit Dart package to a sibling app',
      () async {
        final root = await _createWorkspace(const <String>['apps/*']);
        final apps = Directory(p.join(root.path, 'apps'));
        await _createApp('mobile', parent: apps, includeNative: false);
        final package = Directory(p.join(root.path, 'packages', 'pure_dart'));
        await package.create(recursive: true);
        await File(p.join(package.path, 'pubspec.yaml')).writeAsString('''
name: pure_dart
environment:
  sdk: ^3.13.0
''');
        addTearDown(() => root.delete(recursive: true));

        final report = const ProjectDiscovery().inspect(
          projectPath: package.path,
        );
        expect(report.issueCode, 'T1301');
        expect(report.selected, isNull);
        expect(report.candidates, isEmpty);
      },
    );
  });

  test('reports Android and iOS flavor disagreement independently', () async {
    final root = await _createApp(
      'disagreeing_flavors_app',
      android: '''
android {
  defaultConfig { applicationId "com.example.disagree" }
  productFlavors { dev { } staging { } }
}
''',
      ios: <String, String>{
        'ios/Flutter/Flavors/dev.xcconfig':
            'PRODUCT_BUNDLE_IDENTIFIER = com.example.disagree.dev\n',
        'ios/Flutter/Flavors/prod.xcconfig':
            'PRODUCT_BUNDLE_IDENTIFIER = com.example.disagree\n',
      },
    );
    addTearDown(() => root.delete(recursive: true));

    final project = const ProjectDiscovery().discover(projectPath: root.path);
    expect(project.androidFlavors, <String>['dev', 'staging']);
    expect(project.iosFlavors, <String>['dev', 'prod']);
    expect(
      () => project.resolveTarget(target: 'android', flavor: 'prod'),
      _failureCode('T1307'),
    );
  });

  test('uses independent persisted selections for Android and iOS', () async {
    final root = await _createApp(
      'independent_target_selections_app',
      android: '''
android {
  defaultConfig { applicationId "com.example.independent" }
  productFlavors { dev { } }
}
''',
      ios: <String, String>{
        'ios/Flutter/Flavors/staging.xcconfig':
            'PRODUCT_BUNDLE_IDENTIFIER = com.example.independent.staging\n',
      },
      extraEntrypoints: <String, String>{
        'lib/src/flavors/dev.dart': 'void main() {}\n',
        'lib/src/flavors/staging.dart': 'void main() {}\n',
      },
    );
    addTearDown(() => root.delete(recursive: true));

    await writeHyfensBinding(
      File(p.join(root.path, 'hyfens.yaml')),
      binding: const HyfensProjectBinding(
        profile: 'local',
        projectPath: '.',
        targetSelections: <String, HyfensTargetBinding>{
          'android': HyfensTargetBinding(
            target: 'android',
            flavor: 'dev',
            entrypointPath: 'lib/src/flavors/dev.dart',
          ),
          'ios': HyfensTargetBinding(
            target: 'ios',
            flavor: 'staging',
            entrypointPath: 'lib/src/flavors/staging.dart',
          ),
        },
      ),
    );

    final binding = HyfensProjectBinding.load(
      File(p.join(root.path, 'hyfens.yaml')),
    )!;
    final toolchain = HyfensToolchain();
    final android = toolchain.resolveTarget(
      target: 'android',
      projectPath: root.path,
    );
    final ios = toolchain.resolveTarget(target: 'ios', projectPath: root.path);
    expect(android.flavor, 'dev');
    expect(ios.flavor, 'staging');
    expect(
      binding.targetSelections.keys,
      containsAll(<String>['android', 'ios']),
    );
  });

  test(
    'detects a project-pinned Flutter toolchain without reading secrets',
    () async {
      final root = await _createApp('fvm_app');
      await Directory(p.join(root.path, '.fvm')).create(recursive: true);
      await File(p.join(root.path, '.fvm', 'fvm_config.json'))
          .writeAsString('{"flutter": "3.47.2"}');
      addTearDown(() => root.delete(recursive: true));

      final project = const ProjectDiscovery().discover(projectPath: root.path);
      expect(project.toolchainHint, contains('FVM Flutter 3.47.2'));
    },
  );

  test(
    'rejects a stale workspace project binding before target resolution',
    () async {
      final root = await _createWorkspace(const <String>['apps/*']);
      final apps = Directory(p.join(root.path, 'apps'));
      final app = await _createApp(
        'mobile',
        parent: apps,
        includeNative: false,
      );
      await File(p.join(root.path, 'hyfens.yaml')).writeAsString('''
version: 1
profile: local
project: apps/renamed
''');
      addTearDown(() => root.delete(recursive: true));

      final failure = await _captureFailure(
        () => HyfensToolchain().resolveTarget(
          target: 'android',
          projectPath: app.path,
        ),
      );
      expect(failure.diagnostics.single.code, 'H1209');
    },
  );

  test(
    'release and patch selection metadata can be round-tripped safely',
    () async {
      final root = await _createApp(
        'binding_app',
        android: '''
android {
  defaultConfig { applicationId "com.example.binding" }
  productFlavors { dev { applicationIdSuffix ".dev" } }
}
''',
        extraEntrypoints: <String, String>{
          'lib/main_dev.dart': 'void main() {}\n',
        },
      );
      addTearDown(() => root.delete(recursive: true));
      final bindingFile = File(p.join(root.path, 'hyfens.yaml'));
      await writeHyfensBinding(
        bindingFile,
        binding: const HyfensProjectBinding(
          profile: 'local',
          projectPath: '.',
          flavor: 'dev',
          entrypointPath: 'lib/main_dev.dart',
        ),
      );

      final project = const ProjectDiscovery().discover(projectPath: root.path);
      final binding = HyfensProjectBinding.load(bindingFile)!;
      final selection = project.resolveTarget(
        target: 'android',
        persistedFlavor: binding.flavor,
        persistedEntrypoint: binding.entrypointPath,
      );
      expect(selection.flavor, 'dev');
      expect(selection.entrypointPath, 'lib/main_dev.dart');
      expect(binding.toJson(), containsPair('project', '.'));
    },
  );
}

Matcher _failureCode(String code) => throwsA(
  isA<ToolFailure>().having(
    (failure) => failure.diagnostics.single.code,
    'code',
    code,
  ),
);

Future<ToolFailure> _captureFailure(
  FutureOr<Object?> Function() callback,
) async {
  try {
    await callback();
  } on ToolFailure catch (failure) {
    return failure;
  }
  fail('Expected a ToolFailure');
}

Future<Directory> _createApp(
  String name, {
  Directory? parent,
  String? android,
  Map<String, String> ios = const <String, String>{},
  String main = 'void main() {}\n',
  Map<String, String> extraEntrypoints = const <String, String>{},
  bool includeNative = true,
}) async {
  final root = Directory(p.join((parent ?? Directory.systemTemp).path, name));
  await Directory(p.join(root.path, 'lib')).create(recursive: true);
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: $name
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
  await File(p.join(root.path, 'lib', 'main.dart')).writeAsString(main);
  for (final entry in extraEntrypoints.entries) {
    final file = File(p.join(root.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  if (includeNative && android != null) {
    final file = File(p.join(root.path, 'android', 'app', 'build.gradle.kts'));
    await file.parent.create(recursive: true);
    await file.writeAsString(android);
  }
  if (includeNative) {
    for (final entry in ios.entries) {
      final file = File(p.join(root.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }
  return root;
}

Future<Directory> _createWorkspace(List<String> melosPackages) async {
  final root = await Directory.systemTemp.createTemp(
    'hyfens-discovery-workspace-',
  );
  final packages = melosPackages.map((item) => '  - $item').join('\n');
  await File(p.join(root.path, 'melos.yaml')).writeAsString('''
name: example_workspace
packages:
$packages
''');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: example_workspace
environment:
  sdk: ^3.13.0
workspace:
  - apps/*
  - packages/*
''');
  return root;
}

Future<Directory> _createPubWorkspace() async {
  final root = await Directory.systemTemp.createTemp('hyfens-pub-workspace-');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: example_pub_workspace
environment:
  sdk: ^3.13.0
workspace:
  - apps/*
  - packages/*
''');
  return root;
}

Future<void> _createPackage(String name, Directory workspace) async {
  final root = Directory(p.join(workspace.path, 'packages', name));
  await Directory(p.join(root.path, 'lib')).create(recursive: true);
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: $name
environment:
  sdk: ^3.13.0
flutter: {}
''');
  await File(p.join(root.path, 'lib', '$name.dart'))
      .writeAsString('class $name {}\n');
}
