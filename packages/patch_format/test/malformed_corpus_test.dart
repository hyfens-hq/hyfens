import 'dart:convert';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

const _parserFuzzSeed = 0x1c_18_24;
const _parserFuzzCases = 96;

void main() {
  final encoded = PatchFormatV1.encode(_sealedArtifact());

  test('minimal malformed binary corpus fails with bounded format errors', () {
    final corpus = <_MalformedCase>[
      _MalformedCase('empty', const <int>[]),
      _MalformedCase('truncated magic', encoded.sublist(0, 7)),
      _MalformedCase('wrong magic', _mutate(encoded, (bytes) => bytes[0] = 0)),
      _MalformedCase(
        'unsupported format version',
        _mutate(encoded, (bytes) => _writeU16(bytes, 8, 2)),
      ),
      _MalformedCase(
        'non-zero header flags',
        _mutate(encoded, (bytes) => _writeU16(bytes, 10, 1)),
      ),
      _MalformedCase(
        'section count exceeds limit',
        _mutate(encoded, (bytes) => _writeU16(bytes, 16, 0xffff)),
      ),
      _MalformedCase(
        'known section is not critical',
        _mutate(encoded, (bytes) => _writeU16(bytes, 20, 0)),
      ),
      _MalformedCase(
        'section length exceeds limit before read',
        _mutate(encoded, (bytes) => _writeU32(bytes, 22, 0xffffffff)),
      ),
      _MalformedCase(
        'duplicate section type',
        _mutate(encoded, (bytes) => _writeU16(bytes, 18, 2)),
      ),
      _MalformedCase(
        'unknown critical section',
        _appendSection(encoded, type: 9, flags: 1),
      ),
      _MalformedCase(
        'identity string length exceeds limit',
        _mutate(encoded, (bytes) {
          final identity = _section(encoded, 1);
          _writeU32(bytes, identity.payloadStart, 0x00000101);
        }),
      ),
      _MalformedCase(
        'identity string is not strict UTF-8',
        _mutate(encoded, (bytes) {
          final identity = _section(encoded, 1);
          bytes[identity.payloadStart + 4] = 0xff;
        }),
      ),
      _MalformedCase(
        'timestamp flag is not boolean',
        _mutate(encoded, (bytes) {
          final identity = _section(encoded, 1);
          bytes[_timestampFlagOffset(encoded, identity.payloadStart)] = 2;
        }),
      ),
      _MalformedCase(
        'function count exceeds limit before allocation',
        _mutate(encoded, (bytes) {
          final functions = _section(encoded, 2);
          _writeU32(bytes, functions.payloadStart, 0x00001001);
        }),
      ),
      _MalformedCase(
        'constant kind is unknown',
        _mutate(encoded, (bytes) {
          final constants = _section(encoded, 4);
          bytes[constants.payloadStart + 4] = 0xff;
        }),
      ),
      _MalformedCase(
        'instruction count exceeds limit before allocation',
        _mutate(encoded, (bytes) {
          final instructions = _section(encoded, 5);
          _writeU32(bytes, instructions.payloadStart, 0x00010001);
        }),
      ),
      _MalformedCase(
        'signature length is zero',
        _mutate(encoded, (bytes) {
          final signature = _section(encoded, 8);
          _writeU16(bytes, signature.payloadStart, 0);
        }),
      ),
      _MalformedCase(
        'payload digest is corrupt',
        _mutate(encoded, (bytes) {
          final digest = _section(encoded, 7);
          bytes[digest.payloadStart] ^= 0xff;
        }),
      ),
      _MalformedCase('trailing byte', <int>[...encoded, 0]),
    ];

    expect(corpus, hasLength(19));
    for (final malformed in corpus) {
      expect(
        () => PatchFormatV1.decode(malformed.bytes),
        throwsA(isA<PatchFormatException>()),
        reason:
            'seed=0x${_parserFuzzSeed.toRadixString(16)} '
            'case=${malformed.name}',
      );
    }
  });

  test('seeded parser and verifier mutations stay bounded and canonical', () {
    var state = _parserFuzzSeed;
    var accepted = 0;
    var rejected = 0;

    for (var index = 0; index < _parserFuzzCases; index++) {
      final next = _nextSeed(state);
      state = next;
      final candidate = _seededMutation(encoded, next, index);
      try {
        final decoded = PatchFormatV1.decode(candidate);
        accepted++;
        expect(PatchFormatV1.encode(decoded), candidate);
        expect(
          PatchFormatV1.verifySignature(
            decoded,
            (signingBytes, signature) => _sameBytes(
              signature,
              List<int>.filled(64, signingBytes.length & 0xff),
            ),
          ),
          isFalse,
          reason:
              'mutated signature must not match the deterministic test '
              'verifier; seed=0x${next.toRadixString(16)} case=$index',
        );
      } on PatchFormatException {
        rejected++;
      }
    }

    expect(accepted + rejected, _parserFuzzCases);
    expect(accepted, greaterThan(0));
    expect(rejected, greaterThan(0));
  });

  test('verifier receives the exact v1 signing domain', () {
    final artifact = _sealedArtifact();
    final decoded = PatchFormatV1.decode(PatchFormatV1.encode(artifact));
    List<int>? receivedBytes;
    List<int>? receivedSignature;

    expect(
      PatchFormatV1.verifySignature(decoded, (signingBytes, signature) {
        receivedBytes = signingBytes;
        receivedSignature = signature;
        return true;
      }),
      isTrue,
    );
    expect(receivedBytes, PatchFormatV1.signingBytes(decoded));
    expect(receivedSignature, decoded.signature);
  });

  test(
    'baseline table bounds reject oversized canonical JSON before mapping',
    () {
      final baseline = _baselineManifest();
      final decoded = _asMap(baseline.encode());
      final oversizedFunctions = List<Object?>.generate(
        PatchFormatLimits.maxFunctions + 1,
        (index) => <String, Object?>{
          'id': 'sha256:${index.toRadixString(16).padLeft(64, '0')}',
          'signatureDigest': 'sha256:${'5' * 64}',
          'slot': index,
        },
        growable: false,
      );
      final oversizedCapabilities = List<Object?>.generate(
        PatchFormatLimits.maxCapabilities + 1,
        (index) => <String, Object?>{
          'argumentSchema': '{"kind":"string"}',
          'classification': 'pure',
          'execution': 'sync',
          'id': 'app.fuzz.cap${index.toString().padLeft(4, '0')}',
          'permissions': const <String>[],
          'returnSchema': '{"kind":"string"}',
          'version': 1,
        },
        growable: false,
      );

      for (final entry in <String, List<Object?>>{
        'functions': oversizedFunctions,
        'capabilities': oversizedCapabilities,
      }.entries) {
        final forged = <String, Object?>{...decoded, entry.key: entry.value};
        expect(
          () => ReleaseBaselineManifest.decode(_json(forged)),
          throwsA(isA<PatchFormatException>()),
          reason: entry.key,
        );
      }
    },
  );
}

