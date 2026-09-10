import 'dart:convert';
import 'dart:typed_data';

enum E0ValueKind {
  nullValue('null'),
  boolean('bool'),
  integer('int'),
  doubleValue('double'),
  string('String'),
  list('List'),
  set('Set'),
  map('Map'),
  closure('Closure'),
  supportedValue('value');

  const E0ValueKind(this.wireName);

  final String wireName;

  static E0ValueKind fromWireName(String name) => values.singleWhere(
    (value) => value.wireName == name,
    orElse: () => throw FormatException('Unsupported value kind $name'),
  );
}

final class E0ValueSchema {
  const E0ValueSchema._(this.kind, {this.nullable = false, this.closureIndex})
    : elementSchema = null,
      mapValueSchema = null;

  static const E0ValueSchema nullValue = E0ValueSchema._(
    E0ValueKind.nullValue,
    nullable: true,
  );
  static const E0ValueSchema boolean = E0ValueSchema._(E0ValueKind.boolean);
  static const E0ValueSchema integer = E0ValueSchema._(E0ValueKind.integer);
  static const E0ValueSchema doubleValue = E0ValueSchema._(
    E0ValueKind.doubleValue,
  );
  static const E0ValueSchema string = E0ValueSchema._(E0ValueKind.string);
  static const E0ValueSchema supportedValue = E0ValueSchema._(
    E0ValueKind.supportedValue,
    nullable: true,
  );

  const E0ValueSchema.closure(int index)
    : this._(E0ValueKind.closure, closureIndex: index);

  const E0ValueSchema.list(
    E0ValueSchema this.elementSchema, {
    this.nullable = false,
  }) : kind = E0ValueKind.list,
       mapValueSchema = null,
       closureIndex = null;

  const E0ValueSchema.set(
    E0ValueSchema this.elementSchema, {
    this.nullable = false,
  }) : kind = E0ValueKind.set,
       mapValueSchema = null,
       closureIndex = null;

  const E0ValueSchema.map(
    E0ValueSchema this.mapValueSchema, {
    this.nullable = false,
  }) : kind = E0ValueKind.map,
       elementSchema = null,
       closureIndex = null;

  final E0ValueKind kind;
  final bool nullable;
  final E0ValueSchema? elementSchema;
  final E0ValueSchema? mapValueSchema;
  final int? closureIndex;

  E0ValueSchema asNullable() {
    if (nullable) return this;
    return switch (kind) {
      E0ValueKind.list => E0ValueSchema.list(elementSchema!, nullable: true),
      E0ValueKind.set => E0ValueSchema.set(elementSchema!, nullable: true),
      E0ValueKind.map => E0ValueSchema.map(mapValueSchema!, nullable: true),
      E0ValueKind.closure => E0ValueSchema._(
        E0ValueKind.closure,
        nullable: true,
        closureIndex: closureIndex,
      ),
      _ => E0ValueSchema._(kind, nullable: true),
    };
  }

  bool accepts(E0ValueSchema actual) {
    if (actual.kind == E0ValueKind.nullValue) return nullable;
    if (kind == E0ValueKind.supportedValue) return true;
    // `supportedValue` is a bounded runtime-checked union, not Dart `dynamic`.
    // Accept it statically so empty/heterogeneous collection construction can
    // flow to an explicit return schema; `toHost` validates every node again.
    if (actual.kind == E0ValueKind.supportedValue) return true;
    if (kind != actual.kind) return false;
    return switch (kind) {
      E0ValueKind.list ||
      E0ValueKind.set => elementSchema!.accepts(actual.elementSchema!),
      E0ValueKind.map => mapValueSchema!.accepts(actual.mapValueSchema!),
      E0ValueKind.closure => closureIndex == actual.closureIndex,
      _ => true,
    };
  }

  bool get isSupportedHostSignature {
    if (kind == E0ValueKind.supportedValue || kind == E0ValueKind.nullValue) {
      return false;
    }
    if (kind == E0ValueKind.list || kind == E0ValueKind.set) {
      return _isScalar(elementSchema!);
    }
    if (kind == E0ValueKind.map) {
      return mapValueSchema!.kind == E0ValueKind.supportedValue ||
          _isScalar(mapValueSchema!);
    }
    return true;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wireName,
    'nullable': nullable,
    if (elementSchema != null) 'element': elementSchema!.toJson(),
    if (mapValueSchema != null) 'value': mapValueSchema!.toJson(),
    if (kind == E0ValueKind.closure) 'closure': closureIndex,
  };

  static E0ValueSchema fromJson(Map<String, Object?> json) {
    return _fromJson(json, 0);
  }

