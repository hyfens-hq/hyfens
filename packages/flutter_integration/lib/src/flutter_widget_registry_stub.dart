import 'package:instrumentation_e0/instrumentation_e0.dart';

/// VM-only fallback so CLI/MCP tooling can load the integration package
/// without importing Flutter's `dart:ui` libraries. A real Flutter isolate
/// selects `flutter_widget_registry.dart` through the conditional import.
E0WidgetFactoryRegistry standardFlutterWidgetRegistry() =>
    throw UnsupportedError('Flutter widget registry requires a Flutter isolate');
