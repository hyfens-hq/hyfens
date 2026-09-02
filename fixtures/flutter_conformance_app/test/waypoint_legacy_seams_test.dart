import 'dart:io';

import 'package:conformance/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy pricing entrypoint remains callable', () {
    expect(calculatePrice(6, 1), 540);
    expect(calculatePrice(6, 2), 480);
  });

  test('main retains evidence hooks and Waypoint launch wiring', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('PhysicalIosEvidenceSession.open'));
    expect(source, contains('PhysicalAndroidEvidenceSession.open'));
    expect(source, contains('createPatchController'));
    expect(source, contains('ProviderScope('));
    expect(source, contains('child: const WaypointApp()'));
    expect(source, contains('calculatePrice'));
    expect(source, contains('calculateAsyncPrice'));
  });
}
