library hyfens_patch_format;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int patchFormatV1 = 1;
const int patchFormatRuntimeCompatibilityV1 = 1;
const int _maxPositiveU64 = 0x7fffffffffffffff;

/// Stable parser limits. These are protocol limits, not tunable application
/// preferences; a larger value requires a format/runtime revision.
final class PatchFormatLimits {
  const PatchFormatLimits._();

  static const maxArtifactBytes = 4 * 1024 * 1024;
  static const maxSections = 32;
  static const maxSectionBytes = 1024 * 1024;
  static const maxIdentifierBytes = 256;
  static const maxSchemaBytes = 64 * 1024;
  static const maxFunctions = 4096;
  static const maxCapabilities = 4096;
  static const maxConstants = 4096;
  static const maxInstructions = 65536;
  static const maxPermissions = 32;
  static const maxNestingDepth = 16;
  static const maxCollectionEntries = 1024;
  static const maxStringBytes = 64 * 1024;
  static const maxSignatureBytes = 128;
}

final class PatchFormatException implements Exception {
  const PatchFormatException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PatchFormatException($code): $message';
}

enum PatchExecutionKind { sync, async }

enum PatchCapabilityClass {
  pure,
  ui,
  network,
  storage,
  navigation,
  device,
  sensitive,
  nativeBoundary,
}

final class PatchFunctionEntry {
  PatchFunctionEntry({
    required this.id,
    required this.slot,
    required this.signatureDigest,
  }) {
    _validateIdentifier(id, 'function ID');
    _validateDigest(signatureDigest, 'signature digest');
    if (slot < 0 || slot > 0xffffffff) {
      throw const PatchFormatException(
        'P1008',
        'Function slot is out of range',
      );
    }
  }

  final String id;
  final int slot;
  final String signatureDigest;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'slot': slot,
    'signatureDigest': signatureDigest,
  };

  static PatchFunctionEntry fromJson(Object? value) {
    final map = _object(value, 'function entry');
    _exactKeys(map, const {'id', 'slot', 'signatureDigest'}, 'function entry');
    if (map['id'] is! String ||
        map['slot'] is! int ||
        map['signatureDigest'] is! String) {
      throw const PatchFormatException('P1009', 'Invalid function entry types');
    }
    return PatchFunctionEntry(
      id: map['id']! as String,
      slot: map['slot']! as int,
      signatureDigest: map['signatureDigest']! as String,
    );
  }
}

final class PatchCapabilityEntry {
  PatchCapabilityEntry({
    required this.id,
    required this.version,
    required this.execution,
    required this.classification,
    required this.argumentSchema,
    required this.returnSchema,
    List<String> permissions = const <String>[],
  }) : permissions = List.unmodifiable(
         _canonicalStringList(permissions, 'capability permissions'),
       ) {
    _validateIdentifier(id, 'capability ID');
    if (version <= 0 || version > 0xffffffff) {
      throw const PatchFormatException(
        'P1010',
        'Capability version must be positive',
      );
    }
    _validateSchema(argumentSchema, 'argument schema');
    _validateSchema(returnSchema, 'return schema');
    if (permissions.length > PatchFormatLimits.maxPermissions) {
      throw const PatchFormatException(
        'P1011',
        'Too many capability permissions',
      );
    }
  }

  final String id;
  final int version;
  final PatchExecutionKind execution;
  final PatchCapabilityClass classification;
  final String argumentSchema;
  final String returnSchema;
  final List<String> permissions;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'version': version,
    'execution': execution.name,
    'classification': classification.name,
    'argumentSchema': argumentSchema,
    'returnSchema': returnSchema,
    'permissions': permissions,
  };

  static PatchCapabilityEntry fromJson(Object? value) {
    final map = _object(value, 'capability entry');
    _exactKeys(map, const {
      'id',
      'version',
      'execution',
      'classification',
      'argumentSchema',
      'returnSchema',
      'permissions',
    }, 'capability entry');
    final execution = _enumValue(
      PatchExecutionKind.values,
      map['execution'],
      'execution kind',
    );
    final classification = _enumValue(
      PatchCapabilityClass.values,
      map['classification'],
      'capability class',
    );
    final permissions = map['permissions'];
    if (map['id'] is! String ||
        map['version'] is! int ||
        map['argumentSchema'] is! String ||
        map['returnSchema'] is! String ||
        permissions is! List<Object?> ||
        permissions.any((item) => item is! String)) {
      throw const PatchFormatException(
        'P1012',
        'Invalid capability entry types',
      );
    }
    return PatchCapabilityEntry(
      id: map['id']! as String,
      version: map['version']! as int,
      execution: execution,
      classification: classification,
      argumentSchema: map['argumentSchema']! as String,
      returnSchema: map['returnSchema']! as String,
      permissions: permissions.cast<String>(),
    );
  }
}

enum PatchValueKind {
  nullValue,
  boolean,
  integer,
  doubleValue,
  string,
  list,
  map,
}

final class PatchValue {
  const PatchValue._(this.kind, this.value);

  const PatchValue.nullValue() : this._(PatchValueKind.nullValue, null);
  const PatchValue.boolean(bool value) : this._(PatchValueKind.boolean, value);
  const PatchValue.integer(int value) : this._(PatchValueKind.integer, value);
  const PatchValue.doubleValue(double value)
    : this._(PatchValueKind.doubleValue, value);
  const PatchValue.string(String value) : this._(PatchValueKind.string, value);
  const PatchValue.list(List<PatchValue> value)
    : this._(PatchValueKind.list, value);
  const PatchValue.map(Map<String, PatchValue> value)
    : this._(PatchValueKind.map, value);

