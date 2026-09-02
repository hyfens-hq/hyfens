import 'dart:convert';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:test/test.dart';

final _functionDigestA = 'sha256:${'1' * 64}';
final _functionDigestB = 'sha256:${'2' * 64}';

void main() {
  group('Patch Format v1 malformed corpus', () {
    test('rejects deterministic malformed artifacts before activation use', () {
      final cases = <String, List<int>>{
        'empty artifact': const <int>[],
        'artifact exceeds byte limit': List<int>.filled(
          PatchFormatLimits.maxArtifactBytes + 1,
          0,
        ),
        'truncated header': _validBytes().sublist(0, 12),
        'invalid magic': _mutate(_validBytes(), (bytes) => bytes[0] ^= 1),
        'unsupported format version': _mutate(
          _validBytes(),
          (bytes) => bytes[9] = 2,
        ),
        'non-zero header flags': _mutate(
          _validBytes(),
          (bytes) => bytes[10] = 1,
        ),
        'zero section count': _mutate(
          _validBytes(),
          (bytes) => _writeU16(bytes, 16, 0),
        ),
        'too many sections': _mutate(
          _validBytes(),
          (bytes) => _writeU16(bytes, 16, PatchFormatLimits.maxSections + 1),
        ),
        'duplicate section': _duplicateFirstSectionType(_validBytes()),
        'sections out of order': _outOfOrderSections(_validBytes()),
        'known section marked non-critical': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) => bytes[section.headerOffset + 3] = 0,
        ),
        'unknown critical section': _unknownCriticalSection(),
        'oversized section': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) => _writeU32(
            bytes,
            section.headerOffset + 4,
            PatchFormatLimits.maxSectionBytes + 1,
          ),
        ),
        'section length beyond input': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) =>
              _writeU32(bytes, section.headerOffset + 4, 0xffffffff),
        ),
        'trailing bytes': <int>[..._validBytes(), 0],
        'missing required section': _removeSection(_validBytes(), 8),
        'invalid identity UTF-8': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) => bytes[section.payloadOffset + 4] = 0xff,
        ),
        'oversized identity string': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) => _writeU32(
            bytes,
            section.payloadOffset,
            PatchFormatLimits.maxIdentifierBytes + 1,
          ),
        ),
        'invalid timestamp flag': _mutateSection(
          _validBytes(),
          1,
          (bytes, section) => bytes[_timestampFlagOffset(bytes, section)] = 2,
        ),
        'out-of-range timestamp': _mutateSection(_validBytes(), 1, (
          bytes,
          section,
        ) {
          final flag = _timestampFlagOffset(bytes, section);
          for (var index = flag + 1; index <= flag + 8; index++) {
            bytes[index] = 0x7f;
          }
        }),
        'oversized function table': _mutateSection(
          _validBytes(),
          2,
          (bytes, section) => _writeU32(
            bytes,
            section.payloadOffset,
            PatchFormatLimits.maxFunctions + 1,
          ),
        ),
        'duplicate function ID': _duplicateFunctionId(),
        'oversized capability table': _mutateSection(
          _validBytes(),
          3,
          (bytes, section) => _writeU32(
            bytes,
            section.payloadOffset,
            PatchFormatLimits.maxCapabilities + 1,
          ),
        ),
        'invalid capability enum': _mutateSection(
          _capabilityBytes(),
          3,
          (bytes, section) =>
              bytes[_firstCapabilityExecutionOffset(bytes, section)] = 0xff,
        ),
        'oversized capability permissions': _mutateSection(
          _capabilityBytes(),
          3,
          (bytes, section) => _writeU32(
            bytes,
            _firstCapabilityPermissionCountOffset(bytes, section),
            PatchFormatLimits.maxPermissions + 1,
          ),
        ),
        'duplicate capability ID': _duplicateCapabilityId(),
        'unknown constant kind': _mutateSection(
          _validBytes(),
          4,
          (bytes, section) => bytes[section.payloadOffset + 4] = 0xff,
        ),
        'oversized constant list': _oversizedConstantList(),
        'non-finite constant': _nonFiniteConstant(),
        'oversized instruction table': _mutateSection(
          _validBytes(),
          5,
          (bytes, section) => _writeU32(
            bytes,
            section.payloadOffset,
            PatchFormatLimits.maxInstructions + 1,
          ),
        ),
        'invalid digest length': _replaceSectionPayload(
          _validBytes(),
          7,
          (payload) => payload.sublist(0, payload.length - 1),
        ),
        'invalid signature length': _mutateSection(
          _validBytes(),
          8,
          (bytes, section) => _writeU16(bytes, section.payloadOffset, 0),
        ),
        'payload digest mismatch': _mutateSection(
          _validBytes(),
          4,
          (bytes, section) => bytes[section.payloadOffset + 4] ^= 1,
        ),
      };

      expect(cases, hasLength(33));
      for (final entry in cases.entries) {
        expect(
          () => PatchFormatV1.decode(entry.value),
          throwsA(isA<PatchFormatException>()),
          reason: entry.key,
        );
      }
    });

    test('rejects non-octet input instead of normalizing it', () {
      for (final bytes in <List<int>>[
        <int>[-1],
        <int>[256],
        <int>[..._validBytes(), 256],
      ]) {
        expect(
          () => PatchFormatV1.decode(bytes),
          throwsA(isA<PatchFormatException>()),
          reason: 'input must contain only octets',
        );
      }

      expect(
        () =>
            PatchExtensionSection(type: 9, flags: 0, payload: const <int>[256]),
        throwsA(isA<PatchFormatException>()),
      );
    });

    test(
      'rejects malformed baseline manifests without accepting extra fields',
      () {
        final source = _manifest().encode();
        final decoded = jsonDecode(source) as Map<String, Object?>;

        final unknown = <String, Object?>{...decoded, 'criticalField': true};
        expect(
          () => ReleaseBaselineManifest.decode(jsonEncode(unknown)),
          throwsA(isA<PatchFormatException>()),
        );

        final missing = <String, Object?>{...decoded}..remove('functions');
        expect(
          () => ReleaseBaselineManifest.decode(jsonEncode(missing)),
          throwsA(isA<PatchFormatException>()),
        );

        final oversized = <String, Object?>{
          ...decoded,
          'functions': List<Object?>.filled(
            PatchFormatLimits.maxFunctions + 1,
            <String, Object?>{
              'id': 'sha256:${'a' * 64}',
              'slot': 0,
              'signatureDigest': _functionDigestA,
            },
          ),
        };
        expect(
          () => ReleaseBaselineManifest.decode(jsonEncode(oversized)),
          throwsA(isA<PatchFormatException>()),
        );
      },
    );

    test('seeded parser fuzz remains bounded and deterministic', () {
      const seed = 0x1c2026;
      const cases = 512;
      var state = seed;
      var rejected = 0;
      var accepted = 0;

      for (var index = 0; index < cases; index++) {
        final bytes = _validBytes();
        final mutations = 1 + (_next(state = _next(state)) % 5);
        for (var mutation = 0; mutation < mutations; mutation++) {
          state = _next(state);
          final offset = state % bytes.length;
          state = _next(state);
          bytes[offset] = state & 0xff;
        }
        try {
          PatchFormatV1.decode(bytes);
          accepted++;
        } on PatchFormatException {
          rejected++;
        } on Error {
          rethrow;
        } on Object catch (error, stack) {
          fail(
            'seed=$seed case=$index unexpected parser failure: $error\n$stack',
          );
        }
      }

      expect(rejected, greaterThan(0), reason: 'seed=$seed cases=$cases');
      expect(accepted + rejected, cases);
    });
  });
}

