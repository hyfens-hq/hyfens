import 'dart:convert';
import 'dart:io';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

Future<Directory> createPatchProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-toolchain-');
  await Directory('${root.path}/lib').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: patch_app
version: 1.0.0+1
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
  await Directory('${root.path}/.dart_tool').create();
  await File('${root.path}/.dart_tool/package_config.json').writeAsString('''
{"configVersion":2,"packages":[{"name":"patch_app","rootUri":"${root.uri}","packageUri":"lib/","languageVersion":"3.13"}]}
''');
  await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left + right;
}
class UnsupportedSurface {
  int get value => 1;
}
''');
  await File('${root.path}/lib/native.dart')
      .writeAsString('void nativeHelper() {}\n');
  return root;
}

void main() {
  test(
    'init, release, patch, inspect, and verify use ordinary project source',
    () async {
      final root = await createPatchProject();
      addTearDown(() => root.delete(recursive: true));
      final tool = HyfensToolchain();

      final init = await tool.init(projectPath: root.path);
      expect(init.dryRun, isFalse);
      final key = await tool.generateKeys(projectPath: root.path);
      expect(key.keyId, startsWith('ed25519-'));

      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      expect(release.functions, isNotEmpty);
      expect(release.manifest.patchFormatVersion, patchFormatV1);
      expect(release.resourceSnapshot, isNotNull);
      expect(release.flutterEngineRevision, isNotNull);
      expect(
        release.functions.map((function) => function.slot).toSet(),
        hasLength(release.functions.length),
      );

      final source = File('${root.path}/lib/main.dart');
      await source.writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left - right;
}

class UnsupportedSurface {
  int get value => 1;
}
''');
      final analysis = tool.analyze(
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(analysis.canPatch, isTrue, reason: analysis.toJson().toString());
      expect(analysis.items.single.line, isNotNull);
      expect(analysis.items.single.column, isNotNull);
      expect(analysis.items.single.libraryUri, 'package:patch_app/main.dart');

      final patch = await tool.patch(
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(patch.output.existsSync(), isTrue);
      expect(patch.artifact.releaseId, release.releaseId);
      expect(patch.artifact.signatureMetadata.keyId, key.keyId);

      final inspection = tool.inspect(patch.output);
      expect(inspection.artifact.patchId, patch.artifact.patchId);
      final verified = await tool.verify(
        file: patch.output,
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(verified.artifact.sequence, 1);
    },
  );

  test(
    'changed unsupported declaration blocks an otherwise patchable file',
    () async {
      final root = await createPatchProject();
      addTearDown(() => root.delete(recursive: true));
      final tool = HyfensToolchain();
      await tool.init(projectPath: root.path);
      final source = File('${root.path}/lib/main.dart');
      await source.writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left + right;
}

class UnsupportedSurface {
  int get value => 1;
}
''');
      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      await source.writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left - right;
}

class UnsupportedSurface {
  int get value => 2;
}
''');
      final analysis = tool.analyze(
        projectPath: root.path,
        releaseId: release.releaseId,
      );
      expect(analysis.canPatch, isFalse);
      expect(
        analysis.diagnostics.any((diagnostic) => diagnostic.code == 'P2003'),
        isTrue,
      );
    },
  );

  test('ambiguous baselines require an explicit release target', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final first = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await tool.release(
      target: 'ios',
      projectPath: root.path,
      metadataOnly: true,
    );
    expect(
      () => tool.analyze(projectPath: root.path),
      throwsA(isA<ToolFailure>()),
    );
    expect(
      tool
          .analyze(projectPath: root.path, releaseId: first.releaseId)
          .release
          .releaseId,
      first.releaseId,
    );
  });

  test('repeating the same metadata baseline is idempotent', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final first = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    final second = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    expect(second.releaseId, first.releaseId);
    expect(
      ToolStore(const ProjectDiscovery().discover(projectPath: root.path))
          .listReleases(),
      hasLength(1),
    );
  });

  test('comment-only changes do not produce an empty patch', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    final source = File('${root.path}/lib/main.dart');
    await source.writeAsString(
      '${source.readAsStringSync()}\n// no behavior change\n',
    );

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );
    expect(analysis.canPatch, isFalse);
    expect(
      () => tool.patch(projectPath: root.path, releaseId: release.releaseId),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          'P2010',
        ),
      ),
    );
  });

  test('changed native-boundary Dart is store-release-required', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await File('${root.path}/lib/native.dart').writeAsString('''
import 'package:flutter/services.dart';

void nativeHelper() {
  MethodChannel('native').invokeMethod<void>('ping');
}
''');

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );
    expect(analysis.canPatch, isFalse);
    expect(
      analysis.items.any(
        (item) =>
            item.classification == ChangeClassification.storeReleaseRequired &&
            item.diagnostic?.code == 'N3005',
      ),
      isTrue,
    );
  });

  test('signature changes are store-release-required', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right, [int offset = 0]) {
  return left + right + offset;
}
class UnsupportedSurface {
  int get value => 1;
}
''');

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );
    expect(analysis.canPatch, isFalse);
    expect(
      analysis.items.any(
        (item) =>
            item.classification == ChangeClassification.storeReleaseRequired &&
            item.diagnostic?.code == 'P2007',
      ),
      isTrue,
    );
  });

  test('native project inputs are store-release-required', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await Directory('${root.path}/android/app').create(recursive: true);
    await File('${root.path}/android/app/src/main/AndroidManifest.xml')
        .create(recursive: true);
    await File('${root.path}/android/app/src/main/AndroidManifest.xml')
        .writeAsString('<manifest package="com.example.patch_app"/>\n');

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );
    expect(analysis.canPatch, isFalse);
    expect(
      analysis.diagnostics.any((diagnostic) => diagnostic.code == 'N3001'),
      isTrue,
    );
  });

  test('configured paths cannot escape the project', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final project = const ProjectDiscovery().discover(projectPath: root.path);
    expect(
      () =>
          ToolStore(project).resolveConfiguredPath('nested/../../outside.key'),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          'T1205',
        ),
      ),
    );
  });

  test('asset-only changes are store-release-required', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/assets/data').create(recursive: true);
    await File('${root.path}/assets/data/value.json').writeAsString('{"v":1}');
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: patch_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/data/
dependencies: {}
''');
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await File('${root.path}/assets/data/value.json').writeAsString('{"v":2}');

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );

    expect(analysis.canPatch, isFalse);
    expect(
      analysis.diagnostics.any(
        (diagnostic) =>
            diagnostic.code == 'A3010' && diagnostic.storeReleaseRequired,
      ),
      isTrue,
    );
    expect(
      analysis.items.any(
        (item) =>
            item.classification == ChangeClassification.storeReleaseRequired &&
            item.path == '<packaged assets>',
      ),
      isTrue,
    );
  });

  test(
    'mixed Dart and asset changes cannot generate a code-only patch',
    () async {
      final root = await createPatchProject();
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/assets/data').create(recursive: true);
      await File('${root.path}/assets/data/value.json')
          .writeAsString('{"v":1}');
      await File('${root.path}/pubspec.yaml').writeAsString('''
name: patch_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/data/
dependencies: {}
''');
      final tool = HyfensToolchain();
      await tool.init(projectPath: root.path);
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
class UnsupportedSurface {
  int get value => 1;
}
''');
      await File('${root.path}/assets/data/value.json')
          .writeAsString('{"v":2}');

      final analysis = tool.analyze(
        projectPath: root.path,
        releaseId: release.releaseId,
      );

      expect(analysis.canPatch, isFalse);
      expect(
        analysis.items.any(
          (item) => item.classification == ChangeClassification.patchable,
        ),
        isTrue,
      );
      expect(
        analysis.diagnostics.any((diagnostic) => diagnostic.code == 'A3010'),
        isTrue,
      );
      expect(
        () => tool.patch(projectPath: root.path, releaseId: release.releaseId),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.any(
              (diagnostic) => diagnostic.code == 'A3010',
            ),
            'asset boundary diagnostic',
            isTrue,
          ),
        ),
      );
    },
  );

  test('native packaged resource changes are store-release-required', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final resource = File(
      '${root.path}/android/app/src/main/res/drawable/icon.png',
    );
    await resource.parent.create(recursive: true);
    await resource.writeAsBytes(<int>[1, 2, 3]);
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final release = await tool.release(
      target: 'android',
      projectPath: root.path,
      metadataOnly: true,
    );
    await resource.writeAsBytes(<int>[4, 5, 6]);

    final analysis = tool.analyze(
      projectPath: root.path,
      releaseId: release.releaseId,
    );

    expect(analysis.canPatch, isFalse);
    expect(
      analysis.diagnostics.any((diagnostic) => diagnostic.code == 'N3010'),
      isTrue,
    );
  });

  test(
    'legacy baselines without resource or engine metadata require a new base',
    () async {
      final root = await createPatchProject();
      addTearDown(() => root.delete(recursive: true));
      final tool = HyfensToolchain();
      await tool.init(projectPath: root.path);
      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );
      final raw = jsonDecode(release.encode()) as Map<String, Object?>
        ..remove('resourceSnapshot')
        ..remove('flutterEngineRevision');
      final project = tool.project(projectPath: root.path);
      await ToolStore(project)
          .releaseMetadata(release.releaseId)
          .writeAsString(jsonEncode(raw));

      final analysis = tool.analyze(
        projectPath: root.path,
        releaseId: release.releaseId,
      );

      expect(analysis.canPatch, isFalse);
      expect(
        analysis.diagnostics.map((diagnostic) => diagnostic.code),
        containsAll(<String>['R5010', 'T1103']),
      );
    },
  );

  test('architecture is part of release identity', () async {
    final root = await createPatchProject();
    addTearDown(() => root.delete(recursive: true));
    final tool = HyfensToolchain();
    await tool.init(projectPath: root.path);
    final arm = await tool.release(
      target: 'android',
      projectPath: root.path,
      architecture: 'arm64',
      metadataOnly: true,
    );
    final x64 = await tool.release(
      target: 'android',
      projectPath: root.path,
      architecture: 'x64',
      metadataOnly: true,
    );
    expect(x64.releaseId, isNot(arm.releaseId));
  });

  test('release identity excludes checkout-specific paths', () async {
    final first = await createPatchProject();
    final second = await createPatchProject();
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));
    final tool = HyfensToolchain();
    final firstRelease = await tool.release(
      target: 'android',
      projectPath: first.path,
      metadataOnly: true,
    );
    final secondRelease = await tool.release(
      target: 'android',
      projectPath: second.path,
      metadataOnly: true,
    );
    expect(secondRelease.releaseId, firstRelease.releaseId);
  });
}