  static E0ValueSchema _fromJson(Map<String, Object?> json, int depth) {
    if (depth > E0ValueCodec.maxNestingDepth) {
      throw const FormatException('Schema nesting limit exceeded');
    }
    final kindValue = json['kind'];
    final nullableValue = json['nullable'];
    if (kindValue is! String || nullableValue is! bool) {
      throw const FormatException('Invalid value schema');
    }
    final kind = E0ValueKind.fromWireName(kindValue);
    final expectedKeys = switch (kind) {
      E0ValueKind.list ||
      E0ValueKind.set => const <String>{'kind', 'nullable', 'element'},
      E0ValueKind.map => const <String>{'kind', 'nullable', 'value'},
      E0ValueKind.closure => const <String>{'kind', 'nullable', 'closure'},
      _ => const <String>{'kind', 'nullable'},
    };
    if (!_hasExactKeys(json, expectedKeys)) {
      throw FormatException('Invalid ${kind.wireName} schema fields');
    }
    if (kind == E0ValueKind.nullValue && !nullableValue) {
      throw const FormatException('Null schema must be nullable');
    }
    if (kind == E0ValueKind.supportedValue && !nullableValue) {
      throw const FormatException('Supported-value schema must include null');
    }
    if (kind == E0ValueKind.closure) {
      final index = json['closure'];
      if (index is! int || index < 0) {
        throw const FormatException(
          'Closure schema must contain a valid index',
        );
      }
      return E0ValueSchema._(
        E0ValueKind.closure,
        nullable: nullableValue,
        closureIndex: index,
      );
    }
    if (kind == E0ValueKind.list) {
      return E0ValueSchema.list(
        _nestedSchema(json['element'], depth + 1),
        nullable: nullableValue,
      );
    }
    if (kind == E0ValueKind.set) {
      return E0ValueSchema.set(
        _nestedSchema(json['element'], depth + 1),
        nullable: nullableValue,
      );
    }
    if (kind == E0ValueKind.map) {
      return E0ValueSchema.map(
        _nestedSchema(json['value'], depth + 1),
        nullable: nullableValue,
      );
    }
    return E0ValueSchema._(kind, nullable: nullableValue);
  }

  static E0ValueSchema parseDartType(String source) {
    final parser = _DartTypeParser(source.replaceAll(RegExp(r'\s+'), ''));
    final result = parser.parse();
    if (!parser.isAtEnd) {
      throw FormatException('Unsupported Dart type $source');
    }
    return result;
  }

  String toDartSource() {
    final base = switch (kind) {
      E0ValueKind.nullValue => 'Null',
      E0ValueKind.boolean => 'bool',
      E0ValueKind.integer => 'int',
      E0ValueKind.doubleValue => 'double',
      E0ValueKind.string => 'String',
      E0ValueKind.list => 'List<${elementSchema!.toDartSource()}>',
      E0ValueKind.set => 'Set<${elementSchema!.toDartSource()}>',
      E0ValueKind.map => 'Map<String, ${mapValueSchema!.toDartSource()}>',
      E0ValueKind.closure => 'Closure',
      E0ValueKind.supportedValue => 'dynamic',
    };
    return nullable &&
            kind != E0ValueKind.nullValue &&
            kind != E0ValueKind.supportedValue &&
            kind != E0ValueKind.closure
        ? '$base?'
        : base;
  }

  @override
  bool operator ==(Object other) =>
      other is E0ValueSchema &&
      kind == other.kind &&
      nullable == other.nullable &&
      elementSchema == other.elementSchema &&
      mapValueSchema == other.mapValueSchema &&
      closureIndex == other.closureIndex;

  @override
  int get hashCode =>
      Object.hash(kind, nullable, elementSchema, mapValueSchema, closureIndex);

  @override
  String toString() => toDartSource();

  static E0ValueSchema _nestedSchema(Object? value, int depth) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid nested value schema');
    }
    return _fromJson(value, depth);
  }

  static bool _isScalar(E0ValueSchema schema) => switch (schema.kind) {
    E0ValueKind.boolean ||
    E0ValueKind.integer ||
    E0ValueKind.doubleValue ||
    E0ValueKind.string => true,
    _ => false,
  };
}

enum E0ParameterKind {
  requiredPositional,
  optionalPositional,
  requiredNamed,
  optionalNamed,
}

final class E0ParameterDescriptor {
  const E0ParameterDescriptor({
    required this.name,
    required this.schema,
    required this.kind,
    this.hasDefault = false,
    this.defaultValue,
  });

