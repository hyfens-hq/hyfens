import 'dart:convert';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';
import 'package:test/test.dart';

const _interpreterFuzzSeed = 0x1c_47_48;
const _containerFuzzCases = 64;
const _interpreterFuzzCases = 64;
const _capabilityFuzzCases = 32;

void main() {
  late E0ReleaseManifest manifest;
  late List<int> validPatch;
  late E0PatchProgram validProgram;

  setUp(() {
    E0PatchRuntime.reset();
    final transformed = E0SourceTransformer().transform(
      source:
          'int target(int left, int right) { return left + right; }\n'
          'void main(List<String> arguments) {}',
      packageName: 'fuzz_fixture',
      logicalLibraryPath: 'lib/target.dart',
      appId: 'fuzz-app',
      releaseId: 'fuzz-release',
      buildFingerprint: 'fuzz-build',
    );
    manifest = transformed.manifest;
    validPatch = E0PatchCompiler().compile(
      source: 'int target(int left, int right) { return left + right; }',
      manifest: manifest,
      functionName: 'target',
      patchSequence: 1,
    );
    validProgram = E0PatchContainer.decode(
      validPatch,
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
  });

  tearDown(E0PatchRuntime.reset);

  test('seeded container mutations never replace an active program', () {
    expect(_install(validPatch, manifest), isTrue);
    final active = E0PatchRuntime.lookup(0)!;
    var state = _interpreterFuzzSeed;

    for (var index = 0; index < _containerFuzzCases; index++) {
      state = _nextSeed(state);
      final candidate = _mutatedContainer(validPatch, state, index);
      expect(
        _install(candidate, manifest),
        isFalse,
        reason: 'seed=0x${state.toRadixString(16)} case=$index',
      );
      expect(E0PatchRuntime.lookup(0), same(active));
      expect(E0PatchRuntime.lastRejection, isNotNull);
    }

    final nonOctet = validPatch.toList()..add(256);
    expect(_install(nonOctet, manifest), isFalse);
    expect(E0PatchRuntime.lookup(0), same(active));
  });

  test('deterministic interpreter corpus rejects malformed programs', () {
    final malformed = <E0PatchProgram>[
      _copyProgram(validProgram, code: const <int>[255]),
      _copyProgram(validProgram, code: <int>[E0Opcode.loadArgument.code]),
      _copyProgram(
        validProgram,
        code: <int>[E0Opcode.loadArgument.code, 99, E0Opcode.returnValue.code],
      ),
      _copyProgram(
        validProgram,
        code: <int>[E0Opcode.loadArgument.code, -1, E0Opcode.returnValue.code],
      ),
      _copyProgram(
        validProgram,
        code: <int>[E0Opcode.loadConstant.code, 99, E0Opcode.returnValue.code],
      ),
      _copyProgram(
        validProgram,
        code: <int>[E0Opcode.jump.code, 1, E0Opcode.returnValue.code],
      ),
      _copyProgram(validProgram, code: <int>[E0Opcode.returnValue.code]),
      _copyProgram(validProgram, code: const <int>[-1]),
      _copyProgram(
        validProgram,
        code: <int>[
          E0Opcode.callSyncCapability.code,
          0,
          0,
          E0Opcode.returnValue.code,
        ],
      ),
    ];

    for (var index = 0; index < malformed.length; index++) {
      expect(
        () => E0Interpreter.validate(malformed[index]),
        throwsFormatException,
        reason:
            'seed=0x${_interpreterFuzzSeed.toRadixString(16)} '
            'case=$index',
      );
    }
  });

  test('seeded interpreter verifier mutations remain bounded', () {
    var state = _interpreterFuzzSeed;
    var accepted = 0;
    var rejected = 0;

    for (var index = 0; index < _interpreterFuzzCases; index++) {
      state = _nextSeed(state);
      final candidate = switch (state % 4) {
        0 => _copyProgram(validProgram, code: const <int>[255]),
        1 => _copyProgram(
          validProgram,
          code: <int>[
            E0Opcode.loadArgument.code,
            99,
            E0Opcode.returnValue.code,
          ],
        ),
        2 => _copyProgram(validProgram, code: <int>[E0Opcode.returnValue.code]),
        _ => _copyProgram(validProgram),
      };
      try {
        E0Interpreter.validate(candidate);
        accepted++;
        expect(E0Interpreter.execute(candidate, 1, 2), 3);
      } on FormatException {
        rejected++;
      }
    }

    expect(accepted + rejected, _interpreterFuzzCases);
    expect(accepted, greaterThan(0));
    expect(rejected, greaterThan(0));
  });

  test('valid looping bytecode stops at the explicit instruction budget', () {
    final looping = E0PatchProgram(
      functionId: validProgram.functionId,
      slot: validProgram.slot,
      signature: validProgram.signature,
      receiver: validProgram.receiver,
      constants: const <Object?>[],
      code: const <int>[1, 0, 1, 1, 7, 8, 0, 1, 0, 9],
      patchSequence: validProgram.patchSequence,
    );
    E0Interpreter.validate(looping);
    expect(
      () => E0Interpreter.execute(looping, 0, 1, instructionBudget: 4),
      throwsA(isA<E0RuntimeFault>()),
    );
  });

  test('seeded capability contract corpus fails closed', () {
    final descriptor = E0AsyncCapabilityDescriptor(
      id: 'app.fuzz.echo',
      sourceName: 'fuzzEcho',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.boolean,
      resources: const <String>['test:fuzz'],
    );
    var state = _interpreterFuzzSeed;
    final base = descriptor.toRuntimeJson();

    for (var index = 0; index < _capabilityFuzzCases; index++) {
      state = _nextSeed(state);
      final candidate = _mutatedCapability(base, state, index);
      expect(
        () => E0AsyncCapabilityDescriptor.fromContractJson(candidate),
        throwsFormatException,
        reason: 'seed=0x${state.toRadixString(16)} case=$index',
      );
    }
  });

  test('forged capability authority cannot replace an active program', () {
    final descriptor = E0AsyncCapabilityDescriptor(
      id: 'app.fuzz.echo',
      sourceName: 'fuzzEcho',
      version: 1,
      arguments: const <E0ValueSchema>[],
      result: E0ValueSchema.boolean,
      resources: const <String>['test:fuzz'],
    );
    final transformed = E0SourceTransformer().transform(
      source:
          'Future<bool> target() async { return await fuzzEcho(); }\n'
          'void main(List<String> arguments) {}',
      packageName: 'fuzz_fixture',
      logicalLibraryPath: 'lib/capability.dart',
      appId: 'fuzz-app',
      releaseId: 'fuzz-release',
      buildFingerprint: 'fuzz-build',
      capabilities: <E0AsyncCapabilityDescriptor>[descriptor],
    );
    final capabilityManifest = transformed.manifest;
    final patch = E0PatchCompiler().compile(
      source: 'Future<bool> target() async { return await fuzzEcho(); }',
      manifest: capabilityManifest,
      functionName: 'target',
      patchSequence: 1,
    );
    E0PatchRuntime.configureCapabilities(
      E0CapabilityAuthority(
        shipped: <E0AsyncCapabilityDescriptor>[descriptor],
        registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
          E0CapabilityRegistration(descriptor, (_) async => true),
        ]),
      ),
    );
    expect(_install(patch, capabilityManifest), isTrue);
    final active = E0PatchRuntime.lookup(0)!;
    final decoded = _decode(patch, capabilityManifest);
    final forgedDescriptor = E0AsyncCapabilityDescriptor(
      id: descriptor.id,
      version: descriptor.version + 1,
      arguments: descriptor.arguments,
      result: descriptor.result,
      resources: descriptor.resources,
    );
    final forged = E0PatchContainer.encode(
      appId: capabilityManifest.appId,
      releaseId: capabilityManifest.releaseId,
      buildFingerprint: capabilityManifest.buildFingerprint,
      program: _copyProgram(
        decoded,
        capabilities: <E0AsyncCapabilityDescriptor>[forgedDescriptor],
        patchSequence: decoded.patchSequence + 1,
      ),
    );

    expect(_install(forged, capabilityManifest), isFalse);
    expect(E0PatchRuntime.lookup(0), same(active));
    expect(E0PatchRuntime.lastRejection, contains('Capability'));
  });
}