final class _MalformedCase {
  const _MalformedCase(this.name, this.bytes);

  final String name;
  final List<int> bytes;
}

final class _Section {
  const _Section({required this.payloadStart, required this.length});

  final int payloadStart;
  final int length;
}

PatchArtifact _sealedArtifact() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'1' * 64}',
    patchId: 'sha256:${'2' * 64}',
    sequence: 1,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true),
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'3' * 64}',
        slot: 0,
        signatureDigest: 'sha256:${'4' * 64}',
      ),
    ],
    capabilities: <PatchCapabilityEntry>[
      PatchCapabilityEntry(
        id: 'app.fuzz.read',
        version: 1,
        execution: PatchExecutionKind.sync,
        classification: PatchCapabilityClass.pure,
        argumentSchema: '{"kind":"string"}',
        returnSchema: '{"kind":"string"}',
        permissions: const <String>['test:fuzz'],
      ),
    ],
    constants: const <PatchValue>[
      PatchValue.integer(7),
      PatchValue.map(<String, PatchValue>{'name': PatchValue.string('fuzz')}),
    ],
    instructions: const <int>[1, 0, 9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  return PatchFormatV1.seal(
    draft,
    (signingBytes) =>
        List<int>.filled(64, signingBytes.length & 0xff, growable: false),
  );
}

