library;

import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'src/runtime_diagnostics.dart';
import 'src/value.dart';
import 'src/widget.dart';

export 'src/value.dart';
export 'src/widget.dart';
export 'src/runtime_diagnostics.dart';

const int e0PatchFormatVersion = 9;
const int e0RuntimeVersion = 9;

enum E0CapabilityExecutionKind { sync, async }

enum E0CapabilityCancellation { detachOnly, cooperative, abortable }

enum E0CapabilitySideEffect { none, idempotent, exactlyOnce }

final class E0CapabilityPolicy {
  const E0CapabilityPolicy({
    this.timeout = const Duration(seconds: 5),
    this.maxOutputBytes = 16 * 1024,
    this.sideEffect = E0CapabilitySideEffect.none,
  });

  final Duration timeout;
  final int maxOutputBytes;
  final E0CapabilitySideEffect sideEffect;

  Map<String, Object?> toJson() => <String, Object?>{
    'timeoutMs': timeout.inMilliseconds,
    'maxOutputBytes': maxOutputBytes,
    'sideEffect': sideEffect.name,
  };

  static E0CapabilityPolicy fromJson(Map<String, Object?> value) {
    const keys = <String>{'timeoutMs', 'maxOutputBytes', 'sideEffect'};
    final timeoutMs = value['timeoutMs'];
    final maxOutputBytes = value['maxOutputBytes'];
    final sideEffectName = value['sideEffect'];
    final actualKeys = value.keys.toSet();
    if (actualKeys.difference(keys).isNotEmpty ||
        keys.difference(actualKeys).isNotEmpty ||
        timeoutMs is! int ||
        timeoutMs <= 0 ||
        timeoutMs > 30000 ||
        maxOutputBytes is! int ||
        maxOutputBytes <= 0 ||
        maxOutputBytes > 65536 ||
        sideEffectName is! String) {
      throw const FormatException('Invalid capability policy');
    }
    final sideEffect = E0CapabilitySideEffect.values
        .where((item) => item.name == sideEffectName)
        .firstOrNull;
    if (sideEffect == null) {
      throw const FormatException('Invalid capability side-effect policy');
    }
    return E0CapabilityPolicy(
      timeout: Duration(milliseconds: timeoutMs),
      maxOutputBytes: maxOutputBytes,
      sideEffect: sideEffect,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is E0CapabilityPolicy &&
      timeout == other.timeout &&
      maxOutputBytes == other.maxOutputBytes &&
      sideEffect == other.sideEffect;

  @override
  int get hashCode => Object.hash(timeout, maxOutputBytes, sideEffect);
}

final class E0AsyncCapabilityDescriptor {
  factory E0AsyncCapabilityDescriptor({
    required String id,
    required int version,
    required List<E0ValueSchema> arguments,
    required E0ValueSchema result,
    String? sourceName,
    E0CapabilityExecutionKind executionKind = E0CapabilityExecutionKind.async,
    List<String> resources = const <String>[],
    E0CapabilityPolicy policy = const E0CapabilityPolicy(),
    E0CapabilityCancellation cancellation = E0CapabilityCancellation.detachOnly,
  }) {
    final descriptor = E0AsyncCapabilityDescriptor._(
      id: id,
      version: version,
      arguments: List.unmodifiable(arguments),
      result: result,
      sourceName: sourceName,
      executionKind: executionKind,
      resources: List.unmodifiable(resources),
      policy: policy,
      cancellation: cancellation,
    );
    descriptor._validateContract();
    return descriptor;
  }

  const E0AsyncCapabilityDescriptor._({
    required this.id,
    required this.version,
    required this.arguments,
    required this.result,
    required this.sourceName,
    required this.executionKind,
    required this.resources,
    required this.policy,
    required this.cancellation,
  });

  final String id;
  final int version;
  final List<E0ValueSchema> arguments;
  final E0ValueSchema result;
  final String? sourceName;
  final E0CapabilityExecutionKind executionKind;
  final List<String> resources;
  final E0CapabilityPolicy policy;
  final E0CapabilityCancellation cancellation;

  static const int contractVersion = 1;

  String get contractDigest => sha256
      .convert(
        utf8.encode(jsonEncode(_canonicalContractJson(toContractJson()))),
      )
      .toString();

  Map<String, Object?> toContractJson() => <String, Object?>{
    'contractVersion': contractVersion,
    'id': id,
    'version': version,
    'arguments': arguments.map((schema) => schema.toJson()).toList(),
    'result': result.toJson(),
    'executionKind': executionKind.name,
    'resources': resources,
    'policy': policy.toJson(),
    'cancellation': cancellation.name,
  };

  Map<String, Object?> toRuntimeJson() => <String, Object?>{
    ...toContractJson(),
    'contractDigest': contractDigest,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ...toContractJson(),
    'sourceName': sourceName,
    'contractDigest': contractDigest,
  };

  static E0AsyncCapabilityDescriptor fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'id',
      'contractVersion',
      'version',
      'arguments',
      'result',
      'sourceName',
      'executionKind',
      'resources',
      'policy',
      'cancellation',
      'contractDigest',
    };
    final actualKeys = value.keys.toSet();
    if (actualKeys.difference(keys).isNotEmpty ||
        keys.difference(actualKeys).isNotEmpty ||
        value['contractVersion'] != contractVersion ||
        value['id'] is! String ||
        (value['id']! as String).isEmpty ||
        value['version'] is! int ||
        (value['version']! as int) <= 0 ||
        value['arguments'] is! List<Object?> ||
        value['result'] is! Map<String, Object?>) {
      throw const FormatException('Invalid async capability descriptor');
    }
    final sourceName = value['sourceName'];
    final executionKindName = value['executionKind'];
    final resourcesValue = value['resources'];
    final policyValue = value['policy'];
    final cancellationName = value['cancellation'];
    final executionKind = E0CapabilityExecutionKind.values
        .where((item) => item.name == executionKindName)
        .firstOrNull;
    final cancellation = E0CapabilityCancellation.values
        .where((item) => item.name == cancellationName)
        .firstOrNull;
    if ((sourceName != null && sourceName is! String) ||
        executionKind == null ||
        cancellation == null ||
        resourcesValue is! List<Object?> ||
        resourcesValue.any((item) => item is! String) ||
        policyValue is! Map<String, Object?>) {
      throw const FormatException('Invalid capability contract metadata');
    }
    final arguments = (value['arguments']! as List<Object?>)
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid async capability argument');
          }
          return E0ValueSchema.fromJson(item);
        })
        .toList(growable: false);
    if (arguments.length > 16) {
      throw const FormatException('Async capability argument limit exceeded');
    }
    final result = E0ValueSchema.fromJson(
      value['result']! as Map<String, Object?>,
    );
    if (arguments.any((schema) => !schema.isSupportedHostSignature) ||
        !result.isSupportedHostSignature) {
      throw const FormatException('Async capability uses unsupported schema');
    }
    final descriptor = E0AsyncCapabilityDescriptor(
      id: value['id']! as String,
      version: value['version']! as int,
      arguments: List.unmodifiable(arguments),
      result: result,
      sourceName: sourceName as String?,
      executionKind: executionKind,
      resources: List.unmodifiable(resourcesValue.cast<String>()),
      policy: E0CapabilityPolicy.fromJson(policyValue),
      cancellation: cancellation,
    );
    if (value['contractDigest'] != descriptor.contractDigest) {
      throw const FormatException('Capability contract digest mismatch');
    }
    descriptor._validateContract();
    return descriptor;
  }

  static E0AsyncCapabilityDescriptor fromContractJson(
    Map<String, Object?> value,
  ) {
    const keys = <String>{
      'contractVersion',
      'id',
      'version',
      'arguments',
      'result',
      'executionKind',
      'resources',
      'policy',
      'cancellation',
      'contractDigest',
    };
    final actual = value.keys.toSet();
    if (actual.difference(keys).isNotEmpty ||
        keys.difference(actual).isNotEmpty) {
      throw const FormatException('Invalid runtime capability fields');
    }
    return fromJson(<String, Object?>{...value, 'sourceName': null});
  }

  void _validateContract() {
    if (version <= 0 ||
        arguments.length > 16 ||
        arguments.any((schema) => !schema.isSupportedHostSignature) ||
        !result.isSupportedHostSignature ||
        policy.timeout <= Duration.zero ||
        policy.timeout > const Duration(seconds: 30) ||
        policy.maxOutputBytes <= 0 ||
        policy.maxOutputBytes > 65536 ||
        !_validStableCapabilityId.hasMatch(id) ||
        (sourceName != null && !_validSourceName.hasMatch(sourceName!)) ||
        resources.toSet().length != resources.length ||
        resources.any((item) => !_validResource.hasMatch(item)) ||
        cancellation != E0CapabilityCancellation.detachOnly) {
      throw FormatException('Invalid capability contract $id');
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! E0AsyncCapabilityDescriptor ||
        id != other.id ||
        version != other.version ||
        result != other.result ||
        executionKind != other.executionKind ||
        cancellation != other.cancellation ||
        policy != other.policy ||
        !_equalStrings(resources, other.resources) ||
        arguments.length != other.arguments.length) {
      return false;
    }
    for (var index = 0; index < arguments.length; index++) {
      if (arguments[index] != other.arguments[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    result,
    executionKind,
    cancellation,
    policy,
    Object.hashAll(resources),
    Object.hashAll(arguments),
  );

  static bool _equalStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static Object? _canonicalContractJson(Object? value) {
    if (value is List<Object?>) {
      return value.map(_canonicalContractJson).toList();
    }
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalContractJson(value[key]),
      };
    }
    return value;
  }
}

final class E0AsyncPoint {
  const E0AsyncPoint({
    required this.id,
    required this.awaitPc,
    required this.resumePc,
    required this.result,
    required this.handlerDepth,
  });

  final int id;
  final int awaitPc;
  final int resumePc;
  final E0ValueSchema result;
  final int handlerDepth;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'awaitPc': awaitPc,
    'resumePc': resumePc,
    'result': result.toJson(),
    'handlerDepth': handlerDepth,
  };

  static E0AsyncPoint fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'id',
      'awaitPc',
      'resumePc',
      'result',
      'handlerDepth',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['id'] is! int ||
        value['awaitPc'] is! int ||
        value['resumePc'] is! int ||
        value['handlerDepth'] is! int ||
        value['result'] is! Map<String, Object?>) {
      throw const FormatException('Invalid async point');
    }
    return E0AsyncPoint(
      id: value['id']! as int,
      awaitPc: value['awaitPc']! as int,
      resumePc: value['resumePc']! as int,
      result: E0ValueSchema.fromJson(value['result']! as Map<String, Object?>),
      handlerDepth: value['handlerDepth']! as int,
    );
  }
}

final class E0ExceptionHandler {
  const E0ExceptionHandler({
    required this.id,
    required this.tryStart,
    required this.tryEnd,
    required this.catchStart,
    required this.catchEnd,
    required this.finallyStart,
    required this.finallyEnd,
    required this.afterPc,
  });

  final int id;
  final int tryStart;
  final int tryEnd;
  final int? catchStart;
  final int? catchEnd;
  final int? finallyStart;
  final int? finallyEnd;
  final int afterPc;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tryStart': tryStart,
    'tryEnd': tryEnd,
    'catchStart': catchStart,
    'catchEnd': catchEnd,
    'finallyStart': finallyStart,
    'finallyEnd': finallyEnd,
    'afterPc': afterPc,
  };

  static E0ExceptionHandler fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'id',
      'tryStart',
      'tryEnd',
      'catchStart',
      'catchEnd',
      'finallyStart',
      'finallyEnd',
      'afterPc',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['id'] is! int ||
        value['tryStart'] is! int ||
        value['tryEnd'] is! int ||
        (value['catchStart'] != null && value['catchStart'] is! int) ||
        (value['catchEnd'] != null && value['catchEnd'] is! int) ||
        (value['finallyStart'] != null && value['finallyStart'] is! int) ||
        (value['finallyEnd'] != null && value['finallyEnd'] is! int) ||
        value['afterPc'] is! int) {
      throw const FormatException('Invalid exception handler fields');
    }
    return E0ExceptionHandler(
      id: value['id']! as int,
      tryStart: value['tryStart']! as int,
      tryEnd: value['tryEnd']! as int,
      catchStart: value['catchStart'] as int?,
      catchEnd: value['catchEnd'] as int?,
      finallyStart: value['finallyStart'] as int?,
      finallyEnd: value['finallyEnd'] as int?,
      afterPc: value['afterPc']! as int,
    );
  }
}

final class E0GuestTrace implements StackTrace {
  E0GuestTrace(this.functionId, this.pc)
    : location = E0RuntimeSourceMaps.lookup(functionId, pc);

  final String functionId;
  final int pc;
  final E0RuntimeSourceLocation? location;

  @override
  String toString() {
    final mapped = location;
    if (mapped == null) {
      return 'E0 guest frame: ${e0BoundedDiagnosticMessage(functionId)} '
          'at bytecode pc $pc';
    }
    return 'E0 guest frame: ${mapped.functionName} at '
        '${mapped.logicalUri}:${mapped.line}:${mapped.column} '
        '(bytecode pc $pc)';
  }
}

final class E0GuestThrow implements Exception {
  const E0GuestThrow(this.value, this.trace);

  final Object value;
  final E0GuestTrace trace;

  @override
  String toString() => 'E0GuestThrow($value)';
}

final class E0HostFailure implements Exception {
  const E0HostFailure({
    required this.boundaryId,
    required this.code,
    required this.errorKind,
    required this.message,
  });

  final String boundaryId;
  final String code;
  final String errorKind;
  final String message;

  Map<String, Object?> toGuestValue() => <String, Object?>{
    'kind': 'host-failure',
    'boundary': boundaryId,
    'code': code,
    'errorKind': errorKind,
    'message': message,
  };

  @override
  String toString() => 'E0HostFailure($boundaryId/$code: $message)';
}

final class E0CapabilityException implements Exception {
  const E0CapabilityException._(this.code);
  const E0CapabilityException.deadlineExceeded() : this._('deadlineExceeded');
  const E0CapabilityException.resourceExhausted() : this._('resourceExhausted');
  const E0CapabilityException.denied() : this._('denied');

  final String code;
}

final class E0RuntimeFault implements Exception {
  const E0RuntimeFault(
    this.message, {
    this.pc,
    this.functionId,
    this.code = E0RuntimeDiagnosticCode.execution,
  });

  final String message;
  final int? pc;
  final String? functionId;
  final String code;

  E0RuntimeSourceLocation? get location {
    final id = functionId;
    final offset = pc;
    if (id == null || offset == null) return null;
    return E0RuntimeSourceMaps.lookup(id, offset);
  }

  E0RuntimeFunctionContext? get functionContext {
    final id = functionId;
    return id == null ? null : E0RuntimeFunctionContexts.lookup(id);
  }

  @override
  String toString() {
    final mapped = location;
    final prefix = 'E0RuntimeFault $code';
    if (mapped != null) {
      return '$prefix at ${mapped.logicalUri}:${mapped.line}:'
          '${mapped.column}: ${_boundedMessage(message)}';
    }
    final context = functionContext;
    if (context != null) {
      final pcDetail = pc == null ? '' : ' (pc $pc)';
      return '$prefix in ${context.functionName} at '
          '${context.logicalUri}$pcDetail: ${_boundedMessage(message)}';
    }
    final bounded = _boundedMessage(message);
    return pc == null ? '$prefix: $bounded' : '$prefix at pc $pc: $bounded';
  }
}

final class E0ReceiverMember {
  const E0ReceiverMember({
    required this.id,
    required this.name,
    required this.slot,
    required this.schema,
  });

  final String id;
  final String name;
  final int slot;
  final E0ValueSchema schema;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'slot': slot,
    'schema': schema.toJson(),
  };

  static E0ReceiverMember fromJson(Map<String, Object?> value) {
    const keys = <String>{'id', 'name', 'slot', 'schema'};
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['slot'] is! int ||
        value['schema'] is! Map<String, Object?>) {
      throw const FormatException('Invalid receiver member descriptor');
    }
    return E0ReceiverMember(
      id: value['id']! as String,
      name: value['name']! as String,
      slot: value['slot']! as int,
      schema: E0ValueSchema.fromJson(value['schema']! as Map<String, Object?>),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is E0ReceiverMember &&
      id == other.id &&
      name == other.name &&
      slot == other.slot &&
      schema == other.schema;

  @override
  int get hashCode => Object.hash(id, name, slot, schema);
}

final class E0ReceiverDescriptor {
  const E0ReceiverDescriptor({
    required this.id,
    required this.ownerClass,
    required this.members,
  });

  static const none = E0ReceiverDescriptor(
    id: 'none',
    ownerClass: null,
    members: <E0ReceiverMember>[],
  );

  final String id;
  final String? ownerClass;
  final List<E0ReceiverMember> members;

