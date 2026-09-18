import 'dart:convert';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

const _source = r'''
abstract class Widget {}
abstract class StatelessWidget extends Widget {}
class BuildContext {}
enum MainAxisSize { min, max }
class TextStyle {
  const TextStyle({double? fontSize});
}
class Text extends Widget {
  const Text(String data, {TextStyle? style});
}
class Column extends Widget {
  const Column({MainAxisSize mainAxisSize = MainAxisSize.max, required List<Widget> children});
}
class ElevatedButton extends Widget {
  const ElevatedButton({required void Function()? onPressed, required Widget child});
}

class PricingCard extends StatelessWidget {
  const PricingCard(this.featured, this.plan);
  final bool featured;
  final String plan;

  Widget build(BuildContext context) {
    if (this.featured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('PATCH ${this.plan}', style: TextStyle(fontSize: 24.0)),
          Text('conditional hierarchy'),
          ElevatedButton(onPressed: null, child: Text('Upgrade')),
        ],
      );
    }
    return Text('standard ${this.plan}');
  }
}

void main(List<String> arguments) {}
''';

final _textFactory = E0WidgetFactoryDescriptor(
  id: 'flutter.text.v1',
  sourceName: 'Text',
  properties: const <E0WidgetPropertyDescriptor>[
    E0WidgetPropertyDescriptor(
      name: 'data',
      schema: E0ValueSchema.string,
      required: true,
    ),
    E0WidgetPropertyDescriptor(
      name: 'fontSize',
      schema: E0ValueSchema.doubleValue,
    ),
  ],
  minChildren: 0,
  maxChildren: 0,
);

final _columnFactory = E0WidgetFactoryDescriptor(
  id: 'flutter.column.v1',
  sourceName: 'Column',
  properties: const <E0WidgetPropertyDescriptor>[
    E0WidgetPropertyDescriptor(
      name: 'mainAxisSize',
      schema: E0ValueSchema.string,
      allowedValues: <String>['min', 'max'],
    ),
  ],
  minChildren: 0,
  maxChildren: E0WidgetFactoryRegistry.maxChildren,
);

final _buttonFactory = E0WidgetFactoryDescriptor(
  id: 'flutter.elevated-button.v1',
  sourceName: 'ElevatedButton',
  properties: const <E0WidgetPropertyDescriptor>[],
  minChildren: 1,
  maxChildren: 1,
);

List<E0WidgetFactoryDescriptor> get _factories => <E0WidgetFactoryDescriptor>[
  _textFactory,
  _columnFactory,
  _buttonFactory,
];