bool _install(
  List<int> bytes,
  E0ReleaseManifest manifest,
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

E0PatchProgram _decode(List<int> bytes, E0ReleaseManifest manifest) =>
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

E0PatchProgram _copyProgram(
  E0PatchProgram program, {
  List<int>? code,
  List<E0AsyncCapabilityDescriptor>? capabilities,
  int? patchSequence,
}) => E0PatchProgram(
  functionId: program.functionId,
  slot: program.slot,
  signature: program.signature,
  receiver: program.receiver,
  constants: program.constants,
  code: code ?? program.code,
  locals: program.locals,
  handlers: program.handlers,
  capabilities: capabilities ?? program.capabilities,
  asyncPoints: program.asyncPoints,
  widgetFactories: program.widgetFactories,
  closures: program.closures,
  patchSequence: patchSequence ?? program.patchSequence,
  payloadHash: program.payloadHash,
);

List<int> _mutatedContainer(List<int> validPatch, int seed, int index) {
  if ((seed + index) % 9 == 8) {
    return List<int>.filled(E0PatchContainer.maxBytes + 1, 0);
  }
  final value = jsonDecode(utf8.decode(validPatch)) as Map<String, Object?>;
  switch ((seed + index) % 9) {
    case 0:
      value['code'] = const <int>[255];
    case 1:
      value['code'] = <int>[
        E0Opcode.loadArgument.code,
        99,
        E0Opcode.returnValue.code,
      ];
    case 2:
      value['slot'] = -1;
    case 3:
      value['unexpected'] = true;
    case 4:
      value['constants'] = List<Object?>.filled(
        E0PatchContainer.maxConstants + 1,
        null,
      );
    case 5:
      value['code'] = List<int>.filled(E0PatchContainer.maxCodeWords + 1, 0);
    case 6:
      value['payloadHash'] = '0' * 64;
    case 7:
      value['patchSequence'] = 0;
  }
  return utf8.encode(jsonEncode(value));
}

Map<String, Object?> _mutatedCapability(
  Map<String, Object?> base,
  int seed,
  int index,
) {
  final value = <String, Object?>{...base};
  switch ((seed + index) % 8) {
    case 0:
      value['contractDigest'] = '0' * 64;
    case 1:
      value['unexpected'] = true;
    case 2:
      value['version'] = 0;
    case 3:
      value['arguments'] = List<Object?>.filled(17, <String, Object?>{
        'kind': 'integer',
        'nullable': false,
      });
    case 4:
      value['resources'] = const <String>['test:fuzz', 'test:fuzz'];
    case 5:
      value['cancellation'] = 'abortable';
    case 6:
      value['policy'] = <String, Object?>{
        'timeoutMs': 0,
        'maxOutputBytes': 1024,
        'sideEffect': 'none',
      };
    case 7:
      value['result'] = <String, Object?>{'kind': 'object', 'nullable': false};
  }
  return value;
}

int _nextSeed(int state) => (state * 1_664_525 + 1_013_904_223) & 0x7fffffff;