  factory PatchValue.fromDart(Object? value) {
    if (value == null) return const PatchValue.nullValue();
    if (value is bool) return PatchValue.boolean(value);
    if (value is int) return PatchValue.integer(value);
    if (value is double) return PatchValue.doubleValue(value);
    if (value is String) return PatchValue.string(value);
    if (value is List<Object?>) {
      return PatchValue.list(List.unmodifiable(value.map(PatchValue.fromDart)));
    }
    if (value is Map<Object?, Object?>) {
      final result = <String, PatchValue>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const PatchFormatException('P1013', 'Map keys must be strings');
        }
        result[entry.key! as String] = PatchValue.fromDart(entry.value);
      }
      return PatchValue.map(Map.unmodifiable(result));
    }
    throw PatchFormatException(
      'P1014',
      'Unsupported patch constant ${value.runtimeType}',
    );
  }

  final PatchValueKind kind;
  final Object? value;

  Object? toDart() => switch (kind) {
    PatchValueKind.nullValue => null,
    PatchValueKind.boolean ||
    PatchValueKind.integer ||
    PatchValueKind.doubleValue ||
    PatchValueKind.string => value,
    PatchValueKind.list =>
      (value! as List<PatchValue>)
          .map((item) => item.toDart())
          .toList(growable: false),
    PatchValueKind.map => <String, Object?>{
      for (final entry in (value! as Map<String, PatchValue>).entries)
        entry.key: entry.value.toDart(),
    },
  };

  void writeTo(_Writer writer, [int depth = 0]) {
    if (depth > PatchFormatLimits.maxNestingDepth) {
      throw const PatchFormatException(
        'P1015',
        'Constant nesting limit exceeded',
      );
    }
    writer.writeU8(kind.index);
    switch (kind) {
      case PatchValueKind.nullValue:
        return;
      case PatchValueKind.boolean:
        writer.writeU8(value! as bool ? 1 : 0);
      case PatchValueKind.integer:
        writer.writeI64(value! as int);
      case PatchValueKind.doubleValue:
        final number = value! as double;
        if (!number.isFinite) {
          throw const PatchFormatException('P1016', 'Non-finite constant');
        }
        writer.writeF64(number);
      case PatchValueKind.string:
        writer.writeString(value! as String, 'constant string');
      case PatchValueKind.list:
        final list = value! as List<PatchValue>;
        if (list.length > PatchFormatLimits.maxCollectionEntries) {
          throw const PatchFormatException(
            'P1017',
            'Constant list is too large',
          );
        }
        writer.writeU32(list.length);
        for (final item in list) {
          item.writeTo(writer, depth + 1);
        }
      case PatchValueKind.map:
        final map = value! as Map<String, PatchValue>;
        if (map.length > PatchFormatLimits.maxCollectionEntries) {
          throw const PatchFormatException(
            'P1018',
            'Constant map is too large',
          );
        }
        final keys = map.keys.toList()..sort();
        if (!_sameStrings(map.keys.toList(), keys)) {
          throw const PatchFormatException(
            'P1019',
            'Constant map is not canonical',
          );
        }
        writer.writeU32(keys.length);
        for (final key in keys) {
          writer.writeString(key, 'constant map key');
          map[key]!.writeTo(writer, depth + 1);
        }
    }
  }

  static PatchValue readFrom(_Reader reader, [int depth = 0]) {
    if (depth > PatchFormatLimits.maxNestingDepth) {
      throw const PatchFormatException(
        'P1015',
        'Constant nesting limit exceeded',
      );
    }
    final rawKind = reader.readU8('constant kind');
    if (rawKind >= PatchValueKind.values.length) {
      throw const PatchFormatException('P1020', 'Unknown constant kind');
    }
    final kind = PatchValueKind.values[rawKind];
    return switch (kind) {
      PatchValueKind.nullValue => const PatchValue.nullValue(),
      PatchValueKind.boolean => PatchValue.boolean(
        _readBool(reader, 'constant bool'),
      ),
      PatchValueKind.integer => PatchValue.integer(
        reader.readI64('constant int'),
      ),
      PatchValueKind.doubleValue => _readDouble(reader),
      PatchValueKind.string => PatchValue.string(
        reader.readString('constant string', PatchFormatLimits.maxStringBytes),
      ),
      PatchValueKind.list => _readList(reader, depth),
      PatchValueKind.map => _readMap(reader, depth),
    };
  }
}

final class PatchSignatureMetadata {
  PatchSignatureMetadata({required this.algorithm, required this.keyId}) {
    _validateIdentifier(algorithm, 'signature algorithm');
    _validateIdentifier(keyId, 'signature key ID');
  }

  final String algorithm;
  final String keyId;
}

final class PatchExtensionSection {
  PatchExtensionSection({
    required this.type,
    required this.flags,
    required List<int> payload,
  }) : payload = List.unmodifiable(payload) {
    if (type <= 8 || type > 0xffff || flags != 0) {
      throw const PatchFormatException('P1021', 'Invalid extension section');
    }
    _validateByteValues(this.payload, 'extension payload');
    if (this.payload.length > PatchFormatLimits.maxSectionBytes) {
      throw const PatchFormatException(
        'P1022',
        'Extension section is too large',
      );
    }
  }

  final int type;
  final int flags;
  final List<int> payload;
}

final class PatchArtifact {
  PatchArtifact({
    required this.runtimeCompatibilityVersion,
    required this.applicationId,
    required this.releaseId,
    required this.patchId,
    required this.sequence,
    required List<PatchFunctionEntry> functions,
    required List<PatchCapabilityEntry> capabilities,
    required List<PatchValue> constants,
    required List<int> instructions,
    required this.signatureMetadata,
    required List<int> payloadDigest,
    required List<int> signature,
    this.createdAtUtc,
    List<PatchExtensionSection> extensions = const <PatchExtensionSection>[],
  }) : functions = List.unmodifiable(functions),
       capabilities = List.unmodifiable(capabilities),
       constants = List.unmodifiable(constants),
       instructions = List.unmodifiable(instructions),
       payloadDigest = List.unmodifiable(payloadDigest),
       signature = List.unmodifiable(signature),
       extensions = List.unmodifiable(extensions) {
    _validateIdentity(applicationId, 'application ID');
    _validateIdentity(releaseId, 'release ID');
    _validateIdentity(patchId, 'patch ID');
    if (runtimeCompatibilityVersion <= 0 ||
        runtimeCompatibilityVersion > 0xffffffff) {
      throw const PatchFormatException(
        'P1023',
        'Invalid runtime compatibility',
      );
    }
    if (sequence <= 0 || sequence > _maxPositiveU64) {
      throw const PatchFormatException('P1024', 'Invalid patch sequence');
    }
    if (functions.length > PatchFormatLimits.maxFunctions ||
        capabilities.length > PatchFormatLimits.maxCapabilities ||
        constants.length > PatchFormatLimits.maxConstants ||
        instructions.length > PatchFormatLimits.maxInstructions) {
      throw const PatchFormatException('P1025', 'Patch table limit exceeded');
    }
    _validateSortedFunctions(functions);
    _validateSortedCapabilities(capabilities);
    _validateExtensions(extensions);
    _validateByteValues(payloadDigest, 'payload digest');
    _validateByteValues(signature, 'signature');
    if (payloadDigest.isNotEmpty && payloadDigest.length != 32) {
      throw const PatchFormatException(
        'P1026',
        'Payload digest must be SHA-256',
      );
    }
    if (signature.length > PatchFormatLimits.maxSignatureBytes) {
      throw const PatchFormatException('P1027', 'Signature is too large');
    }
  }

