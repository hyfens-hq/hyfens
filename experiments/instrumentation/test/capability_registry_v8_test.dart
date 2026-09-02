import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

final _logging = E0AsyncCapabilityDescriptor(
  id: 'app.logging.write',
  sourceName: 'capabilityLog',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.string],
  result: E0ValueSchema.boolean,
  resources: <String>['log:application'],
  policy: E0CapabilityPolicy(sideEffect: E0CapabilitySideEffect.exactlyOnce),
);
final _clock = E0AsyncCapabilityDescriptor(
  id: 'app.clock.now',
  sourceName: 'capabilityNow',
  version: 1,
  arguments: <E0ValueSchema>[],
  result: E0ValueSchema.integer,
  resources: <String>['clock:wall'],
);
final _storageRead = E0AsyncCapabilityDescriptor(
  id: 'app.storage.read',
  sourceName: 'capabilityStorageRead',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.string],
  result: E0ValueSchema.string,
  resources: <String>['storage:preferences'],
);
final _storageWrite = E0AsyncCapabilityDescriptor(
  id: 'app.storage.write',
  sourceName: 'capabilityStorageWrite',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.string, E0ValueSchema.string],
  result: E0ValueSchema.boolean,
  resources: <String>['storage:preferences'],
  policy: E0CapabilityPolicy(sideEffect: E0CapabilitySideEffect.exactlyOnce),
);
final _navigation = E0AsyncCapabilityDescriptor(
  id: 'app.navigation.push',
  sourceName: 'capabilityNavigationPush',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.string],
  result: E0ValueSchema.boolean,
  resources: <String>['navigation:route'],
  policy: E0CapabilityPolicy(sideEffect: E0CapabilitySideEffect.exactlyOnce),
);
final _http = E0AsyncCapabilityDescriptor(
  id: 'app.http.get',
  sourceName: 'capabilityHttpGet',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.string],
  result: E0ValueSchema.map(E0ValueSchema.supportedValue),
  resources: <String>['network:https'],
  policy: E0CapabilityPolicy(
    timeout: Duration(seconds: 2),
    maxOutputBytes: 4096,
    sideEffect: E0CapabilitySideEffect.idempotent,
  ),
);

final _contracts = <E0AsyncCapabilityDescriptor>[
  _logging,
  _clock,
  _storageRead,
  _storageWrite,
  _navigation,
  _http,
];

