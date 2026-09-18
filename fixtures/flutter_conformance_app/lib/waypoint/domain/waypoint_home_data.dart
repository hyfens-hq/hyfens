import 'waypoint_activity.dart';
import 'waypoint_destination.dart';
import 'waypoint_discover_category.dart';
import 'waypoint_discover_collection.dart';
import 'waypoint_home_hero.dart';
import 'waypoint_offer.dart';
import 'waypoint_permission_action.dart';
import 'waypoint_test_action.dart';
import 'waypoint_trip.dart';

final class WaypointHomeData {
  const WaypointHomeData({
    required this.destinations,
    required this.trips,
    required this.activities,
    required this.offer,
    required this.actions,
    this.permissionActions = const <WaypointPermissionAction>[],
    this.categories = const <WaypointDiscoverCategory>[],
    this.collections = const <WaypointDiscoverCollection>[],
    this.searchSuggestions = const <String>[],
    this.greeting,
    this.discoverTitle,
    this.hero,
  });

  final List<WaypointDestination> destinations;
  final List<WaypointTrip> trips;
  final List<WaypointActivity> activities;
  final WaypointOffer? offer;
  final List<WaypointTestAction> actions;
  final List<WaypointPermissionAction> permissionActions;
  final List<WaypointDiscoverCategory> categories;
  final List<WaypointDiscoverCollection> collections;
  final List<String> searchSuggestions;
  final String? greeting;
  final String? discoverTitle;
  final WaypointHomeHero? hero;
}