  final String name;
  final E0ValueSchema schema;
  final E0ParameterKind kind;
  final bool hasDefault;
  final Object? defaultValue;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'schema': schema.toJson(),
    'kind': kind.name,
    'hasDefault': hasDefault,
    'default': hasDefault ? E0Value.infer(defaultValue).toJson() : null,
  };

  static E0ParameterDescriptor fromJson(Map<String, Object?> json) {
    if (!_hasExactKeys(json, const <String>{
      'name',
      'schema',
      'kind',
      'hasDefault',
      'default',
    })) {
      throw const FormatException('Invalid parameter descriptor fields');
    }
    final rawKind = json['kind'];
    if (json['name'] is! String ||
        (json['name']! as String).isEmpty ||
        json['schema'] is! Map<String, Object?> ||
        rawKind is! String ||
        json['hasDefault'] is! bool) {
      throw const FormatException('Invalid parameter descriptor');
    }
    final kind = E0ParameterKind.values
        .where((value) => value.name == rawKind)
        .firstOrNull;
    if (kind == null) throw const FormatException('Unknown parameter kind');
    final hasDefault = json['hasDefault']! as bool;
    final rawDefault = json['default'];
    if (!hasDefault && rawDefault != null) {
      throw const FormatException('Unexpected parameter default');
    }
    Object? defaultValue;
    if (hasDefault) {
      if (rawDefault is! Map<String, Object?>) {
        throw const FormatException('Invalid parameter default');
      }
      final encoded = E0Value.fromJson(rawDefault);
      defaultValue = encoded.toHost(encoded.schema);
    }
    return E0ParameterDescriptor(
      name: json['name']! as String,
      schema: E0ValueSchema.fromJson(json['schema']! as Map<String, Object?>),
      kind: kind,
      hasDefault: hasDefault,
      defaultValue: defaultValue,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is E0ParameterDescriptor &&
      name == other.name &&
      schema == other.schema &&
      kind == other.kind &&
      hasDefault == other.hasDefault &&
      (!hasDefault ||
          E0Value.infer(defaultValue) == E0Value.infer(other.defaultValue));

  @override
  int get hashCode => Object.hash(
    name,
    schema,
    kind,
    hasDefault,
    hasDefault ? E0Value.infer(defaultValue) : null,
  );
}

final class E0FunctionSignature {
  const E0FunctionSignature({
    required this.parameters,
    required this.returnSchema,
    this.isAsync = false,
    this.parameterDetails = const <E0ParameterDescriptor>[],
  });

  static const E0FunctionSignature legacyInt2 = E0FunctionSignature(
    parameters: <E0ValueSchema>[E0ValueSchema.integer, E0ValueSchema.integer],
    returnSchema: E0ValueSchema.integer,
  );

  final List<E0ValueSchema> parameters;
  final E0ValueSchema returnSchema;

  /// When true, [returnSchema] is the element type of `Future<T>`.
  final bool isAsync;

  /// Empty for the original required-positional protocol. When present, the
  /// list is in declaration order and carries names, optionality, and defaults.
  final List<E0ParameterDescriptor> parameterDetails;

  List<E0ParameterDescriptor> get descriptors => parameterDetails.isEmpty
      ? List<E0ParameterDescriptor>.generate(
          parameters.length,
          (index) => E0ParameterDescriptor(
            name: 'p$index',
            schema: parameters[index],
            kind: E0ParameterKind.requiredPositional,
          ),
        )
      : parameterDetails;

  Map<String, Object?> toJson() => <String, Object?>{
    'parameters': parameters.map((schema) => schema.toJson()).toList(),
    'return': returnSchema.toJson(),
    'async': isAsync,
    if (parameterDetails.isNotEmpty)
      'parameterDetails': parameterDetails
          .map((item) => item.toJson())
          .toList(),
  };

  String encode() => jsonEncode(toJson());

  static E0FunctionSignature decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Function signature must be an object');
    }
    return fromJson(value);
  }

  static E0FunctionSignature fromJson(Map<String, Object?> json) {
    final baseKeys = const <String>{'parameters', 'return', 'async'};
    final detailKeys = <String>{...baseKeys, 'parameterDetails'};
    if (!_hasExactKeys(json, baseKeys) && !_hasExactKeys(json, detailKeys)) {
      throw const FormatException('Invalid function signature fields');
    }
    final parameterValues = json['parameters'];
    final returnValue = json['return'];
    final asyncValue = json['async'];
    if (parameterValues is! List<Object?> || parameterValues.length > 16) {
      throw const FormatException('Invalid function parameter schemas');
    }
    if (returnValue is! Map<String, Object?> || asyncValue is! bool) {
      throw const FormatException('Invalid return schema');
    }
    final parameters = parameterValues
        .map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Invalid parameter schema');
          }
          return E0ValueSchema.fromJson(value);
        })
        .toList(growable: false);
    final details = <E0ParameterDescriptor>[];
    if (json.containsKey('parameterDetails')) {
      final rawDetails = json['parameterDetails'];
      if (rawDetails is! List<Object?> ||
          rawDetails.length != parameters.length) {
        throw const FormatException('Invalid parameter descriptor count');
      }
      for (final value in rawDetails) {
        if (value is! Map<String, Object?>) {
          throw const FormatException('Invalid parameter descriptor');
        }
        details.add(E0ParameterDescriptor.fromJson(value));
      }
      _validateParameterDetails(parameters, details);
    }
    return E0FunctionSignature(
      parameters: List.unmodifiable(parameters),
      returnSchema: E0ValueSchema.fromJson(returnValue),
      isAsync: asyncValue,
      parameterDetails: List.unmodifiable(details),
    );
  }

  /// Validates the optional parameter metadata before it crosses a runtime
  /// or persistence boundary.
  void validate() {
    if (parameterDetails.isNotEmpty) {
      _validateParameterDetails(parameters, parameterDetails);
    }
  }

  List<Object?> bindArguments(
    List<Object?> positional, {
    Map<String, Object?> named = const <String, Object?>{},
  }) {
    if (parameterDetails.isEmpty) {
      if (named.isNotEmpty || positional.length != parameters.length) {
        throw const FormatException('Argument shape does not match signature');
      }
      return List<Object?>.unmodifiable(positional);
    }
    final result = List<Object?>.filled(parameterDetails.length, _missing);
    var positionalIndex = 0;
    final consumedNames = <String>{};
    for (var index = 0; index < parameterDetails.length; index++) {
      final parameter = parameterDetails[index];
      Object? value = _missing;
      if (parameter.kind == E0ParameterKind.requiredPositional ||
          parameter.kind == E0ParameterKind.optionalPositional) {
        if (positionalIndex < positional.length) {
          value = positional[positionalIndex++];
        }
      } else if (named.containsKey(parameter.name)) {
        value = named[parameter.name];
        consumedNames.add(parameter.name);
      }
      if (identical(value, _missing)) {
        if (parameter.kind == E0ParameterKind.requiredPositional ||
            parameter.kind == E0ParameterKind.requiredNamed) {
          throw FormatException('Missing required parameter ${parameter.name}');
        }
        value = parameter.hasDefault ? parameter.defaultValue : null;
      }
      result[index] = value;
    }
    if (positionalIndex != positional.length ||
        named.keys.any((name) => !consumedNames.contains(name))) {
      throw const FormatException('Unknown or excessive function argument');
    }
    return List<Object?>.unmodifiable(result);
  }

  @override
  bool operator ==(Object other) {
    if (other is! E0FunctionSignature ||
        returnSchema != other.returnSchema ||
        isAsync != other.isAsync ||
        parameters.length != other.parameters.length ||
        parameterDetails.length != other.parameterDetails.length) {
      return false;
    }
    for (var index = 0; index < parameters.length; index++) {
      if (parameters[index] != other.parameters[index]) return false;
    }
    for (var index = 0; index < parameterDetails.length; index++) {
      if (parameterDetails[index] != other.parameterDetails[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    ...parameters,
    ...parameterDetails,
    returnSchema,
    isAsync,
  ]);

  @override
  String toString() =>
      '${isAsync ? 'Future<${returnSchema.toDartSource()}>' : returnSchema.toDartSource()} Function('
      '${(parameterDetails.isEmpty ? parameters.map((schema) => schema.toDartSource()) : parameterDetails.map(_parameterSource)).join(', ')})';
}

String _parameterSource(E0ParameterDescriptor parameter) {
  final type = parameter.schema.toDartSource();
  final source = switch (parameter.kind) {
    E0ParameterKind.requiredPositional => '$type ${parameter.name}',
    E0ParameterKind.optionalPositional => '$type ${parameter.name}',
    E0ParameterKind.requiredNamed => 'required $type ${parameter.name}',
    E0ParameterKind.optionalNamed => '$type ${parameter.name}',
  };
  return parameter.hasDefault &&
          (parameter.kind == E0ParameterKind.optionalPositional ||
              parameter.kind == E0ParameterKind.optionalNamed)
      ? '$source = ${parameter.defaultValue}'
      : source;
}

const Object _missing = Object();

void _validateParameterDetails(
  List<E0ValueSchema> parameters,
  List<E0ParameterDescriptor> details,
) {
  if (parameters.length != details.length) {
    throw const FormatException('Parameter metadata does not match schemas');
  }
  final names = <String>{};
  var seenOptionalPositional = false;
  var seenNamed = false;
  for (var index = 0; index < details.length; index++) {
    final parameter = details[index];
    if (!names.add(parameter.name) || parameter.schema != parameters[index]) {
      throw const FormatException('Invalid parameter metadata');
    }
    if (parameter.kind == E0ParameterKind.optionalPositional) {
      seenOptionalPositional = true;
    }
    if (parameter.kind == E0ParameterKind.requiredNamed ||
        parameter.kind == E0ParameterKind.optionalNamed) {
      seenNamed = true;
    }
    if (seenOptionalPositional &&
        parameter.kind == E0ParameterKind.requiredPositional) {
      throw const FormatException(
        'Required positional parameter follows optional positional',
      );
    }
    if (seenNamed &&
        (parameter.kind == E0ParameterKind.requiredPositional ||
            parameter.kind == E0ParameterKind.optionalPositional)) {
      throw const FormatException(
        'Positional parameter follows named parameter',
      );
    }
    if ((parameter.kind == E0ParameterKind.requiredPositional ||
            parameter.kind == E0ParameterKind.requiredNamed) &&
        parameter.hasDefault) {
      throw const FormatException('Required parameter cannot have a default');
    }
    if (parameter.hasDefault) {
      E0Value.fromHost(parameter.defaultValue, parameter.schema);
    }
  }
}

final class E0Value {
  const E0Value._(this.schema, this._value);

  final E0ValueSchema schema;
  final Object? _value;

  static E0Value fromHost(Object? value, E0ValueSchema expected) {
    final budget = _ValueBudget();
    final normalized = _normalize(value, expected, budget, r'$');
    final actual = value == null ? E0ValueSchema.nullValue : expected;
    return E0Value._(actual, normalized);
  }

  static E0Value infer(Object? value) {
    final schema = _inferSchema(value, _ValueBudget(), r'$');
    return fromHost(value, schema);
  }

  Object? toHost(E0ValueSchema expected) {
    if (!expected.accepts(schema)) {
      throw FormatException('Value $schema does not match $expected');
    }
    _normalize(_value, expected, _ValueBudget(), r'$');
    return _typedCopy(_value, expected);
  }

  Map<String, Object?> toJson() => _encodeValue(_value, _ValueBudget(), r'$');

  static E0Value fromJson(Object? json) {
    final decoded = _decodeValue(json, _ValueBudget(), r'$');
    return infer(decoded);
  }

  @override
  bool operator ==(Object other) =>
      other is E0Value &&
      schema == other.schema &&
      _deepEquals(_value, other._value);

  @override
  int get hashCode => Object.hash(schema, jsonEncode(toJson()));

  @override
  String toString() => jsonEncode(toJson());
}

final class E0ValueCodec {
  static const int maxNestingDepth = 16;
  static const int maxCollectionEntries = 1024;
  static const int maxValueNodes = 4096;
  static const int maxStringBytes = 64 * 1024;
  static const int maxEncodedBytes = 64 * 1024;

  static Uint8List encode(E0Value value) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value.toJson())));
    if (bytes.length > maxEncodedBytes) {
      throw const FormatException('Encoded value exceeds byte limit');
    }
    return bytes;
  }

  static E0Value decode(List<int> bytes) {
    if (bytes.length > maxEncodedBytes) {
      throw const FormatException('Encoded value exceeds byte limit');
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Value is not strict UTF-8 JSON');
    }
    return E0Value.fromJson(json);
  }

  static Uint8List encodeArguments(
    List<Object?> arguments,
    List<E0ValueSchema> schemas,
  ) {
    if (arguments.length != schemas.length) {
      throw const FormatException('Argument count does not match signature');
    }
    final values = <Object?>[];
    for (var index = 0; index < arguments.length; index++) {
      values.add(E0Value.fromHost(arguments[index], schemas[index]).toJson());
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(values)));
    if (bytes.length > maxEncodedBytes) {
      throw const FormatException('Encoded arguments exceed byte limit');
    }
    return bytes;
  }
}