void main() {
  late E0ReleaseManifest manifest;

  setUp(() {
    E0PatchRuntime.reset();
    manifest = E0SourceTransformer()
        .transform(
          source: _releaseSource,
          packageName: 'fixture',
          logicalLibraryPath: 'lib/capabilities.dart',
          appId: 'app',
          releaseId: 'capability-v8',
          buildFingerprint: 'build-1',
          capabilities: _contracts,
        )
        .manifest;
  });

  test('manifest round-trips exact application capability contracts', () {
    final decoded = E0ReleaseManifest.decode(manifest.encode());
    expect(decoded.capabilities, _contracts);
    expect(decoded.encode(), manifest.encode());
  });

  test('contracts own lists and source renames do not change authority', () {
    final arguments = <E0ValueSchema>[E0ValueSchema.string];
    final resources = <String>['log:application'];
    final first = E0AsyncCapabilityDescriptor(
      id: 'app.logging.owned',
      sourceName: 'oldName',
      version: 1,
      arguments: arguments,
      result: E0ValueSchema.boolean,
      resources: resources,
    );
    arguments.clear();
    resources.clear();
    final renamed = E0AsyncCapabilityDescriptor(
      id: first.id,
      sourceName: 'newName',
      version: 1,
      arguments: <E0ValueSchema>[E0ValueSchema.string],
      result: first.result,
      resources: <String>['log:application'],
    );
    expect(first.arguments, hasLength(1));
    expect(first.resources, hasLength(1));
    expect(first, renamed);
    expect(first.contractDigest, renamed.contractDigest);
    expect(first.hashCode, renamed.hashCode);
    expect(<E0AsyncCapabilityDescriptor>{first}, contains(renamed));
    expect(first.toRuntimeJson(), isNot(contains('sourceName')));
  });

  test('malformed digest and unsupported cancellation reject', () {
    final json = _logging.toJson()
      ..['contractDigest'] = List<String>.filled(64, '0').join();
    expect(
      () => E0AsyncCapabilityDescriptor.fromJson(json),
      throwsFormatException,
    );
    expect(
      () => E0AsyncCapabilityDescriptor(
        id: 'app.http.abort',
        version: 1,
        arguments: <E0ValueSchema>[],
        result: E0ValueSchema.boolean,
        cancellation: E0CapabilityCancellation.abortable,
      ),
      throwsFormatException,
    );
  });

  test('application descriptors enforce the same bounds as wire decode', () {
    for (final version in <int>[0, -1]) {
      expect(
        () => E0AsyncCapabilityDescriptor(
          id: 'app.test.version',
          version: version,
          arguments: <E0ValueSchema>[],
          result: E0ValueSchema.boolean,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => E0AsyncCapabilityDescriptor(
        id: 'app.test.arguments',
        version: 1,
        arguments: List<E0ValueSchema>.filled(17, E0ValueSchema.integer),
        result: E0ValueSchema.boolean,
      ),
      throwsFormatException,
    );
    for (final schema in <E0ValueSchema>[
      E0ValueSchema.supportedValue,
      E0ValueSchema.nullValue,
    ]) {
      expect(
        () => E0AsyncCapabilityDescriptor(
          id: 'app.test.schema',
          version: 1,
          arguments: <E0ValueSchema>[schema],
          result: E0ValueSchema.boolean,
        ),
        throwsFormatException,
      );
      expect(
        () => E0AsyncCapabilityDescriptor(
          id: 'app.test.result',
          version: 1,
          arguments: <E0ValueSchema>[],
          result: schema,
        ),
        throwsFormatException,
      );
    }
    for (final policy in <E0CapabilityPolicy>[
      const E0CapabilityPolicy(timeout: Duration.zero),
      const E0CapabilityPolicy(timeout: Duration(seconds: 31)),
      const E0CapabilityPolicy(maxOutputBytes: 0),
      const E0CapabilityPolicy(maxOutputBytes: 65537),
    ]) {
      expect(
        () => E0AsyncCapabilityDescriptor(
          id: 'app.test.policy',
          version: 1,
          arguments: <E0ValueSchema>[],
          result: E0ValueSchema.boolean,
          policy: policy,
        ),
        throwsFormatException,
      );
    }
  });

  test('verifier rejects opcode and execution-kind mismatches', () {
    final asyncDescriptor = E0AsyncCapabilityDescriptor(
      id: 'app.test.async',
      version: 1,
      arguments: <E0ValueSchema>[],
      result: E0ValueSchema.integer,
    );
    final syncDescriptor = E0AsyncCapabilityDescriptor(
      id: 'app.test.sync',
      version: 1,
      arguments: <E0ValueSchema>[],
      result: E0ValueSchema.integer,
      executionKind: E0CapabilityExecutionKind.sync,
    );
    expect(
      () => E0Interpreter.validate(
        E0PatchProgram(
          functionId: 'f',
          slot: 0,
          constants: const <Object?>[],
          signature: const E0FunctionSignature(
            parameters: <E0ValueSchema>[],
            returnSchema: E0ValueSchema.integer,
            isAsync: true,
          ),
          capabilities: <E0AsyncCapabilityDescriptor>[syncDescriptor],
          asyncPoints: const <E0AsyncPoint>[
            E0AsyncPoint(
              id: 0,
              awaitPc: 3,
              resumePc: 5,
              result: E0ValueSchema.integer,
              handlerDepth: 0,
            ),
          ],
          code: <int>[
            E0Opcode.callAsyncCapability.code,
            0,
            0,
            E0Opcode.awaitValue.code,
            0,
            E0Opcode.returnValue.code,
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => E0Interpreter.validate(
        E0PatchProgram(
          functionId: 'f',
          slot: 0,
          constants: const <Object?>[],
          signature: const E0FunctionSignature(
            parameters: <E0ValueSchema>[],
            returnSchema: E0ValueSchema.integer,
            isAsync: false,
          ),
          capabilities: <E0AsyncCapabilityDescriptor>[asyncDescriptor],
          code: <int>[
            E0Opcode.callSyncCapability.code,
            0,
            0,
            E0Opcode.returnValue.code,
          ],
        ),
      ),
      throwsFormatException,
    );

    final validAsyncBytes = E0PatchCompiler().compile(
      source:
          "Future<bool> target() async { return await capabilityLog('x'); }",
      manifest: manifest,
      functionName: 'target',
    );
    final validAsync = decodeProgram(manifest, validAsyncBytes);
    final forgedSyncRequirement = E0AsyncCapabilityDescriptor(
      id: _logging.id,
      version: _logging.version,
      arguments: _logging.arguments,
      result: _logging.result,
      executionKind: E0CapabilityExecutionKind.sync,
      resources: _logging.resources,
      policy: _logging.policy,
    );
    final forgedAsyncBytes = _replaceCapabilities(
      manifest,
      validAsync,
      <E0AsyncCapabilityDescriptor>[forgedSyncRequirement],
    );
    expect(
      () => decodeProgram(manifest, forgedAsyncBytes),
      throwsFormatException,
    );

    final syncRoute = E0AsyncCapabilityDescriptor(
      id: 'app.test.sync.route',
      sourceName: 'syncCall',
      version: 1,
      arguments: <E0ValueSchema>[],
      result: E0ValueSchema.boolean,
      executionKind: E0CapabilityExecutionKind.sync,
    );
    final syncManifest = E0SourceTransformer()
        .transform(
          source: 'bool target() { return false; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/kind.dart',
          appId: 'app',
          releaseId: 'kind',
          buildFingerprint: 'build-1',
          capabilities: <E0AsyncCapabilityDescriptor>[syncRoute],
        )
        .manifest;
    final validSync = decodeProgram(
      syncManifest,
      E0PatchCompiler().compile(
        source: 'bool target() { return syncCall(); }',
        manifest: syncManifest,
        functionName: 'target',
      ),
    );
    final forgedAsyncRequirement = E0AsyncCapabilityDescriptor(
      id: syncRoute.id,
      version: 1,
      arguments: <E0ValueSchema>[],
      result: E0ValueSchema.boolean,
    );
    final forgedSyncBytes = _replaceCapabilities(
      syncManifest,
      validSync,
      <E0AsyncCapabilityDescriptor>[forgedAsyncRequirement],
    );
    expect(
      () => decodeProgram(syncManifest, forgedSyncBytes),
      throwsFormatException,
    );
  });

  test('async activation rejects an otherwise valid sync capability call', () {
    final asyncDescriptor = E0AsyncCapabilityDescriptor(
      id: 'app.test.mixed.async',
      sourceName: 'mixedAsync',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.integer,
    );
    final syncDescriptor = E0AsyncCapabilityDescriptor(
      id: 'app.test.mixed.sync',
      sourceName: 'mixedSync',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.integer,
      executionKind: E0CapabilityExecutionKind.sync,
    );
    final mixedManifest = E0SourceTransformer()
        .transform(
          source: 'Future<int> target() async { return 0; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/mixed.dart',
          appId: 'app',
          releaseId: 'mixed',
          buildFingerprint: 'build-1',
          capabilities: <E0AsyncCapabilityDescriptor>[
            asyncDescriptor,
            syncDescriptor,
          ],
        )
        .manifest;
    final function = mixedManifest.functions.single;
    final forged = E0PatchContainer.encode(
      appId: mixedManifest.appId,
      releaseId: mixedManifest.releaseId,
      buildFingerprint: mixedManifest.buildFingerprint,
      program: E0PatchProgram(
        functionId: function.id,
        slot: function.slot,
        signature: function.signature,
        receiver: function.receiver,
        constants: const <Object?>[],
        capabilities: <E0AsyncCapabilityDescriptor>[
          asyncDescriptor,
          syncDescriptor,
        ],
        asyncPoints: const <E0AsyncPoint>[
          E0AsyncPoint(
            id: 0,
            awaitPc: 3,
            resumePc: 5,
            result: E0ValueSchema.integer,
            handlerDepth: 0,
          ),
        ],
        code: <int>[
          E0Opcode.callAsyncCapability.code,
          0,
          0,
          E0Opcode.awaitValue.code,
          0,
          E0Opcode.pop.code,
          E0Opcode.callSyncCapability.code,
          1,
          0,
          E0Opcode.returnValue.code,
        ],
      ),
    );

    expect(
      () => decodeProgram(mixedManifest, forged),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Sync capability is not supported in async program'),
        ),
      ),
    );
  });

  test(
    'compiler routes only declared source names without runtime authority',
    () {
      final bytes = E0PatchCompiler().compile(
        source: "Future<bool> target() async { return await capabilityLog('value'); }",
        manifest: manifest,
        functionName: 'target',
      );
      expect(
        decodeProgram(manifest, bytes).capabilities,
        <E0AsyncCapabilityDescriptor>[_logging],
      );
    },
  );

  test(
    'explicit fake adapter executes once and validates the result',
    () async {
      var calls = 0;
      _configure(<E0CapabilityRegistration>[
        E0CapabilityRegistration(_logging, (arguments) async {
          calls++;
          expect(arguments, <Object?>['hello']);
          return true;
        }),
      ]);
      final bytes = E0PatchCompiler().compile(
        source: "Future<bool> target() async { return await capabilityLog('hello'); }",
        manifest: manifest,
        functionName: 'target',
      );
      expect(installProgram(manifest, bytes), isTrue);
      expect(
        await E0PatchRuntime.invokeAsync<bool>(
          E0PatchRuntime.lookup(0)!,
          const [],
        ),
        isTrue,
      );
      expect(calls, 1);
    },
  );

  test(
    'activation rejects version, schema, and policy metadata atomically',
    () {
      _configure(<E0CapabilityRegistration>[
        E0CapabilityRegistration(_logging, (_) async => true),
      ]);
      final good = E0PatchCompiler().compile(
        source:
            "Future<bool> target() async { return await capabilityLog('ok'); }",
        manifest: manifest,
        functionName: 'target',
      );
      expect(installProgram(manifest, good), isTrue);
      final active = E0PatchRuntime.lookup(0);
      final decoded = decodeProgram(manifest, good);
      for (final mismatch in <E0AsyncCapabilityDescriptor>[
        E0AsyncCapabilityDescriptor(
          id: _logging.id,
          sourceName: _logging.sourceName,
          version: 2,
          arguments: _logging.arguments,
          result: _logging.result,
          resources: _logging.resources,
          policy: _logging.policy,
        ),
        E0AsyncCapabilityDescriptor(
          id: _logging.id,
          sourceName: _logging.sourceName,
          version: 1,
          arguments: const <E0ValueSchema>[E0ValueSchema.integer],
          result: _logging.result,
        ),
        E0AsyncCapabilityDescriptor(
          id: _logging.id,
          sourceName: _logging.sourceName,
          version: 1,
          arguments: _logging.arguments,
          result: _logging.result,
          policy: const E0CapabilityPolicy(maxOutputBytes: 32),
        ),
      ]) {
        final candidate = E0PatchContainer.encode(
          appId: manifest.appId,
          releaseId: manifest.releaseId,
          buildFingerprint: manifest.buildFingerprint,
          program: E0PatchProgram(
            functionId: decoded.functionId,
            slot: decoded.slot,
            signature: decoded.signature,
            receiver: decoded.receiver,
            constants: decoded.constants,
            code: decoded.code,
            locals: decoded.locals,
            handlers: decoded.handlers,
            capabilities: <E0AsyncCapabilityDescriptor>[mismatch],
            asyncPoints: decoded.asyncPoints,
            patchSequence: 2,
          ),
        );
        expect(installProgram(manifest, candidate), isFalse);
        expect(E0PatchRuntime.lookup(0), same(active));
      }
    },
  );

  test('duplicate IDs and unshipped capabilities fail closed', () {
    expect(
      () => E0CapabilityRegistry(<E0CapabilityRegistration>[
        E0CapabilityRegistration(_logging, (_) async => true),
        E0CapabilityRegistration(_logging, (_) async => true),
      ]),
      throwsStateError,
    );
    final unshipped = E0AsyncCapabilityDescriptor(
      id: 'app.extra.call',
      sourceName: 'extraCall',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.integer,
    );
    _configure(<E0CapabilityRegistration>[
      E0CapabilityRegistration(_logging, (_) async => true),
      E0CapabilityRegistration(unshipped, (_) async => 1),
    ]);
    expect(
      () => E0PatchCompiler().compile(
        source: 'Future<int> target() async { return await extraCall(); }',
        manifest: manifest,
        functionName: 'target',
      ),
      throwsFormatException,
    );
    final good = E0PatchCompiler().compile(
      source:
          "Future<bool> target() async { return await capabilityLog('ok'); }",
      manifest: manifest,
      functionName: 'target',
    );
    final decoded = decodeProgram(manifest, good);
    final forged = E0PatchContainer.encode(
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      program: E0PatchProgram(
        functionId: decoded.functionId,
        slot: decoded.slot,
        signature: decoded.signature,
        receiver: decoded.receiver,
        constants: decoded.constants,
        code: decoded.code,
        locals: decoded.locals,
        handlers: decoded.handlers,
        capabilities: <E0AsyncCapabilityDescriptor>[
          E0AsyncCapabilityDescriptor(
            id: unshipped.id,
            sourceName: unshipped.sourceName,
            version: unshipped.version,
            arguments: _logging.arguments,
            result: _logging.result,
          ),
        ],
        asyncPoints: decoded.asyncPoints,
      ),
    );
    expect(installProgram(manifest, forged), isFalse);
    expect(E0PatchRuntime.lastRejection, contains('shipped authority'));
  });

  test('sync execution kind has a dedicated bounded runtime path', () {
    final sync = E0AsyncCapabilityDescriptor(
      id: 'app.clock.sync',
      sourceName: 'syncClock',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.integer,
      executionKind: E0CapabilityExecutionKind.sync,
    );
    E0PatchRuntime.configureCapabilities(
      E0CapabilityAuthority(
        shipped: <E0AsyncCapabilityDescriptor>[sync],
        registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
          E0CapabilityRegistration(sync, (_) => 42),
        ]),
      ),
    );
    final syncManifest = E0SourceTransformer()
        .transform(
          source: 'int target() { return 0; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/sync.dart',
          appId: 'app',
          releaseId: 'sync',
          buildFingerprint: 'build-1',
          capabilities: <E0AsyncCapabilityDescriptor>[sync],
        )
        .manifest;
    final bytes = E0PatchCompiler().compile(
      source: 'int target() { return syncClock(); }',
      manifest: syncManifest,
      functionName: 'target',
    );
    expect(installProgram(syncManifest, bytes), isTrue);
    expect(
      E0PatchRuntime.invoke(E0PatchRuntime.lookup(0)!, const []).value,
      42,
    );
  });

  test('fatal sync failure disables slot and cannot select AOT fallback', () {
    final sync = E0AsyncCapabilityDescriptor(
      id: 'app.logging.sync',
      sourceName: 'syncLog',
      version: 1,
      arguments: <E0ValueSchema>[],
      result: E0ValueSchema.boolean,
      executionKind: E0CapabilityExecutionKind.sync,
      policy: const E0CapabilityPolicy(
        sideEffect: E0CapabilitySideEffect.exactlyOnce,
      ),
    );
    E0PatchRuntime.configureCapabilities(
      E0CapabilityAuthority(
        shipped: <E0AsyncCapabilityDescriptor>[sync],
        registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
          E0CapabilityRegistration(
            sync,
            (_) => throw const E0RuntimeFault('fatal'),
          ),
        ]),
      ),
    );
    final localManifest = E0SourceTransformer()
        .transform(
          source: 'bool target() { return false; } void main() {}',
          packageName: 'fixture',
          logicalLibraryPath: 'lib/sync_log.dart',
          appId: 'app',
          releaseId: 'sync-log',
          buildFingerprint: 'build-1',
          capabilities: <E0AsyncCapabilityDescriptor>[sync],
        )
        .manifest;
    final bytes = E0PatchCompiler().compile(
      source: 'bool target() { return syncLog(); }',
      manifest: localManifest,
      functionName: 'target',
    );
    expect(installProgram(localManifest, bytes), isTrue);
    final program = E0PatchRuntime.lookup(0)!;
    expect(
      () => E0PatchRuntime.invoke(program, const []),
      throwsA(isA<E0RuntimeFault>()),
    );
    expect(E0PatchRuntime.lookup(0), isNull);
  });

  test(
    'arbitrary, reflection, raw channel, FFI, and plugin calls diagnose',
    () {
      for (final expression in <String>[
        'arbitraryNativeCall()',
        'reflect(target)',
        "platformChannel.invokeMethod('x')",
        "dynamicLibrary.lookup('x')",
        'plugin.invoke()',
      ]) {
        expect(
          () => E0PatchCompiler().compile(
            source: 'Future<int> target() async { return await $expression; }',
            manifest: manifest,
            functionName: 'target',
          ),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'deterministic fake adapters enforce app policy without native I/O',
    () async {
      final host = _FakeCapabilityHost();
      expect(host.clock(const []), 1700000000000);
      expect(host.storageWrite(<Object?>['theme', 'dark']), isTrue);
      expect(host.storageRead(<Object?>['theme']), 'dark');
      await expectLater(
        Future<Object?>.sync(() => host.storageRead(<Object?>['../secret'])),
        throwsA(isA<E0CapabilityException>()),
      );
      expect(host.navigation(<Object?>['/home']), isTrue);
      host.userIntent = false;
      await expectLater(
        Future<Object?>.sync(() => host.navigation(<Object?>['/admin'])),
        throwsA(isA<E0CapabilityException>()),
      );
      expect(
        host.http(<Object?>['https://api.example.test/data']),
        <String, Object?>{'status': 200, 'body': 'fixture'},
      );
      await expectLater(
        Future<Object?>.sync(() => host.http(<Object?>['https://evil.test/'])),
        throwsA(isA<E0CapabilityException>()),
      );
      expect(host.log(<Object?>['token=abc']), isTrue);
      expect(host.logs.single, '[redacted]');
      await expectLater(
        Future<Object?>.sync(() => host.log(<Object?>['second'])),
        throwsA(isA<E0CapabilityException>()),
      );
    },
  );

  test(
    'authority is configure-once and pinned during an active call',
    () async {
      final gate = Completer<Object?>();
      _configure(<E0CapabilityRegistration>[
        E0CapabilityRegistration(_logging, (_) => gate.future),
      ]);
      final bytes = E0PatchCompiler().compile(
        source:
            "Future<bool> target() async { return await capabilityLog('x'); }",
        manifest: manifest,
        functionName: 'target',
      );
      expect(installProgram(manifest, bytes), isTrue);
      final pending = E0PatchRuntime.invokeAsync<bool>(
        E0PatchRuntime.lookup(0)!,
        const [],
      )!;
      expect(() => _configure(<E0CapabilityRegistration>[]), throwsStateError);
      expect(E0PatchRuntime.reset, throwsStateError);
      gate.complete(true);
      expect(await pending, isTrue);
    },
  );

  test('pending install cannot cross a reset lifecycle', () {
    final bytes = E0PatchCompiler().compile(
      source:
          "Future<bool> target() async { return await capabilityLog('x'); }",
      manifest: manifest,
      functionName: 'target',
    );
    final file = File(
      '${Directory.systemTemp.path}/e0-stale-${DateTime.now().microsecondsSinceEpoch}.patch',
    )..writeAsBytesSync(bytes);
    addTearDown(() => file.deleteSync());
    E0PatchRuntime.installFromArguments(
      <String>['--e0-patch=${file.path}'],
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      functions: <String, int>{manifest.functions.single.id: 0},
      signatures: <String, String>{
        manifest.functions.single.id: manifest.functions.single.signature
            .encode(),
      },
      receivers: <String, String>{
        manifest.functions.single.id: manifest.functions.single.receiver
            .encode(),
      },
    );
    expect(E0PatchRuntime.lookup(0), isNull);
    E0PatchRuntime.reset();
    _configure(<E0CapabilityRegistration>[
      E0CapabilityRegistration(_logging, (_) async => true),
    ]);
    expect(E0PatchRuntime.lookup(0), isNull);
  });

  test(
    'timeout, output exhaustion, and host errors are stable and redacted',
    () async {
      Future<E0HostFailure> runFailure(
        E0AsyncCapabilityDescriptor descriptor,
        E0CapabilityHandler handler,
      ) async {
        final localManifest = _asyncStringManifest(descriptor);
        E0PatchRuntime.configureCapabilities(
          E0CapabilityAuthority(
            shipped: <E0AsyncCapabilityDescriptor>[descriptor],
            registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
              E0CapabilityRegistration(descriptor, handler),
            ]),
          ),
        );
        final bytes = E0PatchCompiler().compile(
          source:
              'Future<String> target() async { return await boundedCall(); }',
          manifest: localManifest,
          functionName: 'target',
        );
        expect(installProgram(localManifest, bytes), isTrue);
        try {
          await E0PatchRuntime.invokeAsync<String>(
            E0PatchRuntime.lookup(0)!,
            const [],
          );
          fail('expected failure');
        } on E0HostFailure catch (error) {
          return error;
        }
      }

      var descriptor = E0AsyncCapabilityDescriptor(
        id: 'app.test.timeout',
        sourceName: 'boundedCall',
        version: 1,
        arguments: <E0ValueSchema>[],
        result: E0ValueSchema.string,
        policy: const E0CapabilityPolicy(timeout: Duration(milliseconds: 10)),
      );
      var error = await runFailure(
        descriptor,
        (_) => Completer<Object?>().future,
      );
      expect(error.code, 'deadlineExceeded');

      E0PatchRuntime.reset();
      descriptor = E0AsyncCapabilityDescriptor(
        id: 'app.test.output',
        sourceName: 'boundedCall',
        version: 1,
        arguments: <E0ValueSchema>[],
        result: E0ValueSchema.string,
        policy: const E0CapabilityPolicy(maxOutputBytes: 32),
      );
      error = await runFailure(descriptor, (_) async => 'x' * 100);
      expect(error.code, 'resourceExhausted');

      E0PatchRuntime.reset();
      error = await runFailure(
        descriptor,
        (_) => throw StateError('secret=/tmp/key url=https://token'),
      );
      expect(error.code, 'hostFailure');
      final guest = jsonEncode(error.toGuestValue());
      expect(guest, isNot(contains('secret')));
      expect(guest, isNot(contains('/tmp')));
      expect(guest, isNot(contains('https://')));
    },
  );
}

