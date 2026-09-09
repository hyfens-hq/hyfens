import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

const _appId = 'dev.hyfens.conformance';
const _releaseId = 'android-e1-release-1';
const _buildFingerprint = 'conformance-build-1';
const _keyId = 'release-2026-a';
const _seed = <int>[
  0x9d,
  0x61,
  0xb1,
  0x9d,
  0xef,
  0xfd,
  0x5a,
  0x60,
  0xba,
  0x84,
  0x4a,
  0xf4,
  0x92,
  0xec,
  0x2c,
  0xc4,
  0x44,
  0x49,
  0xc5,
  0x69,
  0x7b,
  0x32,
  0x69,
  0x19,
  0x70,
  0x3b,
  0xac,
  0x03,
  0x1c,
  0xae,
  0x7f,
  0x60,
];
const _otherSeed = <int>[
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
];
const _functionId =
    'sha256:d5a3b64831b9a76d7d43cc8645ce79415061f59039f12963a272c51a005fe361';
const _functions = <String, int>{_functionId: 0};
const _signatures = <String, String>{
  _functionId: '{"parameters":[{"kind":"int","nullable":false},{"kind":"int","nullable":false}],"return":{"kind":"int","nullable":false},"async":false}',
};
const _receivers = <String, String>{
  _functionId: '{"id":"none","ownerClass":null,"members":[]}',
};
final _rollbackWaitCapability = E0AsyncCapabilityDescriptor(
  id: 'test.rollback.wait',
  version: 1,
  arguments: const <E0ValueSchema>[],
  result: E0ValueSchema.integer,
);

