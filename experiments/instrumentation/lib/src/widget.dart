import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'value.dart';

/// The bounded value ABI used by an instrumented `StatelessWidget.build`.
const E0ValueSchema e0WidgetDescriptionSchema = E0ValueSchema.map(
  E0ValueSchema.supportedValue,
);

const E0FunctionSignature e0WidgetBuildSignature = E0FunctionSignature(
  parameters: <E0ValueSchema>[],
  returnSchema: e0WidgetDescriptionSchema,
);

final class E0WidgetPropertyDescriptor {
  const E0WidgetPropertyDescriptor({
    required this.name,
    required this.schema,
    this.required = false,
    this.allowedValues = const <Object?>[],
  });

  final String name;
  final E0ValueSchema schema;
  final bool required;
  final List<Object?> allowedValues;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'schema': schema.toJson(),
    'required': required,
    'allowedValues': allowedValues
        .map((value) => E0Value.fromHost(value, schema).toJson())
        .toList(growable: false),
  };

  static E0WidgetPropertyDescriptor fromJson(Map<String, Object?> value) {
    const keys = <String>{'name', 'schema', 'required', 'allowedValues'};
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['name'] is! String ||
        (value['name']! as String).isEmpty ||
        value['schema'] is! Map<String, Object?> ||
        value['required'] is! bool ||
        value['allowedValues'] is! List<Object?>) {
      throw const FormatException('Invalid widget property descriptor');
    }
    final schema = E0ValueSchema.fromJson(
      value['schema']! as Map<String, Object?>,
    );
    if (!schema.isSupportedHostSignature) {
      throw const FormatException('Unsupported widget property schema');
    }
    final allowedValues = (value['allowedValues']! as List<Object?>)
        .map((item) => E0Value.fromJson(item).toHost(schema))
        .toList(growable: false);
    return E0WidgetPropertyDescriptor(
      name: value['name']! as String,
      schema: schema,
      required: value['required']! as bool,
      allowedValues: List.unmodifiable(allowedValues),
    );
  }
}

final class E0WidgetFactoryDescriptor {
  E0WidgetFactoryDescriptor({
    required this.id,
    required this.sourceName,
    required List<E0WidgetPropertyDescriptor> properties,
    required this.minChildren,
    required this.maxChildren,
  }) : properties = List.unmodifiable(
         properties.map(
           (property) => E0WidgetPropertyDescriptor(
             name: property.name,
             schema: property.schema,
             required: property.required,
             allowedValues: List.unmodifiable(property.allowedValues),
           ),
         ),
       ) {
    _validate();
  }

  final String id;
  final String sourceName;
  final List<E0WidgetPropertyDescriptor> properties;
  final int minChildren;
  final int maxChildren;

  String get contractDigest => sha256
      .convert(utf8.encode(jsonEncode(_canonicalJson(toContractJson()))))
      .toString();

  Map<String, Object?> toContractJson() => <String, Object?>{
    'contractVersion': 1,
    'id': id,
    'sourceName': sourceName,
    'properties': properties.map((property) => property.toJson()).toList(),
    'minChildren': minChildren,
    'maxChildren': maxChildren,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ...toContractJson(),
    'contractDigest': contractDigest,
  };

  static E0WidgetFactoryDescriptor fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'contractVersion',
      'id',
      'sourceName',
      'properties',
      'minChildren',
      'maxChildren',
      'contractDigest',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['contractVersion'] != 1 ||
        value['id'] is! String ||
        value['sourceName'] is! String ||
        value['properties'] is! List<Object?> ||
        value['minChildren'] is! int ||
        value['maxChildren'] is! int ||
        value['contractDigest'] is! String) {
      throw const FormatException('Invalid widget factory descriptor');
    }
    final descriptor = E0WidgetFactoryDescriptor(
      id: value['id']! as String,
      sourceName: value['sourceName']! as String,
      properties: (value['properties']! as List<Object?>)
          .map((property) {
            if (property is! Map<String, Object?>) {
              throw const FormatException('Invalid widget property descriptor');
            }
            return E0WidgetPropertyDescriptor.fromJson(property);
          })
          .toList(growable: false),
      minChildren: value['minChildren']! as int,
      maxChildren: value['maxChildren']! as int,
    );
    if (value['contractDigest'] != descriptor.contractDigest) {
      throw const FormatException('Widget factory contract digest mismatch');
    }
    return descriptor;
  }

  void _validate() {
    if (id.isEmpty ||
        sourceName.isEmpty ||
        properties.length > E0WidgetFactoryRegistry.maxProperties ||
        minChildren < 0 ||
        maxChildren < minChildren ||
        maxChildren > E0WidgetFactoryRegistry.maxChildren) {
      throw const FormatException('Invalid widget factory contract');
    }
    final names = <String>{};
    for (final property in properties) {
      final allowedKeys = <String>{};
      if (property.name.isEmpty ||
          !names.add(property.name) ||
          !property.schema.isSupportedHostSignature ||
          property.allowedValues.length > 16 ||
          property.allowedValues.any((value) {
            try {
              final encoded = jsonEncode(
                E0Value.fromHost(value, property.schema).toJson(),
              );
              return !allowedKeys.add(encoded);
            } on Object {
              return true;
            }
          })) {
        throw const FormatException('Invalid widget factory properties');
      }
    }
  }
}