  bool get isInstance => ownerClass != null;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'ownerClass': ownerClass,
    'members': members.map((member) => member.toJson()).toList(),
  };

  static E0ReceiverDescriptor decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid receiver descriptor');
    }
    return fromJson(value);
  }

  static E0ReceiverDescriptor fromJson(Map<String, Object?> value) {
    const keys = <String>{'id', 'ownerClass', 'members'};
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['id'] is! String ||
        (value['ownerClass'] != null && value['ownerClass'] is! String) ||
        value['members'] is! List<Object?>) {
      throw const FormatException('Invalid receiver descriptor');
    }
    final members = (value['members']! as List<Object?>)
        .map((member) {
          if (member is! Map<String, Object?>) {
            throw const FormatException('Invalid receiver member descriptor');
          }
          return E0ReceiverMember.fromJson(member);
        })
        .toList(growable: false);
    for (var index = 0; index < members.length; index++) {
      if (members[index].slot != index) {
        throw const FormatException('Receiver member slots are not dense');
      }
      if (members.take(index).any((member) => member.id == members[index].id)) {
        throw const FormatException('Duplicate receiver member identity');
      }
    }
    final descriptor = E0ReceiverDescriptor(
      id: value['id']! as String,
      ownerClass: value['ownerClass'] as String?,
      members: List.unmodifiable(members),
    );
    if (!descriptor.isInstance && descriptor != none) {
      throw const FormatException('Invalid top-level receiver descriptor');
    }
    return descriptor;
  }

  @override
  bool operator ==(Object other) {
    if (other is! E0ReceiverDescriptor ||
        id != other.id ||
        ownerClass != other.ownerClass ||
        members.length != other.members.length) {
      return false;
    }
    for (var index = 0; index < members.length; index++) {
      if (members[index] != other.members[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, ownerClass, Object.hashAll(members));
}

abstract interface class E0ReceiverCapability {
  String get descriptorId;

  Object? read(int slot);
}

enum E0Opcode {
  loadArgument(1, 2),
  loadConstant(2, 2),
  addInt(3, 1),
  subtractInt(4, 1),
  multiplyInt(5, 1),
  lessThanInt(6, 1),
  equal(7, 1),
  jumpIfFalse(8, 2),
  returnValue(9, 1),
  greaterThanOrEqual(10, 1),
  jump(11, 2),
  indexValue(12, 1),
  makeList(13, 2),
  makeMap(14, 2),
  loadReceiver(15, 2),
  loadLocal(16, 2),
  storeLocal(17, 2),
  pop(18, 1),
  lessThanOrEqual(19, 1),
  greaterThan(20, 1),
  indexSet(21, 1),
  collectionLength(22, 1),
  collectionContains(23, 1),
  collectionAdd(24, 1),
  makeSet(25, 2),
  iterationValue(26, 1),
  mapKeys(27, 1),
  enterTry(28, 2),
  completeTry(29, 2),
  completeCatch(30, 2),
  completeFinally(31, 2),
  throwValue(32, 1),
  rethrowValue(33, 1),
  callAsyncCapability(34, 3),
  awaitValue(35, 2),
  callSyncCapability(36, 3),
  makeClosure(37, 2),
  invokeClosure(38, 2),
  collectionMap(39, 1),
  collectionWhere(40, 1),
  collectionFold(41, 1),
  collectionSort(42, 1),
  futureValue(43, 1);

  const E0Opcode(this.code, this.width);

  final int code;
  final int width;

  static E0Opcode? fromCode(int code) {
    for (final opcode in values) {
      if (opcode.code == code) return opcode;
    }
    return null;
  }
}

final class E0ClosureProgram {
  E0ClosureProgram({
    required List<E0ValueSchema> parameters,
    required List<E0ValueSchema> captures,
    required this.returnSchema,
    required List<Object?> constants,
    required List<int> code,
    List<E0ValueSchema> locals = const <E0ValueSchema>[],
    List<E0ExceptionHandler> handlers = const <E0ExceptionHandler>[],
    this.receiver = E0ReceiverDescriptor.none,
  }) : parameters = List.unmodifiable(parameters),
       captures = List.unmodifiable(captures),
       constants = List.unmodifiable(
         constants.map(
           (value) => value is E0Value ? value : E0Value.infer(value),
         ),
       ),
       code = List.unmodifiable(code),
       locals = List.unmodifiable(locals),
       handlers = List.unmodifiable(handlers);

  final List<E0ValueSchema> parameters;
  final List<E0ValueSchema> captures;
  final E0ValueSchema returnSchema;
  final List<E0Value> constants;
  final List<int> code;
  final List<E0ValueSchema> locals;
  final List<E0ExceptionHandler> handlers;
  final E0ReceiverDescriptor receiver;

  Map<String, Object?> toJson() => <String, Object?>{
    'parameters': parameters.map((schema) => schema.toJson()).toList(),
    'captures': captures.map((schema) => schema.toJson()).toList(),
    'return': returnSchema.toJson(),
    'constants': constants.map((value) => value.toJson()).toList(),
    'code': code,
    'locals': locals.map((schema) => schema.toJson()).toList(),
    'handlers': handlers.map((handler) => handler.toJson()).toList(),
    'receiver': receiver.toJson(),
  };

  static E0ClosureProgram fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'parameters',
      'captures',
      'return',
      'constants',
      'code',
      'locals',
      'handlers',
      'receiver',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['parameters'] is! List<Object?> ||
        value['captures'] is! List<Object?> ||
        value['return'] is! Map<String, Object?> ||
        value['constants'] is! List<Object?> ||
        value['locals'] is! List<Object?> ||
        value['handlers'] is! List<Object?> ||
        value['receiver'] is! Map<String, Object?>) {
      throw const FormatException('Invalid closure program fields');
    }
    List<E0ValueSchema> parseSchemas(Object? raw, String name) {
      final list = raw! as List<Object?>;
      if (list.length > 16) {
        throw FormatException('Oversized closure $name');
      }
      return list
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw FormatException('Invalid closure $name schema');
            }
            return E0ValueSchema.fromJson(item);
          })
          .toList(growable: false);
    }

    final rawConstants = value['constants']! as List<Object?>;
    if (rawConstants.length > E0PatchContainer.maxConstants) {
      throw const FormatException('Oversized closure constants');
    }
    final constants = rawConstants
        .map(E0Value.fromJson)
        .toList(growable: false);
    final code = value['code']! as List<Object?>;
    final locals = parseSchemas(value['locals'], 'local');
    final rawHandlers = value['handlers']! as List<Object?>;
    if (rawHandlers.length > 32) {
      throw const FormatException('Oversized closure handlers');
    }
    final handlers = rawHandlers
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid closure handler');
          }
          return E0ExceptionHandler.fromJson(item);
        })
        .toList(growable: false);
    if (code.length > E0PatchContainer.maxCodeWords ||
        code.any((item) => item is! int || item < 0)) {
      throw const FormatException('Invalid closure code');
    }
    return E0ClosureProgram(
      parameters: parseSchemas(value['parameters'], 'parameter'),
      captures: parseSchemas(value['captures'], 'capture'),
      returnSchema: E0ValueSchema.fromJson(
        value['return']! as Map<String, Object?>,
      ),
      constants: constants,
      code: code.cast<int>(),
      locals: locals,
      handlers: handlers,
      receiver: E0ReceiverDescriptor.fromJson(
        value['receiver']! as Map<String, Object?>,
      ),
    );
  }

  E0PatchProgram asPatchProgram(int index) => E0PatchProgram(
    functionId: 'closure:$index',
    slot: 0,
    signature: E0FunctionSignature(
      parameters: List.unmodifiable(<E0ValueSchema>[
        ...captures,
        ...parameters,
      ]),
      returnSchema: returnSchema,
    ),
    receiver: receiver,
    constants: constants,
    code: code,
    locals: locals,
    handlers: handlers,
  );
}

final class E0PatchProgram {
  E0PatchProgram({
    required this.functionId,
    required this.slot,
    required List<Object?> constants,
    required List<int> code,
    List<E0ValueSchema> locals = const <E0ValueSchema>[],
    List<E0ExceptionHandler> handlers = const <E0ExceptionHandler>[],
    List<E0AsyncCapabilityDescriptor> capabilities =
        const <E0AsyncCapabilityDescriptor>[],
    List<E0AsyncPoint> asyncPoints = const <E0AsyncPoint>[],
    List<E0WidgetFactoryDescriptor> widgetFactories =
        const <E0WidgetFactoryDescriptor>[],
    List<E0ClosureProgram> closures = const <E0ClosureProgram>[],
    this.signature = E0FunctionSignature.legacyInt2,
    this.receiver = E0ReceiverDescriptor.none,
    this.patchSequence = 1,
    this.payloadHash = '',
  }) : constants = List.unmodifiable(
         constants.map(
           (value) => value is E0Value ? value : E0Value.infer(value),
         ),
       ),
       code = List.unmodifiable(code),
       locals = List.unmodifiable(locals),
       handlers = List.unmodifiable(handlers),
       capabilities = List.unmodifiable(capabilities),
       asyncPoints = List.unmodifiable(asyncPoints),
       widgetFactories = List.unmodifiable(widgetFactories),
       closures = List.unmodifiable(closures);

  final String functionId;
  final int slot;
  final E0FunctionSignature signature;
  final E0ReceiverDescriptor receiver;
  final List<E0Value> constants;
  final List<int> code;
  final List<E0ValueSchema> locals;
  final List<E0ExceptionHandler> handlers;
  final List<E0AsyncCapabilityDescriptor> capabilities;
  final List<E0AsyncPoint> asyncPoints;
  final List<E0WidgetFactoryDescriptor> widgetFactories;
  final List<E0ClosureProgram> closures;
  final int patchSequence;
  final String payloadHash;
}

final class E0PatchContainer {
  static const int maxBytes = 64 * 1024;
  static const int maxConstants = 256;
  static const int maxCodeWords = 2048;
  static const int maxClosures = 128;

  static Uint8List encode({
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required E0PatchProgram program,
  }) {
    final widgetFactoryIds = <String>{};
    if (program.widgetFactories.length > E0WidgetFactoryRegistry.maxFactories ||
        program.widgetFactories.any(
          (factory) => !widgetFactoryIds.add(factory.id),
        )) {
      throw const FormatException('Invalid or oversized widget factories');
    }
    final value = <String, Object?>{
      'formatVersion': e0PatchFormatVersion,
      'runtimeVersion': e0RuntimeVersion,
      'appId': appId,
      'releaseId': releaseId,
      'buildFingerprint': buildFingerprint,
      'patchSequence': program.patchSequence,
      'functionId': program.functionId,
      'slot': program.slot,
      'signature': program.signature.toJson(),
      'receiver': program.receiver.toJson(),
      'locals': program.locals.map((schema) => schema.toJson()).toList(),
      'handlers': program.handlers.map((handler) => handler.toJson()).toList(),
      'capabilities': program.capabilities
          .map((capability) => capability.toRuntimeJson())
          .toList(),
      'asyncPoints': program.asyncPoints
          .map((point) => point.toJson())
          .toList(),
      'widgetFactories': program.widgetFactories
          .map((factory) => factory.toJson())
          .toList(),
      'closures': program.closures.map((closure) => closure.toJson()).toList(),
      'constants': program.constants.map((value) => value.toJson()).toList(),
      'code': program.code,
    };
    value['payloadHash'] = _payloadHash(value);
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(_canonicalJson(value))),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Patch exceeds byte limit');
    }
    return bytes;
  }

  static E0PatchProgram decode(
    List<int> bytes, {
    required String expectedAppId,
    required String expectedReleaseId,
    required String expectedBuildFingerprint,
    required Map<String, int> expectedFunctions,
    Map<String, E0FunctionSignature> expectedSignatures = const {},
    Map<String, E0ReceiverDescriptor> expectedReceivers = const {},
  }) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Patch exceeds byte limit');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Patch is not strict UTF-8 JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Patch root must be an object');
    }
    const keys = <String>{
      'formatVersion',
      'runtimeVersion',
      'appId',
      'releaseId',
      'buildFingerprint',
      'patchSequence',
      'functionId',
      'slot',
      'signature',
      'receiver',
      'locals',
      'handlers',
      'capabilities',
      'asyncPoints',
      'widgetFactories',
      'closures',
      'constants',
      'code',
      'payloadHash',
    };
    if (decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const FormatException('Patch fields do not match format v9');
    }
    final canonicalBytes = utf8.encode(jsonEncode(_canonicalJson(decoded)));
    if (!_equalBytes(bytes, canonicalBytes)) {
      throw const FormatException('Patch JSON is not canonically encoded');
    }
    if (decoded['formatVersion'] != e0PatchFormatVersion ||
        decoded['runtimeVersion'] != e0RuntimeVersion) {
      throw const FormatException('Incompatible patch/runtime version');
    }
    if (decoded['appId'] != expectedAppId ||
        decoded['releaseId'] != expectedReleaseId) {
      throw const FormatException('Patch is not bound to this release');
    }
    if (decoded['buildFingerprint'] != expectedBuildFingerprint) {
      throw const FormatException('Patch build fingerprint mismatch');
    }
    final expectedKeys = expectedFunctions.keys.toSet();
    if (expectedSignatures.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(expectedSignatures.keys.toSet()).isNotEmpty ||
        expectedReceivers.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(expectedReceivers.keys.toSet()).isNotEmpty) {
      throw const FormatException('Incomplete release compatibility tables');
    }
    final patchSequence = decoded['patchSequence'];
    if (patchSequence is! int || patchSequence <= 0) {
      throw const FormatException('Invalid patch sequence');
    }
    final functionId = decoded['functionId'];
    final slot = decoded['slot'];
    if (functionId is! String || slot is! int || slot < 0) {
      throw const FormatException('Invalid function identity or slot');
    }
    if (expectedFunctions[functionId] != slot) {
      throw const FormatException('Unknown function or mismatched slot');
    }
    final signatureValue = decoded['signature'];
    if (signatureValue is! Map<String, Object?>) {
      throw const FormatException('Invalid function signature');
    }
    final signature = E0FunctionSignature.fromJson(signatureValue);
    final expectedSignature = expectedSignatures[functionId]!;
    if (signature != expectedSignature) {
      throw const FormatException('Patch function signature mismatch');
    }
    final receiverValue = decoded['receiver'];
    if (receiverValue is! Map<String, Object?>) {
      throw const FormatException('Invalid receiver descriptor');
    }
    final receiver = E0ReceiverDescriptor.fromJson(receiverValue);
    final expectedReceiver = expectedReceivers[functionId]!;
    if (receiver != expectedReceiver) {
      throw const FormatException('Patch receiver descriptor mismatch');
    }
    final constantsValue = decoded['constants'];
    if (constantsValue is! List<Object?> ||
        constantsValue.length > maxConstants) {
      throw const FormatException('Invalid or oversized constants');
    }
    final constants = constantsValue.map(E0Value.fromJson).toList();
    final localsValue = decoded['locals'];
    if (localsValue is! List<Object?> || localsValue.length > 256) {
      throw const FormatException('Invalid or oversized local schemas');
    }
    final locals = localsValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid local schema');
          }
          return E0ValueSchema.fromJson(value);
        })
        .toList(growable: false);
    final handlersValue = decoded['handlers'];
    if (handlersValue is! List<Object?> || handlersValue.length > 32) {
      throw const FormatException('Invalid or oversized exception handlers');
    }
    final handlers = handlersValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid exception handler');
          }
          return E0ExceptionHandler.fromJson(value);
        })
        .toList(growable: false);
    final capabilitiesValue = decoded['capabilities'];
    if (capabilitiesValue is! List<Object?> || capabilitiesValue.length > 32) {
      throw const FormatException('Invalid or oversized async capabilities');
    }
    final capabilities = capabilitiesValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid async capability');
          }
          return E0AsyncCapabilityDescriptor.fromContractJson(value);
        })
        .toList(growable: false);
    for (var index = 0; index < capabilities.length; index++) {
      if (capabilities
          .take(index)
          .any((item) => item.id == capabilities[index].id)) {
        throw const FormatException('Duplicate async capability identity');
      }
    }
    final asyncPointsValue = decoded['asyncPoints'];
    if (asyncPointsValue is! List<Object?> || asyncPointsValue.length > 64) {
      throw const FormatException('Invalid or oversized async points');
    }
    final asyncPoints = asyncPointsValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid async point');
          }
          return E0AsyncPoint.fromJson(value);
        })
        .toList(growable: false);
    final widgetFactoriesValue = decoded['widgetFactories'];
    if (widgetFactoriesValue is! List<Object?> ||
        widgetFactoriesValue.length > E0WidgetFactoryRegistry.maxFactories) {
      throw const FormatException('Invalid or oversized widget factories');
    }
    final widgetFactories = widgetFactoriesValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid widget factory contract');
          }
          return E0WidgetFactoryDescriptor.fromJson(value);
        })
        .toList(growable: false);
    final widgetFactoryIds = <String>{};
    if (widgetFactories.any((factory) => !widgetFactoryIds.add(factory.id))) {
      throw const FormatException('Duplicate widget factory identity');
    }
    final closuresValue = decoded['closures'];
    if (closuresValue is! List<Object?> || closuresValue.length > maxClosures) {
      throw const FormatException('Invalid or oversized closures');
    }
    final closures = closuresValue
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid closure program');
          }
          return E0ClosureProgram.fromJson(value);
        })
        .toList(growable: false);
    final code = _wordList(decoded['code'], 'code', maxCodeWords);
    final payloadHash = decoded['payloadHash'];
    if (payloadHash is! String || payloadHash != _payloadHash(decoded)) {
      throw const FormatException('Patch payload hash mismatch');
    }
    final program = E0PatchProgram(
      functionId: functionId,
      slot: slot,
      signature: signature,
      receiver: receiver,
      constants: constants,
      code: code,
      locals: locals,
      handlers: handlers,
      capabilities: capabilities,
      asyncPoints: asyncPoints,
      widgetFactories: widgetFactories,
      closures: closures,
      patchSequence: patchSequence,
      payloadHash: payloadHash,
    );
    E0Interpreter.validate(program);
    return program;
  }

  static bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static String _payloadHash(Map<String, Object?> value) {
    final payload = <String, Object?>{
      'formatVersion': value['formatVersion'],
      'runtimeVersion': value['runtimeVersion'],
      'appId': value['appId'],
      'releaseId': value['releaseId'],
      'buildFingerprint': value['buildFingerprint'],
      'patchSequence': value['patchSequence'],
      'functionId': value['functionId'],
      'slot': value['slot'],
      'signature': value['signature'],
      'receiver': value['receiver'],
      'locals': value['locals'],
      'handlers': value['handlers'],
      'capabilities': value['capabilities'],
      'asyncPoints': value['asyncPoints'],
      'widgetFactories': value['widgetFactories'],
      'closures': value['closures'],
      'constants': value['constants'],
      'code': value['code'],
    };
    return sha256
        .convert(utf8.encode(jsonEncode(_canonicalJson(payload))))
        .toString();
  }

  static Object? _canonicalJson(Object? value) {
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

  static List<int> _wordList(Object? value, String name, int limit) {
    if (value is! List<Object?> || value.length > limit) {
      throw FormatException('Invalid or oversized $name');
    }
    final result = <int>[];
    for (final item in value) {
      if (item is! int || item < 0 || item > 0xffffffff) {
        throw FormatException('$name must contain 32-bit unsigned integers');
      }
      result.add(item);
    }
    return result;
  }
}

/// Test-only, opt-in interpreter profiling sink.
///
/// The runtime never creates or persists this sink. Production dispatch paths
/// pass `null`, so there is no global profiler, network reporting, or change to
/// patch authority. Stage timings intentionally distinguish top-level loop
/// timing from nested observations; callers must not add overlapping stages as
/// if they were independent costs.
final class E0InterpreterProfileSink {
  E0InterpreterProfileSink({this.enabled = true});

  final bool enabled;
  final Map<String, int> _counts = <String, int>{};
  final Map<String, int> _elapsedMicros = <String, int>{};

  void count(String stage, [int amount = 1]) {
    if (!enabled || amount == 0) return;
    _counts[stage] = (_counts[stage] ?? 0) + amount;
  }

  Stopwatch? start(String stage) {
    if (!enabled) return null;
    count('$stage.count');
    return Stopwatch()..start();
  }

  void finish(String stage, Stopwatch? stopwatch) {
    if (!enabled || stopwatch == null) return;
    stopwatch.stop();
    _elapsedMicros[stage] =
        (_elapsedMicros[stage] ?? 0) + stopwatch.elapsedMicroseconds;
  }

  T measure<T>(String stage, T Function() operation) {
    if (!enabled) return operation();
    final stopwatch = start(stage);
    try {
      return operation();
    } finally {
      finish(stage, stopwatch);
    }
  }

  Future<T> measureAsync<T>(String stage, Future<T> Function() operation) {
    if (!enabled) return operation();
    final stopwatch = start(stage);
    return operation().whenComplete(() => finish(stage, stopwatch));
  }

  void recordOpcode(E0Opcode opcode) {
    if (!enabled) return;
    count('opcode.count');
    count('opcode.${opcode.name}');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'counts': Map<String, int>.unmodifiable(_counts),
    'elapsedMicros': Map<String, int>.unmodifiable(_elapsedMicros),
  };

  Map<String, int> get counts => Map.unmodifiable(_counts);
  Map<String, int> get elapsedMicros => Map.unmodifiable(_elapsedMicros);
}

final class E0Interpreter {
  static const int defaultInstructionBudget = 10000;
  static const int maxStackDepth = 64;

  static void validate(E0PatchProgram program) => _validate(program, 0);