E0ReleaseManifest _asyncStringManifest(
  E0AsyncCapabilityDescriptor descriptor,
) => E0SourceTransformer()
    .transform(
      source: 'Future<String> target() async { return ""; } void main() {}',
      packageName: 'fixture',
      logicalLibraryPath: 'lib/bounded.dart',
      appId: 'app',
      releaseId: descriptor.id,
      buildFingerprint: 'build-1',
      capabilities: <E0AsyncCapabilityDescriptor>[descriptor],
    )
    .manifest;

E0PatchProgram decodeProgram(E0ReleaseManifest manifest, List<int> bytes) =>
    E0PatchContainer.decode(
      bytes,
      expectedAppId: manifest.appId,
      expectedReleaseId: manifest.releaseId,
      expectedBuildFingerprint: manifest.buildFingerprint,
      expectedFunctions: <String, int>{manifest.functions.single.id: 0},
      expectedSignatures: <String, E0FunctionSignature>{
        manifest.functions.single.id: manifest.functions.single.signature,
      },
      expectedReceivers: <String, E0ReceiverDescriptor>{
        manifest.functions.single.id: manifest.functions.single.receiver,
      },
    );

List<int> _replaceCapabilities(
  E0ReleaseManifest manifest,
  E0PatchProgram program,
  List<E0AsyncCapabilityDescriptor> capabilities,
) => E0PatchContainer.encode(
  appId: manifest.appId,
  releaseId: manifest.releaseId,
  buildFingerprint: manifest.buildFingerprint,
  program: E0PatchProgram(
    functionId: program.functionId,
    slot: program.slot,
    signature: program.signature,
    receiver: program.receiver,
    constants: program.constants,
    code: program.code,
    locals: program.locals,
    handlers: program.handlers,
    capabilities: capabilities,
    asyncPoints: program.asyncPoints,
    patchSequence: program.patchSequence,
  ),
);