typedef E0WidgetFactory = Object Function(
  Map<String, Object?> properties,
  List<Object> children,
);

final class E0WidgetFactoryRegistration {
  const E0WidgetFactoryRegistration({
    required this.descriptor,
    required this.create,
  });

  final E0WidgetFactoryDescriptor descriptor;
  final E0WidgetFactory create;
}

/// Immutable host authority for the only widget constructors patches may use.
final class E0WidgetFactoryRegistry {
  E0WidgetFactoryRegistry(List<E0WidgetFactoryRegistration> registrations)
    : _registrations = Map.unmodifiable(<String, E0WidgetFactoryRegistration>{
        for (final registration in registrations)
          registration.descriptor.id: registration,
      }) {
    if (_registrations.length != registrations.length ||
        registrations.length > maxFactories) {
      throw const FormatException('Duplicate or oversized widget registry');
    }
    final sourceNames = <String>{};
    for (final registration in registrations) {
      if (!sourceNames.add(registration.descriptor.sourceName)) {
        throw const FormatException('Duplicate widget factory source name');
      }
    }
  }

  static const int maxFactories = 16;
  static const int maxProperties = 16;
  static const int maxChildren = 32;
  // A node adds a Map and children-List layer to the generic E0 value graph.
  // Six widget edges leave one complete rejection edge below E0's depth 16.
  static const int maxDepth = 6;
  static const int maxNodes = 64;

  final Map<String, E0WidgetFactoryRegistration> _registrations;

  bool containsFactoryId(String id) => _registrations.containsKey(id);

  void requireContracts(List<E0WidgetFactoryDescriptor> contracts) {
    for (final contract in contracts) {
      final registration = _registrations[contract.id];
      if (registration == null ||
          registration.descriptor.contractDigest != contract.contractDigest) {
        throw FormatException(
          'Unavailable widget factory contract ${contract.id}',
        );
      }
    }
  }

  T materialize<T extends Object>(
    Object? description, {
    Set<String>? allowedFactoryIds,
  }) {
    final budget = _WidgetBudget();
    return _materialize<T>(description, budget, 0, allowedFactoryIds);
  }

  T _materialize<T extends Object>(
    Object? value,
    _WidgetBudget budget,
    int depth,
    Set<String>? allowedFactoryIds,
  ) {
    if (depth > maxDepth || ++budget.nodes > maxNodes) {
      throw const FormatException('Widget description bounds exceeded');
    }
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String) ||
        value.keys.toSet().difference(const <String>{
          'factory',
          'properties',
          'children',
        }).isNotEmpty ||
        value.length != 3) {
      throw const FormatException('Invalid widget description node');
    }
    final factoryId = value['factory'];
    final propertiesValue = value['properties'];
    final childrenValue = value['children'];
    if (factoryId is! String ||
        propertiesValue is! Map<Object?, Object?> ||
        propertiesValue.keys.any((key) => key is! String) ||
        childrenValue is! List<Object?>) {
      throw const FormatException('Invalid widget description fields');
    }
    final registration = _registrations[factoryId];
    if (allowedFactoryIds != null && !allowedFactoryIds.contains(factoryId)) {
      throw FormatException(
        'Widget factory $factoryId is not declared by the patch program',
      );
    }
    if (registration == null) {
      throw FormatException('Unknown widget factory $factoryId');
    }
    final descriptor = registration.descriptor;
    if (propertiesValue.length > maxProperties ||
        childrenValue.length < descriptor.minChildren ||
        childrenValue.length > descriptor.maxChildren) {
      throw const FormatException('Widget factory arity limit exceeded');
    }
    final definitions = <String, E0WidgetPropertyDescriptor>{
      for (final property in descriptor.properties) property.name: property,
    };
    if (propertiesValue.keys.any((key) => !definitions.containsKey(key)) ||
        definitions.values.any(
          (property) =>
              property.required && !propertiesValue.containsKey(property.name),
        )) {
      throw const FormatException('Widget properties do not match contract');
    }
    final properties = <String, Object?>{};
    for (final entry in propertiesValue.entries) {
      final name = entry.key! as String;
      final definition = definitions[name]!;
      final schema = definition.schema;
      final property = E0Value.fromHost(entry.value, schema).toHost(schema);
      if (definition.allowedValues.isNotEmpty &&
          !definition.allowedValues.contains(property)) {
        throw FormatException(
          'Widget property $name is outside its allowed values',
        );
      }
      properties[name] = property;
    }
    final children = <T>[
      for (final child in childrenValue)
        _materialize<T>(child, budget, depth + 1, allowedFactoryIds),
    ];
    final materialized = registration.create(
      Map.unmodifiable(properties),
      List<Object>.unmodifiable(children),
    );
    if (materialized is! T) {
      throw FormatException(
        'Widget factory $factoryId returned ${materialized.runtimeType}, expected $T',
      );
    }
    return materialized;
  }
}

final class _WidgetBudget {
  int nodes = 0;
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
