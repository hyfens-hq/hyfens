import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/application/waypoint_providers.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';
import 'package:conformance/waypoint/data/waypoint_repository.dart';
import 'package:conformance/waypoint/presentation/waypoint_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'local Waypoint smoke flow reaches settings without permissions',
    (tester) async {
      final source = WaypointAlphaXDataSource(
        client: AlphaXClient(
          transport: WaypointDemoTransport(latency: Duration.zero),
        ),
        baseUri: Uri.parse('https://waypoint.demo/'),
        modeLabel: 'Local integration demo',
        isDemo: true,
      );
      addTearDown(source.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waypointRepositoryProvider.overrideWithValue(
              WaypointRepository(source),
            ),
          ],
          child: const WaypointApp(),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('waypoint-discover-page')),
      );

      expect(
        find.byKey(const ValueKey<String>('waypoint-offer-banner')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-offer-dismiss')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('waypoint-offer-banner')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('waypoint-header-settings')),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('waypoint-settings-page')),
      );

      expect(
        find.byKey(const ValueKey<String>('waypoint-permission-location')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('waypoint-settings-media')),
        findsOneWidget,
      );
      // Permission buttons are intentionally not tapped here. OS dialog results
      // vary by device state; manual device observation covers the prompt.
    },
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}