  static void _validate(E0PatchProgram program, int validationDepth) {
    if (validationDepth > E0RuntimeLimits.defaults.maxCallDepth) {
      throw const FormatException('Closure validation depth limit exceeded');
    }
    if (program.constants.length > E0PatchContainer.maxConstants ||
        program.code.length > E0PatchContainer.maxCodeWords ||
        program.locals.length > 256 ||
        program.handlers.length > 32 ||
        program.capabilities.length > 32 ||
        program.asyncPoints.length > 64 ||
        program.closures.length > E0PatchContainer.maxClosures) {
      throw const FormatException('Patch program exceeds verifier limits');
    }
    if (program.code.any((word) => word < 0 || word > 0xffffffff)) {
      throw const FormatException('Instruction word is out of range');
    }
    for (var index = 0; index < program.closures.length; index++) {
      final closure = program.closures[index];
      if (closure.parameters.length > 16 || closure.captures.length > 32) {
        throw const FormatException(
          'Closure parameter or capture limit exceeded',
        );
      }
      _validate(closure.asPatchProgram(index), validationDepth + 1);
    }
    if (program.code.isEmpty) throw const FormatException('Empty bytecode');
    final boundaries = <int>{};
    var pc = 0;
    while (pc < program.code.length) {
      boundaries.add(pc);
      final opcode = E0Opcode.fromCode(program.code[pc]);
      if (opcode == null) throw FormatException('Unknown opcode at $pc');
      if (pc + opcode.width > program.code.length) {
        throw FormatException('Truncated operand at $pc');
      }
      if (opcode == E0Opcode.loadArgument) {
        final index = program.code[pc + 1];
        if (index >= program.signature.parameters.length) {
          throw FormatException('Invalid argument index at $pc');
        }
      } else if (opcode == E0Opcode.loadConstant) {
        final index = program.code[pc + 1];
        if (index >= program.constants.length) {
          throw FormatException('Invalid constant index at $pc');
        }
      } else if (opcode == E0Opcode.loadReceiver) {
        final index = program.code[pc + 1];
        if (!program.receiver.isInstance ||
            index >= program.receiver.members.length) {
          throw FormatException('Invalid receiver slot at $pc');
        }
      } else if (opcode == E0Opcode.loadLocal ||
          opcode == E0Opcode.storeLocal) {
        final index = program.code[pc + 1];
        if (index >= program.locals.length) {
          throw FormatException('Invalid local slot at $pc');
        }
      } else if (opcode == E0Opcode.callAsyncCapability ||
          opcode == E0Opcode.callSyncCapability) {
        final index = program.code[pc + 1];
        final count = program.code[pc + 2];
        if (index >= program.capabilities.length ||
            count != program.capabilities[index].arguments.length ||
            (opcode == E0Opcode.callAsyncCapability &&
                program.capabilities[index].executionKind !=
                    E0CapabilityExecutionKind.async) ||
            (opcode == E0Opcode.callSyncCapability &&
                program.capabilities[index].executionKind !=
                    E0CapabilityExecutionKind.sync)) {
          throw FormatException('Invalid async capability call at $pc');
        }
      } else if (opcode == E0Opcode.awaitValue) {
        final index = program.code[pc + 1];
        if (index >= program.asyncPoints.length ||
            program.asyncPoints[index].id != index ||
            program.asyncPoints[index].awaitPc != pc ||
            program.asyncPoints[index].resumePc != pc + opcode.width) {
          throw FormatException('Invalid async point operand at $pc');
        }
      } else if (opcode == E0Opcode.makeClosure) {
        final index = program.code[pc + 1];
        if (index >= program.closures.length) {
          throw FormatException('Invalid closure index at $pc');
        }
      } else if (opcode == E0Opcode.invokeClosure) {
        final index = program.code[pc + 1];
        if (index > 16) {
          throw FormatException('Closure argument limit exceeded at $pc');
        }
      }
      pc += opcode.width;
    }
    boundaries.add(program.code.length);
    pc = 0;
    while (pc < program.code.length) {
      final opcode = E0Opcode.fromCode(program.code[pc])!;
      if (opcode == E0Opcode.jumpIfFalse || opcode == E0Opcode.jump) {
        final target = program.code[pc + 1];
        if (!boundaries.contains(target) || target == program.code.length) {
          throw FormatException('Jump target is not an instruction at $pc');
        }
      }
      pc += opcode.width;
    }
    _validateHandlers(program, boundaries);
    _validateAsyncMetadata(program, boundaries);
    _validateStackAndControlFlow(program);
  }

  static void _validateAsyncMetadata(
    E0PatchProgram program,
    Set<int> boundaries,
  ) {
    if (!program.signature.isAsync) {
      if (program.asyncPoints.isNotEmpty ||
          program.capabilities.any(
            (item) => item.executionKind != E0CapabilityExecutionKind.sync,
          )) {
        throw const FormatException('Synchronous program has async metadata');
      }
      final used = <int>{};
      var syncPc = 0;
      while (syncPc < program.code.length) {
        final opcode = E0Opcode.fromCode(program.code[syncPc])!;
        if (opcode == E0Opcode.callSyncCapability) {
          used.add(program.code[syncPc + 1]);
        }
        syncPc += opcode.width;
      }
      if (used.length != program.capabilities.length) {
        throw const FormatException('Unused sync capability metadata');
      }
      var syncScanPc = 0;
      var usesFutureValue = false;
      while (syncScanPc < program.code.length) {
        final syncOpcode = E0Opcode.fromCode(program.code[syncScanPc]);
        if (syncOpcode == null) break;
        if (syncOpcode == E0Opcode.futureValue) usesFutureValue = true;
        syncScanPc += syncOpcode.width;
      }
      if (usesFutureValue) {
        throw const FormatException(
          'Future value opcode is only valid in an async program',
        );
      }
      return;
    }
    if (program.asyncPoints.isEmpty) {
      throw const FormatException(
        'Async patch must contain at least one await',
      );
    }
    final usedPoints = <int>{};
    final usedCapabilities = <int>{};
    var scanPc = 0;
    while (scanPc < program.code.length) {
      final opcode = E0Opcode.fromCode(program.code[scanPc])!;
      if (opcode == E0Opcode.callSyncCapability) {
        throw FormatException(
          'Sync capability is not supported in async program at $scanPc',
        );
      }
      if (opcode == E0Opcode.awaitValue &&
          !usedPoints.add(program.code[scanPc + 1])) {
        throw FormatException('Async point is reused at $scanPc');
      }
      if (opcode == E0Opcode.callAsyncCapability ||
          opcode == E0Opcode.callSyncCapability) {
        usedCapabilities.add(program.code[scanPc + 1]);
      }
      if (opcode == E0Opcode.indexValue ||
          opcode == E0Opcode.makeList ||
          opcode == E0Opcode.makeMap ||
          opcode == E0Opcode.indexSet ||
          opcode == E0Opcode.collectionLength ||
          opcode == E0Opcode.collectionContains ||
          opcode == E0Opcode.collectionAdd ||
          opcode == E0Opcode.makeSet ||
          opcode == E0Opcode.iterationValue ||
          opcode == E0Opcode.mapKeys ||
          opcode == E0Opcode.makeClosure ||
          opcode == E0Opcode.invokeClosure ||
          opcode == E0Opcode.collectionMap ||
          opcode == E0Opcode.collectionWhere ||
          opcode == E0Opcode.collectionFold ||
          opcode == E0Opcode.collectionSort) {
        throw FormatException(
          'Opcode ${opcode.name} is not supported in async v6',
        );
      }
      scanPc += opcode.width;
    }
    if (usedPoints.length != program.asyncPoints.length ||
        usedCapabilities.length != program.capabilities.length) {
      throw const FormatException('Unused async metadata');
    }
    for (var index = 0; index < program.asyncPoints.length; index++) {
      final point = program.asyncPoints[index];
      if (point.id != index ||
          !boundaries.contains(point.awaitPc) ||
          !boundaries.contains(point.resumePc) ||
          point.resumePc != point.awaitPc + E0Opcode.awaitValue.width ||
          point.handlerDepth < 0 ||
          point.handlerDepth > program.handlers.length) {
        throw FormatException('Malformed async point ${point.id}');
      }
      final actualDepth = program.handlers.where((handler) {
        final start = handler.tryStart - E0Opcode.enterTry.width;
        return point.awaitPc >= start && point.awaitPc < handler.afterPc;
      }).length;
      if (actualDepth != point.handlerDepth) {
        throw FormatException(
          'Async handler depth mismatch at ${point.awaitPc}',
        );
      }
    }
  }