final class _DartTypeParser {
  _DartTypeParser(this.source);

  final String source;
  int offset = 0;

  bool get isAtEnd => offset == source.length;

  E0ValueSchema parse([int depth = 0]) {
    if (depth > E0ValueCodec.maxNestingDepth) {
      throw const FormatException('Dart type nesting limit exceeded');
    }
    final name = _identifier();
    E0ValueSchema schema;
    if (name == 'List') {
      _expect('<');
      final element = parse(depth + 1);
      _expect('>');
      schema = E0ValueSchema.list(element);
    } else if (name == 'Set') {
      _expect('<');
      final element = parse(depth + 1);
      _expect('>');
      schema = E0ValueSchema.set(element);
    } else if (name == 'Map') {
      _expect('<');
      if (_identifier() != 'String') {
        throw const FormatException('Only String map keys are supported');
      }
      _expect(',');
      final value = parse(depth + 1);
      _expect('>');
      schema = E0ValueSchema.map(value);
    } else {
      schema = switch (name) {
        'Null' => E0ValueSchema.nullValue,
        'bool' => E0ValueSchema.boolean,
        'int' => E0ValueSchema.integer,
        'double' => E0ValueSchema.doubleValue,
        'String' => E0ValueSchema.string,
        'dynamic' => E0ValueSchema.supportedValue,
        _ => throw FormatException('Unsupported Dart type $name'),
      };
    }
    if (offset < source.length && source[offset] == '?') {
      offset++;
      schema = schema.asNullable();
    }
    return schema;
  }

