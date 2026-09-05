import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

Future<Directory> _createProject({String source = 'void main() {}\n'}) async {
  final root = await Directory.systemTemp.createTemp('hyfens-resource-');
  await Directory('${root.path}/lib').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  uses-material-design: true
  assets:
    - assets/data/
  fonts:
    - family: FixtureFont
      fonts:
        - asset: assets/fonts/fixture.ttf
dependencies: {}
''');
  await File('${root.path}/pubspec.lock').writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/.dart_tool/package_config.json').writeAsString('''
{"configVersion":2,"packages":[{"name":"resource_app","rootUri":"${root.uri}","packageUri":"lib/","languageVersion":"3.13"}]}
''');
  await File('${root.path}/lib/main.dart').writeAsString(source);
  await Directory('${root.path}/assets/data').create(recursive: true);
  await Directory('${root.path}/assets/fonts').create(recursive: true);
  await File('${root.path}/assets/data/one.json').writeAsString('{"one":1}');
  await File('${root.path}/assets/fonts/fixture.ttf')
      .writeAsBytes(<int>[1, 2, 3]);
  return root;
}

ResourceSnapshot _capture(Directory root, {String target = 'android'}) {
  final project = const ProjectDiscovery().discover(projectPath: root.path);
  final graph = const ProjectGraphLoader().load(project);
  return ResourceSnapshot.capture(
    project: project,
    graph: graph,
    target: target,
  );
}

void _expectRedactedDiagnostic(
  ResourceSnapshotFailure failure, {
  required String rootSentinel,
  required String code,
}) {
  final diagnostic = failure.toDiagnostic();
  final rendered = jsonEncode(<String, Object?>{
    'failure': failure.toString(),
    ...diagnostic.toJson(),
  });

  expect(diagnostic.code, code);
  expect(rendered, isNot(contains(rootSentinel)));
  expect(rendered, isNot(contains('FileSystemException')));
  expect(rendered, isNot(contains('FormatException')));
}

void main() {
  test('captures deterministic declared assets, fonts, and native resources', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/android/app/src/main/res/drawable')
        .create(recursive: true);
    await File('${root.path}/android/app/src/main/res/drawable/icon.png')
        .writeAsBytes(<int>[9, 8, 7]);
    await Directory(
      '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset',
    ).create(recursive: true);
    await File(
      '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
    ).writeAsString('{"images":[]}');

    final first = _capture(root);
    final second = _capture(root);

    expect(first.encode(), second.encode());
    expect(
      ResourceSnapshot.decode(first.encode()).fingerprint,
      first.fingerprint,
    );
    expect(
      first.entries.map((entry) => entry.kind),
      containsAll(<ResourceInputKind>[
        ResourceInputKind.asset,
        ResourceInputKind.font,
        ResourceInputKind.native,
      ]),
    );
    expect(
      first.entries.any(
        (entry) =>
            entry.kind == ResourceInputKind.native &&
            entry.path.endsWith('res/drawable/icon.png'),
      ),
      isTrue,
    );
    final ios = _capture(root, target: 'ios');
    expect(
      ios.entries.any(
        (entry) =>
            entry.kind == ResourceInputKind.native &&
            entry.path.endsWith(
              'Assets.xcassets/AppIcon.appiconset/Contents.json',
            ),
      ),
      isTrue,
    );
  });

  test('detects resource additions, removals, and byte changes', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    final before = _capture(root);
    await File('${root.path}/assets/data/one.json').writeAsString('{"one":2}');
    await File('${root.path}/assets/data/two.svg').writeAsString('<svg/>');

    final changes = before.diff(_capture(root)).changes;

    expect(
      changes.any(
        (change) =>
            change.kind == ResourceInputKind.asset &&
            change.path.endsWith('one.json') &&
            change.reason == 'bytes-changed',
      ),
      isTrue,
    );
    expect(
      changes.any(
        (change) =>
            change.kind == ResourceInputKind.asset &&
            change.path.endsWith('two.svg') &&
            change.reason == 'added',
      ),
      isTrue,
    );
    await File('${root.path}/assets/fonts/fixture.ttf')
        .writeAsBytes(<int>[4, 5, 6]);
    expect(
      before
          .diff(_capture(root))
          .changes
          .any(
            (change) =>
                change.kind == ResourceInputKind.font &&
                change.path.endsWith('fixture.ttf') &&
                change.reason == 'bytes-changed',
          ),
      isTrue,
    );

    await File('${root.path}/assets/data/one.json').delete();
    final removal = before.diff(_capture(root)).changes;
    expect(
      removal.any(
        (change) =>
            change.kind == ResourceInputKind.asset &&
            change.path.endsWith('one.json') &&
            change.reason == 'removed',
      ),
      isTrue,
    );
  });

  test('rejects unsafe declared paths and symlink escapes', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    final outside = await Directory.systemTemp.createTemp(
      'hyfens-resource-outside-',
    );
    addTearDown(() => outside.delete(recursive: true));

    await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - ../outside/
dependencies: {}
''');
    expect(
      () => _capture(root),
      throwsA(
        isA<ResourceSnapshotFailure>().having(
          (failure) => failure.kind,
          'kind',
          ResourceInputKind.asset,
        ),
      ),
    );

    await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/data/
