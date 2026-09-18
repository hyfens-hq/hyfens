import 'package:hyfens_instrumenter/instrumenter.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('runtime bootstrap source is sorted and release-bound', () {
    final configuration = RuntimeBootstrapConfiguration(
      updateUrl: Uri.parse('http://127.0.0.1:18080/v1/patch'),
      keyId: 'ed25519-test',
      publicKey: List<int>.filled(32, 7),
    );
    final functions = HyfensInstrumenter()
        .transform(
          const SourceInstrumentationRequest(
            source:
                'int second() { return 2; }\n'
                'int first() { return 1; }\n'
                'void main() {}',
            packageName: 'example',
            logicalLibraryPath: 'lib/main.dart',
            appId: 'app',
            releaseId: 'release',
            buildFingerprint: 'build',
          ),
        )
        .manifest
        .functions
        .reversed
        .toList();
    final sortedIds = functions.map((function) => function.id).toList()..sort();
    final source = configuration.invocation(
      appId: 'com.example.app',
      releaseId: 'release-a',
      buildFingerprint: 'build-a',
      functions: functions,
    );
    expect(source, contains('releaseId: "release-a"'));
    expect(source, contains('"${sortedIds[0]}"'));
    expect(source, contains('"${sortedIds[1]}"'));
    expect(
      source.indexOf(sortedIds[0]),
      lessThan(source.indexOf(sortedIds[1])),
    );
    expect(source, contains('keyId: "ed25519-test"'));
    expect(
      source,
      contains(
        '_hyfens_bootstrap.HyfensControlPlaneConfiguration.fromEnvironment()',
      ),
    );
  });

  test('generated entrypoint registers logical runtime function context', () {
    final configuration = RuntimeBootstrapConfiguration(
      updateUrl: Uri.parse('http://127.0.0.1:18080/v1/patch'),
      keyId: 'ed25519-test',
      publicKey: List<int>.filled(32, 7),
    );
    const source =
        'int calculate(int value) { return value + 1; }\n'
        'void main() {}';
    final instrumenter = HyfensInstrumenter();
    final baseline = instrumenter.transform(
      const SourceInstrumentationRequest(
        source: source,
        packageName: 'example',
        logicalLibraryPath: 'lib/main.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'build',
      ),
    );
    final transformed = instrumenter.transform(
      SourceInstrumentationRequest(
        source: source,
        packageName: 'example',
        logicalLibraryPath: 'lib/main.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'build',
        runtimeBootstrapImport: configuration.importSource,
        runtimeBootstrapInvocation: configuration.invocation(
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
          functions: baseline.manifest.functions,
        ),
      ),
    );

    expect(transformed.source, contains('functionNames'));
    expect(transformed.source, contains('functionUris'));
    expect(transformed.source, contains('package:example/main.dart'));
    expect(transformed.source, contains('HyfensFlutterIntegration.start'));
  });
}
