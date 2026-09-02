library hyfens_runtime;

import 'dart:async';
import 'dart:convert';

import 'package:hyfens_patch_format/patch_format.dart';

typedef CapabilityHandler = FutureOr<Object?> Function(List<Object?> arguments);
typedef CapabilityValueValidator = bool Function(Object? value);

/// The first local runtime adapter for the CLI-generated Patch Format v1
/// artifact. The extension is deliberately non-critical: runtimes that do
/// not implement this adapter must reject activation rather than reinterpret
/// its payload.
const int patchFormatV1E0BridgeExtensionType = 9;

final class PatchFormatBridgeException implements Exception {
  const PatchFormatBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PatchFormatBridgeException($code): $message';
}

final class PatchFormatV1E0Bridge {
  PatchFormatV1E0Bridge._();

  static const int version = 1;
  static const String encoding = 'e0-patch-container-v9-bytes';

  /// Extracts the exact per-function E0 containers from one already parsed
  /// Patch Format v1 artifact. Signature verification remains the caller's
  /// responsibility; this method only validates the bounded bridge payload
  /// and its relationship to the normative function table.
  static Map<String, List<int>> decode(PatchArtifact artifact) {
    final sections = artifact.extensions
        .where((section) => section.type == patchFormatV1E0BridgeExtensionType)
        .toList(growable: false);
    if (sections.length != 1) {
      throw const PatchFormatBridgeException(
        'B1001',
        'Exactly one E0 bridge extension is required',
      );
    }
    final section = sections.single;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(section.payload, allowMalformed: false));
    } on Object {
      throw const PatchFormatBridgeException(
        'B1002',
        'E0 bridge payload is not strict UTF-8 JSON',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const PatchFormatBridgeException(
        'B1003',
        'E0 bridge payload must be an object',
      );
    }
    final canonical = utf8.encode(jsonEncode(_canonicalJson(decoded)));
    if (!_sameBytes(canonical, section.payload)) {
      throw const PatchFormatBridgeException(
        'B1009',
        'E0 bridge payload is not canonically encoded',
      );
    }
    const keys = <String>{'bridgeVersion', 'encoding', 'functions'};
    if (decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['bridgeVersion'] != version ||
        decoded['encoding'] != encoding) {
      throw const PatchFormatBridgeException(
        'B1004',
        'Unsupported E0 bridge payload',
      );
    }
    final values = decoded['functions'];
    if (values is! Map<String, Object?> ||
        values.length == 0 ||
        values.length > PatchFormatLimits.maxFunctions) {
      throw const PatchFormatBridgeException(
        'B1005',
        'E0 bridge function table is invalid or oversized',
      );
    }
    final expected = artifact.functions.map((function) => function.id).toSet();
    if (values.keys.toSet().length != values.length ||
        values.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(values.keys.toSet()).isNotEmpty) {
      throw const PatchFormatBridgeException(
        'B1006',
        'E0 bridge functions do not match the Patch Format function table',
      );
    }
    final result = <String, List<int>>{};
    for (final entry in values.entries) {
      if (entry.value is! String) {
        throw const PatchFormatBridgeException(
          'B1007',
          'E0 bridge function bytes must be base64 strings',
        );
      }
      try {
        final bytes = base64.decode(entry.value! as String);
        if (base64.encode(bytes) != entry.value || bytes.isEmpty) {
          throw const FormatException('non-canonical or empty bytes');
        }
        result[entry.key] = List<int>.unmodifiable(bytes);
      } on Object {
        throw PatchFormatBridgeException(
          'B1008',
          'Invalid E0 bridge bytes for ${entry.key}',
        );
      }
    }
    return Map.unmodifiable(result);
  }
}