  final int runtimeCompatibilityVersion;
  final String applicationId;
  final String releaseId;
  final String patchId;
  final int sequence;
  final DateTime? createdAtUtc;
  final List<PatchFunctionEntry> functions;
  final List<PatchCapabilityEntry> capabilities;
  final List<PatchValue> constants;
  final List<int> instructions;
  final PatchSignatureMetadata signatureMetadata;
  final List<int> payloadDigest;
  final List<int> signature;
  final List<PatchExtensionSection> extensions;

  PatchArtifact copyWith({List<int>? payloadDigest, List<int>? signature}) =>
      PatchArtifact(
        runtimeCompatibilityVersion: runtimeCompatibilityVersion,
        applicationId: applicationId,
        releaseId: releaseId,
        patchId: patchId,
        sequence: sequence,
        createdAtUtc: createdAtUtc,
        functions: functions,
        capabilities: capabilities,
        constants: constants,
        instructions: instructions,
        signatureMetadata: signatureMetadata,
        payloadDigest: payloadDigest ?? this.payloadDigest,
        signature: signature ?? this.signature,
        extensions: extensions,
      );
}

final class PatchFormatV1 {
  PatchFormatV1._();

  static const List<int> magic = <int>[72, 89, 70, 69, 78, 83, 80, 49];

  static const int _identity = 1;
  static const int _functions = 2;
  static const int _capabilities = 3;
  static const int _constants = 4;
  static const int _instructions = 5;
  static const int _signatureMetadata = 6;
  static const int _payloadDigest = 7;
  static const int _signature = 8;

  static PatchArtifact seal(
    PatchArtifact draft,
    List<int> Function(List<int> signingBytes) signer,
  ) {
    final payloadDigest = sha256.convert(payloadBytes(draft)).bytes;
    final withDigest = draft.copyWith(
      payloadDigest: payloadDigest,
      signature: const [],
    );
    final signature = signer(signingBytes(withDigest));
    if (signature.isEmpty ||
        signature.length > PatchFormatLimits.maxSignatureBytes) {
      throw const PatchFormatException(
        'P1028',
        'Signer returned an invalid signature',
      );
    }
    return withDigest.copyWith(signature: signature);
  }

  /// Asynchronous counterpart to [seal] for platform cryptography adapters.
  ///
  /// The wire format and signing domain are identical to the synchronous
  /// method. The separate interface keeps the protocol package independent
  /// of a particular Ed25519 implementation while allowing Dart's supported
  /// cryptography adapters to remain asynchronous.
  static Future<PatchArtifact> sealAsync(
    PatchArtifact draft,
    Future<List<int>> Function(List<int> signingBytes) signer,
  ) async {
    final payloadDigest = sha256.convert(payloadBytes(draft)).bytes;
    final withDigest = draft.copyWith(
      payloadDigest: payloadDigest,
      signature: const [],
    );
    final signature = await signer(signingBytes(withDigest));
    if (signature.isEmpty ||
        signature.length > PatchFormatLimits.maxSignatureBytes) {
      throw const PatchFormatException(
        'P1028',
        'Signer returned an invalid signature',
      );
    }
    return withDigest.copyWith(signature: signature);
  }

  static Uint8List encode(PatchArtifact artifact) {
    final expectedDigest = sha256.convert(payloadBytes(artifact)).bytes;
    if (!_sameBytes(expectedDigest, artifact.payloadDigest)) {
      throw const PatchFormatException('P1029', 'Payload digest mismatch');
    }
    if (artifact.signature.isEmpty) {
      throw const PatchFormatException('P1030', 'Unsigned patch artifact');
    }
    final bytes = _encode(
      artifact,
      includeDigest: true,
      includeSignature: true,
    );
    if (bytes.length > PatchFormatLimits.maxArtifactBytes) {
      throw const PatchFormatException('P1031', 'Patch artifact is too large');
    }
    return bytes;
  }

