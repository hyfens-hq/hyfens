import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

const _flutterSource = '''
import 'package:flutter/material.dart';

class CardView extends StatelessWidget {
  const CardView();

  Widget build(BuildContext context) {
    if (context == context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('patched'),
          ElevatedButton(onPressed: () {}, child: Text('tap')),
        ],
      );
    }
    return Text('unreachable');
  }
}

class Counter extends StatefulWidget {
  const Counter();
}

class CounterState extends State<Counter> {
  final int count = 1;
  final String label = 'state';

  int increment() {
    return this.count + 1;
  }

  Widget build(BuildContext context) {
    return Text(label);
  }
}

class ConsumerState<T> extends State<T> {}

class ConsumerCounterState extends ConsumerState<Counter> {
  Widget build(BuildContext context) {
    return Text('consumer');
  }
}

void main() {}
''';

const _voidSource = '''
class Controller {
  void handle() {
    final int value = 1;
  }
}

void main() {}
''';

const _asyncSource = '''
Future<int> compute(int value) async {
  final int result = await Future.value(value);
  return result + 1;
}

void main() {}
''';

void main() {
  setUp(E0PatchRuntime.reset);
  tearDown(E0PatchRuntime.reset);

  test(
    'ordinary Flutter build receives opaque BuildContext and materializes',
    () {
      final transformation = _transform(_flutterSource);
      final build = transformation.manifest.functions.singleWhere(
        (function) =>
            function.name == 'build' &&
            function.receiver.ownerClass == 'CardView',
      );
      expect(build.signature, e0FlutterWidgetBuildSignature);
      expect(transformation.source, contains('invokeWidget<Widget>'));
      expect(transformation.source, contains('<Object?>[context]'));
      expect(
        transformation.manifest.functions
            .singleWhere(
              (function) =>
                  function.name == 'build' &&
                  function.receiver.ownerClass == 'CounterState',
            )
            .signature,
        e0FlutterWidgetBuildSignature,
      );
      expect(
        transformation.manifest.functions
            .singleWhere(
              (function) =>
                  function.name == 'build' &&
                  function.receiver.ownerClass == 'CounterState',
            )
            .receiver
            .members
            .map((member) => member.name),
        contains('label'),
      );
      expect(
        transformation.manifest.functions
            .singleWhere(
              (function) =>
                  function.name == 'build' &&
                  function.receiver.ownerClass == 'ConsumerCounterState',
            )
            .signature,
        e0FlutterWidgetBuildSignature,
      );

      final bytes = E0PatchCompiler().compile(
        source: _flutterSource,
        manifest: transformation.manifest,
        className: 'CardView',
        functionName: 'build',
      );
      E0PatchRuntime.configureWidgetFactories(_fakeWidgetRegistry());
      expect(
        E0PatchRuntime.installBytes(
          bytes,
          appId: 'flutter-abi',
          releaseId: 'release-1',
          buildFingerprint: 'build-1',
          functions: <String, int>{
            for (final item in transformation.manifest.functions)
              item.id: item.slot,
          },
          signatures: <String, String>{
            for (final item in transformation.manifest.functions)
              item.id: item.signature.encode(),
          },
          receivers: <String, String>{
            for (final item in transformation.manifest.functions)
              item.id: item.receiver.encode(),
          },
        ),
        isTrue,
        reason: E0PatchRuntime.lastRejection,
      );

      final program = E0PatchRuntime.lookup(build.slot)!;
      final result = E0PatchRuntime.invokeWidget<_Node>(program, <Object?>[
        Object(),
      ], receiver: _DescriptorReceiver(build.receiver));
      expect(result.isSuccess, isTrue, reason: E0PatchRuntime.lastRejection);
      final root = result.value! as _Node;
      expect(root.factory, 'flutter.column.v1');
      expect(root.properties['mainAxisSize'], 'min');
      expect(root.children, hasLength(2));
      expect(root.children[0].properties['data'], 'patched');
      final callback = root.children[1].properties['onPressed'];
      expect(callback, isA<E0HostCallbackValue>());
      expect((callback! as E0HostCallbackValue).invoke(), isNull);
    },
  );

  test('ordinary State<T> method behavior reads the existing state schema', () {
    final transformation = _transform(_flutterSource);
    final increment = transformation.manifest.functions.singleWhere(
      (function) =>
          function.name == 'increment' &&
          function.receiver.ownerClass == 'CounterState',
    );
    expect(
      increment.receiver.members.map((member) => member.name),
      contains('count'),
    );
    final bytes = E0PatchCompiler().compile(
      source: _flutterSource,
      manifest: transformation.manifest,
      className: 'CounterState',
      functionName: 'increment',
    );
    expect(
      E0PatchRuntime.installBytes(
        bytes,
        appId: 'flutter-abi',
        releaseId: 'release-1',
        buildFingerprint: 'build-1',
        functions: <String, int>{
          for (final item in transformation.manifest.functions)
            item.id: item.slot,
        },
        signatures: <String, String>{
          for (final item in transformation.manifest.functions)
            item.id: item.signature.encode(),
        },
        receivers: <String, String>{
          for (final item in transformation.manifest.functions)
            item.id: item.receiver.encode(),
        },
      ),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );
    final result = E0PatchRuntime.invoke(
      E0PatchRuntime.lookup(increment.slot)!,
      const <Object?>[],
      receiver: _DescriptorReceiver(increment.receiver, <String, Object?>{
        'count': 4,
      }),
    );
    expect(result.isSuccess, isTrue, reason: E0PatchRuntime.lastRejection);
    expect(result.value, 5);
  });

  test('widget builds can read schema-safe state fields implicitly', () {
    final transformation = _transform(_flutterSource);
    final build = transformation.manifest.functions.singleWhere(
      (function) =>
          function.name == 'build' &&
          function.receiver.ownerClass == 'CounterState',
    );
    final bytes = E0PatchCompiler().compile(
      source: _flutterSource,
      manifest: transformation.manifest,
      className: 'CounterState',
      functionName: 'build',
    );
    E0PatchRuntime.configureWidgetFactories(_fakeWidgetRegistry());
    expect(
      E0PatchRuntime.installBytes(
        bytes,
        appId: 'flutter-abi',
        releaseId: 'release-1',
        buildFingerprint: 'build-1',
        functions: <String, int>{
          for (final item in transformation.manifest.functions)
            item.id: item.slot,
        },
        signatures: <String, String>{
          for (final item in transformation.manifest.functions)
            item.id: item.signature.encode(),
        },
        receivers: <String, String>{
          for (final item in transformation.manifest.functions)
            item.id: item.receiver.encode(),
        },
      ),
      isTrue,
      reason: E0PatchRuntime.lastRejection,
    );
    final result = E0PatchRuntime.invokeWidget<_Node>(
      E0PatchRuntime.lookup(build.slot)!,
      <Object?>[Object()],
      receiver: _DescriptorReceiver(build.receiver, <String, Object?>{
        'label': 'patched state',
      }),
    );
    expect(result.isSuccess, isTrue, reason: E0PatchRuntime.lastRejection);
    expect((result.value! as _Node).properties['data'], 'patched state');
  });

  test('void state/controller behavior has a typed no-value ABI', () {
    final transformation = _transform(_voidSource);
    final handle = transformation.manifest.functions.singleWhere(
      (function) =>
          function.name == 'handle' &&
          function.receiver.ownerClass == 'Controller',
    );
    expect(handle.signature.returnSchema, E0ValueSchema.voidValue);
    final bytes = E0PatchCompiler().compile(
      source: _voidSource,
      manifest: transformation.manifest,
      className: 'Controller',
      functionName: 'handle',
    );
    expect(
      E0PatchRuntime.installBytes(
        bytes,
        appId: 'flutter-abi',
        releaseId: 'release-1',
        buildFingerprint: 'build-1',
        functions: <String, int>{handle.id: handle.slot},
        signatures: <String, String>{handle.id: handle.signature.encode()},
        receivers: <String, String>{handle.id: handle.receiver.encode()},
      ),
      isTrue,
    );
    final result = E0PatchRuntime.invoke(
      E0PatchRuntime.lookup(handle.slot)!,
      const <Object?>[],
      receiver: _DescriptorReceiver(handle.receiver),
    );
    expect(result.isSuccess, isTrue, reason: E0PatchRuntime.lastRejection);
    expect(result.value, isNull);
  });

  test('ordinary Future.value async methods remain patchable', () async {
    final transformation = _transform(_asyncSource);
    final function = transformation.manifest.functions.singleWhere(
      (item) => item.name == 'compute',
    );
    expect(function.signature.isAsync, isTrue);
    final bytes = E0PatchCompiler().compile(
      source: _asyncSource,
      manifest: transformation.manifest,
      functionName: 'compute',
    );
    expect(
      E0PatchRuntime.installBytes(
        bytes,
        appId: 'flutter-abi',
        releaseId: 'release-1',
        buildFingerprint: 'build-1',
        functions: <String, int>{function.id: function.slot},
        signatures: <String, String>{function.id: function.signature.encode()},
        receivers: <String, String>{function.id: function.receiver.encode()},
      ),
      isTrue,
    );
    final result = await E0PatchRuntime.invokeAsync<int>(
      E0PatchRuntime.lookup(function.slot)!,
      <Object?>[4],
    );
    expect(result, 5);
  });
}