  String _identifier() {
    final start = offset;
    while (offset < source.length &&
        RegExp(r'[A-Za-z]').hasMatch(source[offset])) {
      offset++;
    }
    if (start == offset) throw FormatException('Expected type at $offset');
    return source.substring(start, offset);
  }

  void _expect(String token) {
    if (offset >= source.length || source[offset] != token) {
      throw FormatException('Expected $token at $offset');
    }
    offset++;
  }
}

final class _ValueBudget {
  int nodes = 0;

  void consume(int depth, String path) {
    if (depth > E0ValueCodec.maxNestingDepth) {
      throw FormatException('Value nesting limit exceeded at $path');
    }
    nodes++;
    if (nodes > E0ValueCodec.maxValueNodes) {
      throw const FormatException('Value node limit exceeded');
    }
  }
}

Object? _normalize(
  Object? value,
  E0ValueSchema schema,
  _ValueBudget budget,
  String path, [
  int depth = 0,
]) {
  budget.consume(depth, path);
  if (value == null) {
    if (!schema.nullable) throw FormatException('$path must not be null');
    return null;
  }
  if (schema.kind == E0ValueKind.supportedValue) {
    return _normalizeAny(value, budget, path, depth);
  }
  switch (schema.kind) {
    case E0ValueKind.nullValue:
      throw FormatException('$path must be null');
    case E0ValueKind.boolean:
      if (value is! bool) throw FormatException('$path must be bool');
      return value;
    case E0ValueKind.integer:
      if (value is! int) throw FormatException('$path must be int');
      return value;
    case E0ValueKind.doubleValue:
      if (value is! double || !value.isFinite) {
        throw FormatException('$path must be a finite double');
      }
      return value;
    case E0ValueKind.string:
      if (value is! String) throw FormatException('$path must be String');
      _checkString(value, path);
      return value;
    case E0ValueKind.list:
      if (value is! List<Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('$path must be a bounded List');
      }
      return List<Object?>.unmodifiable(<Object?>[
        for (var index = 0; index < value.length; index++)
          _normalize(
            value[index],
            schema.elementSchema!,
            budget,
            '$path[$index]',
            depth + 1,
          ),
      ]);
    case E0ValueKind.set:
      if (value is! Set<Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('$path must be a bounded Set');
      }
      final result = <Object?>{};
      for (final item in value) {
        final normalized = _normalize(
          item,
          schema.elementSchema!,
          budget,
          '$path element',
          depth + 1,
        );
        if (!result.add(normalized)) {
          throw FormatException('$path contains duplicate Set values');
        }
      }
      return Set<Object?>.unmodifiable(result);
    case E0ValueKind.map:
      if (value is! Map<Object?, Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('$path must be a bounded Map');
      }
      final result = <String, Object?>{};
      final keys = <String>[];
      for (final key in value.keys) {
        if (key is! String) throw FormatException('$path keys must be String');
        _checkString(key, '$path key');
        keys.add(key);
      }
      keys.sort();
      for (final key in keys) {
        result[key] = _normalize(
          value[key],
          schema.mapValueSchema!,
          budget,
          '$path.$key',
          depth + 1,
        );
      }
      return Map<String, Object?>.unmodifiable(result);
    case E0ValueKind.closure:
      throw FormatException('$path contains an internal closure value');
    case E0ValueKind.supportedValue:
      throw StateError('Supported-value normalization was not dispatched');
  }
}