  static PatchArtifact decode(List<int> bytes) {
    if (bytes.length > PatchFormatLimits.maxArtifactBytes) {
      throw const PatchFormatException('P1031', 'Patch artifact is too large');
    }
    final reader = _Reader(bytes);
    for (final expected in magic) {
      if (reader.readU8('magic') != expected) {
        throw const PatchFormatException('P1001', 'Invalid patch magic');
      }
    }
    if (reader.readU16('format version') != patchFormatV1 ||
        reader.readU16('header flags') != 0) {
      throw const PatchFormatException('P1002', 'Unsupported patch header');
    }
    final runtimeVersion = reader.readU32('runtime version');
    final sectionCount = reader.readU16('section count');
    if (sectionCount == 0 || sectionCount > PatchFormatLimits.maxSections) {
      throw const PatchFormatException('P1032', 'Invalid section count');
    }
    final sections = <int, ({int flags, List<int> payload})>{};
    var previousType = 0;
    for (var index = 0; index < sectionCount; index++) {
      final type = reader.readU16('section type');
      final flags = reader.readU16('section flags');
      final length = reader.readU32('section length');
      if (type <= previousType || sections.containsKey(type)) {
        throw const PatchFormatException(
          'P1033',
          'Sections are not unique and sorted',
        );
      }
      if (length > PatchFormatLimits.maxSectionBytes ||
          length > reader.remaining) {
        throw const PatchFormatException('P1034', 'Invalid section length');
      }
      if (flags & ~1 != 0) {
        throw const PatchFormatException('P1035', 'Unknown section flags');
      }
      previousType = type;
      sections[type] = (
        flags: flags,
        payload: reader.readBytes(length, 'section'),
      );
    }
    if (!reader.isAtEnd) {
      throw const PatchFormatException('P1036', 'Trailing patch bytes');
    }
    for (final entry in sections.entries) {
      if (entry.key <= _signature && entry.value.flags != 1) {
        throw const PatchFormatException(
          'P1037',
          'Known sections must be critical',
        );
      }
      if (entry.key > _signature && entry.value.flags & 1 != 0) {
        throw const PatchFormatException('P1038', 'Unknown critical section');
      }
    }
    const required = <int>{
      _identity,
      _functions,
      _capabilities,
      _constants,
      _instructions,
      _signatureMetadata,
      _payloadDigest,
      _signature,
    };
    if (!sections.keys.toSet().containsAll(required)) {
      throw const PatchFormatException(
        'P1039',
        'Required patch section is missing',
      );
    }

    final identity = _readIdentity(sections[_identity]!.payload);
    final functions = _readFunctions(sections[_functions]!.payload);
    final capabilities = _readCapabilities(sections[_capabilities]!.payload);
    final constants = _readConstants(sections[_constants]!.payload);
    final instructions = _readInstructions(sections[_instructions]!.payload);
    final metadata = _readSignatureMetadata(
      sections[_signatureMetadata]!.payload,
    );
    final digest = sections[_payloadDigest]!.payload;
    if (digest.length != 32) {
      throw const PatchFormatException(
        'P1040',
        'Invalid payload digest length',
      );
    }
    final signature = _readSignature(sections[_signature]!.payload);
    final extensions = <PatchExtensionSection>[
      for (final entry in sections.entries)
        if (entry.key > _signature)
          PatchExtensionSection(
            type: entry.key,
            flags: entry.value.flags,
            payload: entry.value.payload,
          ),
    ];
    final artifact = PatchArtifact(
      runtimeCompatibilityVersion: runtimeVersion,
      applicationId: identity.applicationId,
      releaseId: identity.releaseId,
      patchId: identity.patchId,
      sequence: identity.sequence,
      createdAtUtc: identity.createdAtUtc,
      functions: functions,
      capabilities: capabilities,
      constants: constants,
      instructions: instructions,
      signatureMetadata: metadata,
      payloadDigest: digest,
      signature: signature,
      extensions: extensions,
    );
    final expectedDigest = sha256.convert(payloadBytes(artifact)).bytes;
    if (!_sameBytes(expectedDigest, digest)) {
      throw const PatchFormatException('P1041', 'Payload digest mismatch');
    }
    final canonical = encode(artifact);
    if (!_sameBytes(canonical, bytes)) {
      throw const PatchFormatException(
        'P1042',
        'Patch is not canonically encoded',
      );
    }
    return artifact;
  }

  static List<int> payloadBytes(PatchArtifact artifact) =>
      _encode(artifact, includeDigest: false, includeSignature: false);

  static List<int> signingBytes(PatchArtifact artifact) {
    if (artifact.payloadDigest.length != 32) {
      throw const PatchFormatException(
        'P1043',
        'Signing requires a payload digest',
      );
    }
    return _encode(artifact, includeDigest: true, includeSignature: false);
  }

  static bool verifySignature(
    PatchArtifact artifact,
    bool Function(List<int> signingBytes, List<int> signature) verifier,
  ) => verifier(signingBytes(artifact), artifact.signature);

  /// Asynchronous counterpart to [verifySignature].
  static Future<bool> verifySignatureAsync(
    PatchArtifact artifact,
    Future<bool> Function(List<int> signingBytes, List<int> signature) verifier,
  ) => verifier(signingBytes(artifact), artifact.signature);

  static Uint8List _encode(
    PatchArtifact artifact, {
    required bool includeDigest,
    required bool includeSignature,
  }) {
    final sections = <(int type, int flags, List<int> payload)>[
      (_identity, 1, _encodeIdentity(artifact)),
      (_functions, 1, _encodeFunctions(artifact.functions)),
      (_capabilities, 1, _encodeCapabilities(artifact.capabilities)),
      (_constants, 1, _encodeConstants(artifact.constants)),
      (_instructions, 1, _encodeInstructions(artifact.instructions)),
      (
        _signatureMetadata,
        1,
        _encodeSignatureMetadata(artifact.signatureMetadata),
      ),
      if (includeDigest) (_payloadDigest, 1, artifact.payloadDigest),
      if (includeSignature)
        (_signature, 1, _encodeSignature(artifact.signature)),
      for (final extension in artifact.extensions)
        (extension.type, extension.flags, extension.payload),
    ];
    sections.sort((left, right) => left.$1.compareTo(right.$1));
    if (sections.length > PatchFormatLimits.maxSections) {
      throw const PatchFormatException('P1032', 'Invalid section count');
    }
    final writer = _Writer();
    writer.writeBytes(magic);
    writer.writeU16(patchFormatV1);
    writer.writeU16(0);
    writer.writeU32(artifact.runtimeCompatibilityVersion);
    writer.writeU16(sections.length);
    for (final section in sections) {
      if (section.$3.length > PatchFormatLimits.maxSectionBytes) {
        throw const PatchFormatException('P1034', 'Invalid section length');
      }
      writer
        ..writeU16(section.$1)
        ..writeU16(section.$2)
        ..writeU32(section.$3.length)
        ..writeBytes(section.$3);
    }
    return writer.bytes;
  }

  static List<int> _encodeIdentity(PatchArtifact artifact) {
    final writer = _Writer()
      ..writeString(artifact.applicationId, 'application ID')
      ..writeString(artifact.releaseId, 'release ID')
      ..writeString(artifact.patchId, 'patch ID')
      ..writeU64(artifact.sequence);
    final timestamp = artifact.createdAtUtc?.toUtc().millisecondsSinceEpoch;
    writer.writeU8(timestamp == null ? 0 : 1);
    if (timestamp != null) writer.writeI64(timestamp);
    return writer.bytes;
  }

