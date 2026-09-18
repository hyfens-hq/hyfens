import 'package:conformance/waypoint/presentation/widgets/waypoint_asset_artwork.dart';
import 'package:conformance/waypoint/presentation/waypoint_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the placeholder for a missing raster asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: waypointTheme(Brightness.light),
        home: const Scaffold(
          body: WaypointAssetArtwork(
            assetPath: 'assets/images/waypoint/missing-artwork.png',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.landscape_outlined), findsOneWidget);
  });
}
