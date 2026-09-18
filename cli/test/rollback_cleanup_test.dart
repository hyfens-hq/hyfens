import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

final class _Fixture {
  const _Fixture({
    required this.root,
    required this.tool,
    required this.release,
  });

  final Directory root;
  final HyfensToolchain tool;
  final ReleaseRecord release;
}

Future<Directory> _createProject() async {
  final root = await Directory.systemTemp.createTemp('hyfens-rollback-');
  await Directory('${root.path}/lib').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: rollback_app
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
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'rollback_app',
          'rootUri': root.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left + right;
}
''');
  return root;
}

Future<_Fixture> _createTrustedFixture() async {
  final root = await _createProject();
  final tool = HyfensToolchain();
  await tool.init(projectPath: root.path);
  await tool.generateKeys(projectPath: root.path);
  final metadata = await tool.release(
    target: 'android',
    projectPath: root.path,
    metadataOnly: true,
  );
  final project = tool.project(projectPath: root.path);
  final store = ToolStore(project);
  await store.release(metadata.releaseId).delete(recursive: true);
  final sourceArtifact = File('${root.path}/base.apk');
  await sourceArtifact.writeAsBytes(<int>[1, 2, 3, 4]);
  final trusted = ReleaseRecord(
    applicationId: metadata.applicationId,
    releaseId: metadata.releaseId,
    target: metadata.target,
    architecture: metadata.architecture,
    buildMode: metadata.buildMode,
    buildFingerprint: metadata.buildFingerprint,
    sourceFingerprint: metadata.sourceFingerprint,
    graphFingerprint: metadata.graphFingerprint,
    toolVersion: metadata.toolVersion,
    flutterVersion: metadata.flutterVersion,
    dartVersion: metadata.dartVersion,
    manifest: metadata.manifest,
    graph: metadata.graph,
    sourceFingerprints: metadata.sourceFingerprints,
    instrumentation: metadata.instrumentation,
    build: const <String, Object?>{
      'artifact': 'base.apk',
      'metadataOnly': false,
      'status': 'SUCCESS',
    },
    sources: metadata.sources,
    functions: metadata.functions,
    diagnostics: metadata.diagnostics,
    configFingerprint: metadata.configFingerprint,
    nativeFingerprints: metadata.nativeFingerprints,
  );
  await store.writeRelease(trusted, artifacts: <File>[sourceArtifact]);
  return _Fixture(root: root, tool: tool, release: trusted);
}

Future<PatchBuildResult> _makePatch(_Fixture fixture, String expression) async {
  await File('${fixture.root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return $expression;
}
''');
  return fixture.tool.patch(
    projectPath: fixture.root.path,
    releaseId: fixture.release.releaseId,
  );
}