void main() {
  late List<int> patchBytes;

  setUp(() {
    E0PatchRuntime.reset();
    transformation = E0SourceTransformer().transform(
      source: _source,
      packageName: 'widget_fixture',
      logicalLibraryPath: 'lib/main.dart',
      appId: 'widget-app',
      releaseId: 'release-1',
      buildFingerprint: 'widget-build-1',
      widgetFactories: _factories,
      widgetBuildClasses: const <String>{'PricingCard'},
      allowSyntheticWidgetTypes: true,
    );
    buildFunction = transformation.manifest.functions.singleWhere(
      (function) =>
          function.name == 'build' &&
          function.receiver.ownerClass == 'PricingCard',
    );
    patchBytes = E0PatchCompiler().compile(
      source: _source,
      manifest: transformation.manifest,
      className: 'PricingCard',
      functionName: 'build',
      allowSyntheticWidgetTypes: true,
    );
  });

  tearDown(E0PatchRuntime.reset);

  test('transparent guard keeps BuildContext host-owned', () {
    expect(buildFunction.signature, e0WidgetBuildSignature);
    expect(
      buildFunction.receiver.members.map((item) => item.name),
      containsAll(<String>['featured', 'plan']),
    );
    expect(transformation.source, contains('E0PatchRuntime.invokeWidget'));
    expect(transformation.source, contains('<Object?>[]'));
    expect(transformation.source, isNot(contains('<Object?>[context]')));
    expect(_source, isNot(contains('PatchView')));
    expect(_source, isNot(contains('@')));
  });

  test('syntax-only Flutter and factory shadows fail closed by default', () {
    final shadowed = E0SourceTransformer().transform(
      source: "import 'package:flutter/material.dart';\n$_source",
      packageName: 'widget_fixture',
      logicalLibraryPath: 'lib/main.dart',
      appId: 'widget-app',
      releaseId: 'release-1',
      buildFingerprint: 'widget-build-1',
      widgetFactories: _factories,
      widgetBuildClasses: const <String>{'PricingCard'},
    );
    expect(
      shadowed.manifest.functions.where(
        (function) => function.receiver.ownerClass == 'PricingCard',
      ),
      isEmpty,
    );
    expect(
      shadowed.exclusions,
      contains(
        contains(
          'widget ABI requires canonical unshadowed package:flutter types',
        ),
      ),
    );

    expect(
      () => E0PatchCompiler().compile(
        source: _source,
        manifest: transformation.manifest,
        className: 'PricingCard',
        functionName: 'build',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('package:flutter import'),
        ),
      ),
    );

    const factoryShadowPatch = '''
import 'package:flutter/material.dart';
Widget Text(String value) => throw value;
class PricingCard extends StatelessWidget {
  const PricingCard({required this.featured, required this.plan});
  final bool featured;
  final String plan;
  Widget build(BuildContext context) { return Text(this.plan); }
}
''';
    expect(
      () => E0PatchCompiler().compile(
        source: factoryShadowPatch,
        manifest: transformation.manifest,
        className: 'PricingCard',
        functionName: 'build',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('shadows the bounded Flutter ABI'),
        ),
      ),
    );
  });

  test('compiler and runtime produce text, conditional hierarchy, style, and children', () {
    E0PatchRuntime.configureWidgetFactories(_registry());
    expect(_install(patchBytes), isTrue);
    final program = E0PatchRuntime.lookup(buildFunction.slot)!;

    final featured = E0PatchRuntime.invokeWidget(
      program,
      const <Object?>[],
      receiver: _Receiver(buildFunction.receiver, featured: true, plan: 'Pro'),
    );
    expect(featured.isSuccess, isTrue);
    expect(
      featured.value,
      _Node(
        'Column',
        const <String, Object?>{'mainAxisSize': 'min'},
        <_Node>[
          _Node('Text', const <String, Object?>{
            'data': 'PATCH Pro',
            'fontSize': 24.0,
          }),
          _Node('Text', const <String, Object?>{
            'data': 'conditional hierarchy',
          }),
          _Node('ElevatedButton', const <String, Object?>{}, <_Node>[
            _Node('Text', const <String, Object?>{'data': 'Upgrade'}),
          ]),
        ],
      ),
    );

    final standard = E0PatchRuntime.invokeWidget(
      program,
      const <Object?>[],
      receiver: _Receiver(
        buildFunction.receiver,
        featured: false,
        plan: 'Basic',
      ),
    );
    expect(
      standard.value,
      _Node('Text', const <String, Object?>{'data': 'standard Basic'}),
    );
  });

  test(
    'unknown factories, properties, types, and invalid trees fail closed',
    () {
      final registry = _registry();
      expect(
        () => registry.materialize(<String, Object?>{
          'factory': 'flutter.unknown.v1',
          'properties': <String, Object?>{},
          'children': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => registry.materialize(<String, Object?>{
          'factory': 'flutter.column.v1',
          'properties': <String, Object?>{'mainAxisSize': 'sideways'},
          'children': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('outside its allowed values'),
          ),
        ),
      );
      expect(
        () => registry.materialize(
          _description('flutter.text.v1', <String, Object?>{
            'data': 'ok',
            'unknown': true,
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => registry.materialize(
          _description('flutter.text.v1', <String, Object?>{'data': 7}),
        ),
        throwsFormatException,
      );
      expect(
        () => registry.materialize(<String, Object?>{
          'factory': 'flutter.text.v1',
          'properties': <String, Object?>{'data': 'bad'},
          'children': <Object?>[],
          'extra': true,
        }),
        throwsFormatException,
      );

      Object tree = _description('flutter.text.v1', <String, Object?>{
        'data': 'leaf',
      });
      for (var index = 0; index <= E0WidgetFactoryRegistry.maxDepth; index++) {
        tree = <String, Object?>{
          'factory': 'flutter.column.v1',
          'properties': <String, Object?>{},
          'children': <Object?>[tree],
        };
      }
      expect(() => registry.materialize(tree), throwsFormatException);
    },
  );

  test('widget depth bound is reachable through E0 value normalization', () {
    final registry = _registry();
    Object atLimit = _description('flutter.text.v1', <String, Object?>{
      'data': 'leaf',
    });
    for (var depth = 0; depth < E0WidgetFactoryRegistry.maxDepth; depth++) {
      atLimit = <String, Object?>{
        'factory': 'flutter.column.v1',
        'properties': <String, Object?>{},
        'children': <Object?>[atLimit],
      };
    }
    final normalized = E0Value.fromHost(
      atLimit,
      e0WidgetDescriptionSchema,
    ).toHost(e0WidgetDescriptionSchema);
    expect(registry.materialize<_Node>(normalized), isA<_Node>());

    final overLimit = <String, Object?>{
      'factory': 'flutter.column.v1',
      'properties': <String, Object?>{},
      'children': <Object?>[atLimit],
    };
    final normalizedOver = E0Value.fromHost(
      overLimit,
      e0WidgetDescriptionSchema,
    ).toHost(e0WidgetDescriptionSchema);
    expect(
      () => registry.materialize<_Node>(normalizedOver),
      throwsFormatException,
    );
  });

  test('empty direct property names are rejected by factory contracts', () {
    expect(
      () => E0WidgetFactoryDescriptor(
        id: 'invalid.empty-property.v1',
        sourceName: 'InvalidWidget',
        properties: const <E0WidgetPropertyDescriptor>[
          E0WidgetPropertyDescriptor(name: '', schema: E0ValueSchema.string),
        ],
        minChildren: 0,
        maxChildren: 0,
      ),
      throwsFormatException,
    );
  });

  test('program factory list is the install and execution allowlist', () {
    final valid = _decode(patchBytes);
    final omitted = _copyProgram(
      valid,
      widgetFactories: valid.widgetFactories
          .where((factory) => factory.id != _textFactory.id)
          .toList(growable: false),
    );
    final omittedBytes = E0PatchContainer.encode(
      appId: transformation.manifest.appId,
      releaseId: transformation.manifest.releaseId,
      buildFingerprint: transformation.manifest.buildFingerprint,
      program: omitted,
    );
    E0PatchRuntime.configureWidgetFactories(_registry());
    expect(_install(omittedBytes), isFalse);
    expect(E0PatchRuntime.lastRejection, contains('referenced but undeclared'));

    final direct = E0PatchRuntime.invokeWidget<_Node>(
      omitted,
      const <Object?>[],
      receiver: _Receiver(
        buildFunction.receiver,
        featured: false,
        plan: 'Base',
      ),
    );
    expect(direct.isRuntimeFault, isTrue);
    expect(E0PatchRuntime.lastRejection, contains('not declared'));
  });

  test('wrong materialized root deactivates before the generated cast', () {
    final wrongRoot = E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
      E0WidgetFactoryRegistration(
        descriptor: _textFactory,
        create: (_, _) => 'not a widget node',
      ),
      ..._registrations().skip(1),
    ]);
    E0PatchRuntime.configureWidgetFactories(wrongRoot);
    expect(_install(patchBytes), isTrue);
    final program = E0PatchRuntime.lookup(buildFunction.slot)!;
    final result = E0PatchRuntime.invokeWidget<_Node>(
      program,
      const <Object?>[],
      receiver: _Receiver(
        buildFunction.receiver,
        featured: false,
        plan: 'Base',
      ),
    );
    expect(result.isRuntimeFault, isTrue);
    expect(E0PatchRuntime.lookup(buildFunction.slot), isNull);
    expect(E0PatchRuntime.lastRejection, contains('expected _Node'));
  });

  test(
    'invalid materialization deactivates the slot and exposes base path',
    () {
      final rejectingRegistry = E0WidgetFactoryRegistry(
        <E0WidgetFactoryRegistration>[
          E0WidgetFactoryRegistration(
            descriptor: _textFactory,
            create: (_, _) => throw StateError('host rejected widget'),
          ),
          ..._registrations().skip(1),
        ],
      );
      E0PatchRuntime.configureWidgetFactories(rejectingRegistry);
      expect(_install(patchBytes), isTrue);
      final program = E0PatchRuntime.lookup(buildFunction.slot)!;
      final result = E0PatchRuntime.invokeWidget(
        program,
        const <Object?>[],
        receiver: _Receiver(
          buildFunction.receiver,
          featured: false,
          plan: 'Base',
        ),
      );
      expect(result.isRuntimeFault, isTrue);
      expect(E0PatchRuntime.lookup(buildFunction.slot), isNull);
      // This is the exact condition under which the generated callee guard
      // continues into the original AOT `build` body.
      expect(transformation.source, contains('if (\$e0Result.isSuccess)'));
    },
  );

  test(
    'compiler rejects unsupported constructors, properties, and callbacks',
    () {
      List<int> compileReplacement(String replacement) =>
          E0PatchCompiler().compile(
            source: _source.replaceFirst(
              "return Text('standard \${this.plan}');",
              replacement,
            ),
            manifest: transformation.manifest,
            className: 'PricingCard',
            functionName: 'build',
            allowSyntheticWidgetTypes: true,
          );

      expect(
        () => compileReplacement("return Container();"),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unknown widget factory'),
          ),
        ),
      );
      expect(
        () => compileReplacement("return Text('x', key: null);"),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported Text properties'),
          ),
        ),
      );
      expect(
        () => compileReplacement(
          "return ElevatedButton(onPressed: () {}, child: Text('x'));",
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('host-owned'),
          ),
        ),
      );
    },
  );
}