  static void _validateHandlers(E0PatchProgram program, Set<int> boundaries) {
    final handlers = program.handlers;
    if (handlers.length > 32) {
      throw const FormatException('Exception handler limit exceeded');
    }
    for (var index = 0; index < handlers.length; index++) {
      final handler = handlers[index];
      if (handler.id != index) {
        throw const FormatException('Exception handler IDs must be dense');
      }
      if (!boundaries.contains(handler.tryStart) ||
          !boundaries.contains(handler.tryEnd) ||
          !boundaries.contains(handler.afterPc) ||
          handler.tryStart >= handler.tryEnd ||
          handler.afterPc > program.code.length ||
          handler.tryStart < E0Opcode.enterTry.width) {
        throw FormatException('Invalid handler ${handler.id} range');
      }
      final hasCatch = handler.catchStart != null || handler.catchEnd != null;
      final hasFinally =
          handler.finallyStart != null || handler.finallyEnd != null;
      if (!hasCatch && !hasFinally) {
        throw FormatException('Handler ${handler.id} has no catch or finally');
      }
      if (hasCatch !=
              (handler.catchStart != null && handler.catchEnd != null) ||
          hasFinally !=
              (handler.finallyStart != null && handler.finallyEnd != null)) {
        throw FormatException('Incomplete handler ${handler.id} range');
      }
      for (final point in <int?>[
        handler.catchStart,
        handler.catchEnd,
        handler.finallyStart,
        handler.finallyEnd,
      ]) {
        if (point != null && !boundaries.contains(point)) {
          throw FormatException(
            'Handler ${handler.id} point is not a boundary',
          );
        }
      }
      if (hasCatch &&
          (handler.catchStart! > handler.catchEnd! ||
              handler.catchStart! < handler.tryEnd + 2 ||
              handler.catchEnd! > handler.afterPc)) {
        throw FormatException('Invalid catch range for handler ${handler.id}');
      }
      if (hasFinally &&
          (handler.finallyStart! > handler.finallyEnd! ||
              handler.finallyStart! <
                  (handler.catchEnd ?? handler.tryEnd + 2) ||
              handler.finallyEnd! > handler.afterPc)) {
        throw FormatException(
          'Invalid finally range for handler ${handler.id}',
        );
      }
      final enterPc = handler.tryStart - E0Opcode.enterTry.width;
      _requireControlOpcode(program, enterPc, E0Opcode.enterTry, handler.id);
      _requireControlOpcode(
        program,
        handler.tryEnd,
        E0Opcode.completeTry,
        handler.id,
      );
      if (hasCatch) {
        _requireControlOpcode(
          program,
          handler.catchEnd!,
          E0Opcode.completeCatch,
          handler.id,
        );
      }
      if (hasFinally) {
        _requireControlOpcode(
          program,
          handler.finallyEnd!,
          E0Opcode.completeFinally,
          handler.id,
        );
      }
      final expectedAfter = hasFinally
          ? handler.finallyEnd! + E0Opcode.completeFinally.width
          : hasCatch
          ? handler.catchEnd! + E0Opcode.completeCatch.width
          : handler.tryEnd + E0Opcode.completeTry.width;
      if (handler.afterPc != expectedAfter) {
        throw FormatException('Invalid after pc for handler ${handler.id}');
      }
    }
    for (var leftIndex = 0; leftIndex < handlers.length; leftIndex++) {
      final left = handlers[leftIndex];
      final leftStart = left.tryStart - E0Opcode.enterTry.width;
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < handlers.length;
        rightIndex++
      ) {
        final right = handlers[rightIndex];
        final rightStart = right.tryStart - E0Opcode.enterTry.width;
        final disjoint =
            left.afterPc <= rightStart || right.afterPc <= leftStart;
        final nested =
            (leftStart < rightStart && right.afterPc <= left.afterPc) ||
            (rightStart < leftStart && left.afterPc <= right.afterPc);
        if (!disjoint && !nested) {
          throw const FormatException('Exception handlers partially overlap');
        }
      }
    }
    var pc = 0;
    while (pc < program.code.length) {
      final opcode = E0Opcode.fromCode(program.code[pc])!;
      if (opcode == E0Opcode.enterTry ||
          opcode == E0Opcode.completeTry ||
          opcode == E0Opcode.completeCatch ||
          opcode == E0Opcode.completeFinally) {
        final id = program.code[pc + 1];
        if (id >= handlers.length) {
          throw FormatException('Invalid handler operand at $pc');
        }
        final handler = handlers[id];
        final validPc = switch (opcode) {
          E0Opcode.enterTry => handler.tryStart - opcode.width,
          E0Opcode.completeTry => handler.tryEnd,
          E0Opcode.completeCatch => handler.catchEnd,
          E0Opcode.completeFinally => handler.finallyEnd,
          _ => null,
        };
        if (pc != validPc) {
          throw FormatException('Illegal handler transition at $pc');
        }
      }
      if (opcode == E0Opcode.jump || opcode == E0Opcode.jumpIfFalse) {
        final target = program.code[pc + 1];
        if (_handlerSection(program.handlers, pc) !=
            _handlerSection(program.handlers, target)) {
          throw FormatException('Jump crosses handler boundary at $pc');
        }
      }
      pc += opcode.width;
    }
  }

  static void _requireControlOpcode(
    E0PatchProgram program,
    int pc,
    E0Opcode opcode,
    int id,
  ) {
    if (pc < 0 ||
        pc + opcode.width > program.code.length ||
        E0Opcode.fromCode(program.code[pc]) != opcode ||
        program.code[pc + 1] != id) {
      throw FormatException('Missing ${opcode.name} for handler $id');
    }
  }

  static String _handlerSection(List<E0ExceptionHandler> handlers, int pc) {
    E0ExceptionHandler? owner;
    String section = 'root';
    for (final handler in handlers) {
      String? candidate;
      if (pc >= handler.tryStart && pc <= handler.tryEnd) {
        candidate = 'try';
      } else if (handler.catchStart != null &&
          pc >= handler.catchStart! &&
          pc <= handler.catchEnd!) {
        candidate = 'catch';
      } else if (handler.finallyStart != null &&
          pc >= handler.finallyStart! &&
          pc <= handler.finallyEnd!) {
        candidate = 'finally';
      }
      if (candidate != null &&
          (owner == null || handler.afterPc <= owner.afterPc)) {
        owner = handler;
        section = '${handler.id}:$candidate';
      }
    }
    return section;
  }

  static void _validateStackAndControlFlow(E0PatchProgram program) {
    final states = <int, _VerifierState>{
      0: const _VerifierState(<E0ValueSchema>[], <int>{}),
    };
    final pending = <int>[0];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final incoming = states[current]!;
      final stack = List<E0ValueSchema>.of(incoming.stack);
      final initialized = Set<int>.of(incoming.initialized);
      final opcode = E0Opcode.fromCode(program.code[current])!;
      switch (opcode) {
        case E0Opcode.loadArgument:
          stack.add(program.signature.parameters[program.code[current + 1]]);
        case E0Opcode.loadConstant:
          stack.add(program.constants[program.code[current + 1]].schema);
        case E0Opcode.loadReceiver:
          stack.add(program.receiver.members[program.code[current + 1]].schema);
        case E0Opcode.loadLocal:
          final slot = program.code[current + 1];
          if (!initialized.contains(slot)) {
            throw FormatException(
              'Local $slot may be uninitialized at $current',
            );
          }
          stack.add(program.locals[slot]);
        case E0Opcode.storeLocal:
          final slot = program.code[current + 1];
          final actual = _popStatic(stack, current);
          if (!program.locals[slot].accepts(actual)) {
            throw FormatException('Invalid local store at $current');
          }
          initialized.add(slot);
        case E0Opcode.pop:
          _popStatic(stack, current);
        case E0Opcode.addInt:
          final right = _popStatic(stack, current);
          final left = _popStatic(stack, current);
          if (left != right || !_supportsAddition(left)) {
            throw FormatException('Invalid addition operands at $current');
          }
          stack.add(left);
        case E0Opcode.subtractInt:
        case E0Opcode.multiplyInt:
          final right = _popStatic(stack, current);
          final left = _popStatic(stack, current);
          if (left != right || !_isNumeric(left)) {
            throw FormatException('Invalid numeric operands at $current');
          }
          stack.add(left);
        case E0Opcode.lessThanInt:
        case E0Opcode.greaterThanOrEqual:
        case E0Opcode.lessThanOrEqual:
        case E0Opcode.greaterThan:
          final right = _popStatic(stack, current);
          final left = _popStatic(stack, current);
          if (left != right || !_isNumeric(left)) {
            throw FormatException('Invalid comparison operands at $current');
          }
          stack.add(E0ValueSchema.boolean);
        case E0Opcode.equal:
          _popStatic(stack, current);
          _popStatic(stack, current);
          stack.add(E0ValueSchema.boolean);
        case E0Opcode.indexValue:
          final index = _popStatic(stack, current);
          final target = _popStatic(stack, current);
          if (target.kind == E0ValueKind.list &&
              index.kind == E0ValueKind.integer) {
            stack.add(target.elementSchema!);
          } else if (target.kind == E0ValueKind.map &&
              index.kind == E0ValueKind.string) {
            stack.add(target.mapValueSchema!);
          } else {
            throw FormatException('Invalid index operands at $current');
          }
        case E0Opcode.indexSet:
          final value = _popStatic(stack, current);
          final index = _popStatic(stack, current);
          final target = _popStatic(stack, current);
          if (target.kind == E0ValueKind.list &&
              index == E0ValueSchema.integer &&
              target.elementSchema!.accepts(value)) {
            break;
          }
          if (target.kind == E0ValueKind.map &&
              index == E0ValueSchema.string &&
              target.mapValueSchema!.accepts(value)) {
            break;
          }
          throw FormatException('Invalid indexed assignment at $current');
        case E0Opcode.collectionLength:
          final target = _popStatic(stack, current);
          if (target.kind != E0ValueKind.list &&
              target.kind != E0ValueKind.map &&
              target.kind != E0ValueKind.set &&
              target.kind != E0ValueKind.string) {
            throw FormatException('Invalid length operand at $current');
          }
          stack.add(E0ValueSchema.integer);
        case E0Opcode.collectionContains:
          final value = _popStatic(stack, current);
          final target = _popStatic(stack, current);
          final valid = switch (target.kind) {
            E0ValueKind.list ||
            E0ValueKind.set => target.elementSchema!.accepts(value),
            E0ValueKind.map => value == E0ValueSchema.string,
            E0ValueKind.string => value == E0ValueSchema.string,
            _ => false,
          };
          if (!valid) {
            throw FormatException('Invalid contains operands at $current');
          }
          stack.add(E0ValueSchema.boolean);
        case E0Opcode.collectionAdd:
          final value = _popStatic(stack, current);
          final target = _popStatic(stack, current);
          if ((target.kind != E0ValueKind.list &&
                  target.kind != E0ValueKind.set) ||
              !target.elementSchema!.accepts(value)) {
            throw FormatException('Invalid add operands at $current');
          }
        case E0Opcode.iterationValue:
          _requireStatic(stack, E0ValueSchema.integer, current);
          final target = _popStatic(stack, current);
          if (target.kind != E0ValueKind.list &&
              target.kind != E0ValueKind.set) {
            throw FormatException('Invalid iteration target at $current');
          }
          stack.add(target.elementSchema!);
        case E0Opcode.mapKeys:
          final target = _popStatic(stack, current);
          if (target.kind != E0ValueKind.map) {
            throw FormatException('Invalid map.keys target at $current');
          }
          stack.add(const E0ValueSchema.set(E0ValueSchema.string));
        case E0Opcode.enterTry:
          if (stack.isNotEmpty) {
            throw FormatException('Non-empty stack at try entry $current');
          }
          final handler = program.handlers[program.code[current + 1]];
          if (handler.catchStart != null) {
            _mergeState(
              states,
              pending,
              handler.catchStart!,
              const <E0ValueSchema>[],
              initialized,
            );
          }
          if (handler.finallyStart != null) {
            _mergeState(
              states,
              pending,
              handler.finallyStart!,
              const <E0ValueSchema>[],
              initialized,
            );
          }
        case E0Opcode.completeTry:
          if (stack.isNotEmpty) {
            throw FormatException('Non-empty stack at try completion $current');
          }
          final handler = program.handlers[program.code[current + 1]];
          final target = handler.finallyStart ?? handler.afterPc;
          if (target < program.code.length) {
            _mergeState(states, pending, target, stack, initialized);
          }
          continue;
        case E0Opcode.completeCatch:
          if (stack.isNotEmpty) {
            throw FormatException(
              'Non-empty stack at catch completion $current',
            );
          }
          final handler = program.handlers[program.code[current + 1]];
          final target = handler.finallyStart ?? handler.afterPc;
          if (target < program.code.length) {
            _mergeState(states, pending, target, stack, initialized);
          }
          continue;
        case E0Opcode.completeFinally:
          if (stack.isNotEmpty) {
            throw FormatException(
              'Non-empty stack at finally completion $current',
            );
          }
          final handler = program.handlers[program.code[current + 1]];
          if (handler.afterPc < program.code.length) {
            _mergeState(states, pending, handler.afterPc, stack, initialized);
          }
          continue;
        case E0Opcode.throwValue:
          final actual = _popStatic(stack, current);
          if (actual.nullable || actual.kind == E0ValueKind.nullValue) {
            throw FormatException('Guest throw may not be null at $current');
          }
          if (stack.isNotEmpty) {
            throw FormatException('Non-empty stack at throw $current');
          }
          continue;
        case E0Opcode.rethrowValue:
          if (stack.isNotEmpty) {
            throw FormatException('Non-empty stack at rethrow $current');
          }
          if (_handlerSection(program.handlers, current).split(':').last !=
              'catch') {
            throw FormatException('rethrow outside catch at $current');
          }
          continue;
        case E0Opcode.callAsyncCapability:
          if (!program.signature.isAsync) {
            throw FormatException(
              'Async call in synchronous program at $current',
            );
          }
          final capability = program.capabilities[program.code[current + 1]];
          for (
            var index = capability.arguments.length - 1;
            index >= 0;
            index--
          ) {
            final actual = _popStatic(stack, current);
            if (!capability.arguments[index].accepts(actual)) {
              throw FormatException('Invalid capability argument at $current');
            }
          }
          stack.add(capability.result);
        case E0Opcode.callSyncCapability:
          final capability = program.capabilities[program.code[current + 1]];
          if (capability.executionKind != E0CapabilityExecutionKind.sync) {
            throw FormatException('Non-sync capability at $current');
          }
          for (
            var index = capability.arguments.length - 1;
            index >= 0;
            index--
          ) {
            final actual = _popStatic(stack, current);
            if (!capability.arguments[index].accepts(actual)) {
              throw FormatException('Invalid capability argument at $current');
            }
          }
          stack.add(capability.result);
        case E0Opcode.awaitValue:
          if (!program.signature.isAsync) {
            throw FormatException('await in synchronous program at $current');
          }
          final point = program.asyncPoints[program.code[current + 1]];
          final actual = _popStatic(stack, current);
          if (!point.result.accepts(actual) || stack.isNotEmpty) {
            throw FormatException('Invalid await stack at $current');
          }
          stack.add(point.result);
        case E0Opcode.futureValue:
          final value = _popStatic(stack, current);
          stack.add(value);
        case E0Opcode.makeClosure:
          final closureIndex = program.code[current + 1];
          final closure = program.closures[closureIndex];
          for (var index = 0; index < closure.captures.length; index++) {
            _popStatic(stack, current);
          }
          stack.add(E0ValueSchema.closure(closureIndex));
        case E0Opcode.invokeClosure:
          final argumentCount = program.code[current + 1];
          final closureSchema = _popStatic(stack, current);
          if (closureSchema.kind != E0ValueKind.closure ||
              closureSchema.closureIndex == null) {
            throw FormatException('Invalid closure invocation at $current');
          }
          final closure = program.closures[closureSchema.closureIndex!];
          if (argumentCount != closure.parameters.length) {
            throw FormatException(
              'Closure argument count mismatch at $current',
            );
          }
          for (var index = 0; index < argumentCount; index++) {
            final actual = _popStatic(stack, current);
            final expected = closure.parameters[argumentCount - index - 1];
            if (!expected.accepts(actual)) {
              throw FormatException('Invalid closure argument at $current');
            }
          }
          stack.add(closure.returnSchema);
        case E0Opcode.collectionMap:
          final mapClosure = _popStatic(stack, current);
          final mapTarget = _popStatic(stack, current);
          final mapProgram = _requireClosure(program, mapClosure, current);
          if (mapTarget.kind != E0ValueKind.list ||
              mapProgram.parameters.length != 1 ||
              !mapProgram.parameters.single.accepts(mapTarget.elementSchema!)) {
            throw FormatException(
              'Invalid collection map operands at $current',
            );
          }
          stack.add(E0ValueSchema.list(mapProgram.returnSchema));
        case E0Opcode.collectionWhere:
          final whereClosure = _popStatic(stack, current);
          final whereTarget = _popStatic(stack, current);
          final whereProgram = _requireClosure(program, whereClosure, current);
          if (whereTarget.kind != E0ValueKind.list ||
              whereProgram.parameters.length != 1 ||
              !whereProgram.parameters.single.accepts(
                whereTarget.elementSchema!,
              ) ||
              whereProgram.returnSchema != E0ValueSchema.boolean) {
            throw FormatException(
              'Invalid collection where operands at $current',
            );
          }
          stack.add(whereTarget);
        case E0Opcode.collectionFold:
          final foldClosure = _popStatic(stack, current);
          final initial = _popStatic(stack, current);
          final foldTarget = _popStatic(stack, current);
          final foldProgram = _requireClosure(program, foldClosure, current);
          if (foldTarget.kind != E0ValueKind.list ||
              foldProgram.parameters.length != 2 ||
              !foldProgram.parameters[0].accepts(initial) ||
              !foldProgram.parameters[1].accepts(foldTarget.elementSchema!) ||
              !foldProgram.returnSchema.accepts(initial)) {
            throw FormatException(
              'Invalid collection fold operands at $current',
            );
          }
          stack.add(initial);
        case E0Opcode.collectionSort:
          final sortClosure = _popStatic(stack, current);
          final sortTarget = _popStatic(stack, current);
          final sortProgram = _requireClosure(program, sortClosure, current);
          if (sortTarget.kind != E0ValueKind.list ||
              sortProgram.parameters.length != 2 ||
              !sortProgram.parameters[0].accepts(sortTarget.elementSchema!) ||
              !sortProgram.parameters[1].accepts(sortTarget.elementSchema!) ||
              sortProgram.returnSchema != E0ValueSchema.integer) {
            throw FormatException(
              'Invalid collection sort operands at $current',
            );
          }
          stack.add(E0ValueSchema.nullValue);
        case E0Opcode.makeList:
          final count = program.code[current + 1];
          final schemas = <E0ValueSchema>[];
          for (var index = 0; index < count; index++) {
            schemas.add(_popStatic(stack, current));
          }
          stack.add(E0ValueSchema.list(_commonSchema(schemas)));
        case E0Opcode.makeMap:
          final count = program.code[current + 1];
          final schemas = <E0ValueSchema>[];
          for (var index = 0; index < count; index++) {
            schemas.add(_popStatic(stack, current));
            _requireStatic(stack, E0ValueSchema.string, current);
          }
          stack.add(E0ValueSchema.map(_commonSchema(schemas)));
        case E0Opcode.makeSet:
          final count = program.code[current + 1];
          final schemas = <E0ValueSchema>[];
          for (var index = 0; index < count; index++) {
            schemas.add(_popStatic(stack, current));
          }
          stack.add(E0ValueSchema.set(_commonSchema(schemas)));
        case E0Opcode.jumpIfFalse:
          _requireStatic(stack, E0ValueSchema.boolean, current);
          _mergeState(
            states,
            pending,
            program.code[current + 1],
            stack,
            initialized,
          );
        case E0Opcode.jump:
          _mergeState(
            states,
            pending,
            program.code[current + 1],
            stack,
            initialized,
          );
          continue;
        case E0Opcode.returnValue:
          final actual = _popStatic(stack, current);
          if (!program.signature.returnSchema.accepts(actual)) {
            throw FormatException(
              'Return type $actual does not match '
              '${program.signature.returnSchema} at $current',
            );
          }
          if (stack.isNotEmpty) {
            throw FormatException('Non-empty stack at return $current');
          }
          continue;
      }
      if (stack.length > maxStackDepth) {
        throw const FormatException('Static stack depth limit exceeded');
      }
      final next = current + opcode.width;
      if (next >= program.code.length) {
        throw FormatException('Reachable path ends without return at $current');
      }
      _mergeState(states, pending, next, stack, initialized);
    }
  }

  static int execute(
    E0PatchProgram program,
    int argument0,
    int argument1, {
    int instructionBudget = defaultInstructionBudget,
  }) {
    final result = executeValues(program, <Object?>[
      argument0,
      argument1,
    ], instructionBudget: instructionBudget);
    if (result is! int) throw StateError('Legacy E0 call did not return int');
    return result;
  }

  static Object? executeValues(
    E0PatchProgram program,
    List<Object?> arguments, {
    Map<String, Object?> namedArguments = const <String, Object?>{},
    int instructionBudget = defaultInstructionBudget,
    E0ReceiverCapability? receiver,
    E0CapabilityAuthority? authority,
    void Function()? onCapabilityStarted,
    void Function()? onInstruction,
    E0InterpreterProfileSink? profile,
    E0RuntimeLimits limits = E0RuntimeLimits.defaults,
  }) {
    try {
      return _executeValues(
        program,
        arguments,
        namedArguments: namedArguments,
        instructionBudget: instructionBudget,
        receiver: receiver,
        authority: authority,
        onCapabilityStarted: onCapabilityStarted,
        onInstruction: onInstruction,
        profile: profile,
        limits: limits,
        closureDepth: 0,
        counters: _E0ExecutionCounters(),
      );
    } on E0GuestThrow {
      rethrow;
    } on E0RuntimeFault catch (error) {
      profile?.count('diagnosticSourceMapLookup');
      if (error.functionId == program.functionId) rethrow;
      throw E0RuntimeFault(
        error.message,
        pc: error.pc,
        functionId: program.functionId,
        code: error.code,
      );
    } on StackOverflowError {
      rethrow;
    } on OutOfMemoryError {
      rethrow;
    } on Object catch (error) {
      throw E0RuntimeFault(
        _boundedMessage(error.toString()),
        functionId: program.functionId,
      );
    }
  }

  static Object? _executeValues(
    E0PatchProgram program,
    List<Object?> arguments, {
    required Map<String, Object?> namedArguments,
    required int instructionBudget,
    E0ReceiverCapability? receiver,
    E0CapabilityAuthority? authority,
    void Function()? onCapabilityStarted,
    void Function()? onInstruction,
    E0InterpreterProfileSink? profile,
    required E0RuntimeLimits limits,
    required int closureDepth,
    required _E0ExecutionCounters counters,
  }) {
    if (program.signature.isAsync) {
      throw E0RuntimeFault(
        'Async program used with synchronous executor',
        functionId: program.functionId,
      );
    }
    try {
      limits.validateInstructionBudget(instructionBudget);
    } on FormatException catch (error) {
      throw E0RuntimeFault(
        error.message,
        functionId: program.functionId,
        code: E0RuntimeDiagnosticCode.budget,
      );
    }
    if (closureDepth > limits.maxCallDepth) {
      throw E0RuntimeFault(
        'Interpreter call depth limit exceeded',
        functionId: program.functionId,
        code: E0RuntimeDiagnosticCode.budget,
      );
    }
    profile?.count('functionSlotEntry');
    final boundArguments =
        profile?.measure(
          'argumentBinding',
          () =>
              program.signature.bindArguments(arguments, named: namedArguments),
        ) ??
        program.signature.bindArguments(arguments, named: namedArguments);
    final invocationCopies = HashMap<Object, Object>.identity();
    final pinnedAuthority =
        authority ??
        (program.capabilities.isEmpty
            ? null
            : E0PatchRuntime._requireAuthority());
    final encodedArguments = <_RuntimeValue>[];
    for (var index = 0; index < boundArguments.length; index++) {
      final schema = program.signature.parameters[index];
      void encode() {
        E0Value.fromHost(boundArguments[index], schema);
        encodedArguments.add(
          _RuntimeValue(
            schema,
            _mutableCopy(boundArguments[index], invocationCopies),
          ),
        );
      }

      if (profile == null) {
        encode();
      } else {
        profile.measure('valueAllocationConversion', encode);
      }
    }
    final stack =
        profile?.measure('frameCreation', () => <_RuntimeValue>[]) ??
        <_RuntimeValue>[];
    final locals =
        profile?.measure(
          'frameCreation',
          () => List<_RuntimeValue?>.filled(program.locals.length, null),
        ) ??
        List<_RuntimeValue?>.filled(program.locals.length, null);
    final frames =
        profile?.measure('frameCreation', () => <_HandlerFrame>[]) ??
        <_HandlerFrame>[];
    var pc = 0;
    var remaining = instructionBudget;
    void consumeNestedInstruction() {
      profile?.count('budgetAccounting');
      if (remaining-- <= 0) {
        throw E0RuntimeFault(
          'Instruction budget exhausted',
          functionId: program.functionId,
          code: E0RuntimeDiagnosticCode.budget,
        );
      }
    }

    void consumeClosureInvocation(int currentPc) {
      if (++counters.closureInvocations > limits.maxClosureInvocations) {
        throw E0RuntimeFault(
          'Closure invocation limit exceeded',
          pc: currentPc,
          functionId: program.functionId,
          code: E0RuntimeDiagnosticCode.closureBudget,
        );
      }
    }

    void consumeCapabilityCall(int currentPc) {
      if (++counters.capabilityCalls > limits.maxCapabilityCalls) {
        throw E0RuntimeFault(
          'Capability call limit exceeded',
          pc: currentPc,
          functionId: program.functionId,
          code: E0RuntimeDiagnosticCode.capabilityBudget,
        );
      }
    }

    if (program.receiver.isInstance) {
      if (receiver == null || receiver.descriptorId != program.receiver.id) {
        throw const FormatException('Receiver capability mismatch');
      }
    } else if (receiver != null) {
      throw const FormatException('Unexpected receiver capability');
    }
    final opcodeWatch = profile?.start('opcodeDecodeDispatch');
    try {
      while (pc < program.code.length) {
        profile?.count('budgetAccounting');
        if (remaining-- == 0) {
          throw E0RuntimeFault(
            'Instruction budget exhausted',
            pc: pc,
            functionId: program.functionId,
            code: E0RuntimeDiagnosticCode.budget,
          );
        }
        onInstruction?.call();
        final opcode = E0Opcode.fromCode(program.code[pc]);
        if (opcode == null) {
          throw E0RuntimeFault(
            'Unvalidated opcode',
            pc: pc,
            functionId: program.functionId,
            code: E0RuntimeDiagnosticCode.invalidOpcode,
          );
        }
        profile?.recordOpcode(opcode);
        switch (opcode) {
          case E0Opcode.loadArgument:
            stack.add(encodedArguments[program.code[pc + 1]]);
          case E0Opcode.loadConstant:
            final constant = program.constants[program.code[pc + 1]];
            stack.add(
              _RuntimeValue(
                constant.schema,
                _mutableCopy(constant.toHost(constant.schema)),
              ),
            );
          case E0Opcode.loadReceiver:
            final member = program.receiver.members[program.code[pc + 1]];
            Object? value;
            try {
              value = receiver!.read(member.slot);
            } on E0RuntimeFault {
              rethrow;
            } on StackOverflowError {
              rethrow;
            } on OutOfMemoryError {
              rethrow;
            } on Object {
              final failure = E0HostFailure(
                boundaryId: member.id,
                code: 'receiverFailure',
                errorKind: 'boundaryFailure',
                message: 'Receiver request failed',
              );
              final guest = E0GuestThrow(
                failure,
                E0GuestTrace(program.functionId, pc),
              );
              final dispatch = _dispatchTransfer(
                frames,
                _ThrowCompletion(guest),
              );
              if (dispatch.escapedThrow != null) {
                throw dispatch.escapedThrow!;
              }
              pc = dispatch.nextPc!;
              continue;
            }
            E0Value.fromHost(value, member.schema);
            stack.add(
              _RuntimeValue(
                member.schema,
                _mutableCopy(value, invocationCopies),
              ),
            );
          case E0Opcode.loadLocal:
            final slot = program.code[pc + 1];
            stack.add(
              locals[slot] ?? (throw StateError('Uninitialized local $slot')),
            );
          case E0Opcode.storeLocal:
            locals[program.code[pc + 1]] = _popRuntime(stack, pc);
          case E0Opcode.pop:
            _popRuntime(stack, pc);
          case E0Opcode.addInt:
            final right = _popRuntime(stack, pc);
            final left = _popRuntime(stack, pc);
            stack.add(_runtimeAdd(left, right, pc));
          case E0Opcode.subtractInt:
            final right = _popRuntime(stack, pc);
            final left = _popRuntime(stack, pc);
            stack.add(_runtimeNumeric(left, right, pc, (a, b) => a - b));
          case E0Opcode.multiplyInt:
            final right = _popRuntime(stack, pc);
            final left = _popRuntime(stack, pc);
            stack.add(_runtimeNumeric(left, right, pc, (a, b) => a * b));
          case E0Opcode.lessThanInt:
            _compareRuntime(stack, pc, (left, right) => left < right);
          case E0Opcode.greaterThanOrEqual:
            _compareRuntime(stack, pc, (left, right) => left >= right);
          case E0Opcode.lessThanOrEqual:
            _compareRuntime(stack, pc, (left, right) => left <= right);
          case E0Opcode.greaterThan:
            _compareRuntime(stack, pc, (left, right) => left > right);
          case E0Opcode.equal:
            final right = _popRuntime(stack, pc);
            final left = _popRuntime(stack, pc);
            stack.add(
              _RuntimeValue(E0ValueSchema.boolean, left.value == right.value),
            );
          case E0Opcode.indexValue:
            final index = _popRuntime(stack, pc);
            final target = _popRuntime(stack, pc);
            if (target.schema.kind == E0ValueKind.list) {
              final values = target.value as List<Object?>;
              final integerIndex = index.value as int;
              if (integerIndex < 0 || integerIndex >= values.length) {
                final dispatch = _dispatchHostFailure(
                  program,
                  frames,
                  pc: pc,
                  boundaryId: 'collection.list.index.read',
                  code: 'range',
                  errorKind: 'RangeError',
                  message:
                      'List index $integerIndex outside length ${values.length}',
                );
                if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
                pc = dispatch.nextPc!;
                continue;
              }
              stack.add(
                _RuntimeValue(
                  target.schema.elementSchema!,
                  values[integerIndex],
                ),
              );
            } else if (target.schema.kind == E0ValueKind.map) {
              final values = target.value as Map<String, Object?>;
              final key = index.value as String;
              if (!values.containsKey(key)) {
                if (target.schema.mapValueSchema!.nullable) {
                  stack.add(_RuntimeValue(target.schema.mapValueSchema!, null));
                  break;
                }
                final dispatch = _dispatchHostFailure(
                  program,
                  frames,
                  pc: pc,
                  boundaryId: 'collection.map.index.read',
                  code: 'missing-key',
                  errorKind: 'StateError',
                  message: 'Map key is absent',
                );
                if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
                pc = dispatch.nextPc!;
                continue;
              }
              stack.add(
                _RuntimeValue(target.schema.mapValueSchema!, values[key]),
              );
            } else {
              throw StateError('Expected List or Map at $pc');
            }
          case E0Opcode.indexSet:
            final value = _popRuntime(stack, pc);
            final index = _popRuntime(stack, pc);
            final target = _popRuntime(stack, pc);
            if (target.schema.kind == E0ValueKind.list) {
              final values = target.value as List<Object?>;
              final integerIndex = index.value as int;
              if (integerIndex < 0 || integerIndex >= values.length) {
                final dispatch = _dispatchHostFailure(
                  program,
                  frames,
                  pc: pc,
                  boundaryId: 'collection.list.index.write',
                  code: 'range',
                  errorKind: 'RangeError',
                  message:
                      'List index $integerIndex outside length ${values.length}',
                );
                if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
                pc = dispatch.nextPc!;
                continue;
              }
              values[integerIndex] = value.value;
            } else if (target.schema.kind == E0ValueKind.map) {
              final map = target.value as Map<String, Object?>;
              final key = index.value as String;
              if (!map.containsKey(key) &&
                  map.length >= E0ValueCodec.maxCollectionEntries) {
                throw StateError('Map size limit exceeded at $pc');
              }
              map[key] = value.value;
            } else {
              throw StateError('Expected mutable List or Map at $pc');
            }
          case E0Opcode.collectionLength:
            final target = _popRuntime(stack, pc).value;
            final length = switch (target) {
              List<Object?> value => value.length,
              Set<Object?> value => value.length,
              Map<Object?, Object?> value => value.length,
              String value => value.length,
              _ => throw StateError('Expected collection at $pc'),
            };
            stack.add(_RuntimeValue(E0ValueSchema.integer, length));
          case E0Opcode.collectionContains:
            final value = _popRuntime(stack, pc).value;
            final target = _popRuntime(stack, pc).value;
            final contains = switch (target) {
              List<Object?> items => items.contains(value),
              Set<Object?> items => items.contains(value),
              Map<Object?, Object?> items => items.containsKey(value),
              String text when value is String => text.contains(value),
              _ => throw StateError('Expected collection at $pc'),
            };
            stack.add(_RuntimeValue(E0ValueSchema.boolean, contains));
          case E0Opcode.collectionAdd:
            final value = _popRuntime(stack, pc).value;
            final target = _popRuntime(stack, pc).value;
            if (target is List<Object?>) {
              if (target.length >= E0ValueCodec.maxCollectionEntries) {
                throw StateError('List size limit exceeded at $pc');
              }
              target.add(value);
            } else if (target is Set<Object?>) {
              if (!target.contains(value) &&
                  target.length >= E0ValueCodec.maxCollectionEntries) {
                throw StateError('Set size limit exceeded at $pc');
              }
              target.add(value);
            } else {
              throw StateError('Expected mutable List or Set at $pc');
            }
          case E0Opcode.iterationValue:
            final index = _popRuntime(stack, pc).value as int;
            final target = _popRuntime(stack, pc);
            final length = switch (target.value) {
              List<Object?> values => values.length,
              Set<Object?> values => values.length,
              _ => throw StateError('Expected iterable collection at $pc'),
            };
            if (index < 0 || index >= length) {
              final dispatch = _dispatchHostFailure(
                program,
                frames,
                pc: pc,
                boundaryId: 'collection.iteration.read',
                code: 'range',
                errorKind: 'RangeError',
                message: 'Iteration index $index outside length $length',
              );
              if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
              pc = dispatch.nextPc!;
              continue;
            }
            final value = switch (target.value) {
              List<Object?> values => values[index],
              Set<Object?> values => values.elementAt(index),
              _ => throw StateError('Expected iterable collection at $pc'),
            };
            stack.add(_RuntimeValue(target.schema.elementSchema!, value));
          case E0Opcode.mapKeys:
            final target = _popRuntime(stack, pc);
            final keys = (target.value as Map<String, Object?>).keys.toSet();
            stack.add(
              _RuntimeValue(
                const E0ValueSchema.set(E0ValueSchema.string),
                keys,
              ),
            );
          case E0Opcode.enterTry:
            final handler = program.handlers[program.code[pc + 1]];
            frames.add(_HandlerFrame(handler));
          case E0Opcode.completeTry:
            final frame = _requireFrame(
              frames,
              program.code[pc + 1],
              _HandlerPhase.tryBody,
              pc,
            );
            if (frame.handler.finallyStart != null) {
              frame
                ..phase = _HandlerPhase.finallyBody
                ..pending = _NormalCompletion(frame.handler.afterPc);
              pc = frame.handler.finallyStart!;
            } else {
              frames.removeLast();
              pc = frame.handler.afterPc;
            }
            continue;
          case E0Opcode.completeCatch:
            final frame = _requireFrame(
              frames,
              program.code[pc + 1],
              _HandlerPhase.catchBody,
              pc,
            );
            if (frame.handler.finallyStart != null) {
              frame
                ..phase = _HandlerPhase.finallyBody
                ..pending = _NormalCompletion(frame.handler.afterPc);
              pc = frame.handler.finallyStart!;
            } else {
              frames.removeLast();
              pc = frame.handler.afterPc;
            }
            continue;
          case E0Opcode.completeFinally:
            final frame = _requireFrame(
              frames,
              program.code[pc + 1],
              _HandlerPhase.finallyBody,
              pc,
            );
            frames.removeLast();
            final pending = frame.pending;
            if (pending == null) {
              throw E0RuntimeFault('Finally has no pending completion', pc: pc);
            }
            if (pending is _NormalCompletion) {
              pc = pending.targetPc;
              continue;
            }
            final dispatch = _dispatchTransfer(frames, pending);
            if (dispatch.returnValue != null) {
              return dispatch.returnValue!.toHost(
                program.signature.returnSchema,
              );
            }
            if (dispatch.escapedThrow != null) {
              throw dispatch.escapedThrow!;
            }
            pc = dispatch.nextPc!;
            continue;
          case E0Opcode.throwValue:
            final thrown = _popRuntime(stack, pc).value;
            if (thrown == null) {
              throw E0RuntimeFault('Guest throw may not be null', pc: pc);
            }
            final encodedThrow = E0Value.infer(thrown);
            final bounded = encodedThrow.toHost(encodedThrow.schema);
            final guest = E0GuestThrow(
              bounded!,
              E0GuestTrace(program.functionId, pc),
            );
            final dispatch = _dispatchTransfer(frames, _ThrowCompletion(guest));
            if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
            pc = dispatch.nextPc!;
            continue;
          case E0Opcode.rethrowValue:
            if (frames.isEmpty ||
                frames.last.phase != _HandlerPhase.catchBody ||
                frames.last.caught == null) {
              throw E0RuntimeFault('rethrow outside active catch', pc: pc);
            }
            final dispatch = _dispatchTransfer(
              frames,
              _ThrowCompletion(frames.last.caught!),
            );
            if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
            pc = dispatch.nextPc!;
            continue;
          case E0Opcode.makeList:
            final count = program.code[pc + 1];
            final reversed = <_RuntimeValue>[];
            for (var index = 0; index < count; index++) {
              reversed.add(_popRuntime(stack, pc));
            }
            final values = reversed.reversed.toList(growable: false);
            final schema = E0ValueSchema.list(
              _commonSchema(values.map((value) => value.schema).toList()),
            );
            stack.add(
              _RuntimeValue(
                schema,
                values.map((value) => value.value).toList(),
              ),
            );
          case E0Opcode.makeMap:
            final count = program.code[pc + 1];
            final entries = <(String, _RuntimeValue)>[];
            final schemas = <E0ValueSchema>[];
            for (var index = 0; index < count; index++) {
              final value = _popRuntime(stack, pc);
              final key = _popRuntime(stack, pc).value as String;
              entries.add((key, value));
              schemas.add(value.schema);
            }
            final valueSchema = _commonSchema(schemas);
            final map = <String, Object?>{};
            for (final entry in entries.reversed) {
              map[entry.$1] = entry.$2.value;
            }
            stack.add(_RuntimeValue(E0ValueSchema.map(valueSchema), map));
          case E0Opcode.makeSet:
            final count = program.code[pc + 1];
            final reversed = <_RuntimeValue>[];
            for (var index = 0; index < count; index++) {
              reversed.add(_popRuntime(stack, pc));
            }
            final values = reversed.reversed.toList(growable: false);
            final schema = E0ValueSchema.set(
              _commonSchema(values.map((value) => value.schema).toList()),
            );
            stack.add(
              _RuntimeValue(schema, values.map((value) => value.value).toSet()),
            );
          case E0Opcode.jumpIfFalse:
            if (_popRuntime(stack, pc).value != true) {
              pc = program.code[pc + 1];
              continue;
            }
          case E0Opcode.jump:
            pc = program.code[pc + 1];
            continue;
          case E0Opcode.returnValue:
            final result = _popRuntime(stack, pc);
            final checked =
                profile?.measure(
                  'returnConversion',
                  () => E0Value.fromHost(
                    result.value,
                    program.signature.returnSchema,
                  ),
                ) ??
                E0Value.fromHost(result.value, program.signature.returnSchema);
            final dispatch = _dispatchTransfer(
              frames,
              _ReturnCompletion(checked),
            );
            if (dispatch.returnValue != null) {
              if (profile == null) {
                return dispatch.returnValue!.toHost(
                  program.signature.returnSchema,
                );
              }
              return profile.measure(
                'returnConversion',
                () => dispatch.returnValue!.toHost(
                  program.signature.returnSchema,
                ),
              );
            }
            if (dispatch.escapedThrow != null) throw dispatch.escapedThrow!;
            pc = dispatch.nextPc!;
            continue;
          case E0Opcode.callSyncCapability:
            final descriptor = program.capabilities[program.code[pc + 1]];
            final binding =
                profile?.measure(
                  'capabilityValidation',
                  () => pinnedAuthority!._require(descriptor),
                ) ??
                pinnedAuthority!._require(descriptor);
            final values = List<_RuntimeValue>.generate(
              program.code[pc + 2],
              (_) => _popRuntime(stack, pc),
            ).reversed.toList(growable: false);
            final hostArguments = <Object?>[];
            for (var index = 0; index < values.length; index++) {
              hostArguments.add(
                E0Value.fromHost(
                  values[index].value,
                  descriptor.arguments[index],
                ).toHost(descriptor.arguments[index]),
              );
            }
            consumeCapabilityCall(pc);
            onCapabilityStarted?.call();
            try {
              final result = profile == null
                  ? binding.handler(List.unmodifiable(hostArguments))
                  : profile.measure(
                      'capabilityCall',
                      () => binding.handler(List.unmodifiable(hostArguments)),
                    );
              if (result is Future<Object?>) {
                throw const E0RuntimeFault('Sync capability returned Future');
              }
              final checked = E0Value.fromHost(result, descriptor.result);
              if (utf8.encode(jsonEncode(checked.toJson())).length >
                  descriptor.policy.maxOutputBytes) {
                throw const E0CapabilityException.resourceExhausted();
              }
              stack.add(
                _RuntimeValue(
                  descriptor.result,
                  checked.toHost(descriptor.result),
                ),
              );
            } on E0RuntimeFault {
              rethrow;
            } on StackOverflowError {
              rethrow;
            } on OutOfMemoryError {
              rethrow;
            } on Object catch (error) {
              final code = error is E0CapabilityException
                  ? error.code
                  : 'hostFailure';
              throw E0GuestThrow(
                E0HostFailure(
                  boundaryId: descriptor.id,
                  code: code,
                  errorKind: 'capabilityFailure',
                  message: 'Capability request failed',
                ),
                E0GuestTrace(program.functionId, pc),
              );
            }
          case E0Opcode.callAsyncCapability:
          case E0Opcode.awaitValue:
          case E0Opcode.futureValue:
            throw E0RuntimeFault(
              'Async opcode in synchronous executor',
              pc: pc,
            );
          case E0Opcode.makeClosure:
            final closureIndex = program.code[pc + 1];
            final closure = program.closures[closureIndex];
            final captures = List<_RuntimeValue>.generate(
              closure.captures.length,
              (_) => _popRuntime(stack, pc),
            ).reversed.toList(growable: false);
            stack.add(
              _RuntimeValue(
                E0ValueSchema.closure(closureIndex),
                _RuntimeClosure(closureIndex, closure, captures, receiver),
              ),
            );
          case E0Opcode.invokeClosure:
            final count = program.code[pc + 1];
            final closureValue = _popRuntime(stack, pc).value;
            if (closureValue is! _RuntimeClosure) {
              throw E0RuntimeFault('Invalid closure value', pc: pc);
            }
            consumeClosureInvocation(pc);
            final arguments = List<_RuntimeValue>.generate(
              count,
              (_) => _popRuntime(stack, pc),
            ).reversed.toList(growable: false);
            stack.add(
              _invokeClosure(
                closureValue,
                arguments,
                authority: pinnedAuthority,
                instructionBudget: remaining,
                onInstruction: consumeNestedInstruction,
                profile: profile,
                limits: limits,
                closureDepth: closureDepth,
                counters: counters,
              ),
            );
          case E0Opcode.collectionMap:
            final closure = _popRuntime(stack, pc).value;
            final target = _popRuntime(stack, pc);
            if (closure is! _RuntimeClosure || target.value is! List<Object?>) {
              throw E0RuntimeFault('Invalid collection map operands', pc: pc);
            }
            final values = <Object?>[];
            for (final item in target.value! as List<Object?>) {
              consumeClosureInvocation(pc);
              values.add(
                _invokeClosure(
                  closure,
                  <_RuntimeValue>[
                    _RuntimeValue(target.schema.elementSchema!, item),
                  ],
                  authority: pinnedAuthority,
                  instructionBudget: remaining,
                  onInstruction: consumeNestedInstruction,
                  profile: profile,
                  limits: limits,
                  closureDepth: closureDepth,
                  counters: counters,
                ).value,
              );
            }
            stack.add(
              _RuntimeValue(
                E0ValueSchema.list(closure.program.returnSchema),
                values,
              ),
            );
          case E0Opcode.collectionWhere:
            final closure = _popRuntime(stack, pc).value;
            final target = _popRuntime(stack, pc);
            if (closure is! _RuntimeClosure || target.value is! List<Object?>) {
              throw E0RuntimeFault('Invalid collection where operands', pc: pc);
            }
            final values = <Object?>[];
            for (final item in target.value! as List<Object?>) {
              consumeClosureInvocation(pc);
              final keep = _invokeClosure(
                closure,
                <_RuntimeValue>[
                  _RuntimeValue(target.schema.elementSchema!, item),
                ],
                authority: pinnedAuthority,
                instructionBudget: remaining,
                onInstruction: consumeNestedInstruction,
                profile: profile,
                limits: limits,
                closureDepth: closureDepth,
                counters: counters,
              ).value;
              if (keep is! bool) {
                throw E0RuntimeFault(
                  'Closure where result was not bool',
                  pc: pc,
                );
              }
              if (keep) values.add(item);
            }
            stack.add(_RuntimeValue(target.schema, values));
          case E0Opcode.collectionFold:
            final closure = _popRuntime(stack, pc).value;
            final initial = _popRuntime(stack, pc);
            final target = _popRuntime(stack, pc);
            if (closure is! _RuntimeClosure || target.value is! List<Object?>) {
              throw E0RuntimeFault('Invalid collection fold operands', pc: pc);
            }
            var accumulator = initial;
            for (final item in target.value! as List<Object?>) {
              consumeClosureInvocation(pc);
              accumulator = _invokeClosure(
                closure,
                <_RuntimeValue>[
                  accumulator,
                  _RuntimeValue(target.schema.elementSchema!, item),
                ],
                authority: pinnedAuthority,
                instructionBudget: remaining,
                onInstruction: consumeNestedInstruction,
                profile: profile,
                limits: limits,
                closureDepth: closureDepth,
                counters: counters,
              );
            }
            stack.add(accumulator);
          case E0Opcode.collectionSort:
            final closure = _popRuntime(stack, pc).value;
            final target = _popRuntime(stack, pc);
            if (closure is! _RuntimeClosure || target.value is! List<Object?>) {
              throw E0RuntimeFault('Invalid collection sort operands', pc: pc);
            }
            final values = List<Object?>.of(target.value! as List<Object?>);
            values.sort((left, right) {
              consumeClosureInvocation(pc);
              final result = _invokeClosure(
                closure,
                <_RuntimeValue>[
                  _RuntimeValue(target.schema.elementSchema!, left),
                  _RuntimeValue(target.schema.elementSchema!, right),
                ],
                authority: pinnedAuthority,
                instructionBudget: remaining,
                onInstruction: consumeNestedInstruction,
                profile: profile,
                limits: limits,
                closureDepth: closureDepth,
                counters: counters,
              ).value;
              if (result is! int) {
                throw E0RuntimeFault('Closure sort result was not int', pc: pc);
              }
              return result;
            });
            stack.add(const _RuntimeValue(E0ValueSchema.nullValue, null));
        }
        if (stack.length > maxStackDepth) {
          throw E0RuntimeFault(
            'Stack depth limit exceeded',
            pc: pc,
            functionId: program.functionId,
            code: E0RuntimeDiagnosticCode.budget,
          );
        }
        pc += opcode.width;
      }
      throw StateError('Program ended without return');
    } finally {
      profile?.finish('opcodeDecodeDispatch', opcodeWatch);
    }
  }

  static E0ClosureProgram _requireClosure(
    E0PatchProgram program,
    E0ValueSchema schema,
    int pc,
  ) {
    final index = schema.closureIndex;
    if (schema.kind != E0ValueKind.closure ||
        index == null ||
        index < 0 ||
        index >= program.closures.length) {
      throw FormatException('Invalid closure reference at $pc');
    }
    return program.closures[index];
  }

  static _RuntimeValue _invokeClosure(
    _RuntimeClosure closure,
    List<_RuntimeValue> arguments, {
    required E0CapabilityAuthority? authority,
    required int instructionBudget,
    void Function()? onInstruction,
    E0InterpreterProfileSink? profile,
    required E0RuntimeLimits limits,
    required int closureDepth,
    required _E0ExecutionCounters counters,
  }) {
    if (arguments.length != closure.program.parameters.length) {
      throw const E0RuntimeFault('Closure argument count mismatch');
    }
    if (closureDepth >= limits.maxCallDepth) {
      throw E0RuntimeFault(
        'Interpreter call depth limit exceeded',
        code: E0RuntimeDiagnosticCode.budget,
      );
    }
    final values = <Object?>[
      ...closure.captures.map((capture) => capture.value),
      ...arguments.map((argument) => argument.value),
    ];
    final program = closure.program.asPatchProgram(closure.index);
    final result = _executeValues(
      program,
      values,
      namedArguments: const <String, Object?>{},
      instructionBudget: instructionBudget,
      receiver: closure.receiver,
      authority: authority,
      onInstruction: onInstruction,
      profile: profile,
      limits: limits,
      closureDepth: closureDepth + 1,
      counters: counters,
    );
    final checked = E0Value.fromHost(result, closure.program.returnSchema);
    return _RuntimeValue(
      closure.program.returnSchema,
      _mutableCopy(checked.toHost(closure.program.returnSchema)),
    );
  }

  static void _mergeState(
    Map<int, _VerifierState> states,
    List<int> pending,
    int target,
    List<E0ValueSchema> incoming,
    Set<int> initialized,
  ) {
    final existing = states[target];
    if (existing != null) {
      if (!_sameTypes(existing.stack, incoming)) {
        throw FormatException('Inconsistent stack at join $target');
      }
      final definite = existing.initialized.intersection(initialized);
      if (definite.length != existing.initialized.length) {
        states[target] = _VerifierState(
          existing.stack,
          Set<int>.unmodifiable(definite),
        );
        pending.add(target);
      }
      return;
    }
    states[target] = _VerifierState(
      List<E0ValueSchema>.unmodifiable(incoming),
      Set<int>.unmodifiable(initialized),
    );
    pending.add(target);
  }

  static bool _sameTypes(List<E0ValueSchema> left, List<E0ValueSchema> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static void _requireStatic(
    List<E0ValueSchema> stack,
    E0ValueSchema expected,
    int pc,
  ) {
    final actual = _popStatic(stack, pc);
    if (actual != expected) {
      throw FormatException('Invalid operand type at $pc');
    }
  }

  static E0ValueSchema _popStatic(List<E0ValueSchema> stack, int pc) {
    if (stack.isEmpty) throw FormatException('Static stack underflow at $pc');
    return stack.removeLast();
  }

  static _RuntimeValue _popRuntime(List<_RuntimeValue> stack, int pc) {
    if (stack.isEmpty) throw E0RuntimeFault('Stack underflow', pc: pc);
    return stack.removeLast();
  }

  static _RuntimeValue _runtimeAdd(
    _RuntimeValue left,
    _RuntimeValue right,
    int pc,
  ) {
    if (left.schema != right.schema) {
      throw E0RuntimeFault('Mismatched addition types', pc: pc);
    }
    if (left.schema.kind == E0ValueKind.string) {
      final result = (left.value as String) + (right.value as String);
      try {
        E0RuntimeLimits.validateString(result, pc: pc);
      } on FormatException {
        throw E0RuntimeFault(
          'String size limit exceeded',
          pc: pc,
          code: E0RuntimeDiagnosticCode.budget,
        );
      }
      return _RuntimeValue(E0ValueSchema.string, result);
    }
    return _runtimeNumeric(left, right, pc, (a, b) => a + b);
  }

  static _RuntimeValue _runtimeNumeric(
    _RuntimeValue left,
    _RuntimeValue right,
    int pc,
    num Function(num left, num right) operation,
  ) {
    if (left.schema != right.schema || !_isNumeric(left.schema)) {
      throw E0RuntimeFault('Expected matching numeric values', pc: pc);
    }
    final result = operation(left.value! as num, right.value! as num);
    return _RuntimeValue(left.schema, result);
  }

  static void _compareRuntime(
    List<_RuntimeValue> stack,
    int pc,
    bool Function(num left, num right) compare,
  ) {
    final right = _popRuntime(stack, pc);
    final left = _popRuntime(stack, pc);
    stack.add(
      _RuntimeValue(
        E0ValueSchema.boolean,
        compare(left.value! as num, right.value! as num),
      ),
    );
  }

  static bool _supportsAddition(E0ValueSchema schema) =>
      _isNumeric(schema) || schema.kind == E0ValueKind.string;

  static bool _isNumeric(E0ValueSchema schema) =>
      !schema.nullable &&
      (schema.kind == E0ValueKind.integer ||
          schema.kind == E0ValueKind.doubleValue);

  static E0ValueSchema _commonSchema(List<E0ValueSchema> schemas) {
    if (schemas.isEmpty) return E0ValueSchema.supportedValue;
    final first = schemas.first;
    return schemas.every((schema) => schema == first)
        ? first
        : E0ValueSchema.supportedValue;
  }

  static _HandlerFrame _requireFrame(
    List<_HandlerFrame> frames,
    int id,
    _HandlerPhase phase,
    int pc,
  ) {
    if (frames.isEmpty ||
        frames.last.handler.id != id ||
        frames.last.phase != phase) {
      throw E0RuntimeFault('Invalid handler completion', pc: pc);
    }
    return frames.last;
  }

  static _DispatchResult _dispatchTransfer(
    List<_HandlerFrame> frames,
    _Completion completion,
  ) {
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.phase == _HandlerPhase.finallyBody) {
        frames.removeLast();
        continue;
      }
      if (completion is _ThrowCompletion &&
          frame.phase == _HandlerPhase.tryBody &&
          frame.handler.catchStart != null) {
        frame
          ..phase = _HandlerPhase.catchBody
          ..caught = completion.guest
          ..pending = null;
        return _DispatchResult.next(frame.handler.catchStart!);
      }
      if (frame.handler.finallyStart != null) {
        frame
          ..phase = _HandlerPhase.finallyBody
          ..pending = completion;
        return _DispatchResult.next(frame.handler.finallyStart!);
      }
      frames.removeLast();
    }
    return switch (completion) {
      _ReturnCompletion(:final value) => _DispatchResult.returned(value),
      _ThrowCompletion(:final guest) => _DispatchResult.thrown(guest),
      _NormalCompletion(:final targetPc) => _DispatchResult.next(targetPc),
    };
  }

  static _DispatchResult _dispatchHostFailure(
    E0PatchProgram program,
    List<_HandlerFrame> frames, {
    required int pc,
    required String boundaryId,
    required String code,
    required String errorKind,
    required String message,
  }) {
    final failure = E0HostFailure(
      boundaryId: boundaryId,
      code: code,
      errorKind: errorKind,
      message: _boundedMessage(message),
    );
    return _dispatchTransfer(
      frames,
      _ThrowCompletion(
        E0GuestThrow(failure, E0GuestTrace(program.functionId, pc)),
      ),
    );
  }
}