void main() {
  test(
    'rollback persists base and retains high-water across tool instances',
    () async {
      final fixture = await _createTrustedFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final first = await _makePatch(fixture, 'left - right');
      final second = await _makePatch(fixture, 'left + right + 1');
      final project = fixture.tool.project(projectPath: fixture.root.path);
      final store = ToolStore(project);

      final result = await fixture.tool.rollback(
        projectPath: fixture.root.path,
        releaseId: fixture.release.releaseId,
      );

      expect(result.state.target, 'base-aot');
      expect(result.state.highWaterSequence, 2);
      expect(result.state.highWaterDigest, isNotNull);
      expect(
        store.rollbackStatePrimary(fixture.release.releaseId).existsSync(),
        isTrue,
      );
      expect(
        store.rollbackStateBackup(fixture.release.releaseId).existsSync(),
        isTrue,
      );
      expect(first.output.existsSync(), isTrue);
      expect(second.output.existsSync(), isTrue);
      expect(
        store.sequenceFile(fixture.release.releaseId).readAsStringSync(),
        contains('"last":2'),
      );

      final restarted = HyfensToolchain();
      final restartedStore = ToolStore(
        restarted.project(projectPath: fixture.root.path),
      );
      final persisted = restartedStore.readRollbackState(
        fixture.release.releaseId,
      );
      expect(persisted?.target, 'base-aot');
      expect(persisted?.highWaterSequence, 2);
      expect(restartedStore.nextSequence(fixture.release.releaseId), 3);
    },
  );

  test('patches after rollback stay above high-water and old bytes remain stale evidence', () async {
    final fixture = await _createTrustedFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final first = await _makePatch(fixture, 'left - right');
    await fixture.tool.rollback(
      projectPath: fixture.root.path,
      releaseId: fixture.release.releaseId,
    );

    final next = await _makePatch(fixture, 'left - right - 1');
    final store = ToolStore(
      fixture.tool.project(projectPath: fixture.root.path),
    );
    expect(first.artifact.sequence, 1);
    expect(next.artifact.sequence, 2);
    expect(first.output.existsSync(), isTrue);
    expect(store.nextSequence(fixture.release.releaseId), 3);
    expect(
      store.readRollbackState(fixture.release.releaseId)?.highWaterSequence,
      1,
    );
  });

  test(
    'rollback rejects prior-patch selection instead of replaying old bytes',
    () async {
      final fixture = await _createTrustedFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await _makePatch(fixture, 'left - right');
      final store = ToolStore(
        fixture.tool.project(projectPath: fixture.root.path),
      );

      expect(
        () => fixture.tool.rollback(
          projectPath: fixture.root.path,
          releaseId: fixture.release.releaseId,
          target: 'previous',
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            ToolDiagnosticCodes.rollbackTargetUnsupported,
          ),
        ),
      );
      expect(
        store.rollbackStatePrimary(fixture.release.releaseId).existsSync(),
        isFalse,
      );
      expect(store.patch(fixture.release.releaseId, 1).existsSync(), isTrue);
    },
  );

  test(
    'rollback rejects metadata-only baselines as untrusted AOT bases',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      final tool = HyfensToolchain();
      await tool.init(projectPath: root.path);
      final release = await tool.release(
        target: 'android',
        projectPath: root.path,
        metadataOnly: true,
      );

      expect(
        () =>
            tool.rollback(projectPath: root.path, releaseId: release.releaseId),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            ToolDiagnosticCodes.rollbackBaseUnavailable,
          ),
        ),
      );
    },
  );

  test(
    'rollback refuses a sequence regression and preserves the journal',
    () async {
      final fixture = await _createTrustedFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      await _makePatch(fixture, 'left - right');
      await _makePatch(fixture, 'left + right + 1');
      await fixture.tool.rollback(
        projectPath: fixture.root.path,
        releaseId: fixture.release.releaseId,
      );
      final store = ToolStore(
        fixture.tool.project(projectPath: fixture.root.path),
      );
      final before = store.readRollbackState(fixture.release.releaseId)!;
      await store
          .sequenceFile(fixture.release.releaseId)
          .writeAsString('{"version":1,"last":1}\n');

      expect(
        () => fixture.tool.rollback(
          projectPath: fixture.root.path,
          releaseId: fixture.release.releaseId,
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            ToolDiagnosticCodes.rollbackHighWaterRegression,
          ),
        ),
      );
      expect(
        store.readRollbackState(fixture.release.releaseId)?.encode(),
        before.encode(),
      );
      expect(store.patch(fixture.release.releaseId, 2).existsSync(), isTrue);
    },
  );

  test('cleanup requires exact confirmation and protects keys, releases, source, and evidence', () async {
    final fixture = await _createTrustedFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final patch = await _makePatch(fixture, 'left - right');
    await fixture.tool.rollback(
      projectPath: fixture.root.path,
      releaseId: fixture.release.releaseId,
    );
    final project = fixture.tool.project(projectPath: fixture.root.path);
    final store = ToolStore(project);
    final config = fixture.tool.config(project);
    final privateKey = store.resolveConfiguredPath(
      config.privateKeyPath,
      allowExternal: true,
    );
    final source = File('${fixture.root.path}/lib/main.dart');
    final releaseMetadata = store.releaseMetadata(fixture.release.releaseId);
    final releaseArtifact = File(
      '${store.release(fixture.release.releaseId).path}/artifacts/base.apk',
    );

    expect(
      () => fixture.tool.cleanup(
        scope: 'patches',
        projectPath: fixture.root.path,
        releaseId: fixture.release.releaseId,
      ),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          ToolDiagnosticCodes.cleanupConfirmationRequired,
        ),
      ),
    );
    expect(patch.output.existsSync(), isTrue);

    for (final scope in <String>[
      'all',
      'evidence',
      'keys',
      'releases',
      'source',
    ]) {
      expect(
        () => fixture.tool.cleanup(
          scope: scope,
          projectPath: fixture.root.path,
          releaseId: fixture.release.releaseId,
          confirmation: fixture.release.releaseId,
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            ToolDiagnosticCodes.cleanupScopeProtected,
          ),
        ),
      );
    }

    final result = await fixture.tool.cleanup(
      scope: 'patches',
      projectPath: fixture.root.path,
      releaseId: fixture.release.releaseId,
      confirmation: fixture.release.releaseId,
    );
    expect(result.removedPaths, contains(endsWith('/000001.patch')));
    expect(patch.output.existsSync(), isFalse);
    expect(store.sequenceFile(fixture.release.releaseId).existsSync(), isTrue);
    expect(
      store.rollbackStatePrimary(fixture.release.releaseId).existsSync(),
      isTrue,
    );
    expect(
      store.rollbackStateBackup(fixture.release.releaseId).existsSync(),
      isTrue,
    );
    expect(releaseMetadata.existsSync(), isTrue);
    expect(releaseArtifact.existsSync(), isTrue);
    expect(privateKey.existsSync(), isTrue);
    expect(source.existsSync(), isTrue);
    expect(store.nextSequence(fixture.release.releaseId), 2);
  });

  test('patch cleanup is refused while the active target is unknown', () async {
    final fixture = await _createTrustedFixture();
    addTearDown(() => fixture.root.delete(recursive: true));
    final patch = await _makePatch(fixture, 'left - right');

    expect(
      () => fixture.tool.cleanup(
        scope: 'patches',
        projectPath: fixture.root.path,
        releaseId: fixture.release.releaseId,
        confirmation: fixture.release.releaseId,
      ),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          ToolDiagnosticCodes.cleanupRequiresBaseRollback,
        ),
      ),
    );
    expect(patch.output.existsSync(), isTrue);
  });

  test(
    'build cleanup removes only exact ephemeral staging and never source',
    () async {
      final fixture = await _createTrustedFixture();
      addTearDown(() => fixture.root.delete(recursive: true));
      final project = fixture.tool.project(projectPath: fixture.root.path);
      final store = ToolStore(project);
      final staging = Directory(
        '${store.buildStaging.path}/${fixture.release.releaseId}',
      );
      await File('${staging.path}/copied-source.dart').create(recursive: true);
      final source = File('${fixture.root.path}/lib/main.dart');

      final result = await fixture.tool.cleanup(
        scope: 'builds',
        projectPath: fixture.root.path,
        releaseId: fixture.release.releaseId,
        confirmation: fixture.release.releaseId,
      );

      expect(result.removedPaths, hasLength(1));
      expect(staging.existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
      expect(
        store.releaseMetadata(fixture.release.releaseId).existsSync(),
        isTrue,
      );
    },
  );
}
