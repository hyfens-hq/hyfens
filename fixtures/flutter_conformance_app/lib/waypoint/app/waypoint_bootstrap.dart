import 'package:alphax/alphax.dart';
import 'package:alphax_native/alphax_native.dart';
import 'package:flutter/foundation.dart';

import '../data/waypoint_data_source.dart';

const String waypointMode = String.fromEnvironment(
  'WAYPOINT_MODE',
  defaultValue: 'demo',
);
const String waypointClient = String.fromEnvironment(
  'WAYPOINT_CLIENT',
  defaultValue: 'alphax-native',
);
const String waypointBaseUrl = String.fromEnvironment('WAYPOINT_BASE_URL');

Future<WaypointDataSource> createWaypointDataSource() async {
  if (waypointMode == 'demo') {
    return WaypointAlphaXDataSource(
      client: AlphaXClient(transport: WaypointDemoTransport()),
      baseUri: Uri.parse('https://waypoint.demo/'),
      modeLabel: 'Local demo',
      isDemo: true,
    );
  }
  if (waypointMode != 'network') {
    throw StateError(
      'Unsupported WAYPOINT_MODE "$waypointMode". Use demo or network.',
    );
  }
  if (waypointBaseUrl.isEmpty) {
    throw StateError(
      'Network mode needs WAYPOINT_BASE_URL. No network request was made.',
    );
  }
  final transport = await _createNativeTransport();
  return WaypointAlphaXDataSource(
    client: AlphaXClient(transport: transport),
    baseUri: Uri.parse(waypointBaseUrl),
    modeLabel: 'AlphaX native network',
  );
}

Future<AlphaXTransport> _createNativeTransport() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidCronetTransport.create(),
      TargetPlatform.iOS ||
      TargetPlatform.macOS => AppleUrlSessionTransport.create(),
      _ => Future<AlphaXTransport>.value(DartIoTransport()),
    };
