import 'dart:convert';

import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/data/waypoint_asset_paths.dart';
import 'package:conformance/waypoint/data/waypoint_data_exception.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';
import 'package:conformance/waypoint/data/waypoint_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled JSON, font, vector art, and video assets are loadable',
    () async {
      final homeJson = await rootBundle.loadString(WaypointAssetPaths.homeJson);
      final discoverJson = await rootBundle.loadString(
        WaypointAssetPaths.discoverJson,
      );
      final actionsJson = await rootBundle.loadString(
        WaypointAssetPaths.actionsJson,
      );
      final font = await rootBundle.load('assets/fonts/InterVariable.ttf');
      final hero = await rootBundle.load(WaypointAssetPaths.heroImage);
      final video = await rootBundle.load(WaypointAssetPaths.destinationVideo);

      expect(jsonDecode(homeJson), isA<Map<String, dynamic>>());
      expect(jsonDecode(discoverJson), isA<Map<String, dynamic>>());
      expect(jsonDecode(actionsJson), isA<Map<String, dynamic>>());
      expect(font.lengthInBytes, greaterThan(0));
      expect(hero.lengthInBytes, greaterThan(0));
      expect(video.lengthInBytes, greaterThan(0));
    },
  );

  test(
    'AlphaX-backed local source decodes home, search, and activity stream',
    () async {
      final source = WaypointAlphaXDataSource(
        client: AlphaXClient(
          transport: WaypointDemoTransport(latency: Duration.zero),
        ),
        baseUri: Uri.parse('https://waypoint.demo/'),
        modeLabel: 'Test local demo',
        isDemo: true,
      );
      final repository = WaypointRepository(source);

      try {
        final home = await repository.loadHome();
        final search = await repository.searchDestinations('kyoto');
        final activities = await repository.watchActivities().toList();

        expect(home.destinations, isNotEmpty);
        expect(home.trips, isNotEmpty);
        expect(home.offer?.isActive(DateTime.now()), isTrue);
        expect(
          home.destinations.every(
            (destination) =>
                destination.durationLabel.isNotEmpty &&
                destination.durationLabel != 'null' &&
                destination.accentColor != 'null',
          ),
          isTrue,
        );
        expect(home.offer?.accentColor, isNot('null'));
        expect(search, isNotEmpty);
        expect(search.single.name, 'Lantern House');
        expect(activities, isNotEmpty);
      } finally {
        await repository.close();
      }
    },
  );

  test(
    'unknown bundled demo trip propagates a 404 through the repository',
    () async {
      final source = WaypointAlphaXDataSource(
        client: AlphaXClient(
          transport: WaypointDemoTransport(latency: Duration.zero),
        ),
        baseUri: Uri.parse('https://waypoint.demo/'),
        modeLabel: 'Test local demo',
        isDemo: true,
      );
      final repository = WaypointRepository(source);

      try {
        await expectLater(
          repository.loadTrip('unknown-trip'),
          throwsA(
            isA<WaypointDataException>()
                .having((error) => error.statusCode, 'statusCode', 404)
                .having(
                  (error) => error.message,
                  'message',
                  'Waypoint trip not found',
                ),
          ),
        );
      } finally {
        await repository.close();
      }
    },
  );
}