bool installProgram(
  E0ReleaseManifest manifest,
  List<int> bytes,
) => E0PatchRuntime.installBytes(
  bytes,
  appId: manifest.appId,
  releaseId: manifest.releaseId,
  buildFingerprint: manifest.buildFingerprint,
  functions: <String, int>{manifest.functions.single.id: 0},
  signatures: <String, String>{
    manifest.functions.single.id: manifest.functions.single.signature.encode(),
  },
  receivers: <String, String>{
    manifest.functions.single.id: manifest.functions.single.receiver.encode(),
  },
);

void _configure(List<E0CapabilityRegistration> registrations) {
  E0PatchRuntime.configureCapabilities(
    E0CapabilityAuthority(
      shipped: _contracts,
      registry: E0CapabilityRegistry(registrations),
    ),
  );
}

const _releaseSource = '''
Future<bool> target() async { return true; }
void main(List<String> arguments) {}
''';

final class _FakeCapabilityHost {
  final Map<String, String> _storage = <String, String>{};
  final List<String> logs = <String>[];
  bool userIntent = true;
  bool lifecycleActive = true;

  Object clock(List<Object?> arguments) => 1700000000000;

  Object storageRead(List<Object?> arguments) {
    final key = arguments.single! as String;
    if (!RegExp(r'^[a-z][a-z0-9_.-]{0,31}$').hasMatch(key)) {
      throw const E0CapabilityException.denied();
    }
    return _storage[key] ?? '';
  }

  Object storageWrite(List<Object?> arguments) {
    final key = arguments.first! as String;
    if (!RegExp(r'^[a-z][a-z0-9_.-]{0,31}$').hasMatch(key)) {
      throw const E0CapabilityException.denied();
    }
    _storage[key] = arguments.last! as String;
    return true;
  }

  Object navigation(List<Object?> arguments) {
    final route = arguments.single! as String;
    if (!lifecycleActive ||
        !userIntent ||
        !const <String>{'/home', '/settings'}.contains(route)) {
      throw const E0CapabilityException.denied();
    }
    return true;
  }

  Object http(List<Object?> arguments) {
    final url = arguments.single! as String;
    if (url != 'https://api.example.test/data') {
      throw const E0CapabilityException.denied();
    }
    const body = 'fixture';
    if (utf8.encode(body).length > 64) {
      throw const E0CapabilityException.resourceExhausted();
    }
    return <String, Object?>{'status': 200, 'body': body};
  }

  Object log(List<Object?> arguments) {
    if (logs.isNotEmpty) throw const E0CapabilityException.resourceExhausted();
    final message = arguments.single! as String;
    logs.add(message.contains('token=') ? '[redacted]' : message);
    return true;
  }
}