Object _normalizeAny(
  Object value,
  _ValueBudget budget,
  String path,
  int depth,
) {
  if (value is bool || value is int) return value;
  if (value is double) {
    if (!value.isFinite) throw FormatException('$path must be finite');
    return value;
  }
  if (value is String) {
    _checkString(value, path);
    return value;
  }
  if (value is List<Object?>) {
    return _normalize(
      value,
      const E0ValueSchema.list(E0ValueSchema.supportedValue),
      budget,
      path,
      depth,
    ) as Object;
  }
  if (value is Set<Object?>) {
    return _normalize(
      value,
      const E0ValueSchema.set(E0ValueSchema.supportedValue),
      budget,
      path,
      depth,
    ) as Object;
  }
  if (value is Map<Object?, Object?>) {
    return _normalize(
      value,
      const E0ValueSchema.map(E0ValueSchema.supportedValue),
      budget,
      path,
      depth,
    ) as Object;
  }
  throw FormatException('$path contains unsupported ${value.runtimeType}');
}

E0ValueSchema _inferSchema(
  Object? value,
  _ValueBudget budget,
  String path, [
  int depth = 0,
]) {
  budget.consume(depth, path);
  if (value == null) return E0ValueSchema.nullValue;
  if (value is bool) return E0ValueSchema.boolean;
  if (value is int) return E0ValueSchema.integer;
  if (value is double && value.isFinite) return E0ValueSchema.doubleValue;
  if (value is String) {
    _checkString(value, path);
    return E0ValueSchema.string;
  }
  if (value is List<Object?>) {
    if (value.length > E0ValueCodec.maxCollectionEntries) {
      throw FormatException('$path exceeds List size limit');
    }
    E0ValueSchema? element;
    for (var index = 0; index < value.length; index++) {
      final current = _inferSchema(
        value[index],
        budget,
        '$path[$index]',
        depth + 1,
      );
      element = element == null || element == current
          ? current
          : E0ValueSchema.supportedValue;
    }
    return E0ValueSchema.list(element ?? E0ValueSchema.supportedValue);
  }
  if (value is Set<Object?>) {
    if (value.length > E0ValueCodec.maxCollectionEntries) {
      throw FormatException('$path exceeds Set size limit');
    }
    E0ValueSchema? element;
    for (final item in value) {
      final current = _inferSchema(item, budget, '$path element', depth + 1);
      element = element == null || element == current
          ? current
          : E0ValueSchema.supportedValue;
    }
    return E0ValueSchema.set(element ?? E0ValueSchema.supportedValue);
  }
  if (value is Map<Object?, Object?>) {
    if (value.length > E0ValueCodec.maxCollectionEntries ||
        value.keys.any((key) => key is! String)) {
      throw FormatException('$path must be a bounded String-keyed Map');
    }
    for (final entry in value.entries) {
      _inferSchema(entry.value, budget, '$path.${entry.key}', depth + 1);
    }
    return const E0ValueSchema.map(E0ValueSchema.supportedValue);
  }
  throw FormatException('$path contains unsupported ${value.runtimeType}');
}

