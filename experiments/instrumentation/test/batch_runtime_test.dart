import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  late E0ReleaseManifest manifest;

  setUp(() {
    E0PatchRuntime.reset();
    manifest = E0SourceTransformer()
        .transform(
          source: _releaseSource,
          packageName: 'fixture',
          logicalLibraryPath: 'lib/batch.dart',
          appId: 'app',
          releaseId: 'batch-release',
          buildFingerprint: 'batch-build-1',
        )
        .manifest;
  });

  tearDown(E0PatchRuntime.reset);

  Map<String, int> functionsTable() => <String, int>{
    for (final function in manifest.functions) function.id: function.slot,
  };

  Map<String, String> signaturesTable() => <String, String>{
    for (final function in manifest.functions)
      function.id: function.signature.encode(),
  };

  Map<String, String> receiversTable() => <String, String>{
    for (final function in manifest.functions)
      function.id: function.receiver.encode(),
  };

  bool install(List<List<int>> programs) => E0PatchRuntime.installBatchBytes(
    programs,
    appId: manifest.appId,
    releaseId: manifest.releaseId,
    buildFingerprint: manifest.buildFingerprint,
    functions: functionsTable(),
    signatures: signaturesTable(),
    receivers: receiversTable(),
  );

  int slot(String name) =>
      manifest.functions.singleWhere((item) => item.name == name).slot;

  test('installs multiple supported slots atomically and invokes both', () {
    final add = E0PatchCompiler().compile(
      source: 'int add(int left, int right) { return left + right + 1; }',
      manifest: manifest,
      functionName: 'add',
      patchSequence: 1,
    );
    final multiply = E0PatchCompiler().compile(
      source: 'int multiply(int left, int right) { return left * right + 1; }',
      manifest: manifest,
      functionName: 'multiply',
      patchSequence: 1,
    );

    expect(
      install([add, multiply]),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );
    final addFunction = manifest.functions.singleWhere(
      (item) => item.name == 'add',
    );
    final multiplyFunction = manifest.functions.singleWhere(
      (item) => item.name == 'multiply',
    );
    expect(
      E0PatchRuntime.invoke(E0PatchRuntime.lookup(addFunction.slot)!, <Object?>[
        2,
        3,
      ]).value,
      6,
    );
    expect(
      E0PatchRuntime.invoke(
        E0PatchRuntime.lookup(multiplyFunction.slot)!,
        <Object?>[2, 3],
      ).value,
      7,
    );
  });

  test('rejects a mixed-sequence batch without publishing a partial table', () {
    final firstAdd = E0PatchCompiler().compile(
      source: 'int add(int left, int right) { return left + right + 1; }',
      manifest: manifest,
      functionName: 'add',
      patchSequence: 1,
    );
    final firstMultiply = E0PatchCompiler().compile(
      source: 'int multiply(int left, int right) { return left * right + 1; }',
      manifest: manifest,
      functionName: 'multiply',
      patchSequence: 1,
    );
    expect(install([firstAdd, firstMultiply]), isTrue);
    final beforeAdd = E0PatchRuntime.lookup(slot('add'));
    final beforeMultiply = E0PatchRuntime.lookup(slot('multiply'));

    final nextAdd = E0PatchCompiler().compile(
      source: 'int add(int left, int right) { return left + right + 2; }',
      manifest: manifest,
      functionName: 'add',
      patchSequence: 2,
    );
    final wrongSequence = E0PatchCompiler().compile(
      source: 'int multiply(int left, int right) { return left * right + 2; }',
      manifest: manifest,
      functionName: 'multiply',
      patchSequence: 3,
    );

    expect(install([nextAdd, wrongSequence]), isFalse);
    expect(E0PatchRuntime.lookup(slot('add')), same(beforeAdd));
    expect(E0PatchRuntime.lookup(slot('multiply')), same(beforeMultiply));
    expect(E0PatchRuntime.lastRejection, contains('mixed sequences'));
  });

  test('rejects malformed member without disturbing an active batch', () {
    final add = E0PatchCompiler().compile(
      source: 'int add(int left, int right) { return left + right + 1; }',
      manifest: manifest,
      functionName: 'add',
      patchSequence: 1,
    );
    final multiply = E0PatchCompiler().compile(
      source: 'int multiply(int left, int right) { return left * right + 1; }',
      manifest: manifest,
      functionName: 'multiply',
      patchSequence: 1,
    );
    expect(install([add, multiply]), isTrue);
    final beforeAdd = E0PatchRuntime.lookup(slot('add'));
    final beforeMultiply = E0PatchRuntime.lookup(slot('multiply'));

    expect(
      install([
        add,
        <int>[0, 1, 2],
      ]),
      isFalse,
    );
    expect(E0PatchRuntime.lookup(slot('add')), same(beforeAdd));
    expect(E0PatchRuntime.lookup(slot('multiply')), same(beforeMultiply));
    expect(E0PatchRuntime.lastRejection, isNotNull);
  });
}

const _releaseSource = '''
int add(int left, int right) { return left + right; }
int multiply(int left, int right) { return left * right; }
void main(List<String> args) {}
''';
