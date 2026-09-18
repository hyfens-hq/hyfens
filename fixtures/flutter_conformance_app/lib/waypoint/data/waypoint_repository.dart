import 'package:alphax/alphax.dart';

import '../domain/waypoint_activity.dart';
import '../domain/waypoint_destination.dart';
import '../domain/waypoint_home_data.dart';
import '../domain/waypoint_trip.dart';
import 'waypoint_data_source.dart';
import 'waypoint_json_decoder.dart';

final class WaypointRepository {
  const WaypointRepository(this.source);

  final WaypointDataSource source;

  String get modeLabel => source.modeLabel;

  bool get isDemo => source.isDemo;

  String get transportLabel => source.transportLabel;

  Future<WaypointHomeData> loadHome({
    AlphaXCancellationToken? cancellationToken,
  }) async => WaypointJsonDecoder.decodeHome(
    await source.readJson('/api/home', cancellationToken: cancellationToken),
  );

  Future<List<WaypointDestination>> searchDestinations(
    String query, {
    AlphaXCancellationToken? cancellationToken,
  }) async => WaypointJsonDecoder.decodeDestinations(
    await source.readJson(
      '/api/search',
      queryParameters: <String, String>{'q': query},
      cancellationToken: cancellationToken,
    ),
  );

  Future<WaypointTrip> loadTrip(
    String id, {
    AlphaXCancellationToken? cancellationToken,
  }) async => WaypointJsonDecoder.decodeTrip(
    await source.readJson(
      '/api/trips/$id',
      cancellationToken: cancellationToken,
    ),
  );

  Stream<WaypointActivity> watchActivities({
    AlphaXCancellationToken? cancellationToken,
  }) async* {
    await for (final value in source.streamJson(
      '/api/activity',
      cancellationToken: cancellationToken,
    )) {
      yield WaypointJsonDecoder.decodeActivity(value);
    }
  }

  Future<void> close() => source.close();
}
