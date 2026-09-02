import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'selection policy is default-app, dependency-opt-in, and fail-closed',
    () {
      final scratch = Directory.systemTemp.createTempSync('e0_selection_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final appRoot = Directory('${scratch.path}/app');
      final localRoot = Directory('${scratch.path}/local_dep');
      final hostedRoot = Directory('${scratch.path}/hosted_dep');
      final flutterRoot = Directory('${scratch.path}/flutter');
      final nativeRoot = Directory('${scratch.path}/native_dep');
      final app = _source(
        appRoot,
        'app.dart',
        'int applicationLeaf(int value) => value + 1;\n'
            'void main(List<String> arguments) {}',
      );
      final explicitlyExcluded = _source(
        appRoot,
        'excluded.dart',
        'int excludedLeaf(int value) => value + 2;',
      );
      final generated = _source(
        appRoot,
        'model.g.dart',
        'int generatedLeaf(int value) => value + 3;',
      );
      final local = _source(
        localRoot,
        'local.dart',
        'int localLeaf(int value) => value + 4;',
      );
      final explicitlyExcludedLocal = _source(
        localRoot,
        'excluded.dart',
        'int excludedLocalLeaf(int value) => value + 40;',
      );
      final hosted = _source(
        hostedRoot,
        'hosted.dart',
        'int hostedLeaf(int value) => value + 5;',
      );
      final flutter = _source(
        flutterRoot,
        'framework.dart',
        'int frameworkLeaf(int value) => value + 6;',
      );
      final native = _source(
        nativeRoot,
        'native.dart',
        "import 'dart:ffi';\nint nativeLeaf(int value) => value + 7;",
      );
      final flutterImport = _source(
        appRoot,
        'flutter_boundary.dart',
        "import 'package:flutter/widgets.dart';\n"
            'int flutterBoundaryLeaf(int value) => value + 70;',
      );
      final outside = File('${scratch.path}/sdk_like.dart')
        ..writeAsStringSync('int sdkLeaf(int value) => value + 8;');
      final config = _writePackageConfig(
        Directory('${scratch.path}/config'),
        <String, Directory>{
          'selection_app': appRoot,
          'local_dep': localRoot,
          'hosted_dep': hostedRoot,
          'flutter': flutterRoot,
          'native_dep': nativeRoot,
        },
      );
      final candidates = <E0PackageUnit>[
        E0PackageUnit(input: app, isEntrypoint: true),
        E0PackageUnit(input: explicitlyExcluded),
        E0PackageUnit(input: generated),
        E0PackageUnit(input: local),
        E0PackageUnit(input: explicitlyExcludedLocal),
        E0PackageUnit(input: hosted),
        E0PackageUnit(input: flutter),
        E0PackageUnit(input: native),
        E0PackageUnit(input: flutterImport),
        E0PackageUnit(input: outside),
      ];
      final policy = E0InstrumentationSelectionPolicy(
        applicationPackage: 'selection_app',
        optedInPackages: const <String>{
          'local_dep',
          'hosted_dep',
          'flutter',
          'native_dep',
        },
        excludedLibraryUris: const <String>{
          'package:selection_app/excluded.dart',
          'package:local_dep/excluded.dart',
        },
      );
      final plan = policy.plan(candidates: candidates, packageConfig: config);

      expect(
        plan.includedUnits.map((unit) => unit.input.path),
        unorderedEquals(<String>[app.path, local.path, hosted.path]),
      );
      final decisions = <String, E0InstrumentationSelectionDecision>{
        for (final decision in plan.decisions) decision.libraryUri: decision,
      };
      void expectDecision(
        String uri,
        bool included,
        bool hardExcluded,
        E0InstrumentationSelectionReason reason,
      ) {
        final decision = decisions[uri]!;
        expect(decision.included, included, reason: uri);
        expect(decision.hardExcluded, hardExcluded, reason: uri);
        expect(decision.reason, reason, reason: uri);
      }

      expectDecision(
        'package:selection_app/app.dart',
        true,
        false,
        E0InstrumentationSelectionReason.applicationDefault,
      );
      expectDecision(
        'package:selection_app/excluded.dart',
        false,
        false,
        E0InstrumentationSelectionReason.explicitExclude,
      );
      expectDecision(
        'package:selection_app/model.g.dart',
        false,
        true,
        E0InstrumentationSelectionReason.generatedDefaultExclude,
      );
      expectDecision(
        'package:local_dep/local.dart',
        true,
        false,
        E0InstrumentationSelectionReason.packageOptIn,
      );
      expectDecision(
        'package:local_dep/excluded.dart',
        false,
        false,
        E0InstrumentationSelectionReason.explicitExclude,
      );
      expectDecision(
        'package:hosted_dep/hosted.dart',
        true,
        false,
        E0InstrumentationSelectionReason.packageOptIn,
      );
      expectDecision(
        'package:flutter/framework.dart',
        false,
        true,
        E0InstrumentationSelectionReason.flutterHardExclude,
      );
      expectDecision(
        'package:native_dep/native.dart',
        false,
        true,
        E0InstrumentationSelectionReason.nativeBoundary,
      );
      expectDecision(
        'package:selection_app/flutter_boundary.dart',
        false,
        true,
        E0InstrumentationSelectionReason.flutterHardExclude,
      );
      expectDecision(
        outside.absolute.uri.toString(),
        false,
        true,
        E0InstrumentationSelectionReason.sdkHardExclude,
      );

      final withoutOptIn = E0InstrumentationSelectionPolicy(
        applicationPackage: 'selection_app',
      ).plan(candidates: candidates, packageConfig: config);
      expect(
        withoutOptIn.decisions
            .singleWhere(
              (decision) =>
                  decision.libraryUri == 'package:local_dep/local.dart',
            )
            .reason,
        E0InstrumentationSelectionReason.dependencyRequiresOptIn,
      );

      final overlay = E0PackageOverlayBuilder(E0SourceTransformer())
          .buildSelected(
            candidates: candidates,
            selectionPolicy: policy,
            packageConfig: config,
            outputDirectory: Directory('${scratch.path}/overlay'),
            appId: 'app',
            releaseId: 'selective-release',
            buildFingerprint: 'selective-build-1',
          );
      expect(overlay.manifest.libraryUris, <String>[
        'package:hosted_dep/hosted.dart',
        'package:local_dep/local.dart',
        'package:selection_app/app.dart',
      ]);
    },
  );

  test('entrypoint cannot cross an exclusion boundary', () {
    final scratch = Directory.systemTemp.createTempSync('e0_selection_entry_');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final appRoot = Directory('${scratch.path}/app');
    final entrypoint = _source(
      appRoot,
      'main.g.dart',
      'void main(List<String> arguments) {}',
    );
    final config = _writePackageConfig(
      Directory('${scratch.path}/config'),
      <String, Directory>{'selection_app': appRoot},
    );
    expect(
      () =>
          E0InstrumentationSelectionPolicy(applicationPackage: 'selection_app')
              .plan(
                candidates: <E0PackageUnit>[
                  E0PackageUnit(input: entrypoint, isEntrypoint: true),
                ],
                packageConfig: config,
              ),
      throwsFormatException,
    );
  });
}

File _source(Directory root, String name, String source) =>
    File('${root.path}/lib/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(source);

File _writePackageConfig(Directory directory, Map<String, Directory> packages) {
  directory.createSync(recursive: true);
  final instrumentationUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:instrumentation_e0/e0_runtime.dart'),
  )!;
  final cryptoUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:crypto/crypto.dart'),
  )!;
  final roots = <String, Directory>{
    'instrumentation_e0': File.fromUri(instrumentationUri).parent.parent,
    'crypto': File.fromUri(cryptoUri).parent.parent,
    ...packages,
  };
  final config = File('${directory.path}/package_config.json');
  config.writeAsStringSync(
    jsonEncode(<String, Object>{
      'configVersion': 2,
      'packages': <Object>[
        for (final entry
            in (roots.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key))))
          <String, Object>{
            'name': entry.key,
            'rootUri': entry.value.absolute.uri.toString(),
            'packageUri': 'lib/',
          },
      ],
    }),
  );
  return config;
}
