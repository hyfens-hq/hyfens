import 'dart:async';

import 'package:flutter/material.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

/// Creates the immutable host-owned widget registry used by the production
/// Flutter widget ABI. Constructors remain in the AOT application; downloaded
/// code can provide only bounded descriptions and callbacks.
E0WidgetFactoryRegistry standardFlutterWidgetRegistry() {
  E0WidgetFactoryDescriptor descriptor(String sourceName) =>
      e0StandardFlutterWidgetFactories.firstWhere(
        (item) => item.sourceName == sourceName,
      );

  return E0WidgetFactoryRegistry(<E0WidgetFactoryRegistration>[
    E0WidgetFactoryRegistration(
      descriptor: descriptor('Text'),
      create: (properties, children) {
        final fontSize = properties['fontSize'];
        return Text(
          properties['data']! as String,
          style: fontSize == null
              ? null
              : TextStyle(fontSize: fontSize as double),
        );
      },
    ),
    E0WidgetFactoryRegistration(
      descriptor: descriptor('Column'),
      create: (properties, children) => Column(
        mainAxisSize: properties['mainAxisSize'] == 'min'
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: children.cast<Widget>(),
      ),
    ),
    E0WidgetFactoryRegistration(
      descriptor: descriptor('Row'),
      create: (properties, children) => Row(
        mainAxisSize: properties['mainAxisSize'] == 'min'
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: children.cast<Widget>(),
      ),
    ),
    E0WidgetFactoryRegistration(
      descriptor: descriptor('Center'),
      create: (properties, children) =>
          Center(child: children.single as Widget),
    ),
    E0WidgetFactoryRegistration(
      descriptor: descriptor('SizedBox'),
      create: (properties, children) => SizedBox(
        width: properties['width'] as double?,
        height: properties['height'] as double?,
        child: children.isEmpty ? null : children.single as Widget,
      ),
    ),
    E0WidgetFactoryRegistration(
      descriptor: descriptor('ElevatedButton'),
      create: (properties, children) {
        final callback = properties['onPressed'];
        return ElevatedButton(
          onPressed: callback is E0HostCallbackValue
              ? () {
                  final result = callback.invoke();
                  if (result is Future) {
                    unawaited(result.then<void>((_) {}));
                  }
                }
              : null,
          child: children.single as Widget,
        );
      },
    ),
  ]);
}