E0TransformResult _transform(String source) => E0SourceTransformer().transform(
  source: source,
  packageName: 'flutter_abi_fixture',
  logicalLibraryPath: 'lib/main.dart',
  appId: 'flutter-abi',
  releaseId: 'release-1',
  buildFingerprint: 'build-1',
  widgetFactories: e0StandardFlutterWidgetFactories,
  enableFlutterWidgetAbi: true,
);

E0WidgetFactoryRegistry _fakeWidgetRegistry() =>
    E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
      for (final descriptor in e0StandardFlutterWidgetFactories)
        E0WidgetFactoryRegistration(
          descriptor: descriptor,
          create: (properties, children) =>
              _Node(descriptor.id, properties, children.cast<_Node>()),
        ),
    ]);

final class _Node {
  _Node(this.factory, this.properties, this.children);

  final String factory;
  final Map<String, Object?> properties;
  final List<_Node> children;
}

final class _DescriptorReceiver implements E0ReceiverCapability {
  const _DescriptorReceiver(this._descriptor, [this._values = const {}]);

  final E0ReceiverDescriptor _descriptor;
  final Map<String, Object?> _values;

  @override
  String get descriptorId => _descriptor.id;

  @override
  Object? read(int slot) => _values[_descriptor.members[slot].name];
}