List<int> _validBytes({List<PatchExtensionSection> extensions = const []}) {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1234, isUtc: true),
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.integer(1)],
    instructions: const <int>[1, 0, 9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
    extensions: extensions,
  );
  return PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
}

List<int> _capabilityBytes() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
    ],
    capabilities: <PatchCapabilityEntry>[
      PatchCapabilityEntry(
        id: 'http.get',
        version: 1,
        execution: PatchExecutionKind.sync,
        classification: PatchCapabilityClass.network,
        argumentSchema: '{"kind":"string"}',
        returnSchema: '{"kind":"string"}',
      ),
    ],
    constants: const <PatchValue>[PatchValue.integer(1)],
    instructions: const <int>[1, 0, 9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  return PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
}

ReleaseBaselineManifest _manifest() => ReleaseBaselineManifest(
  applicationId: 'dev.hyfens.fuzz',
  releaseId: 'sha256:${'a' * 64}',
  runtimeCompatibilityVersion: 1,
  patchFormatVersion: 1,
  buildFingerprint: 'build-fuzz',
  functions: <PatchFunctionEntry>[
    PatchFunctionEntry(
      id: 'sha256:${'1' * 64}',
      slot: 0,
      signatureDigest: _functionDigestA,
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

List<int> _duplicateFunctionId() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
      PatchFunctionEntry(
        id: 'sha256:${'2' * 64}',
        slot: 1,
        signatureDigest: _functionDigestB,
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[],
    instructions: const <int>[9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  final bytes = PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
  return _mutateSection(bytes, 2, (mutable, section) {
    var offset = section.payloadOffset + 4;
    offset = _skipString(mutable, offset);
    offset += 4;
    offset = _skipString(mutable, offset);
    final secondIdLength = _readU32(mutable, offset);
    final firstIdLength = _readU32(mutable, section.payloadOffset + 4);
    expect(secondIdLength, firstIdLength);
    for (var index = 0; index < firstIdLength; index++) {
      mutable[offset + 4 + index] = mutable[section.payloadOffset + 8 + index];
    }
  });
}

List<int> _duplicateCapabilityId() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
    ],
    capabilities: <PatchCapabilityEntry>[
      PatchCapabilityEntry(
        id: 'a.read',
        version: 1,
        execution: PatchExecutionKind.sync,
        classification: PatchCapabilityClass.pure,
        argumentSchema: '{"kind":"int"}',
        returnSchema: '{"kind":"int"}',
      ),
      PatchCapabilityEntry(
        id: 'b.read',
        version: 1,
        execution: PatchExecutionKind.sync,
        classification: PatchCapabilityClass.pure,
        argumentSchema: '{"kind":"int"}',
        returnSchema: '{"kind":"int"}',
      ),
    ],
    constants: const <PatchValue>[],
    instructions: const <int>[9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  final bytes = PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
  return _mutateSection(bytes, 3, (mutable, section) {
    var first = section.payloadOffset + 4;
    final firstIdLength = _readU32(mutable, first);
    final firstIdStart = first + 4;
    first = _skipCapability(mutable, first);
    final secondIdLength = _readU32(mutable, first);
    expect(secondIdLength, firstIdLength);
    for (var index = 0; index < firstIdLength; index++) {
      mutable[first + 4 + index] = mutable[firstIdStart + index];
    }
  });
}

List<int> _oversizedConstantList() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.list(const <PatchValue>[])],
    instructions: const <int>[9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  final bytes = PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
  return _mutateSection(bytes, 4, (mutable, section) {
    _writeU32(mutable, section.payloadOffset + 5, 0xffffffff);
  });
}

List<int> _nonFiniteConstant() {
  final draft = PatchArtifact(
    runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
    applicationId: 'dev.hyfens.fuzz',
    releaseId: 'sha256:${'a' * 64}',
    patchId: 'sha256:${'b' * 64}',
    sequence: 1,
    functions: <PatchFunctionEntry>[
      PatchFunctionEntry(
        id: 'sha256:${'1' * 64}',
        slot: 0,
        signatureDigest: _functionDigestA,
      ),
    ],
    capabilities: const <PatchCapabilityEntry>[],
    constants: const <PatchValue>[PatchValue.doubleValue(1.0)],
    instructions: const <int>[9],
    signatureMetadata: PatchSignatureMetadata(
      algorithm: 'ed25519',
      keyId: 'fuzz-key',
    ),
    payloadDigest: const <int>[],
    signature: const <int>[],
  );
  final bytes = PatchFormatV1.encode(
    PatchFormatV1.seal(draft, (_) => List<int>.filled(64, 0x5a)),
  );
  return _mutateSection(bytes, 4, (mutable, section) {
    for (
      var index = section.payloadOffset + 5;
      index < section.payloadOffset + 13;
      index++
    ) {
      mutable[index] = 0xff;
    }
  });
}

List<int> _unknownCriticalSection() {
  final bytes = _validBytes(
    extensions: <PatchExtensionSection>[
      PatchExtensionSection(type: 9, flags: 0, payload: const <int>[1]),
    ],
  );
  final extension = _sections(bytes)
      .singleWhere((section) => section.type == 9);
  bytes[extension.headerOffset + 3] = 1;
  return bytes;
}

List<int> _duplicateFirstSectionType(List<int> source) {
  final bytes = List<int>.of(source);
  final sections = _sections(bytes);
  _writeU16(bytes, sections[1].headerOffset, sections[0].type);
  return bytes;
}

List<int> _outOfOrderSections(List<int> source) {
  final bytes = List<int>.of(source);
  final sections = _sections(bytes);
  final first = bytes.sublist(
    sections[0].headerOffset,
    sections[1].headerOffset,
  );
  final second = bytes.sublist(
    sections[1].headerOffset,
    sections[2].headerOffset,
  );
  bytes..setRange(sections[0].headerOffset, sections[2].headerOffset, <int>[
    ...second,
    ...first,
  ]);
  return bytes;
}

List<int> _removeSection(List<int> source, int type) {
  final sections = _sections(source);
  final target = sections.singleWhere((section) => section.type == type);
  final bytes = <int>[
    ...source.sublist(0, target.headerOffset),
    ...source.sublist(target.payloadOffset + target.length),
  ];
  _writeU16(bytes, 16, sections.length - 1);
  return bytes;
}

List<int> _replaceSectionPayload(
  List<int> source,
  int type,
  List<int> Function(List<int> payload) transform,
) {
  final sections = _sections(source);
  final target = sections.singleWhere((section) => section.type == type);
  final payload = transform(
    source.sublist(target.payloadOffset, target.payloadOffset + target.length),
  );
  final bytes = <int>[
    ...source.sublist(0, target.payloadOffset),
    ...payload,
    ...source.sublist(target.payloadOffset + target.length),
  ];
  _writeU32(bytes, target.headerOffset + 4, payload.length);
  return bytes;
}

List<int> _mutateSection(
  List<int> source,
  int type,
  void Function(List<int> bytes, _Section section) mutation,
) {
  final bytes = List<int>.of(source);
  final section = _sections(bytes).singleWhere((item) => item.type == type);
  mutation(bytes, section);
  return bytes;
}

List<int> _mutate(List<int> source, void Function(List<int>) mutation) {
  final bytes = List<int>.of(source);
  mutation(bytes);
  return bytes;
}

int _timestampFlagOffset(List<int> bytes, _Section section) {
  var offset = section.payloadOffset;
  for (var index = 0; index < 3; index++) {
    final length = _readU32(bytes, offset);
    offset += 4 + length;
  }
  return offset + 8;
}

int _firstCapabilityExecutionOffset(List<int> bytes, _Section section) {
  var offset = section.payloadOffset + 4;
  offset = _skipString(bytes, offset);
  return offset + 4;
}

int _firstCapabilityPermissionCountOffset(List<int> bytes, _Section section) {
  return _firstCapabilityExecutionOffset(bytes, section) + 2;
}

int _skipCapability(List<int> bytes, int offset) {
  offset = _skipString(bytes, offset);
  offset += 4 + 1 + 1;
  final permissions = _readU32(bytes, offset);
  offset += 4;
  for (var index = 0; index < permissions; index++) {
    offset = _skipString(bytes, offset);
  }
  offset = _skipString(bytes, offset);
  return _skipString(bytes, offset);
}

int _skipString(List<int> bytes, int offset) {
  final length = _readU32(bytes, offset);
  return offset + 4 + length;
}

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

List<_Section> _sections(List<int> bytes) {
  var offset = 18;
  final count = _readU16(bytes, 16);
  final result = <_Section>[];
  for (var index = 0; index < count; index++) {
    final headerOffset = offset;
    final type = _readU16(bytes, offset);
    final flags = _readU16(bytes, offset + 2);
    final length = _readU32(bytes, offset + 4);
    final payloadOffset = offset + 8;
    result.add(
      _Section(
        type: type,
        flags: flags,
        headerOffset: headerOffset,
        payloadOffset: payloadOffset,
        length: length,
      ),
    );
    offset = payloadOffset + length;
  }
  return result;
}

int _readU16(List<int> bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

int _next(int value) => (value * 1103515245 + 12345) & 0x7fffffff;

final class _Section {
  const _Section({
    required this.type,
    required this.flags,
    required this.headerOffset,
    required this.payloadOffset,
    required this.length,
  });

  final int type;
  final int flags;
  final int headerOffset;
  final int payloadOffset;
  final int length;
}