  static List<int> _encodeFunctions(List<PatchFunctionEntry> functions) {
    _validateSortedFunctions(functions);
    final writer = _Writer()..writeU32(functions.length);
    for (final function in functions) {
      writer
        ..writeString(function.id, 'function ID')
        ..writeU32(function.slot)
        ..writeString(function.signatureDigest, 'signature digest');
    }
    return writer.bytes;
  }

  static List<int> _encodeCapabilities(
    List<PatchCapabilityEntry> capabilities,
  ) {
    _validateSortedCapabilities(capabilities);
    final writer = _Writer()..writeU32(capabilities.length);
    for (final capability in capabilities) {
      writer
        ..writeString(capability.id, 'capability ID')
        ..writeU32(capability.version)
        ..writeU8(capability.execution.index)
        ..writeU8(capability.classification.index)
        ..writeU32(capability.permissions.length);
      for (final permission in capability.permissions) {
        writer.writeString(permission, 'capability permission');
      }
      writer
        ..writeString(capability.argumentSchema, 'argument schema')
        ..writeString(capability.returnSchema, 'return schema');
    }
    return writer.bytes;
  }

  static List<int> _encodeConstants(List<PatchValue> constants) {
    if (constants.length > PatchFormatLimits.maxConstants) {
      throw const PatchFormatException('P1025', 'Patch table limit exceeded');
    }
    final writer = _Writer()..writeU32(constants.length);
    for (final constant in constants) {
      constant.writeTo(writer);
    }
    return writer.bytes;
  }

  static List<int> _encodeInstructions(List<int> instructions) {
    if (instructions.length > PatchFormatLimits.maxInstructions) {
      throw const PatchFormatException('P1025', 'Patch table limit exceeded');
    }
    final writer = _Writer()..writeU32(instructions.length);
    for (final instruction in instructions) {
      if (instruction < 0 || instruction > 0xffffffff) {
        throw const PatchFormatException(
          'P1044',
          'Instruction word is out of range',
        );
      }
      writer.writeU32(instruction);
    }
    return writer.bytes;
  }

  static List<int> _encodeSignatureMetadata(PatchSignatureMetadata metadata) {
    return (_Writer()
          ..writeString(metadata.algorithm, 'signature algorithm')
          ..writeString(metadata.keyId, 'signature key ID'))
        .bytes;
  }

  static List<int> _encodeSignature(List<int> signature) =>
      (_Writer()
            ..writeU16(signature.length)
            ..writeBytes(signature))
          .bytes;

  static ({
    String applicationId,
    String releaseId,
    String patchId,
    int sequence,
    DateTime? createdAtUtc,
  })
  _readIdentity(List<int> bytes) {
    final reader = _Reader(bytes);
    final applicationId = reader.readString(
      'application ID',
      PatchFormatLimits.maxIdentifierBytes,
    );
    final releaseId = reader.readString(
      'release ID',
      PatchFormatLimits.maxIdentifierBytes,
    );
    final patchId = reader.readString(
      'patch ID',
      PatchFormatLimits.maxIdentifierBytes,
    );
    final sequence = reader.readU64('patch sequence');
    final hasTimestamp = _readBool(reader, 'timestamp flag');
    final timestamp = hasTimestamp ? reader.readI64('timestamp') : null;
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1045', 'Trailing identity bytes');
    DateTime? createdAtUtc;
    if (timestamp != null) {
      try {
        createdAtUtc = DateTime.fromMillisecondsSinceEpoch(
          timestamp,
          isUtc: true,
        );
      } on Object {
        throw const PatchFormatException('P1075', 'Invalid patch timestamp');
      }
    }
    return (
      applicationId: applicationId,
      releaseId: releaseId,
      patchId: patchId,
      sequence: sequence,
      createdAtUtc: createdAtUtc,
    );
  }

  static List<PatchFunctionEntry> _readFunctions(List<int> bytes) {
    final reader = _Reader(bytes);
    final count = reader.readCount(
      'function count',
      PatchFormatLimits.maxFunctions,
    );
    final result = <PatchFunctionEntry>[];
    for (var index = 0; index < count; index++) {
      result.add(
        PatchFunctionEntry(
          id: reader.readString(
            'function ID',
            PatchFormatLimits.maxIdentifierBytes,
          ),
          slot: reader.readU32('function slot'),
          signatureDigest: reader.readString(
            'signature digest',
            PatchFormatLimits.maxIdentifierBytes,
          ),
        ),
      );
    }
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1046', 'Trailing function bytes');
    _validateSortedFunctions(result);
    return List.unmodifiable(result);
  }

  static List<PatchCapabilityEntry> _readCapabilities(List<int> bytes) {
    final reader = _Reader(bytes);
    final count = reader.readCount(
      'capability count',
      PatchFormatLimits.maxCapabilities,
    );
    final result = <PatchCapabilityEntry>[];
    for (var index = 0; index < count; index++) {
      final id = reader.readString(
        'capability ID',
        PatchFormatLimits.maxIdentifierBytes,
      );
      final version = reader.readU32('capability version');
      final rawExecution = reader.readU8('execution kind');
      final rawClass = reader.readU8('capability class');
      if (rawExecution >= PatchExecutionKind.values.length ||
          rawClass >= PatchCapabilityClass.values.length) {
        throw const PatchFormatException('P1047', 'Unknown capability enum');
      }
      final permissionCount = reader.readCount(
        'permission count',
        PatchFormatLimits.maxPermissions,
      );
      final permissions = <String>[
        for (var permission = 0; permission < permissionCount; permission++)
          reader.readString(
            'capability permission',
            PatchFormatLimits.maxIdentifierBytes,
          ),
      ];
      result.add(
        PatchCapabilityEntry(
          id: id,
          version: version,
          execution: PatchExecutionKind.values[rawExecution],
          classification: PatchCapabilityClass.values[rawClass],
          permissions: permissions,
          argumentSchema: reader.readString(
            'argument schema',
            PatchFormatLimits.maxSchemaBytes,
          ),
          returnSchema: reader.readString(
            'return schema',
            PatchFormatLimits.maxSchemaBytes,
          ),
        ),
      );
    }
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1048', 'Trailing capability bytes');
    _validateSortedCapabilities(result);
    return List.unmodifiable(result);
  }