void main() {
  late Directory storage;
  late E1PatchController controller;
  late E1TrustedPublicKey trustedKey;
  final logs = <String>[];

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('hyfens-e1-signed-test-');
    final keyPair = await DartEd25519().newKeyPairFromSeed(_seed);
    trustedKey = E1TrustedPublicKey(
      keyId: _keyId,
      bytes: (await keyPair.extractPublicKey()).bytes,
    );
    keyPair.destroy();
    controller = _controller(storage, logs, trustedKey);
    E0PatchRuntime.reset();
  });

  tearDown(() async {
    await controller.close();
    E0PatchRuntime.reset();
    await storage.delete(recursive: true);
    logs.clear();
  });

  test(
    'release-owned capability and widget authority survives every E1 reset',
    () async {
      final authority = E0CapabilityAuthority(
        shipped: const <E0AsyncCapabilityDescriptor>[],
        registry: E0CapabilityRegistry(const <E0CapabilityRegistration>[]),
      );
      final factories = E0WidgetFactoryRegistry(
        const <E0WidgetFactoryRegistration>[],
      );
      await controller.close();
      controller = _controller(
        storage,
        logs,
        trustedKey,
        runtimeConfiguration: E1RuntimeConfiguration(
          capabilities: authority,
          widgetFactories: factories,
        ),
      );

      await controller.initialize();
      expect(
        () => E0PatchRuntime.configureCapabilities(authority),
        throwsStateError,
      );
      expect(
        () => E0PatchRuntime.configureWidgetFactories(factories),
        throwsStateError,
      );

      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      expect(await controller.rollback(), isTrue);
      expect(E0PatchRuntime.lookup(0), isNull);
      expect(
        () => E0PatchRuntime.configureCapabilities(authority),
        throwsStateError,
      );
      expect(
        () => E0PatchRuntime.configureWidgetFactories(factories),
        throwsStateError,
      );

      expect(
        await controller.recoverFromRuntimeException(StateError('base fault')),
        isTrue,
      );
      expect(
        () => E0PatchRuntime.configureCapabilities(authority),
        throwsStateError,
      );
      expect(
        () => E0PatchRuntime.configureWidgetFactories(factories),
        throwsStateError,
      );
    },
  );

  test('close is idempotent and rejects every later operation', () async {
    await controller.initialize();
    final durableBefore = await _state(storage);
    final statusBefore = controller.status;
    final logCountBefore = logs.length;

    final firstClose = controller.close();
    final secondClose = controller.close();
    expect(secondClose, same(firstClose));
    await firstClose;
    await controller.close();

    await expectLater(controller.initialize(), throwsStateError);
    await expectLater(
      controller.activateBytes(const <int>[1, 2, 3]),
      throwsStateError,
    );
    await expectLater(controller.downloadAndActivate(), throwsStateError);
    await expectLater(controller.markHealthy(), throwsStateError);
    await expectLater(
      controller.recoverFromRuntimeException(StateError('late')),
      throwsStateError,
    );
    await expectLater(controller.rollback(), throwsStateError);

    expect(await _state(storage), durableBefore);
    expect(controller.status, same(statusBefore));
    expect(logs.length, logCountBefore);
  });

  group('authenticated activation', () {
    test('Patch Format v1 bridge verifies, installs, and persists', () async {
      await controller.initialize();
      final artifact = await _patchFormatArtifact(_discountPatch, 1);
      expect(await _activateHealthy(controller, artifact), isTrue);
      expect(_execute(2, 1), 190);

      await controller.close();
      controller = _controller(storage, logs, trustedKey);
      await controller.initialize();
      expect(controller.status.mode, E1PatchMode.patch);
      expect(_execute(2, 1), 190);
    });

    test(
      'rotation overlap accepts new key and retirement rejects old key',
      () async {
        final nextPair = await DartEd25519().newKeyPairFromSeed(_otherSeed);
        final nextKey = E1TrustedPublicKey(
          keyId: 'release-2026-b',
          bytes: (await nextPair.extractPublicKey()).bytes,
        );
        nextPair.destroy();
        final trustBaseline = E1KeyLifecycleState.staticBaseline(
          applicationId: _appId,
          releaseId: _releaseId,
          keys: <E1ReleaseKey>[
            E1ReleaseKey(
              keyId: _keyId,
              publicKeyBytes: trustedKey.bytes,
              roles: const <E1ReleaseKeyRole>{
                E1ReleaseKeyRole.authority,
                E1ReleaseKeyRole.patch,
                E1ReleaseKeyRole.rollback,
              },
            ),
            E1ReleaseKey(
              keyId: nextKey.keyId,
              publicKeyBytes: nextKey.bytes,
              roles: const <E1ReleaseKeyRole>{
                E1ReleaseKeyRole.authority,
                E1ReleaseKeyRole.patch,
                E1ReleaseKeyRole.rollback,
              },
            ),
          ],
        );
        await controller.close();
        controller = _controller(
          storage,
          logs,
          trustedKey,
          additionalTrustedKeys: <E1TrustedPublicKey>[nextKey],
          initialTrustState: trustBaseline,
        );
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        final rotated = await _signedWith(
          _alternatePatch,
          2,
          keyId: nextKey.keyId,
          seed: _otherSeed,
        );
        expect(await _activateHealthy(controller, rotated), isTrue);
        final retireOld = await _lifecycleCommand(
          operation: E1KeyLifecycleOperation.retire,
          commandSequence: controller.trustState.commandSequence + 1,
          previousStateDigest: controller.trustState.stateDigest,
          signerKeyId: _keyId,
          signerSeed: _seed,
          targetKeyId: _keyId,
        );
        expect(await controller.applyKeyLifecycleCommand(retireOld), isTrue);
        final beforeRetirementAttempt = await _state(storage);
        await controller.close();

        controller = _controller(storage, logs, nextKey);
        await controller.initialize();
        final retiredOld = await _signed(_discountPatch, 3);
        expect(await controller.activateBytes(retiredOld), isFalse);
        expect(controller.status.detail, contains('not trusted'));
        expect(await _state(storage), beforeRetirementAttempt);
        expect(_execute(6, 1), 360);
      },
    );

    test('localhost redirect to external origin is not followed', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://example.invalid/patch.e1.signed.json',
        );
        await request.response.close();
      });
      await controller.close();
      controller = _controller(
        storage,
        logs,
        trustedKey,
        patchUri: Uri.parse(
          'http://127.0.0.1:${server.port}/patch.e1.signed.json',
        ),
      );
      await controller.initialize();

      expect(await controller.downloadAndActivate(), isFalse);
      expect(controller.status.detail, contains('redirects are disabled'));
      expect(requests, 1);
    });

    test('valid patch activates and equal same digest is idempotent', () async {
      await controller.initialize();
      final signed = await _signed(_discountPatch, 1);
      expect(await _activateHealthy(controller, signed), isTrue);
      expect(_execute(6, 1), 450);
      final stateBefore = await _state(storage);

      expect(await controller.activateBytes(signed), isTrue);
      expect(controller.status.detail, contains('idempotent'));
      expect(await _state(storage), stateBefore);
    });

    test(
      'unsigned, tampered, wrong-key, malformed, and partial reject',
      () async {
        await controller.initialize();
        final signed = await _signed(_discountPatch, 1);
        expect(
          await controller.activateBytes(_compile(_discountPatch, 1)),
          isFalse,
        );

        final tampered = List<int>.of(signed)..[signed.length ~/ 2] ^= 1;
        expect(await controller.activateBytes(tampered), isFalse);

        final wrongKey = await E1SignedPatchEnvelope.sign(
          patchBytes: _compile(_discountPatch, 1),
          keyId: _keyId,
          privateKeySeed: _otherSeed,
        );
        expect(await controller.activateBytes(wrongKey), isFalse);
        expect(
          await controller.activateBytes(utf8.encode('{"bad":true}')),
          isFalse,
        );
        expect(
          await controller.activateBytes(signed.sublist(0, signed.length ~/ 2)),
          isFalse,
        );
        expect(controller.status.mode, E1PatchMode.base);
        expect((await _state(storage))['highWaterSequence'], 0);
      },
    );

    test(
      'signed invalid bytecode and incompatible release preserve state',
      () async {
        await controller.initialize();
        final current = await _signed(_discountPatch, 1);
        expect(await _activateHealthy(controller, current), isTrue);
        final stateBefore = await _state(storage);
        final signedGarbage = await E1SignedPatchEnvelope.sign(
          patchBytes: utf8.encode('{"authenticated":"but not e0"}'),
          keyId: _keyId,
          privateKeySeed: _seed,
        );
        expect(await controller.activateBytes(signedGarbage), isFalse);
        final incompatible = await _signed(
          _alternatePatch,
          2,
          releaseId: 'another-release',
        );
        expect(await controller.activateBytes(incompatible), isFalse);
        expect(await _state(storage), stateBefore);
        expect(_execute(6, 1), 450);
      },
    );
  });

  group('durable sequence and recovery', () {
    test(
      'faulting unconfirmed candidate recovers last-known-good on restart',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        expect(
          await controller.activateBytes(await _signed(_faultingPatch, 2)),
          isTrue,
        );
        expect(() => _execute(6, 1), throwsA(anything));
        await controller.close();

        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.phase, 'fallback');
        expect(_execute(6, 1), 450);
        expect((await _state(storage))['highWaterSequence'], 2);
      },
    );

    test(
      'unconfirmed candidate automatically recovers to base on restart',
      () async {
        await controller.initialize();
        expect(
          await controller.activateBytes(await _signed(_discountPatch, 1)),
          isTrue,
        );
        expect(_execute(6, 1), 450);
        await controller.close();

        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.phase, 'fallback');
        expect(controller.status.mode, E1PatchMode.base);
        expect(E0PatchRuntime.lookup(0), isNull);
        expect((await _state(storage))['highWaterSequence'], 1);
      },
    );

    test('sequential patches persist across restart', () async {
      await controller.initialize();
      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      expect(
        await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
        isTrue,
      );
      expect(_execute(6, 1), 360);
      await controller.close();

      controller = _controller(storage, logs, trustedKey);
      await controller.initialize();
      expect(controller.status.mode, E1PatchMode.patch);
      expect(_execute(6, 1), 360);
      expect((await _state(storage))['highWaterSequence'], 2);
      expect(
        await controller.activateBytes(await _signed(_discountPatch, 1)),
        isFalse,
      );
      expect(controller.status.detail, contains('stale'));
    });

    test(
      'lower sequence is stale and equal different digest is equivocation',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
          isTrue,
        );
        final before = await _state(storage);
        expect(
          await controller.activateBytes(await _signed(_discountPatch, 1)),
          isFalse,
        );
        expect(controller.status.detail, contains('stale'));
        expect(
          await controller.activateBytes(await _signed(_discountPatch, 2)),
          isFalse,
        );
        expect(controller.status.detail, contains('equivocation'));
        expect(await _state(storage), before);
        expect(_execute(6, 1), 360);
      },
    );

    test(
      'runtime exception recovers previous locally but preserves high-water',
      () async {
        await controller.initialize();
        final first = await _signed(_discountPatch, 1);
        final second = await _signed(_alternatePatch, 2);
        expect(await _activateHealthy(controller, first), isTrue);
        expect(await controller.activateBytes(second), isTrue);
        expect(
          await controller.recoverFromRuntimeException(StateError('boom')),
          isTrue,
        );
        expect(_execute(6, 1), 450);
        expect((await _state(storage))['highWaterSequence'], 2);
        expect(await controller.activateBytes(second), isFalse);
        expect(controller.status.detail, contains('replay'));
      },
    );

    test('higher signed rollback artifact restores behavior, base keeps high-water', () async {
      await controller.initialize();
      final oldBytes = await _signed(_discountPatch, 1);
      expect(await _activateHealthy(controller, oldBytes), isTrue);
      expect(
        await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
        isTrue,
      );

      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 3)),
        isTrue,
      );
      expect(_execute(6, 1), 450);
      expect(await controller.rollback(), isTrue);
      expect(E0PatchRuntime.lookup(0), isNull);
      expect((await _state(storage))['highWaterSequence'], 3);
      expect(await controller.activateBytes(oldBytes), isFalse);
      expect(controller.status.detail, contains('stale'));
    });

    test(
      'signed rollback control resets base and persists high-water',
      () async {
        await controller.initialize();
        final patch = await _signed(_discountPatch, 1);
        expect(await _activateHealthy(controller, patch), isTrue);
        final before = await _state(storage);
        final command = await _rollbackControl(
          highWaterSequence: before['highWaterSequence']! as int,
          highWaterDigest: before['highWaterDigest']! as String,
        );

        expect(await controller.applyRollbackControl(command), isTrue);
        final after = await _state(storage);
        expect(after['health'], 'base');
        expect(after['current'], isNull);
        expect(after['highWaterSequence'], 1);
        expect(E0PatchRuntime.lookup(0), isNull);

        await controller.close();
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.mode, E1PatchMode.base);
        expect(await controller.activateBytes(patch), isFalse);
        expect(controller.status.detail, contains('replay'));
      },
    );

    test(
      'signed rollback control rejects wrong release and high-water',
      () async {
        await controller.initialize();
        final patch = await _signed(_discountPatch, 1);
        expect(await _activateHealthy(controller, patch), isTrue);
        final before = await _state(storage);
        final wrongRelease = await _rollbackControl(
          highWaterSequence: before['highWaterSequence']! as int,
          highWaterDigest: before['highWaterDigest']! as String,
          releaseId: 'another-release',
        );
        expect(await controller.applyRollbackControl(wrongRelease), isFalse);
        expect(controller.status.detail, contains('another release'));

        final wrongHighWater = await _rollbackControl(
          highWaterSequence: 0,
          highWaterDigest: null,
        );
        expect(await controller.applyRollbackControl(wrongHighWater), isFalse);
        expect(controller.status.detail, contains('high-water'));
        expect(await _state(storage), before);
      },
    );

    test(
      'active async continuation rejects rollback without state/runtime split',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        final durableBefore = await _state(storage);
        final installedBefore = E0PatchRuntime.lookup(0)!;
        final gate = Completer<Object?>();
        final authority = E0CapabilityAuthority(
          shipped: <E0AsyncCapabilityDescriptor>[_rollbackWaitCapability],
          registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
            E0CapabilityRegistration(
              _rollbackWaitCapability,
              (_) => gate.future,
            ),
          ]),
        );
        E0PatchRuntime.configureCapabilities(authority);
        final continuation = E0AsyncInterpreter.execute(
          E0PatchProgram(
            functionId: 'test.rollback.pending',
            slot: 1,
            signature: const E0FunctionSignature(
              parameters: <E0ValueSchema>[],
              returnSchema: E0ValueSchema.integer,
              isAsync: true,
            ),
            constants: const <Object?>[],
            code: <int>[
              E0Opcode.callAsyncCapability.code,
              0,
              0,
              E0Opcode.awaitValue.code,
              0,
              E0Opcode.returnValue.code,
            ],
            capabilities: <E0AsyncCapabilityDescriptor>[
              _rollbackWaitCapability,
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
          ),
          const <Object?>[],
          authority: authority,
          onRuntimeFault: fail,
        );
        expect(E0AsyncInterpreter.activeContinuations, 1);

        expect(await controller.rollback(), isFalse);
        expect(controller.status.phase, 'rejected');
        expect(controller.status.mode, E1PatchMode.patch);
        expect(controller.status.detail, contains('active continuations'));
        expect(await _state(storage), durableBefore);
        expect(E0PatchRuntime.lookup(0), same(installedBefore));
        expect(_execute(6, 1), 450);

        gate.complete(7);
        expect(await continuation, 7);
        expect(E0AsyncInterpreter.activeContinuations, 0);
        expect(await controller.rollback(), isTrue);
        expect(E0PatchRuntime.lookup(0), isNull);
        expect((await _state(storage))['health'], 'base');
      },
    );

    test(
      'rollback commit failure restores prior durable and runtime state',
      () async {
        await controller.close();
        var failNextBackupWrite = false;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (copyName, _) async {
              if (failNextBackupWrite && copyName == 'state-v3-b.json') {
                failNextBackupWrite = false;
                throw const FileSystemException(
                  'injected rollback write fault',
                );
              }
            },
          ),
        );
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        final durableBefore = await _state(storage);
        failNextBackupWrite = true;

        expect(await controller.rollback(), isFalse);
        final durableAfter = await _state(storage);
        expect(durableAfter['current'], durableBefore['current']);
        expect(durableAfter['health'], durableBefore['health']);
        expect(
          durableAfter['highWaterSequence'],
          durableBefore['highWaterSequence'],
        );
        expect(
          durableAfter['highWaterDigest'],
          durableBefore['highWaterDigest'],
        );
        expect(controller.status.mode, E1PatchMode.patch);
        expect(controller.status.detail, contains('prior state retained'));
        expect(_execute(6, 1), 450);

        expect(await controller.rollback(), isTrue);
        expect(E0PatchRuntime.lookup(0), isNull);
        expect((await _state(storage))['health'], 'base');
      },
    );

    test(
      'base recovery write failure restores exact prior durable/runtime state',
      () async {
        await controller.close();
        var failNextBackupWrite = false;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (copyName, _) async {
              if (failNextBackupWrite && copyName == 'state-v3-b.json') {
                failNextBackupWrite = false;
                throw const FileSystemException(
                  'injected base recovery write fault',
                );
              }
            },
          ),
        );
        await controller.initialize();
        expect(
          await controller.activateBytes(await _signed(_discountPatch, 1)),
          isTrue,
        );
        final durableBefore = await _state(storage);
        final installedBefore = E0PatchRuntime.lookup(0)!;
        failNextBackupWrite = true;

        expect(
          await controller.recoverFromRuntimeException(StateError('fault')),
          isFalse,
        );
        expect(await _state(storage), durableBefore);
        expect(E0PatchRuntime.lookup(0), isNot(same(installedBefore)));
        expect(_execute(6, 1), 450);
        expect(controller.recoveryNeeded, isFalse);
        expect(controller.status.phase, 'rejected');
        expect(controller.status.mode, E1PatchMode.patch);
        expect(controller.status.detail, contains('prior state retained'));
      },
    );

    test(
      'last-known-good recovery write failure restores current patch exactly',
      () async {
        await controller.close();
        var failNextBackupWrite = false;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (copyName, _) async {
              if (failNextBackupWrite && copyName == 'state-v3-b.json') {
                failNextBackupWrite = false;
                throw const FileSystemException(
                  'injected LKG recovery write fault',
                );
              }
            },
          ),
        );
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        expect(
          await controller.activateBytes(await _signed(_alternatePatch, 2)),
          isTrue,
        );
        final durableBefore = await _state(storage);
        failNextBackupWrite = true;

        expect(
          await controller.recoverFromRuntimeException(StateError('fault')),
          isFalse,
        );
        expect(await _state(storage), durableBefore);
        expect(_execute(6, 1), 360);
        expect(controller.recoveryNeeded, isFalse);
        expect(controller.status.phase, 'rejected');
        expect(controller.status.mode, E1PatchMode.patch);
        expect(controller.status.detail, contains('prior state retained'));
      },
    );

    test(
      'unrestorable recovery fails closed and locks later activation',
      () async {
        await controller.close();
        var failWrites = false;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (copyName, _) async {
              if (failWrites && copyName == 'state-v3-b.json') {
                throw const FileSystemException(
                  'persistent recovery write fault',
                );
              }
            },
          ),
        );
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        failWrites = true;

        expect(
          await controller.recoverFromRuntimeException(StateError('fault')),
          isFalse,
        );
        expect(controller.recoveryNeeded, isTrue);
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
        expect(
          controller.status.detail,
          isNot(contains('prior state retained')),
        );
        expect(E0PatchRuntime.lookup(0), isNull);
        expect(
          await controller.activateBytes(await _signed(_alternatePatch, 2)),
          isFalse,
        );
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
        expect(controller.status.detail, contains('activation locked'));
        expect(E0PatchRuntime.lookup(0), isNull);
      },
    );

    test(
      'pending startup fallback write failure remains base and recovery locked',
      () async {
        await controller.initialize();
        expect(
          await controller.activateBytes(await _signed(_discountPatch, 1)),
          isTrue,
        );
        final durablePending = await _state(storage);
        await controller.close();
        var failNextBackupWrite = true;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (copyName, _) async {
              if (failNextBackupWrite && copyName == 'state-v3-b.json') {
                failNextBackupWrite = false;
                throw const FileSystemException(
                  'injected startup fallback write fault',
                );
              }
            },
          ),
        );

        await controller.initialize();
        expect(await _state(storage), durablePending);
        expect(E0PatchRuntime.lookup(0), isNull);
        expect(controller.recoveryNeeded, isTrue);
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
        expect(controller.status.detail, contains('unconfirmed candidate'));
        expect(
          await controller.activateBytes(await _signed(_alternatePatch, 2)),
          isFalse,
        );
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
        expect(controller.status.detail, contains('activation locked'));
      },
    );

    test('corrupt current recovers previous and keeps high-water', () async {
      await controller.initialize();
      expect(
        await _activateHealthy(controller, await _signed(_discountPatch, 1)),
        isTrue,
      );
      expect(
        await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
        isTrue,
      );
      final state = await _state(storage);
      await File('${storage.path}/${state['current']}')
          .writeAsString('corrupt');
      await controller.close();
      controller = _controller(storage, logs, trustedKey);
      await controller.initialize();
      expect(controller.status.phase, 'fallback');
      expect(_execute(6, 1), 450);
      expect((await _state(storage))['highWaterSequence'], 2);
    });

    test(
      'invalid durable state fails closed; orphan temp is ignored',
      () async {
        await storage.create(recursive: true);
        await File('${storage.path}/state-v3-a.json.tmp')
            .writeAsString('{partial');
        await controller.initialize();
        expect(controller.status.mode, E1PatchMode.base);
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        await controller.close();

        await File('${storage.path}/state-v3-a.json').writeAsString('{broken');
        await File('${storage.path}/state-v3-b.json').writeAsString('{broken');
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.phase, 'recoveryNeeded');
        expect(
          await controller.activateBytes(await _signed(_alternatePatch, 2)),
          isFalse,
        );
      },
    );

    test(
      'atomic state write failure restores prior runtime and high-water',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        final before = await _state(storage);
        await controller.close();
        var injected = false;
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            beforeStateCopyWrite: (name, generation) async {
              if (!injected && name == 'state-v3-b.json') {
                injected = true;
                throw StateError('injected state write failure');
              }
            },
          ),
        );
        await controller.initialize();

        expect(
          await controller.activateBytes(await _signed(_alternatePatch, 2)),
          isFalse,
        );
        expect(_execute(6, 1), 450);
        final after = await _state(storage);
        expect(after['current'], before['current']);
        expect(after['health'], before['health']);
        expect(after['highWaterSequence'], before['highWaterSequence']);
        expect(after['highWaterDigest'], before['highWaterDigest']);
        expect(controller.status.detail, contains('prior state retained'));
      },
    );

    test(
      'concurrent activations serialize pending state and runtime',
      () async {
        await controller.initialize();
        final first = await _signed(_discountPatch, 1);
        final second = await _signed(_alternatePatch, 2);
        final results = await Future.wait(<Future<bool>>[
          controller.activateBytes(first),
          controller.activateBytes(second),
        ]);
        expect(results, <bool>[true, false]);
        expect(_execute(6, 1), 450);
        expect((await _state(storage))['highWaterSequence'], 1);
        expect((await _state(storage))['health'], 'pending');
        expect(await controller.markHealthy(), isTrue);
      },
    );

    test(
      'completed operation immediately releases the next queued operation',
      () async {
        await controller.initialize();
        expect(
          await controller
              .activateBytes(await _signed(_discountPatch, 1))
              .timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(
          await controller.markHealthy().timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(_execute(6, 1), 450);
      },
    );

    test(
      'operation error reaches caller without poisoning queue tail',
      () async {
        await controller.close();
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            afterInputCopy: () async =>
                throw StateError('injected queue error'),
          ),
        );
        await controller.initialize();
        await expectLater(
          controller.activateBytes(await _signed(_discountPatch, 1)),
          throwsStateError,
        );
        await controller.initialize().timeout(const Duration(seconds: 2));
        expect(controller.status.mode, E1PatchMode.base);
      },
    );

    test(
      'caller mutation after activation call cannot change verified bytes',
      () async {
        await controller.close();
        final copied = Completer<void>();
        final release = Completer<void>();
        controller = _controller(
          storage,
          logs,
          trustedKey,
          testHooks: E1PatchControllerTestHooks(
            afterInputCopy: () async {
              copied.complete();
              await release.future;
            },
          ),
        );
        await controller.initialize();
        final mutable = await _signed(_discountPatch, 1);
        final activation = controller.activateBytes(mutable);
        await copied.future;
        mutable.fillRange(0, mutable.length, 0);
        release.complete();
        expect(await activation, isTrue);
        expect(_execute(6, 1), 450);
        expect(await controller.markHealthy(), isTrue);
      },
    );

    test(
      'idempotent activation repairs corrupt artifact and survives restart',
      () async {
        await controller.initialize();
        final signed = await _signed(_discountPatch, 1);
        expect(await _activateHealthy(controller, signed), isTrue);
        final state = await _state(storage);
        final artifact = File('${storage.path}/${state['current']}');
        await artifact.writeAsString('corrupt');

        expect(await controller.activateBytes(signed), isTrue);
        expect(await artifact.readAsBytes(), signed);
        await controller.close();
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.mode, E1PatchMode.patch);
        expect(_execute(6, 1), 450);
      },
    );

    test(
      'single torn state copy heals; missing copies and predecessor gap lock',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        final predecessor = await File('${storage.path}/state-v3-a.json')
            .readAsBytes();
        await File('${storage.path}/state-v3-a.json').writeAsString('{torn');
        await controller.close();
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.recoveryNeeded, isFalse);
        expect(
          await File('${storage.path}/state-v3-a.json').readAsString(),
          await File('${storage.path}/state-v3-b.json').readAsString(),
        );

        expect(
          await _activateHealthy(controller, await _signed(_alternatePatch, 2)),
          isTrue,
        );
        await File('${storage.path}/state-v3-a.json').writeAsBytes(predecessor);
        await controller.close();
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.phase, 'recoveryNeeded');
        await controller.close();

        await File('${storage.path}/state-v3-a.json').delete();
        await File('${storage.path}/state-v3-b.json').delete();
        controller = _controller(storage, logs, trustedKey);
        await controller.initialize();
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
      },
    );

    test(
      'state bound to another release enters recovery-needed base',
      () async {
        await controller.initialize();
        expect(
          await _activateHealthy(controller, await _signed(_discountPatch, 1)),
          isTrue,
        );
        await controller.close();
        controller = _controller(
          storage,
          logs,
          trustedKey,
          controllerReleaseId: 'different-release',
        );
        await controller.initialize();
        expect(controller.status.phase, 'recoveryNeeded');
        expect(controller.status.mode, E1PatchMode.base);
        expect(E0PatchRuntime.lookup(0), isNull);
      },
    );
  });
}

