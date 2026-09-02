import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

void main() {
  test('instruments instance methods with narrow receiver descriptors', () {
    final result = E0SourceTransformer().transform(
      source: _releaseSource,
      packageName: 'fixture',
      logicalLibraryPath: 'lib/pricing.dart',
      appId: 'app',
      releaseId: 'instance-release',
      buildFingerprint: 'test-build-1',
    );

    final calculate = result.manifest.functions.singleWhere(
      (function) =>
          function.name == 'calculate' &&
          function.receiver.ownerClass == 'PricingService',
    );
    final override = result.manifest.functions.singleWhere(
      (function) => function.receiver.ownerClass == 'OverridePricingService',
    );

    expect(calculate.id, isNot(override.id));
    expect(calculate.identity.ownerName, 'PricingService');
    expect(override.identity.ownerName, 'OverridePricingService');
    expect(
      calculate.receiver.members.map((member) => member.name),
      unorderedEquals(<String>['taxRate', '_fee', 'adjustment']),
    );
    expect(
      calculate.receiver.members.map((member) => member.name),
      isNot(contains('notSelected')),
    );
    expect(
      calculate.receiver.members.map((member) => member.slot),
      orderedEquals(<int>[0, 1, 2]),
    );
    expect(
      calculate.receiver.members.every(
        (member) => member.schema == E0ValueSchema.doubleValue,
      ),
      isTrue,
    );
    expect(result.source, contains('.E0ReceiverCapability'));
    expect(result.source, contains('return _receiver._fee'));
    expect(result.source, contains('return _receiver.adjustment'));
    expect(result.source, contains('receivers: <String, String>'));

    final lookup = result.source.indexOf('E0PatchRuntime.lookup');
    final adapterConstruction = result.source.indexOf(
      'receiver: _E0ReceiverAdapter',
    );
    expect(adapterConstruction, greaterThan(lookup));
    expect(
      result.source.substring(lookup, adapterConstruction),
      contains(r'if ($e0Patch != null)'),
    );

    final decoded = E0ReleaseManifest.decode(result.manifest.encode());
    expect(decoded.functions, hasLength(result.manifest.functions.length));
    expect(
      decoded.functions
          .singleWhere((function) => function.id == calculate.id)
          .receiver,
      calculate.receiver,
    );
  });

  test('freshens every generated identifier against ordinary source', () {
    final result = E0SourceTransformer().transform(
      source: r'''
import 'dart:math' as e0_runtime;
class _E0ReceiverAdapter0 {}
class PricingService {
  final double taxRate = 1;
  double calculate(double amount) {
    final $e0Patch = 0.0;
    final $e0Result = 0.0;
    return amount + this.taxRate + $e0Patch + $e0Result;
  }
}
void main(List<String> args) { e0_runtime.max(1, 2); }
''',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/collisions.dart',
      appId: 'app',
      releaseId: 'collisions',
      buildFingerprint: 'test-build-1',
    );

    expect(result.source, contains(' as e0_runtime_1;'));
    expect(result.source, contains(r'final $e0Patch_1 ='));
    expect(result.source, contains(r'final $e0Result_1 ='));
    expect(result.source, contains('class _E0ReceiverAdapter0_1 '));
    expect(result.source, contains('e0_runtime_1.E0PatchRuntime'));
  });

  test('records explicit unsupported instance target boundaries', () {
    final result = E0SourceTransformer().transform(
      source: '''
abstract class Unsupported {
  static int staticMethod(int value) { return value; }
  int abstractMethod(int value);
  int get accessor => 1;
  set accessor(int value) {}
  int operator +(int value) { return value; }
  R genericMethod<R>(R value) { return value; }
  Future<int> asyncMethod(int value) async { return value; }
}
class GenericOwner<T> {
  int calculate(int value) { return value; }
}
class UnknownProperty {
  int calculate(int value) { return value + this.missing; }
}
void main(List<String> args) {}
''',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/unsupported.dart',
      appId: 'app',
      releaseId: 'unsupported',
      buildFingerprint: 'test-build-1',
    );

    expect(result.manifest.functions, hasLength(1));
    expect(result.manifest.functions.single.name, 'asyncMethod');
    expect(result.manifest.functions.single.signature.isAsync, isTrue);
    expect(result.exclusions, contains(contains('static method target')));
    expect(result.exclusions, contains(contains('abstract method target')));
    expect(result.exclusions, contains(contains('accessor target')));
    expect(result.exclusions, contains(contains('operator target')));
    expect(result.exclusions, contains(contains('generic owner class')));
    expect(result.exclusions, contains(contains('Generic patch functions')));
    expect(result.exclusions, contains(contains('unresolved explicit')));
  });
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

class RegionalPricingService extends PricingService {
  RegionalPricingService(super.taxRate, super.fee);
}

class OverridePricingService extends PricingService {
  OverridePricingService(super.taxRate, super.fee);

  @override
  double calculate(double amount, double quantity) {
    return amount + quantity + this.taxRate;
  }
}

void main(List<String> args) {}
''';