dependencies: {}
''');
    await File('${outside.path}/escape.json').writeAsString('{}');
    await Link('${root.path}/assets/data/escape.json')
        .create('${outside.path}/escape.json');
    expect(
      () => _capture(root),
      throwsA(
        isA<ResourceSnapshotFailure>().having(
          (failure) => failure.kind,
          'kind',
          ResourceInputKind.asset,
        ),
      ),
    );
  });

  test('redacts inaccessible resource traversal diagnostics', () async {
    if (Platform.isWindows) return;

    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    final inaccessible = Directory('${root.path}/assets/inaccessible');
    await inaccessible.create(recursive: true);
    await File('${inaccessible.path}/private.bin').writeAsBytes(<int>[1]);
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/inaccessible/
dependencies: {}
''');

    final chmod = await Process.run('chmod', <String>[
      '000',
      inaccessible.path,
    ]);
    addTearDown(() => Process.run('chmod', <String>['700', inaccessible.path]));
    expect(chmod.exitCode, 0);

    ResourceSnapshotFailure? failure;
    try {
      _capture(root);
    } on ResourceSnapshotFailure catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    _expectRedactedDiagnostic(failure!, rootSentinel: root.path, code: 'A3010');
    expect(
      failure.detail,
      'Unable to enumerate the package resource directory.',
    );
  });

  test('redacts invalid UTF-8 source diagnostics', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/bad.dart').writeAsBytes(<int>[0xff, 0xfe]);

    ResourceSnapshotFailure? failure;
    try {
      _capture(root);
    } on ResourceSnapshotFailure catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    _expectRedactedDiagnostic(failure!, rootSentinel: root.path, code: 'F3010');
    expect(failure.detail, 'Unable to read Dart source for icon evidence.');
  });

  test(
    'captures standard asset maps and fingerprints active metadata',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - path: assets/data/one.json
      platforms:
        - android
    - path: assets/data/ios.json
      platforms:
        - ios
    - path: assets/data/web.json
      platforms:
        - web
dependencies: {}
''');
      await File('${root.path}/assets/data/ios.json').writeAsString('ios');
      await File('${root.path}/assets/data/web.json').writeAsString('web');

      final before = _capture(root);
      final androidEntry = before.entries.firstWhere(
        (entry) => entry.path.endsWith('assets/data/one.json'),
      );
      expect(androidEntry.metadataFingerprint, isNotNull);
      expect(
        before.entries.any((entry) => entry.path.endsWith('ios.json')),
        isFalse,
      );
      expect(
        before.entries.any((entry) => entry.path.endsWith('web.json')),
        isFalse,
      );
      final ios = _capture(root, target: 'ios');
      expect(
        ios.entries.any((entry) => entry.path.endsWith('ios.json')),
        isTrue,
      );
      expect(
        ios.entries.any((entry) => entry.path.endsWith('one.json')),
        isFalse,
      );

      await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - path: assets/data/one.json
      platforms:
        - android
      flavors:
        - free
dependencies: {}
''');
      expect(
        before
            .diff(_capture(root))
            .changes
            .any(
              (change) =>
                  change.kind == ResourceInputKind.asset &&
                  change.path.endsWith('one.json') &&
                  change.reason == 'metadata-changed',
            ),
        isTrue,
      );
      expect(
        ResourceSnapshot.decode(before.encode()).entries
            .firstWhere((entry) => entry.path.endsWith('one.json'))
            .metadataFingerprint,
        androidEntry.metadataFingerprint,
      );
    },
  );

  test(
    'captures resolution variants and fails closed on variant changes',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/images/icon.png
dependencies: {}
''');
      await Directory('${root.path}/assets/images/2x').create(recursive: true);
      await Directory('${root.path}/assets/images/3x').create(recursive: true);
      await File('${root.path}/assets/images/icon.png').writeAsBytes(<int>[1]);
      await File('${root.path}/assets/images/2x/icon.png')
          .writeAsBytes(<int>[2]);
      await File('${root.path}/assets/images/3x/icon.png')
          .writeAsBytes(<int>[3]);

      final before = _capture(root);
      expect(
        before.entries.where((entry) => entry.path.endsWith('icon.png')).length,
        3,
      );
      await File('${root.path}/assets/images/2x/icon.png')
          .writeAsBytes(<int>[8]);
      expect(
        before
            .diff(_capture(root))
            .changes
            .any(
              (change) =>
                  change.kind == ResourceInputKind.asset &&
                  change.path.endsWith('2x/icon.png') &&
                  change.reason == 'bytes-changed',
            ),
        isTrue,
      );
      await File('${root.path}/assets/images/3x/icon.png').delete();
      expect(
        before
            .diff(_capture(root))
            .changes
            .any(
              (change) =>
                  change.kind == ResourceInputKind.asset &&
                  change.path.endsWith('3x/icon.png') &&
                  change.reason == 'removed',
            ),
        isTrue,
      );
    },
  );

  test(
    'accepts a valid asset declaration with only resolution variants',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/images/only.png
dependencies: {}
''');
      await Directory('${root.path}/assets/images/2x').create(recursive: true);
      await File('${root.path}/assets/images/2x/only.png')
          .writeAsBytes(<int>[2]);

      final variantOnly = _capture(root);
      expect(
        variantOnly.entries.any((entry) => entry.path.endsWith('2x/only.png')),
        isTrue,
      );
      expect(
        variantOnly.entries.any(
          (entry) =>
              entry.kind == ResourceInputKind.asset &&
              entry.path.endsWith('images/only.png'),
        ),
        isFalse,
      );
    },
  );

  test(
    'rejects symlinked resolution variant files without absolute diagnostics',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      final outside = await Directory.systemTemp.createTemp(
        'hyfens-resource-variant-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - assets/images/icon.png
dependencies: {}
''');
      await Directory('${root.path}/assets/images/2x').create(recursive: true);
      await Directory('${root.path}/assets/images/3x').create(recursive: true);
      await File('${root.path}/assets/images/icon.png').writeAsBytes(<int>[1]);
      await File('${root.path}/assets/images/2x/icon.png')
          .writeAsBytes(<int>[2]);
      final outsideFile = File('${outside.path}/variant-secret.bin');
      await outsideFile.writeAsBytes(<int>[3]);
      await Link('${root.path}/assets/images/3x/icon.png')
          .create(outsideFile.path);

      ResourceSnapshotFailure? failure;
      try {
        _capture(root);
      } on ResourceSnapshotFailure catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      _expectRedactedDiagnostic(
        failure!,
        rootSentinel: root.path,
        code: 'A3010',
      );
      final rendered = jsonEncode(<String, Object?>{
        'failure': failure.toString(),
        ...failure.toDiagnostic().toJson(),
      });
      expect(rendered, isNot(contains(outside.path)));
      expect(failure.path, 'package:resource_app/assets/images/3x/icon.png');
      expect(failure.detail, 'Resource path traverses a symlink.');
    },
  );

  test('resolves logical package assets through package URI roots', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    final packageRoot = Directory('${root.path}/packages/foo');
    await Directory('${packageRoot.path}/lib/assets').create(recursive: true);
    await File('${packageRoot.path}/pubspec.yaml').writeAsString('''
name: foo
version: 1.0.0
environment:
  sdk: ^3.13.0
''');
    await File('${packageRoot.path}/lib/assets/from_package.txt')
        .writeAsString('package');
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
dependencies:
  foo:
    path: packages/foo
flutter:
  assets:
    - packages/foo/assets/from_package.txt
''');
    await File('${root.path}/pubspec.lock').writeAsString('''
packages:
  foo:
    dependency: "direct main"
    description:
      path: packages/foo
    source: path
    version: 1.0.0
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
    await File('${root.path}/.dart_tool/package_config.json').writeAsString(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'resource_app',
            'rootUri': root.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
          <String, Object?>{
            'name': 'foo',
            'rootUri': packageRoot.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
    );

    final before = _capture(root);
    final packageEntry = before.entries.singleWhere(
      (entry) => entry.path.endsWith('lib/assets/from_package.txt'),
    );
    expect(packageEntry.packageName, 'foo');
    await File('${packageRoot.path}/lib/assets/from_package.txt')
        .writeAsString('changed');
    expect(
      before
          .diff(_capture(root))
          .changes
          .any(
            (change) =>
                change.kind == ResourceInputKind.asset &&
                change.packageName == 'foo' &&
                change.path.endsWith('lib/assets/from_package.txt') &&
                change.reason == 'bytes-changed',
          ),
      isTrue,
    );
  });

  test('fails closed for unsupported asset transformers', () async {
    final root = await _createProject();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: resource_app
version: 1.0.0+1
environment:
  sdk: ^3.13.0
flutter:
  assets:
    - path: assets/data/one.json
      transformers:
        - package: unsupported_transformer
dependencies: {}
''');

    ResourceSnapshotFailure? failure;
    try {
      _capture(root);
    } on ResourceSnapshotFailure catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    _expectRedactedDiagnostic(failure!, rootSentinel: root.path, code: 'A3010');
    expect(
      failure.detail,
      'Asset transformers are unsupported for snapshot capture.',
    );
  });

  test(
    'blocks new Material icon references without exact glyph proof',
    () async {
      final root = await _createProject();
      addTearDown(() => root.delete(recursive: true));
      final before = _capture(root);
      await File('${root.path}/lib/main.dart').writeAsString('''
void main() {
  final icon = Icons.add;
  print(icon);
}
''');

      final changes = before.diff(_capture(root)).changes;

      expect(
        changes.any(
          (change) =>
              change.kind == ResourceInputKind.font &&
              change.reason == 'material-icon-reference-added' &&
              change.path.endsWith('Icons.add'),
        ),
        isTrue,
      );

      await File('${root.path}/lib/main.dart').writeAsString('''
void main() {
  final iconClass = Icons;
  print(iconClass);
}
''');
      expect(_capture(root).materialIconAstComplete, isFalse);
    },
  );

  test('extracts the exact Flutter engine revision from tool output', () {
    expect(
      extractFlutterEngineRevision(
        'Flutter 3.47.0 • channel stable\nEngine • hash ABCdef1234567890123456789012345678901234 (revision ABCdef12) • 2026-01-01',
      ),
      'abcdef1234567890123456789012345678901234',
    );
    expect(
      extractFlutterEngineRevision('Engine • revision ABCdef1234567890'),
      'abcdef1234567890',
    );
    expect(extractFlutterEngineRevision('Flutter 3.47.0 only'), isNull);
  });
}
