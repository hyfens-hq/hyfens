import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test(
    'instruments generalized signatures and emits guarded typed adapters',
    () {
      final result = E0SourceTransformer().transform(
        source:
            'String greet(String name) { return name; }\n'
            'List<int> filterValues(List<int> values) { return values; }\n'
            'Object unsafe(Object value) { return value; }\n'
            'void main(List<String> args) {}',
        packageName: 'fixture',
        logicalLibraryPath: 'lib/app.dart',
        appId: 'app',
        releaseId: 'release',
        buildFingerprint: 'test-build-1',
      );
      expect(result.manifest.functions, hasLength(2));
      expect(
        result.manifest.functions
            .singleWhere((function) => function.name == 'greet')
            .signature,
        const E0FunctionSignature(
          parameters: <E0ValueSchema>[E0ValueSchema.string],
          returnSchema: E0ValueSchema.string,
        ),
      );
      expect(result.source, contains('E0PatchRuntime.invoke'));
      expect(result.source, contains('<Object?>[name]'));
      expect(result.source, contains(r'$e0Result.value as String'));
      expect(result.source, contains('signatures: <String, String>'));
      expect(
        result.exclusions.single,
        contains('Unsupported parameter type Object'),
      );
    },
  );

  test('manifest v2 round-trips signatures and reads legacy manifests', () {
    final result = E0SourceTransformer().transform(
      source:
          'bool eligible(int age, bool verified) { return verified; }\n'
          'void main(List<String> args) {}',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/app.dart',
      appId: 'app',
      releaseId: 'release',
      buildFingerprint: 'test-build-1',
    );
    final decoded = E0ReleaseManifest.decode(result.manifest.encode());
    expect(
      decoded.functions.single.signature,
      result.manifest.functions.single.signature,
    );
    expect(decoded.encode(), result.manifest.encode());
  });
}