bool _install(List<int> bytes) => E0PatchRuntime.installBytes(
  bytes,
  appId: 'widget-app',
  releaseId: 'release-1',
  buildFingerprint: 'widget-build-1',
  functions: <String, int>{buildFunction.id: buildFunction.slot},
  signatures: <String, String>{
    buildFunction.id: buildFunction.signature.encode(),
  },
  receivers: <String, String>{
    buildFunction.id: buildFunction.receiver.encode(),
  },
);

E0PatchProgram _decode(List<int> bytes) => E0PatchContainer.decode(
  bytes,
  expectedAppId: transformation.manifest.appId,
  expectedReleaseId: transformation.manifest.releaseId,
  expectedBuildFingerprint: transformation.manifest.buildFingerprint,
  expectedFunctions: <String, int>{
    for (final function in transformation.manifest.functions)
      function.id: function.slot,
  },
  expectedSignatures: <String, E0FunctionSignature>{
    for (final function in transformation.manifest.functions)
      function.id: function.signature,
  },
  expectedReceivers: <String, E0ReceiverDescriptor>{
    for (final function in transformation.manifest.functions)
      function.id: function.receiver,
  },
);

E0PatchProgram _copyProgram(
  E0PatchProgram source, {
  required List<E0WidgetFactoryDescriptor> widgetFactories,
}) => E0PatchProgram(
  functionId: source.functionId,
  slot: source.slot,
  constants: source.constants,
  code: source.code,
  locals: source.locals,
  handlers: source.handlers,
  capabilities: source.capabilities,
  asyncPoints: source.asyncPoints,
  widgetFactories: widgetFactories,
  signature: source.signature,
  receiver: source.receiver,
  patchSequence: source.patchSequence,
);