Map<String, Object?> _encodeValue(
  Object? value,
  _ValueBudget budget,
  String path, [
  int depth = 0,
]) {
  budget.consume(depth, path);
  if (value == null) return const <String, Object?>{'t': 'null'};
  if (value is bool) return <String, Object?>{'t': 'bool', 'v': value};
  if (value is int) return <String, Object?>{'t': 'int', 'v': value};
  if (value is double && value.isFinite) {
    return <String, Object?>{'t': 'double', 'v': value};
  }
  if (value is String) {
    _checkString(value, path);
    return <String, Object?>{'t': 'String', 'v': value};
  }
  if (value is List<Object?>) {
    if (value.length > E0ValueCodec.maxCollectionEntries) {
      throw FormatException('$path exceeds List size limit');
    }
    return <String, Object?>{
      't': 'List',
      'v': <Object?>[
        for (var index = 0; index < value.length; index++)
          _encodeValue(value[index], budget, '$path[$index]', depth + 1),
      ],
    };
  }
  if (value is Set<Object?>) {
    if (value.length > E0ValueCodec.maxCollectionEntries) {
      throw FormatException('$path exceeds Set size limit');
    }
    final encoded = <Map<String, Object?>>[
      for (final item in value)
        _encodeValue(item, budget, '$path element', depth + 1),
    ]..sort((left, right) => jsonEncode(left).compareTo(jsonEncode(right)));
    for (var index = 1; index < encoded.length; index++) {
      if (jsonEncode(encoded[index - 1]) == jsonEncode(encoded[index])) {
        throw FormatException('$path contains duplicate Set values');
      }
    }
    return <String, Object?>{'t': 'Set', 'v': encoded};
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.map((key) {
      if (key is! String) throw FormatException('$path keys must be String');
      return key;
    }).toList()..sort();
    if (keys.length > E0ValueCodec.maxCollectionEntries) {
      throw FormatException('$path exceeds Map size limit');
    }
    return <String, Object?>{
      't': 'Map',
      'v': <Object?>[
        for (final key in keys)
          <String, Object?>{
            'k': key,
            'v': _encodeValue(value[key], budget, '$path.$key', depth + 1),
          },
      ],
    };
  }
  throw FormatException('$path contains unsupported ${value.runtimeType}');
}