enum _HandlerPhase { tryBody, catchBody, finallyBody }

final class _HandlerFrame {
  _HandlerFrame(this.handler);

  final E0ExceptionHandler handler;
  _HandlerPhase phase = _HandlerPhase.tryBody;
  _Completion? pending;
  E0GuestThrow? caught;
}

sealed class _Completion {
  const _Completion();
}

final class _NormalCompletion extends _Completion {
  const _NormalCompletion(this.targetPc);

  final int targetPc;
}

final class _ReturnCompletion extends _Completion {
  const _ReturnCompletion(this.value);

  final E0Value value;
}

final class _ThrowCompletion extends _Completion {
  const _ThrowCompletion(this.guest);

  final E0GuestThrow guest;
}

final class _DispatchResult {
  const _DispatchResult._({this.nextPc, this.returnValue, this.escapedThrow});

  factory _DispatchResult.next(int pc) => _DispatchResult._(nextPc: pc);

  factory _DispatchResult.returned(E0Value value) =>
      _DispatchResult._(returnValue: value);

  factory _DispatchResult.thrown(E0GuestThrow guest) =>
      _DispatchResult._(escapedThrow: guest);

  final int? nextPc;
  final E0Value? returnValue;
  final E0GuestThrow? escapedThrow;
}

String _boundedMessage(String value) => e0BoundedDiagnosticMessage(value);