E1PatchController _controller(
  Directory storage,
  List<String> logs,
  E1TrustedPublicKey key, {
  E1PatchControllerTestHooks? testHooks,
  List<E1TrustedPublicKey> additionalTrustedKeys = const <E1TrustedPublicKey>[],
  E1KeyLifecycleState? initialTrustState,
  Uri? patchUri,
  String controllerReleaseId = _releaseId,
  E1RuntimeConfiguration runtimeConfiguration = const E1RuntimeConfiguration(),
}) => E1PatchController(
  storageDirectory: storage,
  appId: _appId,
  releaseId: controllerReleaseId,
  buildFingerprint: _buildFingerprint,
  functions: _functions,
  signatures: _signatures,
  receivers: _receivers,
  patchUri:
      patchUri ?? Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
  trustedPublicKeys: <String, E1TrustedPublicKey>{
    key.keyId: key,
    for (final additional in additionalTrustedKeys)
      additional.keyId: additional,
  },
  initialTrustState: initialTrustState,
  runtimeConfiguration: runtimeConfiguration,
  log: logs.add,
  testHooks: testHooks,
);

Future<List<int>> _signed(
  String source,
  int sequence, {
  String releaseId = _releaseId,
}) => E1SignedPatchEnvelope.sign(
  patchBytes: _compile(source, sequence, releaseId: releaseId),
  keyId: _keyId,
  privateKeySeed: _seed,
);

