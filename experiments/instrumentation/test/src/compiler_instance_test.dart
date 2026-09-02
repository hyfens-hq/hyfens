import 'dart:convert';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  late E0ReleaseManifest manifest;
  late E0FunctionManifest function;

  setUp(() {
    E0PatchRuntime.reset();
    manifest = E0SourceTransformer()
        .transform(
          source: _releaseSource,
          packageName: 'fixture',
          logicalLibraryPath: 'lib/pricing.dart',
          appId: 'app',
          releaseId: 'instance-release',
          buildFingerprint: 'test-build-1',
        )
        .manifest;
    function = manifest.functions.singleWhere(
      (item) => item.receiver.ownerClass == 'PricingService',
    );
  });

  test('compiles explicit receiver reads and validates the adapter', () {
    final patch = _compile(manifest);
    expect(_install(patch, manifest), isTrue);

    final values = <String, Object?>{
      'taxRate': 1.5,
      '_fee': 2.0,
      'adjustment': 3.0,
    };
    final result = E0PatchRuntime.invoke(
      E0PatchRuntime.lookup(function.slot)!,
      <Object?>[10.0, 2.0],
      receiver: _Receiver(function.receiver, values),
    );
    expect(result.isSuccess, isTrue);
    expect(result.value, 26.5);
  });

  test('fails closed for wrong adapter identity and member value type', () {
    final patch = _compile(manifest);
    expect(_install(patch, manifest), isTrue);
    var result = E0PatchRuntime.invoke(
      E0PatchRuntime.lookup(function.slot)!,
      <Object?>[10.0, 2.0],
      receiver: _Receiver(
        const E0ReceiverDescriptor(
          id: 'wrong',
          ownerClass: 'PricingService',
          members: <E0ReceiverMember>[],
        ),
        const <String, Object?>{},
      ),
    );
    expect(result.isSuccess, isFalse);
    expect(E0PatchRuntime.lastRejection, contains('capability mismatch'));

    expect(_install(_compile(manifest, patchSequence: 2), manifest), isTrue);
    result = E0PatchRuntime.invoke(
      E0PatchRuntime.lookup(function.slot)!,
      <Object?>[10.0, 2.0],
      receiver: _Receiver(function.receiver, <String, Object?>{
        'taxRate': 'malformed',
        '_fee': 2.0,
        'adjustment': 3.0,
      }),
    );
    expect(result.isSuccess, isFalse);
    expect(E0PatchRuntime.lookup(function.slot), isNull);
    expect(E0PatchRuntime.lastRejection, contains('finite double'));
  });

  test('rejects a mismatched or invalid receiver descriptor at activation', () {
    final patch = _compile(manifest);
    final json = jsonDecode(utf8.decode(patch)) as Map<String, Object?>;
    final receiver = json['receiver']! as Map<String, Object?>;
    receiver['id'] = 'forged';
    expect(_install(utf8.encode(jsonEncode(json)), manifest), isFalse);
    expect(E0PatchRuntime.lastRejection, contains('descriptor mismatch'));

    final invalidSlot = jsonDecode(utf8.decode(patch)) as Map<String, Object?>;
    invalidSlot['code'] = <int>[
      E0Opcode.loadReceiver.code,
      function.receiver.members.length,
      E0Opcode.returnValue.code,
    ];
    expect(_install(utf8.encode(jsonEncode(invalidSlot)), manifest), isFalse);
    expect(E0PatchRuntime.lastRejection, contains('payload hash mismatch'));
  });

  group('compiler capability boundary', () {
    test('rejects raw this', () {
      expect(
        () => _compile(
          manifest,
          source: '''
class PricingService {
  double calculate(double amount, double quantity) { return this; }
}
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Raw this'),
          ),
        ),
      );
    });

    test('rejects receiver method invocation and unselected properties', () {
      expect(
        () => _compile(
          manifest,
          source: '''
class PricingService {
  double calculate(double amount, double quantity) {
    return this.helper(amount);
  }
}
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Receiver method invocation'),
          ),
        ),
      );
      expect(
        () => _compile(
          manifest,
          source: '''
class PricingService {
  double calculate(double amount, double quantity) {
    return amount + this.notSelected;
  }
}
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('not selected'),
          ),
        ),
      );
    });

    test('does not infer unqualified receiver access', () {
      final unqualifiedManifest = E0SourceTransformer()
          .transform(
            source: '''
class PricingService {
  final double taxRate = 1;
  double calculate(double amount, double quantity) {
    return amount + quantity + taxRate;
  }
}
void main(List<String> args) {}
''',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/unqualified.dart',
            appId: 'app',
            releaseId: 'unqualified',
            buildFingerprint: 'test-build-1',
          )
          .manifest;
      expect(unqualifiedManifest.functions.single.receiver.members, isEmpty);
      expect(
        () => E0PatchCompiler().compile(
          source: '''
class PricingService {
  double calculate(double amount, double quantity) {
    return amount + quantity + taxRate;
  }
}
''',
          manifest: unqualifiedManifest,
          className: 'PricingService',
          functionName: 'calculate',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('unqualified receiver'), contains('this.property')),
          ),
        ),
      );
      expect(
        () => E0PatchCompiler().compile(
          source: '''
class PricingService {
  double calculate(double amount, double quantity) {
    return amount + quantity + this.taxRate;
  }
}
''',
          manifest: unqualifiedManifest,
          className: 'PricingService',
          functionName: 'calculate',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('not selected'),
          ),
        ),
      );
    });

    test('rejects setter writes pending staged atomic commit semantics', () {
      expect(
        () => _compile(
          manifest,
          source: '''
class PricingService {
  double calculate(double amount, double quantity) {
    this.taxRate = 9.0;
    return amount;
  }
}
''',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('setter writes'), contains('staged/atomic')),
          ),
        ),
      );
    });

    test('rejects collection mutation rooted in a receiver property', () {
      final collectionManifest = E0SourceTransformer()
          .transform(
            source: '''
class CollectionService {
  CollectionService(this.items);
  final List<int> items;
  List<int> revise() { return this.items; }
}
void main(List<String> args) {}
''',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/collection_service.dart',
            appId: 'app',
            releaseId: 'receiver-collection',
            buildFingerprint: 'test-build-1',
          )
          .manifest;

      for (final body in <String>[
        'this.items.add(3);',
        'this.items[0] = 3;',
        'this.items[0]++;',
      ]) {
        expect(
          () => E0PatchCompiler().compile(
            source:
                '''
class CollectionService {
  List<int> revise() {
    $body
    return this.items;
  }
}
''',
            manifest: collectionManifest,
            className: 'CollectionService',
            functionName: 'revise',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('setter writes'), contains('staged/atomic')),
            ),
          ),
        );
      }
    });

    test('rejects receiver-origin mutation through local alias chains', () {
      final collectionManifest = E0SourceTransformer()
          .transform(
            source: '''
class CollectionService {
  CollectionService(this.items);
  final List<int> items;
  List<int> revise() { return this.items; }
}
void main(List<String> args) {}
''',
            packageName: 'fixture',
            logicalLibraryPath: 'lib/collection_alias_service.dart',
            appId: 'app',
            releaseId: 'receiver-collection-alias',
            buildFingerprint: 'test-build-1',
          )
          .manifest;

      for (final body in <String>[
        '''
    List<int> copy = this.items;
    copy.add(3);
''',
        '''
    List<int> first = (this.items);
    List<int> second = (first);
    second[0] = 3;
''',
        '''
    List<int> copy = <int>[];
    copy = (this.items);
    copy[0]++;
''',
      ]) {
        expect(
          () => E0PatchCompiler().compile(
            source:
                '''
class CollectionService {
  List<int> revise() {
$body
    return this.items;
  }
}
''',
            manifest: collectionManifest,
            className: 'CollectionService',
            functionName: 'revise',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('setter writes'), contains('staged/atomic')),
            ),
          ),
        );
      }

      expect(
        E0PatchCompiler().compile(
          source: '''
class CollectionService {
  List<int> revise() {
    List<int> copy = (this.items);
    int total = 0;
    for (int value in copy) {
      total += value;
    }
    return copy;
  }
}
''',
          manifest: collectionManifest,
          className: 'CollectionService',
          functionName: 'revise',
        ),
        isNotEmpty,
        reason: 'receiver-origin aliases remain readable and iterable',
      );
    });

    final unsupported = <String, String>{
      'static': 'class PricingService { static double calculate(double a, double b) { return a; } }',
      'abstract': 'abstract class PricingService { double calculate(double a, double b); }',
      'getter': 'class PricingService { double get calculate { return 1.0; } }',
      'operator': 'class PricingService { double operator +(double value) { return value; } }',
      'generic':
          'class PricingService { T calculate<T>(T a, T b) { return a; } }',
    };
    for (final scenario in unsupported.entries) {
      test('rejects ${scenario.key} method targets', () {
        expect(
          () => E0PatchCompiler().compile(
            source: scenario.value,
            manifest: manifest,
            className: 'PricingService',
            functionName: scenario.key == 'operator' ? '+' : 'calculate',
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Unsupported patch method'),
            ),
          ),
        );
      });
    }

    test('rejects changing a release method signature from sync to async', () {
      expect(
        () => E0PatchCompiler().compile(
          source: 'class PricingService { Future<double> calculate(double a, double b) async { return a; } }',
          manifest: manifest,
          className: 'PricingService',
          functionName: 'calculate',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('does not match release'),
          ),
        ),
      );
    });
  });
}

List<int> _compile(
  E0ReleaseManifest manifest, {
  String source = _patchSource,
  int patchSequence = 1,
}) => E0PatchCompiler().compile(
  source: source,
  manifest: manifest,
  className: 'PricingService',
  functionName: 'calculate',
  patchSequence: patchSequence,
);

bool _install(List<int> patch, E0ReleaseManifest manifest) =>
    E0PatchRuntime.installBytes(
      patch,
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      functions: <String, int>{
        for (final function in manifest.functions) function.id: function.slot,
      },
      signatures: <String, String>{
        for (final function in manifest.functions)
          function.id: function.signature.encode(),
      },
      receivers: <String, String>{
        for (final function in manifest.functions)
          function.id: function.receiver.encode(),
      },
    );

final class _Receiver implements E0ReceiverCapability {
  const _Receiver(this.descriptor, this.values);

  final E0ReceiverDescriptor descriptor;
  final Map<String, Object?> values;

  @override
  String get descriptorId => descriptor.id;

  @override
  Object? read(int slot) => values[descriptor.members[slot].name];
}

const _releaseSource = '''
class PricingService {
  PricingService(this.taxRate, this._fee);
  final double taxRate;
  final double _fee;
  final double notSelected = 100;
  double get adjustment => 3;
  double calculate(double amount, double quantity) {
    return amount + quantity + this.taxRate + this._fee + this.adjustment;
  }
}
void main(List<String> args) {}
''';

const _patchSource = '''
class PricingService {
  double calculate(double amount, double quantity) {
    return amount * quantity + this.taxRate + this._fee + this.adjustment;
  }
}
''';