final class _E0ExecutionCounters {
  int closureInvocations = 0;
  int capabilityCalls = 0;
}

final class _RuntimeValue {
  const _RuntimeValue(this.schema, this.value);

  final E0ValueSchema schema;
  final Object? value;
}

final class _RuntimeClosure {
  const _RuntimeClosure(this.index, this.program, this.captures, this.receiver);

  final int index;
  final E0ClosureProgram program;
  final List<_RuntimeValue> captures;
  final E0ReceiverCapability? receiver;
}

Object? _mutableCopy(Object? value, [Map<Object, Object>? memo]) {
  memo ??= HashMap<Object, Object>.identity();
  if (value is Object && memo.containsKey(value)) return memo[value];
  if (value is List<Object?>) {
    final result = <Object?>[];
    memo[value] = result;
    result.addAll(<Object?>[
      for (final item in value) _mutableCopy(item, memo),
    ]);
    return result;
  }
  if (value is Set<Object?>) {
    final result = <Object?>{};
    memo[value] = result;
    result.addAll(<Object?>{
      for (final item in value) _mutableCopy(item, memo),
    });
    return result;
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    memo[value] = result;
    for (final entry in value.entries) {
      result[entry.key! as String] = _mutableCopy(entry.value, memo);
    }
    return result;
  }
  return value;
}

final class _VerifierState {
  const _VerifierState(this.stack, this.initialized);

  final List<E0ValueSchema> stack;
  final Set<int> initialized;
}

typedef E0CapabilityHandler = FutureOr<Object?> Function(
  List<Object?> arguments,
);
typedef E0AsyncCapabilityHandler = E0CapabilityHandler;

final class _AsyncCapabilityBinding {
  const _AsyncCapabilityBinding(this.descriptor, this.handler);

  final E0AsyncCapabilityDescriptor descriptor;
  final E0CapabilityHandler handler;
}

/// An application-owned, immutable set of explicitly linked host adapters.
///
/// Construction rejects duplicate stable IDs even when their contracts happen
/// to match. Downloaded code can select only these pre-compiled bindings.
final class E0CapabilityRegistry {
  E0CapabilityRegistry(Iterable<E0CapabilityRegistration> registrations)
    : _bindings = _build(registrations);

  final Map<String, _AsyncCapabilityBinding> _bindings;

  static Map<String, _AsyncCapabilityBinding> _build(
    Iterable<E0CapabilityRegistration> registrations,
  ) {
    final result = <String, _AsyncCapabilityBinding>{};
    for (final registration in registrations) {
      final descriptor = registration.descriptor;
      if (!_validStableCapabilityId.hasMatch(descriptor.id)) {
        throw FormatException('Invalid stable capability ID ${descriptor.id}');
      }
      descriptor._validateContract();
      if (descriptor.sourceName != null &&
          !_validSourceName.hasMatch(descriptor.sourceName!)) {
        throw FormatException(
          'Invalid capability source name ${descriptor.sourceName}',
        );
      }
      if (descriptor.resources.toSet().length != descriptor.resources.length ||
          descriptor.resources.any(
            (resource) => !_validResource.hasMatch(resource),
          )) {
        throw FormatException(
          'Invalid or duplicate resource for capability ${descriptor.id}',
        );
      }
      if (result.containsKey(descriptor.id)) {
        throw StateError('Duplicate capability registration ${descriptor.id}');
      }
      result[descriptor.id] = _AsyncCapabilityBinding(
        descriptor,
        registration.handler,
      );
    }
    return Map.unmodifiable(result);
  }

  Iterable<E0AsyncCapabilityDescriptor> get descriptors =>
      _bindings.values.map((binding) => binding.descriptor);

  bool supports(E0AsyncCapabilityDescriptor descriptor) =>
      _bindings[descriptor.id]?.descriptor == descriptor;

  _AsyncCapabilityBinding _require(E0AsyncCapabilityDescriptor descriptor) {
    final binding = _bindings[descriptor.id];
    if (binding == null || binding.descriptor != descriptor) {
      throw FormatException(
        'Missing or incompatible capability '
        '${descriptor.id}@${descriptor.version}',
      );
    }
    return binding;
  }
}

final class E0CapabilityRegistration {
  const E0CapabilityRegistration(this.descriptor, this.handler);

  final E0AsyncCapabilityDescriptor descriptor;
  final E0CapabilityHandler handler;
}

/// Frozen application authority: shipped contracts and their compiled adapters.
final class E0CapabilityAuthority {
  // ignore: prefer_initializing_formals
  E0CapabilityAuthority({
    required List<E0AsyncCapabilityDescriptor> shipped,
    required E0CapabilityRegistry registry,
  }) : _shipped = Map.unmodifiable(<String, E0AsyncCapabilityDescriptor>{
         for (final descriptor in shipped) descriptor.id: descriptor,
       }),
       // ignore: prefer_initializing_formals
       _registry = registry {
    final list = shipped.toList(growable: false);
    if (list.length != _shipped.length) {
      throw StateError('Duplicate shipped capability ID');
    }
    for (final descriptor in list) {
      descriptor._validateContract();
    }
  }

  final Map<String, E0AsyncCapabilityDescriptor> _shipped;
  final E0CapabilityRegistry _registry;

  _AsyncCapabilityBinding _require(E0AsyncCapabilityDescriptor descriptor) {
    if (_shipped[descriptor.id] != descriptor) {
      throw FormatException(
        'Capability ${descriptor.id} is absent or incompatible with shipped authority',
      );
    }
    return _registry._require(descriptor);
  }
}

final RegExp _validStableCapabilityId = RegExp(
  r'^[a-z][a-z0-9]*(?:[.-][a-z][a-z0-9]*)+$',
);
final RegExp _validSourceName = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
final RegExp _validResource = RegExp(r'^[a-z][a-z0-9]*(?::[a-z0-9.*_-]+)?$');

sealed class _PendingAsyncValue {
  const _PendingAsyncValue(this.result, this.future);

  final E0ValueSchema result;
  final Future<Object?> future;
}

final class _PendingCapability extends _PendingAsyncValue {
  _PendingCapability(this.descriptor, Future<Object?> future)
    : super(descriptor.result, future);

  final E0AsyncCapabilityDescriptor descriptor;
}

final class _PendingFutureValue extends _PendingAsyncValue {
  const _PendingFutureValue(super.result, super.future);
}

final class _E0ResumeToken {
  _E0ResumeToken(this.state, this.token, this.descriptor, this.zone);

  _E0Continuation? state;
  final int token;
  final E0AsyncCapabilityDescriptor? descriptor;
  final Zone zone;

  void detach() => state = null;
}

final class E0AsyncRetentionDebugSnapshot {
  const E0AsyncRetentionDebugSnapshot({
    required this.programRetained,
    required this.argumentsRetained,
    required this.receiverRetained,
    required this.copyMemoEntries,
    required this.stackEntries,
    required this.localEntries,
    required this.handlerFrames,
    required this.resumeTokenAttached,
  });

  final bool programRetained;
  final bool argumentsRetained;
  final bool receiverRetained;
  final int copyMemoEntries;
  final int stackEntries;
  final int localEntries;
  final int handlerFrames;
  final bool resumeTokenAttached;

  bool get heavyStateReleased =>
      !programRetained &&
      !argumentsRetained &&
      !receiverRetained &&
      copyMemoEntries == 0 &&
      stackEntries == 0 &&
      localEntries == 0 &&
      handlerFrames == 0 &&
      !resumeTokenAttached;
}

/// Heap-owned state corresponding to one interpreted async invocation.
final class _E0Continuation {
  _E0Continuation({
    required E0PatchProgram program,
    required this.generation,
    required this._arguments,
    required this._copyMemo,
    required this._receiver,
    required this.instructionBudget,
    required this.deadline,
    required this.maxResumes,
    required this.zone,
    required this._onRuntimeFault,
    required this.authority,
    required this.profile,
    required this.limits,
  }) : _program = program,
       remainingInstructions = instructionBudget,
       stack = <_RuntimeValue>[],
       locals = List<_RuntimeValue?>.filled(program.locals.length, null),
       frames = <_HandlerFrame>[],
       completer = Completer<Object?>();

  E0PatchProgram? _program;
  E0PatchProgram get program =>
      _program ?? (throw StateError('Continuation program was released'));
  final int generation;
  List<_RuntimeValue>? _arguments;
  List<_RuntimeValue> get arguments =>
      _arguments ?? (throw StateError('Continuation arguments were released'));
  Map<Object, Object>? _copyMemo;
  Map<Object, Object> get copyMemo =>
      _copyMemo ?? (throw StateError('Continuation copy memo was released'));
  E0ReceiverCapability? _receiver;
  E0ReceiverCapability? get receiver => _receiver;
  final int instructionBudget;
  final Duration deadline;
  final int maxResumes;
  final E0RuntimeLimits limits;
  final Zone zone;
  final E0CapabilityAuthority? authority;
  final E0InterpreterProfileSink? profile;
  void Function(String message)? _onRuntimeFault;
  void Function(String message)? get onRuntimeFault => _onRuntimeFault;
  final List<_RuntimeValue> stack;
  final List<_RuntimeValue?> locals;
  final List<_HandlerFrame> frames;
  final Completer<Object?> completer;
  int pc = 0;
  int remainingInstructions;
  int suspensions = 0;
  int resumes = 0;
  int capabilityCalls = 0;
  int token = 0;
  bool pending = false;
  bool terminal = false;
  bool capabilityStarted = false;
  Timer? timer;
  _E0ResumeToken? resumeToken;
}

final class E0AsyncInterpreter {
  static const int defaultInstructionBudget = 10000;
  static const int defaultMaxResumes = 32;
  static const Duration defaultDeadline = Duration(seconds: 5);
  static const int maxActiveContinuations = 64;

  static int activeContinuations = 0;
  static int rejectedResumeAttempts = 0;
  static WeakReference<_E0Continuation>? _lastContinuation;
  static E0AsyncRetentionDebugSnapshot? lastRetentionSnapshot;

  static _RuntimeValue _popRuntime(List<_RuntimeValue> stack, int pc) =>
      E0Interpreter._popRuntime(stack, pc);

  static Future<Object?> execute(
    E0PatchProgram program,
    List<Object?> arguments, {
    Map<String, Object?> namedArguments = const <String, Object?>{},
    E0ReceiverCapability? receiver,
    int generation = 0,
    int instructionBudget = defaultInstructionBudget,
    int maxResumes = defaultMaxResumes,
    Duration deadline = defaultDeadline,
    required void Function(String message) onRuntimeFault,
    E0CapabilityAuthority? authority,
    E0InterpreterProfileSink? profile,
    E0RuntimeLimits limits = E0RuntimeLimits.defaults,
  }) {
    if (!program.signature.isAsync) {
      throw const E0RuntimeFault(
        'Synchronous program used with async executor',
      );
    }
    if (activeContinuations >= maxActiveContinuations) {
      throw E0RuntimeFault(
        'Active continuation limit exceeded',
        functionId: program.functionId,
        code: E0RuntimeDiagnosticCode.budget,
      );
    }
    try {
      limits.validateAsyncInvocation(
        instructionBudget: instructionBudget,
        maxResumes: maxResumes,
        deadline: deadline,
      );
    } on FormatException catch (error) {
      throw E0RuntimeFault(
        error.message,
        functionId: program.functionId,
        code: E0RuntimeDiagnosticCode.budget,
      );
    }
    profile?.count('functionSlotEntry');
    final boundArguments =
        profile?.measure(
          'argumentBinding',
          () =>
              program.signature.bindArguments(arguments, named: namedArguments),
        ) ??
        program.signature.bindArguments(arguments, named: namedArguments);
    final pinnedAuthority =
        authority ??
        (program.capabilities.isEmpty
            ? null
            : E0PatchRuntime._requireAuthority());
    for (final descriptor in program.capabilities) {
      if (profile == null) {
        pinnedAuthority!._require(descriptor);
      } else {
        profile.measure(
          'capabilityValidation',
          () => pinnedAuthority!._require(descriptor),
        );
      }
    }
    final copies = HashMap<Object, Object>.identity();
    final encoded = <_RuntimeValue>[];
    for (var index = 0; index < boundArguments.length; index++) {
      final schema = program.signature.parameters[index];
      void encode() {
        E0Value.fromHost(boundArguments[index], schema);
        encoded.add(
          _RuntimeValue(schema, _mutableCopy(boundArguments[index], copies)),
        );
      }

      if (profile == null) {
        encode();
      } else {
        profile.measure('valueAllocationConversion', encode);
      }
    }
    if (program.receiver.isInstance) {
      if (receiver == null || receiver.descriptorId != program.receiver.id) {
        throw const FormatException('Receiver capability mismatch');
      }
    } else if (receiver != null) {
      throw const FormatException('Unexpected receiver capability');
    }
    final continuation = _E0Continuation(
      program: program,
      generation: generation,
      arguments: encoded,
      copyMemo: copies,
      receiver: receiver,
      instructionBudget: instructionBudget,
      deadline: deadline,
      maxResumes: maxResumes,
      zone: Zone.current,
      onRuntimeFault: onRuntimeFault,
      authority: pinnedAuthority,
      profile: profile,
      limits: limits,
    );
    profile?.count('frameCreation');
    _lastContinuation = WeakReference<_E0Continuation>(continuation);
    activeContinuations++;
    continuation.timer = Timer(deadline, () {
      continuation.zone.run(() {
        _runtimeFault(continuation, 'Async invocation deadline exceeded');
      });
    });
    _run(continuation);
    return continuation.completer.future;
  }

  /// Test-only adversarial seam: a completed/stale continuation must reject a
  /// second resume without executing bytecode.
  static bool debugAttemptStaleResume() {
    final continuation = _lastContinuation?.target;
    if (continuation == null) {
      rejectedResumeAttempts++;
      return false;
    }
    final accepted = _resumeValue(continuation, continuation.token - 1, 0);
    if (!accepted) rejectedResumeAttempts++;
    return accepted;
  }

