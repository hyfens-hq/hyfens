import 'package:hyfens_instrumenter/instrumenter.dart';
import 'package:test/test.dart';

void main() {
  test('facade preserves transformed source and manifest boundary', () {
    final result = HyfensInstrumenter().transform(
      const SourceInstrumentationRequest(
        source: 'int add(int left, int right) { return left + right; }\nvoid main() {}',
        packageName: 'instrumenter_fixture',
        logicalLibraryPath: 'lib/add.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'build',
      ),
    );
    expect(result.source, contains('E0PatchRuntime'));
    expect(result.manifest.functions, hasLength(1));
    expect(result.exclusions, isEmpty);
  });

  test(
    'facade injects an aliased generated runtime bootstrap only at main',
    () {
      final result = HyfensInstrumenter().transform(
        const SourceInstrumentationRequest(
          source:
              'int add(int left, int right) { return left + right; }\n'
              'void main() {}',
          packageName: 'instrumenter_fixture',
          logicalLibraryPath: 'lib/main.dart',
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
          runtimeBootstrapImport:
              "import 'package:bootstrap/bootstrap.dart' {prefix};",
          runtimeBootstrapInvocation: '{prefix}.Bootstrap.start();',
        ),
      );
      expect(result.source, contains("package:bootstrap/bootstrap.dart"));
      expect(result.source, contains('Bootstrap.start();'));
      expect(result.source, contains('E0PatchRuntime.installFromArguments'));
      expect(result.source, isNot(contains('{prefix}')));
    },
  );
}