  static List<PatchValue> _readConstants(List<int> bytes) {
    final reader = _Reader(bytes);
    final count = reader.readCount(
      'constant count',
      PatchFormatLimits.maxConstants,
    );
    final result = <PatchValue>[
      for (var index = 0; index < count; index++) PatchValue.readFrom(reader),
    ];
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1049', 'Trailing constant bytes');
    return List.unmodifiable(result);
  }

  static List<int> _readInstructions(List<int> bytes) {
    final reader = _Reader(bytes);
    final count = reader.readCount(
      'instruction count',
      PatchFormatLimits.maxInstructions,
    );
    final result = <int>[
      for (var index = 0; index < count; index++)
        reader.readU32('instruction word'),
    ];
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1050', 'Trailing instruction bytes');
    return List.unmodifiable(result);
  }

  static PatchSignatureMetadata _readSignatureMetadata(List<int> bytes) {
    final reader = _Reader(bytes);
    final result = PatchSignatureMetadata(
      algorithm: reader.readString(
        'signature algorithm',
        PatchFormatLimits.maxIdentifierBytes,
      ),
      keyId: reader.readString(
        'signature key ID',
        PatchFormatLimits.maxIdentifierBytes,
      ),
    );
    if (!reader.isAtEnd)
      throw const PatchFormatException(
        'P1051',
        'Trailing signature metadata bytes',
      );
    return result;
  }

  static List<int> _readSignature(List<int> bytes) {
    final reader = _Reader(bytes);
    final length = reader.readU16('signature length');
    if (length == 0 || length > PatchFormatLimits.maxSignatureBytes) {
      throw const PatchFormatException('P1052', 'Invalid signature length');
    }
    final result = reader.readBytes(length, 'signature');
    if (!reader.isAtEnd)
      throw const PatchFormatException('P1053', 'Trailing signature bytes');
    return List.unmodifiable(result);
  }
}

final class ReleaseBaselineSourceUnit {
  ReleaseBaselineSourceUnit({
    required this.packageName,
    required this.libraryUri,
    required this.sourceKind,
    required this.instrumented,
  }) {
    _validateIdentifier(packageName, 'package name');
    _validateIdentifier(libraryUri, 'library URI');
    _validateIdentifier(sourceKind, 'source kind');
  }

  final String packageName;
  final String libraryUri;
  final String sourceKind;
  final bool instrumented;

  Map<String, Object> toJson() => <String, Object>{
    'packageName': packageName,
    'libraryUri': libraryUri,
    'sourceKind': sourceKind,
    'instrumented': instrumented,
  };

  static ReleaseBaselineSourceUnit fromJson(Object? value) {
    final map = _object(value, 'source unit');
    _exactKeys(map, const {
      'packageName',
      'libraryUri',
      'sourceKind',
      'instrumented',
    }, 'source unit');
    if (map['packageName'] is! String ||
        map['libraryUri'] is! String ||
        map['sourceKind'] is! String ||
        map['instrumented'] is! bool) {
      throw const PatchFormatException('P1054', 'Invalid source unit');
    }
    return ReleaseBaselineSourceUnit(
      packageName: map['packageName']! as String,
      libraryUri: map['libraryUri']! as String,
      sourceKind: map['sourceKind']! as String,
      instrumented: map['instrumented']! as bool,
    );
  }
}

final class ReleaseBaselineManifest {
  static const manifestVersion = 1;

  ReleaseBaselineManifest({
    required this.applicationId,
    required this.releaseId,
    required this.runtimeCompatibilityVersion,
    required this.patchFormatVersion,
    required this.buildFingerprint,
    required List<PatchFunctionEntry> functions,
    required List<PatchCapabilityEntry> capabilities,
    required List<String> packages,
    required List<ReleaseBaselineSourceUnit> sourceUnits,
  }) : functions = List.unmodifiable(functions),
       capabilities = List.unmodifiable(capabilities),
       packages = List.unmodifiable(_canonicalStringList(packages, 'packages')),
       sourceUnits = List.unmodifiable(sourceUnits) {
    _validateIdentity(applicationId, 'application ID');
    _validateIdentity(releaseId, 'release ID');
    _validateIdentifier(buildFingerprint, 'build fingerprint');
    if (runtimeCompatibilityVersion <= 0 || patchFormatVersion <= 0) {
      throw const PatchFormatException('P1055', 'Invalid baseline versions');
    }
    if (this.functions.length > PatchFormatLimits.maxFunctions ||
        this.capabilities.length > PatchFormatLimits.maxCapabilities) {
      throw const PatchFormatException('P1025', 'Patch table limit exceeded');
    }
    _validateSortedFunctions(this.functions);
    _validateSortedCapabilities(this.capabilities);
    final uriValues = sourceUnits.map((unit) => unit.libraryUri).toList();
    final sortedUris = uriValues.toList()..sort();
    if (!_sameStrings(uriValues, sortedUris) ||
        uriValues.toSet().length != uriValues.length) {
      throw const PatchFormatException(
        'P1056',
        'Source units are not canonical',
      );
    }
  }

  final String applicationId;
  final String releaseId;
  final int runtimeCompatibilityVersion;
  final int patchFormatVersion;
  final String buildFingerprint;
  final List<PatchFunctionEntry> functions;
  final List<PatchCapabilityEntry> capabilities;
  final List<String> packages;
  final List<ReleaseBaselineSourceUnit> sourceUnits;

  String encode() => _canonicalJson(<String, Object>{
    'manifestVersion': manifestVersion,
    'applicationId': applicationId,
    'releaseId': releaseId,
    'runtimeCompatibilityVersion': runtimeCompatibilityVersion,
    'patchFormatVersion': patchFormatVersion,
    'buildFingerprint': buildFingerprint,
    'functions': functions.map((entry) => entry.toJson()).toList(),
    'capabilities': capabilities.map((entry) => entry.toJson()).toList(),
    'packages': packages,
    'sourceUnits': sourceUnits.map((entry) => entry.toJson()).toList(),
  });

