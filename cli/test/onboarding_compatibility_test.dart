import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Flutter project onboarding', () {
    test('discovers the checked-in fresh Flutter fixture layout', () {
      final fixture = Directory(
        p.join(_repositoryRoot().path, 'fixtures', 'flutter_toolchain_app'),
      );

      final project = const ProjectDiscovery().discover(
        projectPath: fixture.path,
      );

      expect(project.packageName, 'hyfens_toolchain_app');
      expect(project.androidApplicationId, 'dev.hyfens.hyfens_toolchain_app');
      expect(project.iosApplicationId, 'dev.hyfens.hyfensToolchainApp');
      expect(
        project.applicationIdFor('android'),
        'dev.hyfens.hyfens_toolchain_app',
      );
      expect(project.applicationIdFor('ios'), 'dev.hyfens.hyfensToolchainApp');
    });

    test(
      'discovers an existing Android Groovy project from its pubspec',
      () async {
        final root = await _createFlutterProject(
          androidGroovyApplicationId: 'com.example.groovy',
        );
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: p.join(root.path, 'pubspec.yaml'),
        );

        expect(project.packageName, 'existing_app');
        expect(project.applicationId, 'com.example.groovy');
        expect(project.androidApplicationId, 'com.example.groovy');
        expect(project.applicationIdFor('android'), 'com.example.groovy');
      },
    );

    test('discovers an existing Android Kotlin DSL project', () async {
      final root = await _createFlutterProject(
        androidKotlinApplicationId: 'com.example.kotlin',
      );
      addTearDown(() => root.delete(recursive: true));

      final project = const ProjectDiscovery().discover(projectPath: root.path);

      expect(project.applicationId, 'com.example.kotlin');
      expect(project.androidApplicationId, 'com.example.kotlin');
      expect(project.applicationIdFor('android'), 'com.example.kotlin');
    });

    test('discovers an existing iOS bundle identifier', () async {
      final root = await _createFlutterProject(
        iosApplicationId: 'com.example.ios',
      );
      addTearDown(() => root.delete(recursive: true));

      final project = const ProjectDiscovery().discover(projectPath: root.path);

      expect(project.applicationId, 'com.example.ios');
      expect(project.iosApplicationId, 'com.example.ios');
      expect(project.applicationIdFor('ios'), 'com.example.ios');
    });

    test(
      'falls back to the Flutter package name without platform metadata',
      () async {
        final root = await _createFlutterProject();
        addTearDown(() => root.delete(recursive: true));

        final project = const ProjectDiscovery().discover(
          projectPath: root.path,
        );

        expect(project.applicationId, 'existing_app');
        expect(project.androidApplicationId, isNull);
        expect(project.iosApplicationId, isNull);
      },
    );
  });

  group('tool.yaml compatibility', () {
    test('uses v1 defaults when tool.yaml is absent', () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-onboarding-config-defaults-',
      );
      addTearDown(() => root.delete(recursive: true));

      final config = ToolConfig.load(File(p.join(root.path, 'tool.yaml')));

      expect(config.version, 1);
      expect(config.include, <String>['lib/**']);
      expect(config.exclude, <String>['lib/generated/**']);
      expect(config.includeLocalPackages, isTrue);
      expect(config.includePackages, isEmpty);
      expect(config.applicationId, isNull);
      expect(config.publicKeyPath, '.tool/keys/public.key');
      expect(config.privateKeyPath, '.tool/keys/private.key');
      expect(config.updateUrl, 'http://127.0.0.1:18080/v1/patch');
    });

    test('loads an explicit valid v1 configuration', () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-onboarding-config-v1-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'tool.yaml'));
      await file.writeAsString('''
version: 1
instrumentation:
  include:
    - lib/**
    - lib/features/**
  exclude:
    - lib/generated/**
packages:
  include_local: false
  include:
    - shared_models
application_id: com.example.valid
signing:
  public_key: .keys/public.key
  private_key: /secure/private.key
runtime:
  update_url: https://127.0.0.1:9443/v1/patch
''');

      final config = ToolConfig.load(file);

      expect(config.version, 1);
      expect(config.include, <String>['lib/**', 'lib/features/**']);
      expect(config.exclude, <String>['lib/generated/**']);
      expect(config.includeLocalPackages, isFalse);
      expect(config.includePackages, <String>['shared_models']);
      expect(config.applicationId, 'com.example.valid');
      expect(config.publicKeyPath, '.keys/public.key');
      expect(config.privateKeyPath, '/secure/private.key');
      expect(config.updateUrl, 'https://127.0.0.1:9443/v1/patch');
    });

    test('rejects malformed v1 configuration', () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-onboarding-config-malformed-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'tool.yaml'));
      await file.writeAsString('''
version: 1
instrumentation: false
''');

      expect(
        () => ToolConfig.load(file),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'T1203',
          ),
        ),
      );
    });

    test('rejects unsupported future configuration versions', () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-onboarding-config-future-',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'tool.yaml'));
      await file.writeAsString('version: 2\n');

      expect(
        () => ToolConfig.load(file),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'T1202',
          ),
        ),
      );
    });
  });

  group('toolchain and CLI distribution boundary', () {
    test('reports the declared Flutter and Dart support families', () {
      expect(flutterToolchainStatus(true, '3.47.0'), 'SUPPORTED');
      expect(flutterToolchainStatus(true, '3.47.1'), 'SUPPORTED');
      expect(flutterToolchainStatus(true, null), 'NOT TESTED');
      expect(flutterToolchainStatus(true, '3.46.9'), 'NOT TESTED');
      expect(flutterToolchainStatus(false, null), 'NOT AVAILABLE');

      expect(dartToolchainStatus(true, '3.13.0'), 'SUPPORTED');
      expect(dartToolchainStatus(true, '3.13.1'), 'SUPPORTED');
      expect(dartToolchainStatus(true, null), 'NOT TESTED');
      expect(dartToolchainStatus(true, '3.12.6'), 'NOT TESTED');
      expect(dartToolchainStatus(false, null), 'NOT AVAILABLE');
    });

    test(
      'registers the current top-level command surface and is not publishable',
      () {
        final commands = HyfensCommandRunner().commands.keys.toSet();

        expect(commands, <String>{
          'help',
          'version',
          'doctor',
          'status',
          'mcp',
          'login',
          'logout',
          'profile',
          'auth',
          'init',
          'analyze',
          'release',
          'patch',
          'rollback',
          'cleanup',
          'inspect',
          'verify',
          'keys',
          'serve',
          'deploy',
          'rollout',
          'bundle',
        });

        final manifest = File(
          p.join(_repositoryRoot().path, 'cli', 'pubspec.yaml'),
        );
        expect(
          manifest.readAsStringSync(),
          matches(RegExp(r'^publish_to:\s*none\s*$', multiLine: true)),
        );
      },
    );
  });
}