Future<List<int>> _signedWith(
  String source,
  int sequence, {
  required String keyId,
  required List<int> seed,
}) => E1SignedPatchEnvelope.sign(
  patchBytes: _compile(source, sequence),
  keyId: keyId,
  privateKeySeed: seed,
);

Future<List<int>> _rollbackControl({
  required int highWaterSequence,
  required String? highWaterDigest,
  String releaseId = _releaseId,
}) async {
  final pair = await DartEd25519().newKeyPairFromSeed(_seed);
  try {
    final command = await RollbackControlCommand.sign(
      applicationId: _appId,
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      keyId: _keyId,
      signer: (message) async =>
          (await DartEd25519().sign(message, keyPair: pair)).bytes,
    );
    return command.encodeBytes();
  } finally {
    pair.destroy();
  }
}

Future<List<int>> _lifecycleCommand({
  required E1KeyLifecycleOperation operation,
  required int commandSequence,
  required String previousStateDigest,
  required String signerKeyId,
  required List<int> signerSeed,
  String? targetKeyId,
  String? newKeyId,
  List<int>? newPublicKey,
  Set<E1ReleaseKeyRole>? newRoles,
}) async {
  final pair = await DartEd25519().newKeyPairFromSeed(signerSeed);
  try {
    final command = await E1KeyLifecycleCommand.sign(
      applicationId: _appId,
      releaseId: _releaseId,
      commandSequence: commandSequence,
      previousStateDigest: previousStateDigest,
      operation: operation,
      signerKeyId: signerKeyId,
      targetKeyId: targetKeyId,
      newKeyId: newKeyId,
      newPublicKey: newPublicKey,
      newRoles: newRoles,
      signer: (message) async =>
          (await DartEd25519().sign(message, keyPair: pair)).bytes,
    );
    return command.encodeBytes();
  } finally {
    pair.destroy();
  }
}