  static ReleaseBaselineManifest decode(String source) {
    final decoded = jsonDecode(source);
    final map = _object(decoded, 'baseline manifest');
    _exactKeys(map, const {
      'manifestVersion',
      'applicationId',
      'releaseId',
      'runtimeCompatibilityVersion',
      'patchFormatVersion',
      'buildFingerprint',
      'functions',
      'capabilities',
      'packages',
      'sourceUnits',
    }, 'baseline manifest');
    if (map['manifestVersion'] != manifestVersion ||
        map['applicationId'] is! String ||
        map['releaseId'] is! String ||
        map['runtimeCompatibilityVersion'] is! int ||
        map['patchFormatVersion'] is! int ||
        map['buildFingerprint'] is! String ||
        map['functions'] is! List<Object?> ||
        map['capabilities'] is! List<Object?> ||
        map['packages'] is! List<Object?> ||
        map['sourceUnits'] is! List<Object?>) {
      throw const PatchFormatException(
        'P1057',
        'Invalid baseline manifest fields',
      );
    }
    final rawFunctions = map['functions']! as List<Object?>;
    final rawCapabilities = map['capabilities']! as List<Object?>;
    if (rawFunctions.length > PatchFormatLimits.maxFunctions ||
        rawCapabilities.length > PatchFormatLimits.maxCapabilities) {
      throw const PatchFormatException('P1025', 'Patch table limit exceeded');
    }
    final functions = rawFunctions
        .map(PatchFunctionEntry.fromJson)
        .toList(growable: false);
    final capabilities = rawCapabilities
        .map(PatchCapabilityEntry.fromJson)
        .toList(growable: false);
    final packages = map['packages']! as List<Object?>;
    final sourceUnits = (map['sourceUnits']! as List<Object?>)
        .map(ReleaseBaselineSourceUnit.fromJson)
        .toList(growable: false);
    if (packages.any((item) => item is! String)) {
      throw const PatchFormatException(
        'P1058',
        'Invalid baseline package list',
      );
    }
    final manifest = ReleaseBaselineManifest(
      applicationId: map['applicationId']! as String,
      releaseId: map['releaseId']! as String,
      runtimeCompatibilityVersion: map['runtimeCompatibilityVersion']! as int,
      patchFormatVersion: map['patchFormatVersion']! as int,
      buildFingerprint: map['buildFingerprint']! as String,
      functions: functions,
      capabilities: capabilities,
      packages: packages.cast<String>(),
      sourceUnits: sourceUnits,
    );
    if (manifest.encode() != source) {
      throw const PatchFormatException(
        'P1059',
        'Baseline manifest is not canonical',
      );
    }
    return manifest;
  }
}

String releaseIdFor({
  required String applicationId,
  required String sourceFingerprint,
  required String dependencyFingerprint,
  required int runtimeCompatibilityVersion,
  String target = 'default',
}) => _stableDigest(<String, Object?>{
  'kind': 'release',
  'applicationId': applicationId,
  'sourceFingerprint': sourceFingerprint,
  'dependencyFingerprint': dependencyFingerprint,
  'runtimeCompatibilityVersion': runtimeCompatibilityVersion,
  'target': target,
});

String patchIdFor({
  required String releaseId,
  required String sourceFingerprint,
  required int sequence,
}) => _stableDigest(<String, Object>{
  'kind': 'patch',
  'releaseId': releaseId,
  'sourceFingerprint': sourceFingerprint,
  'sequence': sequence,
});

String functionIdFor({
  required String libraryUri,
  required String ownerKind,
  required String? ownerName,
  required String memberKind,
  required String memberName,
}) => _stableDigest(<String, Object?>{
  'kind': 'function',
  'libraryUri': libraryUri,
  'ownerKind': ownerKind,
  'ownerName': ownerName,
  'memberKind': memberKind,
  'memberName': memberName,
});

String capabilityIdFor({required String namespace, required String name}) {
  _validateIdentifier(namespace, 'capability namespace');
  _validateIdentifier(name, 'capability name');
  return '$namespace.$name';
}

String _stableDigest(Map<String, Object?> value) =>
    'sha256:${sha256.convert(utf8.encode(_canonicalJson(value))).toString()}';

String _canonicalJson(Object? value) {
  Object? canonical(Object? current) {
    if (current is Map<String, Object?>) {
      final keys = current.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: canonical(current[key]),
      };
    }
    if (current is Map<Object?, Object?>) {
      return canonical(<String, Object?>{
        for (final entry in current.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      });
    }
    if (current is List<Object?>) return current.map(canonical).toList();
    return current;
  }

  return jsonEncode(canonical(value));
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw PatchFormatException('P1003', '$name must be an object');
  }
  return value;
}

void _exactKeys(Map<String, Object?> value, Set<String> keys, String name) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw PatchFormatException(
      'P1004',
      '$name contains unknown or missing fields',
    );
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, String name) {
  if (raw is! String) throw PatchFormatException('P1005', 'Invalid $name');
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw PatchFormatException('P1005', 'Unknown $name $raw');
}

List<String> _canonicalStringList(List<String> values, String name) {
  if (values.any((value) {
    try {
      _validateIdentifier(value, name);
      return false;
    } on PatchFormatException {
      return true;
    }
  })) {
    throw PatchFormatException('P1006', 'Invalid $name');
  }
  final sorted = values.toList()..sort();
  if (!_sameStrings(values, sorted) || values.toSet().length != values.length) {
    throw PatchFormatException('P1007', '$name are not canonical');
  }
  return sorted;
}

void _validateSortedFunctions(List<PatchFunctionEntry> entries) {
  final ids = entries.map((entry) => entry.id).toList();
  final sorted = ids.toList()..sort();
  if (!_sameStrings(ids, sorted) || ids.toSet().length != ids.length) {
    throw const PatchFormatException(
      'P1060',
      'Function table is not canonical',
    );
  }
  final slots = entries.map((entry) => entry.slot).toSet();
  if (slots.length != entries.length) {
    throw const PatchFormatException('P1061', 'Function slots are not unique');
  }
}

void _validateSortedCapabilities(List<PatchCapabilityEntry> entries) {
  final ids = entries.map((entry) => entry.id).toList();
  final sorted = ids.toList()..sort();
  if (!_sameStrings(ids, sorted) || ids.toSet().length != ids.length) {
    throw const PatchFormatException(
      'P1062',
      'Capability table is not canonical',
    );
  }
}

