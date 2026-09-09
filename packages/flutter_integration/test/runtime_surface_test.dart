import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Flutter runtime registry does not pull in the analyzer-backed compiler barrel', () {
    final source = File('lib/src/flutter_widget_registry.dart')
        .readAsStringSync();

    expect(source, contains("package:instrumentation_e0/e0_runtime.dart"));
    expect(
      source,
      isNot(contains('package:instrumentation_e0/instrumentation_e0.dart')),
    );
  });
}