late E0FunctionManifest buildFunction;
late E0TransformResult transformation;

E0WidgetFactoryRegistry _registry() =>
    E0WidgetFactoryRegistry(_registrations());

List<E0WidgetFactoryRegistration> _registrations() =>
    <E0WidgetFactoryRegistration>[
      E0WidgetFactoryRegistration(
        descriptor: _textFactory,
        create: (properties, children) => _Node('Text', properties),
      ),
      E0WidgetFactoryRegistration(
        descriptor: _columnFactory,
        create: (properties, children) =>
            _Node('Column', properties, children.cast<_Node>()),
      ),
      E0WidgetFactoryRegistration(
        descriptor: _buttonFactory,
        create: (properties, children) =>
            _Node('ElevatedButton', properties, children.cast<_Node>()),
      ),
    ];

Map<String, Object?> _description(
  String factory,
  Map<String, Object?> properties,
) => <String, Object?>{
  'factory': factory,
  'properties': properties,
  'children': <Object?>[],
};

final class _Receiver implements E0ReceiverCapability {
  _Receiver(this.descriptor, {required this.featured, required this.plan});

  final E0ReceiverDescriptor descriptor;
  final bool featured;
  final String plan;

  @override
  String get descriptorId => descriptor.id;

  @override
  Object? read(int slot) => switch (descriptor.members[slot].name) {
    'featured' => featured,
    'plan' => plan,
    final name => throw StateError('Unexpected receiver member $name'),
  };
}

final class _Node {
  const _Node(this.type, this.properties, [this.children = const <_Node>[]]);

  final String type;
  final Map<String, Object?> properties;
  final List<_Node> children;

  @override
  bool operator ==(Object other) =>
      other is _Node &&
      type == other.type &&
      jsonEncode(properties) == jsonEncode(other.properties) &&
      _listEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(type, jsonEncode(properties), Object.hashAll(children));

  static bool _listEquals(List<_Node> left, List<_Node> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  @override
  String toString() => '$type$properties$children';
}