void _validateExtensions(List<PatchExtensionSection> extensions) {
  final types = extensions.map((extension) => extension.type).toList();
  final sorted = types.toList()..sort();
  if (!_sameInts(types, sorted) || types.toSet().length != types.length) {
    throw const PatchFormatException(
      'P1063',
      'Extension table is not canonical',
    );
  }
}

void _validateIdentifier(String value, String name) {
  if (value.isEmpty ||
      utf8.encode(value).length > PatchFormatLimits.maxIdentifierBytes) {
    throw PatchFormatException('P1006', 'Invalid $name');
  }
}

void _validateIdentity(String value, String name) =>
    _validateIdentifier(value, name);

void _validateDigest(String value, String name) {
  if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value)) {
    throw PatchFormatException('P1006', 'Invalid $name');
  }
}

void _validateSchema(String value, String name) {
  if (value.isEmpty ||
      utf8.encode(value).length > PatchFormatLimits.maxSchemaBytes) {
    throw PatchFormatException('P1006', 'Invalid $name');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _validateByteValues(Iterable<int> bytes, String field) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 0xff) {
      throw PatchFormatException('P1076', 'Invalid byte in $field');
    }
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _readBool(_Reader reader, String field) {
  final value = reader.readU8(field);
  if (value > 1) throw PatchFormatException('P1064', 'Invalid $field');
  return value == 1;
}

PatchValue _readDouble(_Reader reader) {
  final value = reader.readF64('constant double');
  if (!value.isFinite) {
    throw const PatchFormatException('P1016', 'Non-finite constant');
  }
  return PatchValue.doubleValue(value);
}

PatchValue _readList(_Reader reader, int depth) {
  final count = reader.readCount(
    'constant list count',
    PatchFormatLimits.maxCollectionEntries,
  );
  return PatchValue.list(
    List.unmodifiable(<PatchValue>[
      for (var index = 0; index < count; index++)
        PatchValue.readFrom(reader, depth + 1),
    ]),
  );
}

PatchValue _readMap(_Reader reader, int depth) {
  final count = reader.readCount(
    'constant map count',
    PatchFormatLimits.maxCollectionEntries,
  );
  final map = <String, PatchValue>{};
  String? previous;
  for (var index = 0; index < count; index++) {
    final key = reader.readString(
      'constant map key',
      PatchFormatLimits.maxStringBytes,
    );
    if (previous != null && key.compareTo(previous) <= 0) {
      throw const PatchFormatException(
        'P1019',
        'Constant map is not canonical',
      );
    }
    previous = key;
    map[key] = PatchValue.readFrom(reader, depth + 1);
  }
  return PatchValue.map(Map.unmodifiable(map));
}

final class _Writer {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  Uint8List get bytes => _builder.toBytes();

  void writeBytes(List<int> value) => _builder.add(value);

  void writeU8(int value) {
    if (value < 0 || value > 0xff)
      throw const PatchFormatException('P1065', 'u8 out of range');
    writeBytes(<int>[value]);
  }

  void writeU16(int value) {
    if (value < 0 || value > 0xffff)
      throw const PatchFormatException('P1066', 'u16 out of range');
    writeBytes(<int>[(value >> 8) & 0xff, value & 0xff]);
  }

  void writeU32(int value) {
    if (value < 0 || value > 0xffffffff)
      throw const PatchFormatException('P1067', 'u32 out of range');
    writeBytes(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void writeU64(int value) {
    if (value < 0 || value > _maxPositiveU64) {
      throw const PatchFormatException('P1068', 'u64 out of range');
    }
    writeBytes(<int>[
      (value >> 56) & 0xff,
      (value >> 48) & 0xff,
      (value >> 40) & 0xff,
      (value >> 32) & 0xff,
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  void writeI64(int value) {
    if (value < -0x8000000000000000 || value > _maxPositiveU64) {
      throw const PatchFormatException('P1068', 'i64 out of range');
    }
    final data = ByteData(8)..setInt64(0, value, Endian.big);
    writeBytes(data.buffer.asUint8List());
  }

  void writeF64(double value) {
    final data = ByteData(8)..setFloat64(0, value, Endian.big);
    writeBytes(data.buffer.asUint8List());
  }

  void writeString(String value, String field) {
    final bytes = utf8.encode(value);
    if (bytes.length > PatchFormatLimits.maxSchemaBytes) {
      throw PatchFormatException('P1069', '$field is too large');
    }
    writeU32(bytes.length);
    writeBytes(bytes);
  }
}

final class _Reader {
  _Reader(List<int> bytes) {
    _validateByteValues(bytes, 'patch input');
    _bytes = Uint8List.fromList(bytes);
  }

  late final Uint8List _bytes;
  int _offset = 0;

  int get remaining => _bytes.length - _offset;
  bool get isAtEnd => _offset == _bytes.length;

  int readU8(String field) {
    _require(1, field);
    return _bytes[_offset++];
  }

  int readU16(String field) {
    _require(2, field);
    final result = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return result;
  }

  int readU32(String field) {
    _require(4, field);
    final result =
        (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return result;
  }

  int readU64(String field) {
    _require(8, field);
    var result = 0;
    for (var index = 0; index < 8; index++) {
      result = (result << 8) | _bytes[_offset++];
    }
    return result;
  }

  int readI64(String field) {
    final value = readU64(field);
    return value & (1 << 63) == 0 ? value : value - (1 << 64);
  }

  double readF64(String field) {
    _require(8, field);
    final result = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getFloat64(0, Endian.big);
    _offset += 8;
    return result;
  }

  String readString(String field, int maxBytes) {
    final length = readU32('$field length');
    if (length > maxBytes || length > remaining) {
      throw PatchFormatException('P1070', 'Invalid $field length');
    }
    final bytes = readBytes(length, field);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw PatchFormatException('P1071', '$field is not strict UTF-8');
    }
  }

  int readCount(String field, int max) {
    final count = readU32(field);
    if (count > max)
      throw PatchFormatException('P1072', '$field exceeds limit');
    return count;
  }

  List<int> readBytes(int length, String field) {
    if (length < 0 || length > remaining) {
      throw PatchFormatException('P1073', 'Invalid $field length');
    }
    final result = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return result;
  }

  void _require(int length, String field) {
    if (length < 0 || length > remaining) {
      throw PatchFormatException('P1074', 'Truncated $field');
    }
  }
}