Directory _repositoryRoot() {
  var current = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    if (File(p.join(current.path, 'cli', 'pubspec.yaml')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  throw StateError(
    'Hyfens repository root was not found from ${Directory.current.path}',
  );
}

Future<Directory> _createFlutterProject({
  String? androidGroovyApplicationId,
  String? androidKotlinApplicationId,
  String? iosApplicationId,
}) async {
  final root = await Directory.systemTemp.createTemp(
    'hyfens-onboarding-project-',
  );
  await Directory(p.join(root.path, 'lib')).create(recursive: true);
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString('''
name: existing_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  uses-material-design: true
dependencies: {}
''');
  await File(p.join(root.path, 'lib', 'main.dart'))
      .writeAsString('void main() {}\n');

  if (androidGroovyApplicationId != null) {
    final file = File(p.join(root.path, 'android', 'app', 'build.gradle'));
    await file.parent.create(recursive: true);
    await file.writeAsString('''
android {
  namespace "com.example.groovy"
  defaultConfig {
    applicationId "$androidGroovyApplicationId"
  }
}
''');
  }
  if (androidKotlinApplicationId != null) {
    final file = File(p.join(root.path, 'android', 'app', 'build.gradle.kts'));
    await file.parent.create(recursive: true);
    await file.writeAsString('''
android {
  namespace = "com.example.kotlin"
  defaultConfig {
    applicationId = "$androidKotlinApplicationId"
  }
}
''');
  }
  if (iosApplicationId != null) {
    final file = File(
      p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('''
buildSettings = {
  PRODUCT_BUNDLE_IDENTIFIER = $iosApplicationId;
};
''');
  }
  return root;
}