Object? _decodeValue(
  Object? json,
  _ValueBudget budget,
  String path, [
  int depth = 0,
]) {
  budget.consume(depth, path);
  if (json is! Map<String, Object?> || json['t'] is! String) {
    throw FormatException('Invalid encoded value at $path');
  }
  final tag = json['t']! as String;
  if (tag == 'null') {
    if (!_hasExactKeys(json, const <String>{'t'})) {
      throw FormatException('Invalid null value at $path');
    }
    return null;
  }
  if (!_hasExactKeys(json, const <String>{'t', 'v'})) {
    throw FormatException('Invalid $tag value fields at $path');
  }
  final value = json['v'];
  switch (tag) {
    case 'bool':
      if (value is! bool) throw FormatException('Invalid bool at $path');
      return value;
    case 'int':
      if (value is! int) throw FormatException('Invalid int at $path');
      return value;
    case 'double':
      if (value is! double || !value.isFinite) {
        throw FormatException('Invalid double at $path');
      }
      return value;
    case 'String':
      if (value is! String) throw FormatException('Invalid String at $path');
      _checkString(value, path);
      return value;
    case 'List':
      if (value is! List<Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('Invalid List at $path');
      }
      return List<Object?>.unmodifiable(<Object?>[
        for (var index = 0; index < value.length; index++)
          _decodeValue(value[index], budget, '$path[$index]', depth + 1),
      ]);
    case 'Set':
      if (value is! List<Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('Invalid Set at $path');
      }
      final result = <Object?>{};
      String? prior;
      for (var index = 0; index < value.length; index++) {
        final encoded = value[index];
        final canonical = jsonEncode(encoded);
        if (prior != null && canonical.compareTo(prior) <= 0) {
          throw FormatException('Set values are not canonical at $path');
        }
        prior = canonical;
        final decoded = _decodeValue(
          encoded,
          budget,
          '$path[$index]',
          depth + 1,
        );
        if (!result.add(decoded)) {
          throw FormatException('Duplicate Set value at $path[$index]');
        }
      }
      return Set<Object?>.unmodifiable(result);
    case 'Map':
      if (value is! List<Object?> ||
          value.length > E0ValueCodec.maxCollectionEntries) {
        throw FormatException('Invalid Map at $path');
      }
      final result = <String, Object?>{};
      String? prior;
      for (var index = 0; index < value.length; index++) {
        final entry = value[index];
        if (entry is! Map<String, Object?> ||
            !_hasExactKeys(entry, const <String>{'k', 'v'}) ||
            entry['k'] is! String) {
          throw FormatException('Invalid Map entry at $path[$index]');
        }
        final key = entry['k']! as String;
        if (prior != null && key.compareTo(prior) <= 0) {
          throw FormatException('Map keys are not canonical at $path');
        }
        prior = key;
        result[key] = _decodeValue(entry['v'], budget, '$path.$key', depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    default:
      throw FormatException('Unknown value tag $tag at $path');
  }
}

Object? _typedCopy(Object? value, E0ValueSchema schema) {
  if (value == null) return null;
  if (schema.kind == E0ValueKind.supportedValue) return value;
  if (schema.kind == E0ValueKind.list) {
    final source = value as List<Object?>;
    final values = source
        .map((item) => _typedCopy(item, schema.elementSchema!))
        .toList(growable: false);
    return switch (schema.elementSchema!.kind) {
      E0ValueKind.boolean => List<bool>.unmodifiable(values.cast<bool>()),
      E0ValueKind.integer => List<int>.unmodifiable(values.cast<int>()),
      E0ValueKind.doubleValue => List<double>.unmodifiable(
        values.cast<double>(),
      ),
      E0ValueKind.string => List<String>.unmodifiable(values.cast<String>()),
      _ => List<dynamic>.unmodifiable(values),
    };
  }
  if (schema.kind == E0ValueKind.set) {
    final source = value as Set<Object?>;
    final values = source
        .map((item) => _typedCopy(item, schema.elementSchema!))
        .toSet();
    return switch (schema.elementSchema!.kind) {
      E0ValueKind.boolean => Set<bool>.unmodifiable(values.cast<bool>()),
      E0ValueKind.integer => Set<int>.unmodifiable(values.cast<int>()),
      E0ValueKind.doubleValue => Set<double>.unmodifiable(
        values.cast<double>(),
      ),
      E0ValueKind.string => Set<String>.unmodifiable(values.cast<String>()),
      _ => Set<dynamic>.unmodifiable(values),
    };
  }
  if (schema.kind == E0ValueKind.map) {
    final source = value as Map<String, Object?>;
    final values = <String, Object?>{
      for (final entry in source.entries)
        entry.key: _typedCopy(entry.value, schema.mapValueSchema!),
    };
    return switch (schema.mapValueSchema!.kind) {
      E0ValueKind.boolean => Map<String, bool>.unmodifiable(
        values.map((key, value) => MapEntry(key, value! as bool)),
      ),
      E0ValueKind.integer => Map<String, int>.unmodifiable(
        values.map((key, value) => MapEntry(key, value! as int)),
      ),
      E0ValueKind.doubleValue => Map<String, double>.unmodifiable(
        values.map((key, value) => MapEntry(key, value! as double)),
      ),
      E0ValueKind.string => Map<String, String>.unmodifiable(
        values.map((key, value) => MapEntry(key, value! as String)),
      ),
      _ => Map<String, dynamic>.unmodifiable(values),
    };
  }
  return value;
}

void _checkString(String value, String path) {
  if (utf8.encode(value).length > E0ValueCodec.maxStringBytes) {
    throw FormatException('String byte limit exceeded at $path');
  }
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> keys) =>
    value.length == keys.length && value.keys.toSet().containsAll(keys);

bool _deepEquals(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    if (left.length != right.length ||
        !left.keys.toSet().containsAll(right.keys)) {
      return false;
    }
    for (final key in left.keys) {
      if (!_deepEquals(left[key], right[key])) return false;
    }
    return true;
  }
  if (left is Set<Object?> && right is Set<Object?>) {
    return left.length == right.length && left.containsAll(right);
  }
  return left == right;
}