Future<List<int>> _patchFormatArtifact(String source, int sequence) async {
  final e0Bytes = _compile(source, sequence);
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: _appId,
    releaseId: _releaseId,
    patchId: 'patch-format-test-$sequence',
    sequence: sequence,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: _functionId,
        slot: 0,
        signatureDigest: 'sha256:${'0' * 64}',
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.string('hyfens-e0-bridge-v1')],
    instructions: const <int>[0],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: _keyId,
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(
        type: patchFormatV1E0BridgeExtensionType,
        flags: 0,
        payload: utf8.encode(
          jsonEncode(<String, Object?>{
            'bridgeVersion': 1,
            'encoding': 'e0-patch-container-v9-bytes',
            'functions': <String, String>{_functionId: base64.encode(e0Bytes)},
          }),
        ),
      ),
    ],
  );
  final algorithm = DartEd25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_seed);
  try {
    final artifact = await PatchFormatV1.sealAsync(draft, (bytes) async {
      final signature = await algorithm.sign(bytes, keyPair: keyPair);
      return signature.bytes;
    });
    return PatchFormatV1.encode(artifact);
  } finally {
    keyPair.destroy();
  }
}

List<int> _compile(
  String source,
  int sequence, {
  String releaseId = _releaseId,
}) {
  final identity = E0Identity().declaration(
    canonicalLibraryUri: 'package:conformance/main.dart',
    declarationName: 'calculatePrice',
  );
  final manifest = E0ReleaseManifest(
    appId: _appId,
    releaseId: releaseId,
    buildFingerprint: _buildFingerprint,
    canonicalLibraryUri: 'package:conformance/main.dart',
    logicalLibraryPath: 'lib/main.dart',
    functions: <E0FunctionManifest>[
      E0FunctionManifest(
        name: 'calculatePrice',
        identity: identity,
        id: _functionId,
        slot: 0,
        signature: E0FunctionSignature.legacyInt2,
        receiver: E0ReceiverDescriptor.none,
      ),
    ],
  );
  return E0PatchCompiler().compile(
    source: source,
    manifest: manifest,
    functionName: 'calculatePrice',
    patchSequence: sequence,
  );
}

Future<Map<String, Object?>> _state(Directory storage) async =>
    await File('${storage.path}/state-v3-a.json').exists()
    ? jsonDecode(await File('${storage.path}/state-v3-a.json').readAsString())
          as Map<String, Object?>
    : <String, Object?>{'highWaterSequence': 0};

Future<bool> _activateHealthy(
  E1PatchController controller,
  List<int> envelope,
) async {
  if (!await controller.activateBytes(envelope)) return false;
  return controller.markHealthy();
}

int _execute(int quantity, int tier) =>
    E0PatchRuntime.invokeInt2(E0PatchRuntime.lookup(0)!, quantity, tier)!;

const _discountPatch = '''
int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 70;
  if (quantity < 3) return quantity * 95;
  return quantity * 75;
}
''';

const _alternatePatch = '''
int calculatePrice(int quantity, int tier) {
  if (quantity < 1) return 0;
  if (tier == 2) return quantity * 65;
  if (quantity < 3) return quantity * 80;
  return quantity * 60;
}
''';

const _faultingPatch = '''
int calculatePrice(int quantity, int tier) {
  throw quantity;
}
''';