  /// Test-only adversarial seam for a second callback using the last valid
  /// token after the invocation already reached a terminal state.
  static bool debugAttemptDuplicateResume() {
    final continuation = _lastContinuation?.target;
    if (continuation == null) {
      rejectedResumeAttempts++;
      return false;
    }
    final accepted = _resumeValue(continuation, continuation.token, 0);
    if (!accepted) rejectedResumeAttempts++;
    return accepted;
  }

  static void resetDebugState() {
    _lastContinuation = null;
    lastRetentionSnapshot = null;
    rejectedResumeAttempts = 0;
  }

  static void _run(_E0Continuation state) {
    if (state.terminal) return;
    final program = state.program;
    try {
      final opcodeWatch = state.profile?.start('opcodeDecodeDispatch');
      try {
        while (state.pc < program.code.length) {
          state.profile?.count('budgetAccounting');
          if (state.remainingInstructions-- <= 0) {
            _runtimeFault(
              state,
              'Total async instruction budget exhausted',
              code: E0RuntimeDiagnosticCode.budget,
            );
            return;
          }
          final pc = state.pc;
          final opcode = E0Opcode.fromCode(program.code[pc]);
          if (opcode == null) {
            throw E0RuntimeFault(
              'Unknown opcode',
              pc: pc,
              functionId: program.functionId,
              code: E0RuntimeDiagnosticCode.invalidOpcode,
            );
          }
          state.profile?.recordOpcode(opcode);
          switch (opcode) {
            case E0Opcode.loadArgument:
              state.stack.add(state.arguments[program.code[pc + 1]]);
            case E0Opcode.loadConstant:
              final value = program.constants[program.code[pc + 1]];
              state.stack.add(
                _RuntimeValue(
                  value.schema,
                  _mutableCopy(value.toHost(value.schema)),
                ),
              );
            case E0Opcode.loadReceiver:
              final member = program.receiver.members[program.code[pc + 1]];
              Object? value;
              try {
                value = state.receiver!.read(member.slot);
              } on E0RuntimeFault catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on StackOverflowError catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on OutOfMemoryError catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on Object catch (error) {
                if (!_dispatchAsyncHostError(
                  state,
                  pc,
                  member.id,
                  'receiver.read.throw',
                  error,
                )) {
                  return;
                }
                continue;
              }
              E0Value.fromHost(value, member.schema);
              state.stack.add(
                _RuntimeValue(
                  member.schema,
                  _mutableCopy(value, state.copyMemo),
                ),
              );
            case E0Opcode.loadLocal:
              final slot = program.code[pc + 1];
              state.stack.add(
                state.locals[slot] ??
                    (throw E0RuntimeFault('Uninitialized local $slot', pc: pc)),
              );
            case E0Opcode.storeLocal:
              state.locals[program.code[pc + 1]] = _popRuntime(state.stack, pc);
            case E0Opcode.pop:
              _popRuntime(state.stack, pc);
            case E0Opcode.addInt:
              final right = _popRuntime(state.stack, pc);
              final left = _popRuntime(state.stack, pc);
              state.stack.add(E0Interpreter._runtimeAdd(left, right, pc));
            case E0Opcode.subtractInt:
              final right = _popRuntime(state.stack, pc);
              final left = _popRuntime(state.stack, pc);
              state.stack.add(
                E0Interpreter._runtimeNumeric(left, right, pc, (a, b) => a - b),
              );
            case E0Opcode.multiplyInt:
              final right = _popRuntime(state.stack, pc);
              final left = _popRuntime(state.stack, pc);
              state.stack.add(
                E0Interpreter._runtimeNumeric(left, right, pc, (a, b) => a * b),
              );
            case E0Opcode.lessThanInt:
              E0Interpreter._compareRuntime(state.stack, pc, (a, b) => a < b);
            case E0Opcode.greaterThanOrEqual:
              E0Interpreter._compareRuntime(state.stack, pc, (a, b) => a >= b);
            case E0Opcode.lessThanOrEqual:
              E0Interpreter._compareRuntime(state.stack, pc, (a, b) => a <= b);
            case E0Opcode.greaterThan:
              E0Interpreter._compareRuntime(state.stack, pc, (a, b) => a > b);
            case E0Opcode.equal:
              final right = _popRuntime(state.stack, pc);
              final left = _popRuntime(state.stack, pc);
              state.stack.add(
                _RuntimeValue(E0ValueSchema.boolean, left.value == right.value),
              );
            case E0Opcode.jumpIfFalse:
              if (_popRuntime(state.stack, pc).value != true) {
                state.pc = program.code[pc + 1];
                continue;
              }
            case E0Opcode.jump:
              state.pc = program.code[pc + 1];
              continue;
            case E0Opcode.enterTry:
              state.frames.add(
                _HandlerFrame(program.handlers[program.code[pc + 1]]),
              );
            case E0Opcode.completeTry:
              final frame = E0Interpreter._requireFrame(
                state.frames,
                program.code[pc + 1],
                _HandlerPhase.tryBody,
                pc,
              );
              if (frame.handler.finallyStart != null) {
                frame
                  ..phase = _HandlerPhase.finallyBody
                  ..pending = _NormalCompletion(frame.handler.afterPc);
                state.pc = frame.handler.finallyStart!;
              } else {
                state.frames.removeLast();
                state.pc = frame.handler.afterPc;
              }
              continue;
            case E0Opcode.completeCatch:
              final frame = E0Interpreter._requireFrame(
                state.frames,
                program.code[pc + 1],
                _HandlerPhase.catchBody,
                pc,
              );
              if (frame.handler.finallyStart != null) {
                frame
                  ..phase = _HandlerPhase.finallyBody
                  ..pending = _NormalCompletion(frame.handler.afterPc);
                state.pc = frame.handler.finallyStart!;
              } else {
                state.frames.removeLast();
                state.pc = frame.handler.afterPc;
              }
              continue;
            case E0Opcode.completeFinally:
              final frame = E0Interpreter._requireFrame(
                state.frames,
                program.code[pc + 1],
                _HandlerPhase.finallyBody,
                pc,
              );
              state.frames.removeLast();
              final pending = frame.pending;
              if (pending == null) {
                throw E0RuntimeFault(
                  'Finally has no pending completion',
                  pc: pc,
                );
              }
              if (pending is _NormalCompletion) {
                state.pc = pending.targetPc;
                continue;
              }
              if (!_completeAsyncTransfer(state, pending)) return;
              continue;
            case E0Opcode.throwValue:
              final value = _popRuntime(state.stack, pc).value;
              if (value == null) {
                throw E0RuntimeFault('Null guest throw', pc: pc);
              }
              final guest = E0GuestThrow(
                E0Value.infer(value).toHost(E0Value.infer(value).schema)!,
                E0GuestTrace(program.functionId, pc),
              );
              if (!_completeAsyncTransfer(state, _ThrowCompletion(guest))) {
                return;
              }
              continue;
            case E0Opcode.rethrowValue:
              if (state.frames.isEmpty || state.frames.last.caught == null) {
                throw E0RuntimeFault('rethrow outside catch', pc: pc);
              }
              if (!_completeAsyncTransfer(
                state,
                _ThrowCompletion(state.frames.last.caught!),
              )) {
                return;
              }
              continue;
            case E0Opcode.callAsyncCapability:
              final descriptor = program.capabilities[program.code[pc + 1]];
              final values = List<_RuntimeValue>.generate(
                program.code[pc + 2],
                (_) => _popRuntime(state.stack, pc),
              ).reversed.toList(growable: false);
              final hostArguments = <Object?>[];
              for (var index = 0; index < values.length; index++) {
                hostArguments.add(
                  E0Value.fromHost(
                    values[index].value,
                    descriptor.arguments[index],
                  ).toHost(descriptor.arguments[index]),
                );
              }
              final binding = state.profile == null
                  ? state.authority!._require(descriptor)
                  : state.profile!.measure(
                      'capabilityValidation',
                      () => state.authority!._require(descriptor),
                    );
              if (++state.capabilityCalls > state.limits.maxCapabilityCalls) {
                _runtimeFault(
                  state,
                  'Capability call limit exceeded',
                  code: E0RuntimeDiagnosticCode.capabilityBudget,
                );
                return;
              }
              state.capabilityStarted = true;
              Future<Object?> future;
              try {
                Future<Object?> startCapability() =>
                    Future<Object?>.sync(
                      () => binding.handler(List.unmodifiable(hostArguments)),
                    ).timeout(
                      descriptor.policy.timeout,
                      onTimeout: () =>
                          throw const E0CapabilityException.deadlineExceeded(),
                    );
                future = state.profile == null
                    ? startCapability()
                    : state.profile!.measure('capabilityCall', startCapability);
              } on E0RuntimeFault catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on StackOverflowError catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on OutOfMemoryError catch (error, trace) {
                _fatalFault(state, error, trace);
                return;
              } on Object catch (error, trace) {
                future = Future<Object?>.error(error, trace);
              }
              state.stack.add(
                _RuntimeValue(
                  descriptor.result,
                  _PendingCapability(descriptor, future),
                ),
              );
            case E0Opcode.futureValue:
              final value = _popRuntime(state.stack, pc);
              state.stack.add(
                _RuntimeValue(
                  value.schema,
                  _PendingFutureValue(
                    value.schema,
                    Future<Object?>.value(value.value),
                  ),
                ),
              );
            case E0Opcode.callSyncCapability:
              throw E0RuntimeFault(
                'Sync capability is not enabled in async executor',
                pc: pc,
              );
            case E0Opcode.awaitValue:
              final point = program.asyncPoints[program.code[pc + 1]];
              final pending = _popRuntime(state.stack, pc).value;
              if (pending is! _PendingAsyncValue ||
                  pending.result != point.result ||
                  state.stack.isNotEmpty ||
                  state.frames.length != point.handlerDepth) {
                throw E0RuntimeFault('Invalid continuation shape', pc: pc);
              }
              if (state.suspensions >= state.maxResumes) {
                throw E0RuntimeFault(
                  'Async suspension limit exceeded',
                  pc: pc,
                  functionId: program.functionId,
                  code: E0RuntimeDiagnosticCode.budget,
                );
              }
              state.pending = true;
              state.suspensions++;
              state.token++;
              final token = state.token;
              final resumeToken = _E0ResumeToken(
                state,
                token,
                pending is _PendingCapability ? pending.descriptor : null,
                state.zone,
              );
              state.resumeToken = resumeToken;
              Future<void> schedule() => pending.future.then<void>(
                (Object? value) => resumeToken.zone.run(
                  () => _resumeTokenValue(resumeToken, value),
                ),
                onError: (Object error, StackTrace trace) => resumeToken.zone
                    .run(() => _resumeTokenError(resumeToken, error, trace)),
              );
              if (state.profile == null) {
                schedule();
              } else {
                state.profile!.measure('asyncContinuationSchedule', schedule);
              }
              return;
            case E0Opcode.returnValue:
              final value = _popRuntime(state.stack, pc);
              final checked =
                  state.profile?.measure(
                    'returnConversion',
                    () => E0Value.fromHost(
                      value.value,
                      program.signature.returnSchema,
                    ),
                  ) ??
                  E0Value.fromHost(value.value, program.signature.returnSchema);
              if (!_completeAsyncTransfer(state, _ReturnCompletion(checked))) {
                return;
              }
              continue;
            case E0Opcode.indexValue:
            case E0Opcode.makeList:
            case E0Opcode.makeMap:
            case E0Opcode.indexSet:
            case E0Opcode.collectionLength:
            case E0Opcode.collectionContains:
            case E0Opcode.collectionAdd:
            case E0Opcode.makeSet:
            case E0Opcode.iterationValue:
            case E0Opcode.mapKeys:
            case E0Opcode.makeClosure:
            case E0Opcode.invokeClosure:
            case E0Opcode.collectionMap:
            case E0Opcode.collectionWhere:
            case E0Opcode.collectionFold:
            case E0Opcode.collectionSort:
              throw E0RuntimeFault(
                'Closure/collection opcode is not enabled in async v6',
                pc: pc,
              );
          }
          if (state.stack.length > E0Interpreter.maxStackDepth) {
            throw E0RuntimeFault(
              'Stack depth limit exceeded',
              pc: pc,
              functionId: program.functionId,
              code: E0RuntimeDiagnosticCode.budget,
            );
          }
          state.pc += opcode.width;
        }
        throw const E0RuntimeFault('Async program ended without return');
      } finally {
        state.profile?.finish('opcodeDecodeDispatch', opcodeWatch);
      }
    } on E0GuestThrow catch (guest) {
      _guestError(state, guest);
    } on E0RuntimeFault catch (error, trace) {
      _fatalFault(state, error, trace);
    } on StackOverflowError catch (error, trace) {
      _fatalFault(state, error, trace);
    } on OutOfMemoryError catch (error, trace) {
      _fatalFault(state, error, trace);
    } on Object catch (error) {
      _runtimeFault(state, error.toString());
    }
  }

  static bool _resumeTokenValue(_E0ResumeToken token, Object? value) {
    final state = token.state;
    token.detach();
    if (state == null) {
      rejectedResumeAttempts++;
      return false;
    }
    if (identical(state.resumeToken, token)) state.resumeToken = null;
    return _resumeValue(state, token.token, value, token.descriptor);
  }

  static bool _resumeTokenError(
    _E0ResumeToken token,
    Object error,
    StackTrace trace,
  ) {
    final state = token.state;
    token.detach();
    if (state == null) {
      rejectedResumeAttempts++;
      return false;
    }
    if (identical(state.resumeToken, token)) state.resumeToken = null;
    return _resumeError(state, token.token, token.descriptor, error, trace);
  }

  static bool _resumeValue(
    _E0Continuation state,
    int token,
    Object? value, [
    E0AsyncCapabilityDescriptor? descriptor,
  ]) {
    if (state.terminal || !state.pending || token != state.token) return false;
    state.pending = false;
    state.profile?.count('asyncContinuationResume');
    if (++state.resumes > state.maxResumes) {
      _runtimeFault(
        state,
        'Async resume limit exceeded',
        code: E0RuntimeDiagnosticCode.budget,
      );
      return false;
    }
    final point = state.program.asyncPoints.singleWhere(
      (item) => item.resumePc == state.pc + E0Opcode.awaitValue.width,
    );
    try {
      final checked =
          state.profile?.measure(
            'valueAllocationConversion',
            () => E0Value.fromHost(value, point.result),
          ) ??
          E0Value.fromHost(value, point.result);
      if (descriptor != null &&
          utf8.encode(jsonEncode(checked.toJson())).length >
              descriptor.policy.maxOutputBytes) {
        throw const E0CapabilityException.resourceExhausted();
      }
      state.stack.add(
        _RuntimeValue(point.result, checked.toHost(point.result)),
      );
      state.pc = point.resumePc;
      if (state.profile == null) {
        _run(state);
      } else {
        state.profile!.measure('asyncContinuationResume', () => _run(state));
      }
    } on E0CapabilityException catch (error) {
      final guest = E0GuestThrow(
        E0HostFailure(
          boundaryId: descriptor?.id ?? 'capability',
          code: error.code,
          errorKind: 'capabilityFailure',
          message: 'Capability request failed',
        ),
        E0GuestTrace(state.program.functionId, state.pc),
      );
      if (_completeAsyncTransfer(state, _ThrowCompletion(guest))) _run(state);
    } on E0RuntimeFault catch (error, trace) {
      _fatalFault(state, error, trace);
    } on StackOverflowError catch (error, trace) {
      _fatalFault(state, error, trace);
    } on OutOfMemoryError catch (error, trace) {
      _fatalFault(state, error, trace);
    } on Object catch (error) {
      _runtimeFault(state, 'Async result validation failed: $error');
    }
    return true;
  }

  static bool _resumeError(
    _E0Continuation state,
    int token,
    E0AsyncCapabilityDescriptor? descriptor,
    Object error,
    StackTrace trace,
  ) {
    if (state.terminal || !state.pending || token != state.token) return false;
    state.pending = false;
    if (++state.resumes > state.maxResumes) {
      _runtimeFault(
        state,
        'Async resume limit exceeded',
        code: E0RuntimeDiagnosticCode.budget,
      );
      return false;
    }
    if (error is E0RuntimeFault ||
        error is StackOverflowError ||
        error is OutOfMemoryError) {
      _fatalFault(state, error, trace);
      return true;
    }
    final code = error is E0CapabilityException ? error.code : 'hostFailure';
    final guest = E0GuestThrow(
      E0HostFailure(
        boundaryId: descriptor?.id ?? 'future',
        code: code,
        errorKind: 'capabilityFailure',
        message: 'Capability request failed',
      ),
      E0GuestTrace(state.program.functionId, state.pc),
    );
    if (_completeAsyncTransfer(state, _ThrowCompletion(guest))) {
      _run(state);
    }
    return true;
  }

  static bool _dispatchAsyncHostError(
    _E0Continuation state,
    int pc,
    String boundary,
    String code,
    Object error,
  ) {
    final guest = E0GuestThrow(
      E0HostFailure(
        boundaryId: boundary,
        code: 'receiverFailure',
        errorKind: 'boundaryFailure',
        message: 'Receiver request failed',
      ),
      E0GuestTrace(state.program.functionId, pc),
    );
    return _completeAsyncTransfer(state, _ThrowCompletion(guest));
  }

  static bool _completeAsyncTransfer(
    _E0Continuation state,
    _Completion completion,
  ) {
    final dispatch = E0Interpreter._dispatchTransfer(state.frames, completion);
    if (dispatch.returnValue != null) {
      final value = state.profile == null
          ? dispatch.returnValue!.toHost(state.program.signature.returnSchema)
          : state.profile!.measure(
              'returnConversion',
              () => dispatch.returnValue!.toHost(
                state.program.signature.returnSchema,
              ),
            );
      _finishValue(state, value);
      return false;
    }
    if (dispatch.escapedThrow != null) {
      _guestError(state, dispatch.escapedThrow!);
      return false;
    }
    state.pc = dispatch.nextPc!;
    return true;
  }

  static void _finishValue(_E0Continuation state, Object? value) {
    if (state.terminal) return;
    state.terminal = true;
    _dispose(state);
    state.completer.complete(value);
  }

  static void _guestError(_E0Continuation state, E0GuestThrow guest) {
    if (state.terminal) return;
    state.terminal = true;
    _dispose(state);
    state.completer.completeError(guest.value, guest.trace);
  }

  static void _runtimeFault(
    _E0Continuation state,
    String message, {
    String code = E0RuntimeDiagnosticCode.execution,
  }) {
    if (state.terminal) return;
    state.terminal = true;
    final fault = E0RuntimeFault(
      _boundedMessage(message),
      pc: state.pc,
      functionId: state.program.functionId,
      code: code,
    );
    state.profile?.count('diagnosticSourceMapLookup');
    _reportRuntimeFault(state, _boundedMessage(fault.toString()));
    _dispose(state);
    state.completer.completeError(fault, StackTrace.empty);
  }

  static void _fatalFault(
    _E0Continuation state,
    Object error,
    StackTrace trace,
  ) {
    if (state.terminal) return;
    state.terminal = true;
    final enriched = error is E0RuntimeFault && error.functionId == null
        ? E0RuntimeFault(
            error.message,
            pc: error.pc ?? state.pc,
            functionId: state.program.functionId,
            code: error.code,
          )
        : error;
    state.profile?.count('diagnosticSourceMapLookup');
    _reportRuntimeFault(state, _boundedMessage(enriched.toString()));
    _dispose(state);
    state.completer.completeError(enriched, trace);
  }

  static void _reportRuntimeFault(_E0Continuation state, String message) {
    final callback = state.onRuntimeFault;
    if (callback == null) return;
    try {
      callback(message);
    } on Object {
      // Diagnostics must not prevent cleanup or settling the caller Future.
    }
  }

