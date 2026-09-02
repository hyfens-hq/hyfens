// ignore_for_file: unnecessary_this

import 'package:instrumentation_e0/e0_runtime.dart';

abstract class Widget {
  const Widget();

  String get render;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();

  Widget build(BuildContext context);

  @override
  String get render => build(const BuildContext()).render;
}

class BuildContext {
  const BuildContext();
}

enum MainAxisSize { min, max }

class TextStyle {
  const TextStyle({this.fontSize});

  final double? fontSize;
}

class Text extends Widget {
  const Text(this.data, {this.style});

  final String data;
  final TextStyle? style;

  @override
  String get render => style?.fontSize == null
      ? 'Text($data)'
      : 'Text($data,size=${style!.fontSize})';
}

class Column extends Widget {
  const Column({this.mainAxisSize = MainAxisSize.max, required this.children});

  final MainAxisSize mainAxisSize;
  final List<Widget> children;

  @override
  String get render =>
      'Column(${mainAxisSize.name}:[${children.map((child) => child.render).join(',')}])';
}

class ElevatedButton extends Widget {
  const ElevatedButton({required this.onPressed, required this.child});

  final void Function()? onPressed;
  final Widget child;

  @override
  String get render => 'ElevatedButton(${child.render})';
}

class PricingCard extends StatelessWidget {
  const PricingCard({required this.featured, required this.plan});

  final bool featured;
  final String plan;

  @override
  Widget build(BuildContext context) {
    if (this.featured) return Text('BASE ${this.plan}');
    return Text('BASE ${this.plan}');
  }
}

void main(List<String> arguments) {
  E0PatchRuntime.configureWidgetFactories(widgetRegistry());
  print(const PricingCard(featured: true, plan: 'Pro').render);
}

E0WidgetFactoryRegistry widgetRegistry() =>
    E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
      E0WidgetFactoryRegistration(
        descriptor: widgetFactories[0],
        create: (properties, children) => Text(
          properties['data']! as String,
          style: properties['fontSize'] == null
              ? null
              : TextStyle(fontSize: properties['fontSize']! as double),
        ),
      ),
      E0WidgetFactoryRegistration(
        descriptor: widgetFactories[1],
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
        descriptor: widgetFactories[2],
        create: (properties, children) =>
            ElevatedButton(onPressed: null, child: children.single as Widget),
      ),
    ]);

final List<E0WidgetFactoryDescriptor> widgetFactories =
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