ReleaseBaselineManifest _baselineManifest() => ReleaseBaselineManifest(
  applicationId: 'dev.hyfens.fuzz',
  releaseId: 'sha256:${'1' * 64}',
  runtimeCompatibilityVersion: 1,
  patchFormatVersion: 1,
  buildFingerprint: 'fuzz-build',
  functions: <PatchFunctionEntry>[
    PatchFunctionEntry(
      id: 'sha256:${'3' * 64}',
      slot: 0,
      signatureDigest: 'sha256:${'4' * 64}',
    ),
  ],
  capabilities: const <PatchCapabilityEntry>[],
  packages: const <String>['dev.hyfens.fuzz'],
  sourceUnits: <ReleaseBaselineSourceUnit>[
    ReleaseBaselineSourceUnit(
      packageName: 'dev.hyfens.fuzz',
      libraryUri: 'package:dev.hyfens.fuzz/main.dart',
      sourceKind: 'application',
      instrumented: true,
    ),
  ],
);

Map<String, Object?> _asMap(String value) =>
    jsonDecode(value) as Map<String, Object?>;

String _json(Map<String, Object?> value) {
  Object? canonical(Object? current) {
    if (current is Map<String, Object?>) {
      final keys = current.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: canonical(current[key]),
      };
    }
    if (current is List<Object?>) {
      return current.map(canonical).toList(growable: false);
    }
    return current;
  }

  return jsonEncode(canonical(value));
}

List<int> _seededMutation(List<int> input, int seed, int index) {
  final bytes = input.toList();
  switch ((seed + index) % 5) {
    case 0:
      final signature = _section(bytes, 8);
      bytes[signature.payloadStart + 2 + (seed % 62)] ^= 1 << (seed % 7);
    case 1:
      _writeU16(bytes, 10, 1);
    case 2:
      _writeU32(bytes, 22, 0xffffffff);
    case 3:
      return bytes.sublist(0, bytes.length - 1 - (seed % 8));
    case 4:
      final digest = _section(bytes, 7);
      bytes[digest.payloadStart + (seed % 32)] ^= 0x80;
  }
  return bytes;
}

List<int> _appendSection(
  List<int> input, {
  required int type,
  required int flags,
}) {
  final bytes = input.toList()
    ..addAll(<int>[
      (type >> 8) & 0xff,
      type & 0xff,
      (flags >> 8) & 0xff,
      flags & 0xff,
      0,
      0,
      0,
      0,
    ]);
  _writeU16(bytes, 16, _readU16(bytes, 16) + 1);
  return bytes;
}

List<int> _mutate(List<int> input, void Function(List<int> bytes) mutation) {
  final bytes = input.toList();
  mutation(bytes);
  return bytes;
}

_Section _section(List<int> bytes, int wantedType) {
  var offset = 18;
  final count = _readU16(bytes, 16);
  for (var index = 0; index < count; index++) {
    final type = _readU16(bytes, offset);
    final length = _readU32(bytes, offset + 4);
    final payloadStart = offset + 8;
    if (type == wantedType) {
      return _Section(payloadStart: payloadStart, length: length);
    }
    offset = payloadStart + length;
  }
  throw StateError('missing test section $wantedType');
}

int _timestampFlagOffset(List<int> bytes, int identityStart) {
  var offset = identityStart;
  for (var index = 0; index < 3; index++) {
    offset += 4 + _readU32(bytes, offset);
  }
  return offset + 8;
}

int _readU16(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _readU32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void _writeU16(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

void _writeU32(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _nextSeed(int state) => (state * 1_664_525 + 1_013_904_223) & 0x7fffffff;

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