Object? _canonicalJson(Object? value) {
  if (value is List<Object?>) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  return value;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class RuntimeError implements Exception {
  const RuntimeError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RuntimeError($code): $message';
}

final class CapabilityRegistration {
  CapabilityRegistration({
    required this.contract,
    required this.handler,
    this.argumentsValidator,
    this.resultValidator,
  });

  final PatchCapabilityEntry contract;
  final CapabilityHandler handler;
  final CapabilityValueValidator? argumentsValidator;
  final CapabilityValueValidator? resultValidator;
}

final class CapabilityPolicy {
  CapabilityPolicy({
    Iterable<PatchCapabilityClass> allowedClasses = PatchCapabilityClass.values,
    Iterable<String> deniedIds = const <String>[],
    this.maxArgumentBytes = 64 * 1024,
    this.maxResultBytes = 64 * 1024,
  }) : allowedClasses = Set.unmodifiable(allowedClasses),
       deniedIds = Set.unmodifiable(deniedIds) {
    if (maxArgumentBytes <= 0 || maxResultBytes <= 0) {
      throw const RuntimeError(
        'R1001',
        'Capability policy limits must be positive',
      );
    }
  }

  final Set<PatchCapabilityClass> allowedClasses;
  final Set<String> deniedIds;
  final int maxArgumentBytes;
  final int maxResultBytes;

  void authorize(PatchCapabilityEntry contract) {
    if (deniedIds.contains(contract.id) ||
        !allowedClasses.contains(contract.classification)) {
      throw RuntimeError('R1002', 'Capability ${contract.id} is forbidden');
    }
  }
}

/// The immutable set of host adapters shipped with one release.
///
/// A patch can request only an exact contract already present in this
/// authority. The registry never performs reflection or dynamic host lookup.
final class CapabilityAuthority {
  CapabilityAuthority({
    required Iterable<CapabilityRegistration> registrations,
    CapabilityPolicy? policy,
  }) : _policy = policy ?? CapabilityPolicy(),
       _registrations = _freeze(registrations);

  final CapabilityPolicy _policy;
  final Map<String, CapabilityRegistration> _registrations;

  Iterable<PatchCapabilityEntry> get contracts =>
      _registrations.values.map((registration) => registration.contract);

  void validatePatch(Iterable<PatchCapabilityEntry> requirements) {
    final seen = <String>{};
    for (final requirement in requirements) {
      if (!seen.add(requirement.id)) {
        throw RuntimeError('R1003', 'Duplicate capability ${requirement.id}');
      }
      _resolve(requirement);
    }
  }

  void validateArtifact(PatchArtifact artifact) {
    validatePatch(artifact.capabilities);
  }

  FutureOr<Object?> invoke(
    PatchCapabilityEntry requirement,
    List<Object?> arguments,
  ) {
    final registration = _resolve(requirement);
    final argumentCopy = List<Object?>.unmodifiable(arguments);
    final argumentBytes = utf8.encode(jsonEncode(argumentCopy)).length;
    if (argumentBytes > _policy.maxArgumentBytes) {
      throw const RuntimeError(
        'R1004',
        'Capability arguments exceed the policy limit',
      );
    }
    final validator = registration.argumentsValidator;
    if (validator != null && !validator(argumentCopy)) {
      throw RuntimeError('R1005', 'Malformed arguments for ${requirement.id}');
    }
    _policy.authorize(requirement);
    final result = registration.handler(argumentCopy);
    if (requirement.execution == PatchExecutionKind.sync) {
      if (result is Future<Object?>) {
        throw RuntimeError('R1006', 'Synchronous capability returned a Future');
      }
      _validateResult(registration, result, requirement);
      return result;
    }
    return Future<Object?>.sync(() => result).then((value) {
      _validateResult(registration, value, requirement);
      return value;
    });
  }

  CapabilityRegistration _resolve(PatchCapabilityEntry requirement) {
    final registration = _registrations[requirement.id];
    if (registration == null ||
        !_sameContract(registration.contract, requirement)) {
      throw RuntimeError(
        'R1007',
        'Missing or incompatible capability ${requirement.id}@${requirement.version}',
      );
    }
    _policy.authorize(requirement);
    return registration;
  }

  void _validateResult(
    CapabilityRegistration registration,
    Object? value,
    PatchCapabilityEntry requirement,
  ) {
    if (utf8.encode(jsonEncode(value)).length > _policy.maxResultBytes) {
      throw const RuntimeError(
        'R1008',
        'Capability result exceeds the policy limit',
      );
    }
    final validator = registration.resultValidator;
    if (validator != null && !validator(value)) {
      throw RuntimeError('R1009', 'Invalid result from ${requirement.id}');
    }
  }

  static Map<String, CapabilityRegistration> _freeze(
    Iterable<CapabilityRegistration> registrations,
  ) {
    final result = <String, CapabilityRegistration>{};
    for (final registration in registrations) {
      final id = registration.contract.id;
      if (result.containsKey(id)) {
        throw RuntimeError('R1010', 'Duplicate capability registration $id');
      }
      result[id] = registration;
    }
    return Map.unmodifiable(result);
  }
}

bool _sameContract(PatchCapabilityEntry left, PatchCapabilityEntry right) {
  if (left.id != right.id ||
      left.version != right.version ||
      left.execution != right.execution ||
      left.classification != right.classification ||
      left.argumentSchema != right.argumentSchema ||
      left.returnSchema != right.returnSchema ||
      left.permissions.length != right.permissions.length) {
    return false;
  }
  for (var index = 0; index < left.permissions.length; index++) {
    if (left.permissions[index] != right.permissions[index]) return false;
  }
  return true;
}

final class PatchState {
  PatchState({this.currentSequence = 0, this.lastKnownGoodSequence = 0}) {
    if (currentSequence < 0 || lastKnownGoodSequence < 0) {
      throw const RuntimeError(
        'R1011',
        'Patch state sequence cannot be negative',
      );
    }
  }

  int currentSequence;
  int lastKnownGoodSequence;
  bool candidateStaged = false;

  void stage(int sequence) {
    if (sequence <= currentSequence) {
      throw const RuntimeError('R1012', 'Patch sequence is stale or replayed');
    }
    candidateStaged = true;
  }

  void confirmHealth(int sequence) {
    if (!candidateStaged || sequence <= currentSequence) {
      throw const RuntimeError(
        'R1013',
        'No valid candidate is ready for health confirmation',
      );
    }
    currentSequence = sequence;
    lastKnownGoodSequence = sequence;
    candidateStaged = false;
  }

  void discardCandidate() => candidateStaged = false;
}