  static void _dispose(_E0Continuation state) {
    final callbackToken = state.resumeToken;
    state.timer?.cancel();
    state.timer = null;
    state.pending = false;
    state.resumeToken?.detach();
    state.resumeToken = null;
    state.stack.clear();
    state.locals.fillRange(0, state.locals.length, null);
    state.frames.clear();
    state._copyMemo?.clear();
    state._copyMemo = null;
    state._arguments = null;
    state._receiver = null;
    state._program = null;
    state._onRuntimeFault = null;
    lastRetentionSnapshot = E0AsyncRetentionDebugSnapshot(
      programRetained: state._program != null,
      argumentsRetained: state._arguments != null,
      receiverRetained: state._receiver != null,
      copyMemoEntries: state._copyMemo?.length ?? 0,
      stackEntries: state.stack.length,
      localEntries: state.locals.whereType<_RuntimeValue>().length,
      handlerFrames: state.frames.length,
      resumeTokenAttached: callbackToken?.state != null,
    );
    activeContinuations--;
  }
}

enum E0InvocationOutcome { success, guestThrow, runtimeFault }

final class E0InvocationResult {
  const E0InvocationResult._(this.outcome, this.value, this.guestThrow);

  static const E0InvocationResult failure = E0InvocationResult._(
    E0InvocationOutcome.runtimeFault,
    null,
    null,
  );

  factory E0InvocationResult.success(Object? value) =>
      E0InvocationResult._(E0InvocationOutcome.success, value, null);

  factory E0InvocationResult.thrown(E0GuestThrow guest) =>
      E0InvocationResult._(E0InvocationOutcome.guestThrow, null, guest);

  final E0InvocationOutcome outcome;
  final Object? value;
  final E0GuestThrow? guestThrow;

  bool get isSuccess => outcome == E0InvocationOutcome.success;
  bool get isGuestThrow => outcome == E0InvocationOutcome.guestThrow;
  bool get isRuntimeFault => outcome == E0InvocationOutcome.runtimeFault;

  Never rethrowGuest() {
    final guest = guestThrow;
    if (guest == null) {
      throw StateError('Invocation result does not contain a guest throw');
    }
    Error.throwWithStackTrace(guest.value, guest.trace);
  }
}

final class E0PatchRuntime {
  static E0CapabilityAuthority? _authority;
  static E0WidgetFactoryRegistry? _widgetFactories;
  static List<E0PatchProgram?> _slots = const [];
  static final Expando<int> _generations = Expando<int>('e0-generation');
  static int _nextGeneration = 1;
  static int _installedPatchSequence = 0;
  static String? _installedPayloadHash;
  static _PendingPatchInstall? _pendingCapabilities;
  static E0RuntimeDiagnosticSink? _diagnosticSink;
  static int patchedArgumentListAllocations = 0;
  static String? lastRejection;
  static bool _generatedIntegrationStarted = false;

  /// True after the generated Flutter integration bootstrap has been accepted
  /// for this isolate. This is an internal coordination marker for fixtures
  /// that also retain the archived manual E1 controller; it is not a patch
  /// admission or health signal.
  static bool get generatedIntegrationStarted => _generatedIntegrationStarted;

  /// Marks the generated integration bootstrap before it starts asynchronous
  /// controller work. Keeping this marker in the shared runtime lets an
  /// application-owned archival fixture avoid initializing a second
  /// controller against the same process-global registry.
  static void markGeneratedIntegrationStarted() {
    _generatedIntegrationStarted = true;
  }

  /// Registers release-owned logical function context for bounded diagnostics.
  /// Re-registering identical context is harmless; replacement is rejected so
  /// a patch cannot rewrite diagnostic provenance.
  static void configureFunctionContexts(
    Map<String, E0RuntimeFunctionContext> contexts,
  ) {
    E0RuntimeFunctionContexts.registerAll(contexts);
  }

  /// Installs the release-owned sink for already-sanitized runtime messages.
  /// The sink receives no raw exception object, path, URL, or credential.
  static void configureDiagnosticSink(E0RuntimeDiagnosticSink sink) {
    if (_diagnosticSink != null) return;
    _diagnosticSink = sink;
  }

  /// Selects the one immutable registry compiled and assembled by the host
  /// application. Reconfiguration clears active and pending downloaded code so
  /// capability authority cannot change underneath an invocation.
  static void configureCapabilities(E0CapabilityAuthority authority) {
    if (_authority != null) {
      throw StateError('Capability authority is already configured');
    }
    if (E0AsyncInterpreter.activeContinuations != 0) {
      throw StateError('Cannot configure authority with active continuations');
    }
    _authority = authority;
    _retryPendingCapabilities();
  }

  /// Selects the immutable, application-owned widget factory authority.
  /// Reconfiguration is rejected so downloaded code cannot swap constructors.
  static void configureWidgetFactories(E0WidgetFactoryRegistry factories) {
    if (_widgetFactories != null) {
      throw StateError('Widget factory registry is already configured');
    }
    _widgetFactories = factories;
    _retryPendingCapabilities();
  }

  static E0CapabilityAuthority _requireAuthority() =>
      _authority ??
      (throw StateError('Capability authority is not configured'));

  static E0PatchProgram? lookup(int slot) {
    if (slot < 0 || slot >= _slots.length) return null;
    return _slots[slot];
  }

  static E0InvocationResult invoke(
    E0PatchProgram program,
    List<Object?> arguments, {
    Map<String, Object?> namedArguments = const <String, Object?>{},
    E0ReceiverCapability? receiver,
  }) {
    patchedArgumentListAllocations++;
    var capabilityStarted = false;
    try {
      return E0InvocationResult.success(
        E0Interpreter.executeValues(
          program,
          arguments,
          namedArguments: namedArguments,
          receiver: receiver,
          authority: program.capabilities.isEmpty ? null : _requireAuthority(),
          onCapabilityStarted: () => capabilityStarted = true,
        ),
      );
    } on E0GuestThrow catch (guest) {
      return E0InvocationResult.thrown(guest);
    } on StackOverflowError {
      _disableIfCurrent(program, 'Fatal interpreter failure');
      rethrow;
    } on OutOfMemoryError {
      _disableIfCurrent(program, 'Fatal interpreter failure');
      rethrow;
    } on E0RuntimeFault catch (error) {
      if (capabilityStarted) {
        _disableIfCurrent(
          program,
          _boundedMessage(error.toString()),
          fault: error,
        );
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      _disableIfCurrent(
        program,
        _boundedMessage(error.toString()),
        fault: error,
      );
      return E0InvocationResult.failure;
    } on Object catch (error) {
      if (capabilityStarted) {
        _disableIfCurrent(program, 'Capability runtime failure');
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      final fault = E0RuntimeFault(
        _boundedMessage(error.toString()),
        functionId: program.functionId,
      );
      _disableIfCurrent(
        program,
        _boundedMessage(error.toString()),
        fault: fault,
      );
      return E0InvocationResult.failure;
    }
  }

  static E0InvocationResult invokeWidget<T extends Object>(
    E0PatchProgram program,
    List<Object?> arguments, {
    E0ReceiverCapability? receiver,
  }) {
    final result = invoke(program, arguments, receiver: receiver);
    if (!result.isSuccess) return result;
    try {
      final registry =
          _widgetFactories ??
          (throw StateError('Widget factory registry is not configured'));
      registry.requireContracts(program.widgetFactories);
      final materialized = registry.materialize<T>(
        result.value,
        allowedFactoryIds: Set.unmodifiable(
          program.widgetFactories.map((factory) => factory.id).toSet(),
        ),
      );
      return E0InvocationResult.success(materialized);
    } on StackOverflowError {
      _disableIfCurrent(program, 'Fatal widget materialization failure');
      rethrow;
    } on OutOfMemoryError {
      _disableIfCurrent(program, 'Fatal widget materialization failure');
      rethrow;
    } on Object catch (error) {
      _disableIfCurrent(program, _boundedMessage(error.toString()));
      return E0InvocationResult.failure;
    }
  }

  static Future<T>? invokeAsync<T>(
    E0PatchProgram program,
    List<Object?> arguments, {
    Map<String, Object?> namedArguments = const <String, Object?>{},
    E0ReceiverCapability? receiver,
    int instructionBudget = E0AsyncInterpreter.defaultInstructionBudget,
    int maxResumes = E0AsyncInterpreter.defaultMaxResumes,
    Duration deadline = E0AsyncInterpreter.defaultDeadline,
    E0RuntimeLimits limits = E0RuntimeLimits.defaults,
  }) {
    patchedArgumentListAllocations++;
    try {
      final future = E0AsyncInterpreter.execute(
        program,
        arguments,
        namedArguments: namedArguments,
        receiver: receiver,
        generation: _generations[program] ?? 0,
        instructionBudget: instructionBudget,
        maxResumes: maxResumes,
        deadline: deadline,
        limits: limits,
        onRuntimeFault: (message) => _disableIfCurrent(program, message),
        authority: program.capabilities.isEmpty ? null : _requireAuthority(),
      );
      return future.then<T>((value) => value as T);
    } on StackOverflowError {
      _disableIfCurrent(program, 'Fatal async initialization failure');
      rethrow;
    } on OutOfMemoryError {
      _disableIfCurrent(program, 'Fatal async initialization failure');
      rethrow;
    } on Object catch (error) {
      // No host capability has started when initialization throws. The
      // generated guard may safely use the original AOT body.
      _disableIfCurrent(program, _boundedMessage(error.toString()));
      return null;
    }
  }

  static void _disableIfCurrent(
    E0PatchProgram program,
    String message, {
    E0RuntimeFault? fault,
  }) {
    if (program.slot >= 0 &&
        program.slot < _slots.length &&
        identical(_slots[program.slot], program)) {
      final replacement = List<E0PatchProgram?>.of(_slots);
      replacement[program.slot] = null;
      _slots = List.unmodifiable(replacement);
    }
    lastRejection = _boundedMessage(message);
    if (fault != null) _reportRuntimeDiagnostic(fault);
  }

  static void _reportRuntimeDiagnostic(E0RuntimeFault fault) {
    final sink = _diagnosticSink;
    if (sink == null) return;
    try {
      sink(_boundedMessage(fault.toString()));
    } on Object {
      // Diagnostics are best effort and must never alter AOT fallback.
    }
  }

  static int? invokeInt2(E0PatchProgram program, int a, int b) {
    final result = invoke(program, <Object?>[a, b]);
    if (result.isGuestThrow) result.rethrowGuest();
    if (!result.isSuccess) return null;
    final value = result.value;
    if (value is! int) {
      _disableIfCurrent(
        program,
        'Patch returned ${value.runtimeType}, expected int',
      );
      return null;
    }
    return value;
  }

  static bool installBytes(
    List<int> bytes, {
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    Map<String, String> signatures = const {},
    Map<String, String> receivers = const {},
  }) {
    try {
      final decodedSignatures = <String, E0FunctionSignature>{
        for (final entry in signatures.entries)
          entry.key: E0FunctionSignature.decode(entry.value),
      };
      final decodedReceivers = <String, E0ReceiverDescriptor>{
        for (final entry in receivers.entries)
          entry.key: E0ReceiverDescriptor.decode(entry.value),
      };
      final program = E0PatchContainer.decode(
        bytes,
        expectedAppId: appId,
        expectedReleaseId: releaseId,
        expectedBuildFingerprint: buildFingerprint,
        expectedFunctions: functions,
        expectedSignatures: decodedSignatures,
        expectedReceivers: decodedReceivers,
      );
      if (program.slot >= functions.length) {
        throw const FormatException('Patch slot exceeds release table');
      }
      if (program.patchSequence < _installedPatchSequence) {
        throw const FormatException('Patch sequence is stale');
      }
      if (program.patchSequence == _installedPatchSequence) {
        if (program.payloadHash != _installedPayloadHash) {
          throw const FormatException('Patch sequence equivocation detected');
        }
        lastRejection = null;
        return true;
      }
      for (final capability in program.capabilities) {
        _requireAuthority()._require(capability);
      }
      if (program.signature == e0WidgetBuildSignature) {
        final factories =
            _widgetFactories ??
            (throw StateError('Widget factory registry is not configured'));
        factories.requireContracts(program.widgetFactories);
        _requireStaticallyReferencedWidgetFactories(program, factories);
      } else if (program.widgetFactories.isNotEmpty) {
        throw const FormatException(
          'Widget factories require the widget-build ABI signature',
        );
      }
      final slots = List<E0PatchProgram?>.filled(functions.length, null);
      slots[program.slot] = program;
      _generations[program] = _nextGeneration++;
      _slots = slots;
      _installedPatchSequence = program.patchSequence;
      _installedPayloadHash = program.payloadHash;
      lastRejection = null;
      return true;
    } on Object catch (error) {
      lastRejection = _boundedMessage(error.toString());
      return false;
    }
  }

  /// Atomically installs the cumulative function set carried by one v1
  /// bridge artifact. The ordinary E0 API intentionally remains single
  /// program for the archived experiments; this batch seam prevents a
  /// multi-function Patch Format artifact from exposing a partially updated
  /// slot table or from treating each function as a new sequence.
  static bool installBatchBytes(
    List<List<int>> bytePrograms, {
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    Map<String, String> signatures = const {},
    Map<String, String> receivers = const {},
  }) {
    try {
      if (bytePrograms.isEmpty) {
        throw const FormatException('Patch batch is empty');
      }
      final decodedSignatures = <String, E0FunctionSignature>{
        for (final entry in signatures.entries)
          entry.key: E0FunctionSignature.decode(entry.value),
      };
      final decodedReceivers = <String, E0ReceiverDescriptor>{
        for (final entry in receivers.entries)
          entry.key: E0ReceiverDescriptor.decode(entry.value),
      };
      final programs = <E0PatchProgram>[
        for (final bytes in bytePrograms)
          E0PatchContainer.decode(
            bytes,
            expectedAppId: appId,
            expectedReleaseId: releaseId,
            expectedBuildFingerprint: buildFingerprint,
            expectedFunctions: functions,
            expectedSignatures: decodedSignatures,
            expectedReceivers: decodedReceivers,
          ),
      ];
      final sequence = programs.first.patchSequence;
      if (programs.any((program) => program.patchSequence != sequence)) {
        throw const FormatException('Patch batch contains mixed sequences');
      }
      final ids = <String>{};
      final slots = <int>{};
      for (final program in programs) {
        if (!ids.add(program.functionId) || !slots.add(program.slot)) {
          throw const FormatException(
            'Patch batch contains duplicate functions',
          );
        }
        if (program.slot >= functions.length) {
          throw const FormatException('Patch slot exceeds release table');
        }
      }
      if (sequence < _installedPatchSequence) {
        throw const FormatException('Patch sequence is stale');
      }
      final payloadHash = sha256
          .convert(
            utf8.encode(
              (programs.toList()..sort(
                    (left, right) =>
                        left.functionId.compareTo(right.functionId),
                  ))
                  .map((program) => program.payloadHash)
                  .join('\u0000'),
            ),
          )
          .toString();
      if (sequence == _installedPatchSequence) {
        if (payloadHash != _installedPayloadHash) {
          throw const FormatException('Patch sequence equivocation detected');
        }
        lastRejection = null;
        return true;
      }
      for (final program in programs) {
        for (final capability in program.capabilities) {
          _requireAuthority()._require(capability);
        }
        if (program.signature == e0WidgetBuildSignature) {
          final factories =
              _widgetFactories ??
              (throw StateError('Widget factory registry is not configured'));
          factories.requireContracts(program.widgetFactories);
          _requireStaticallyReferencedWidgetFactories(program, factories);
        } else if (program.widgetFactories.isNotEmpty) {
          throw const FormatException(
            'Widget factories require the widget-build ABI signature',
          );
        }
      }
      final nextSlots = List<E0PatchProgram?>.filled(functions.length, null);
      for (final program in programs) {
        _generations[program] = _nextGeneration++;
        nextSlots[program.slot] = program;
      }
      _slots = List.unmodifiable(nextSlots);
      _installedPatchSequence = sequence;
      _installedPayloadHash = payloadHash;
      lastRejection = null;
      return true;
    } on Object catch (error) {
      lastRejection = _boundedMessage(error.toString());
      return false;
    }
  }

  static void installFromArguments(
    List<String> arguments, {
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    required Map<String, int> functions,
    Map<String, String> signatures = const {},
    Map<String, String> receivers = const {},
  }) {
    const prefix = '--e0-patch=';
    final paths = arguments.where((value) => value.startsWith(prefix)).toList();
    if (paths.length != 1) return;
    try {
      final bytes = File(paths.single.substring(prefix.length))
          .readAsBytesSync();
      final installed = installBytes(
        bytes,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
      );
      if (!installed && (_authority == null || _widgetFactories == null)) {
        _pendingCapabilities = _PendingPatchInstall(
          bytes,
          appId,
          releaseId,
          buildFingerprint,
          Map.unmodifiable(functions),
          Map.unmodifiable(signatures),
          Map.unmodifiable(receivers),
        );
      }
    } on Object catch (error) {
      lastRejection = _boundedMessage(error.toString());
    }
  }

  static void reset() {
    if (E0AsyncInterpreter.activeContinuations != 0) {
      throw StateError('Cannot reset runtime with active continuations');
    }
    _slots = const [];
    patchedArgumentListAllocations = 0;
    lastRejection = null;
    E0AsyncInterpreter.resetDebugState();
    _pendingCapabilities = null;
    _installedPatchSequence = 0;
    _installedPayloadHash = null;
    _authority = null;
    _widgetFactories = null;
    E0RuntimeSourceMaps.clear();
    E0RuntimeFunctionContexts.clear();
    _diagnosticSink = null;
    // This is bootstrap coordination state, not guest/runtime state. It must
    // survive the controller reset that follows generated integration start;
    // otherwise an archival fixture can race into a second controller before
    // the generated controller finishes its asynchronous initialization.
  }

  static void _requireStaticallyReferencedWidgetFactories(
    E0PatchProgram program,
    E0WidgetFactoryRegistry registry,
  ) {
    final declared = program.widgetFactories
        .map((factory) => factory.id)
        .toSet();
    var pc = 0;
    while (pc < program.code.length) {
      final opcode = E0Opcode.fromCode(program.code[pc])!;
      if (opcode == E0Opcode.loadConstant &&
          pc + opcode.width < program.code.length) {
        final key = program.constants[program.code[pc + 1]];
        final nextOpcode = E0Opcode.fromCode(program.code[pc + opcode.width]);
        if (key.schema == E0ValueSchema.string &&
            key.toHost(E0ValueSchema.string) == 'factory' &&
            nextOpcode == E0Opcode.loadConstant) {
          final factory =
              program.constants[program.code[pc + opcode.width + 1]];
          if (factory.schema == E0ValueSchema.string) {
            final id = factory.toHost(E0ValueSchema.string)! as String;
            if (registry.containsFactoryId(id) && !declared.contains(id)) {
              throw FormatException(
                'Widget factory $id is referenced but undeclared',
              );
            }
          }
        }
      }
      pc += opcode.width;
    }
  }

  static void _retryPendingCapabilities() {
    final pending = _pendingCapabilities;
    if (pending == null) return;
    if (installBytes(
      pending.bytes,
      appId: pending.appId,
      releaseId: pending.releaseId,
      buildFingerprint: pending.buildFingerprint,
      functions: pending.functions,
      signatures: pending.signatures,
      receivers: pending.receivers,
    )) {
      _pendingCapabilities = null;
    }
  }
}

final class _PendingPatchInstall {
  const _PendingPatchInstall(
    this.bytes,
    this.appId,
    this.releaseId,
    this.buildFingerprint,
    this.functions,
    this.signatures,
    this.receivers,
  );

  final List<int> bytes;
  final String appId;
  final String releaseId;
  final String buildFingerprint;
  final Map<String, int> functions;
  final Map<String, String> signatures;
  final Map<String, String> receivers;
}
