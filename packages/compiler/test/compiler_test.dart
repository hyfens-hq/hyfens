import 'package:hyfens_compiler/compiler.dart';
import 'package:test/test.dart';

void main() {
  test('facade compiles a release-selected typed function', () {
    final manifest = E0SourceTransformer()
        .transform(
          source: 'int add(int left, int right) { return left + right; }\nvoid main() {}',
          packageName: 'compiler_fixture',
          logicalLibraryPath: 'lib/add.dart',
          appId: 'app',
          releaseId: 'release',
          buildFingerprint: 'build',
        )
        .manifest;
    final bytes = const HyfensCompiler().compile(
      PatchCompileRequest(
        source: 'int add(int left, int right) { return left + right; }',
        manifest: manifest,
        functionName: 'add',
      ),
    );
    expect(bytes, isNotEmpty);
    expect(manifest.functions, hasLength(1));
  });
}
