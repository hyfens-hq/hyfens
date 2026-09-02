import 'package:flutter/material.dart';
import 'package:instrumentation_e0/e0_runtime.dart';

final List<E0WidgetFactoryDescriptor> conformanceWidgetFactories =
    <E0WidgetFactoryDescriptor>[
      E0WidgetFactoryDescriptor(
        id: 'flutter.text.v1',
        sourceName: 'Text',
        properties: const <E0WidgetPropertyDescriptor>[
          E0WidgetPropertyDescriptor(
            name: 'data',
            schema: E0ValueSchema.string,
            required: true,
          ),
          E0WidgetPropertyDescriptor(
            name: 'fontSize',
            schema: E0ValueSchema.doubleValue,
          ),
        ],
        minChildren: 0,
        maxChildren: 0,
      ),
      E0WidgetFactoryDescriptor(
        id: 'flutter.column.v1',
        sourceName: 'Column',
        properties: const <E0WidgetPropertyDescriptor>[
          E0WidgetPropertyDescriptor(
            name: 'mainAxisSize',
            schema: E0ValueSchema.string,
            allowedValues: <String>['min', 'max'],
          ),
        ],
        minChildren: 0,
        maxChildren: E0WidgetFactoryRegistry.maxChildren,
      ),
      E0WidgetFactoryDescriptor(
        id: 'flutter.elevated-button.v1',
        sourceName: 'ElevatedButton',
        properties: const <E0WidgetPropertyDescriptor>[],
        minChildren: 1,
        maxChildren: 1,
      ),
    ];

E0WidgetFactoryRegistry createConformanceWidgetRegistry() =>
    E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
      E0WidgetFactoryRegistration(
        descriptor: conformanceWidgetFactories[0],
        create: (properties, children) => Text(
          properties['data']! as String,
          style: properties['fontSize'] == null
              ? null
              : TextStyle(fontSize: properties['fontSize']! as double),
        ),
      ),
      E0WidgetFactoryRegistration(
        descriptor: conformanceWidgetFactories[1],
        create: (properties, children) => Column(
          mainAxisSize: switch (properties['mainAxisSize']) {
            null || 'max' => MainAxisSize.max,
            'min' => MainAxisSize.min,
            _ => throw const FormatException('Invalid MainAxisSize value'),
          },
          children: children.cast<Widget>(),
        ),
      ),
      E0WidgetFactoryRegistration(
        descriptor: conformanceWidgetFactories[2],
        // Guest closures never cross the ABI. This deliberately creates a
        // disabled button; interactive callbacks remain precompiled host code.
        create: (properties, children) =>
            ElevatedButton(onPressed: null, child: children.single as Widget),
      ),
    ]);
