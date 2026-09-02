import 'waypoint_checklist_item.dart';
import 'waypoint_itinerary_item.dart';
import 'waypoint_trip_document.dart';

final class WaypointTrip {
  const WaypointTrip({
    required this.id,
    required this.title,
    required this.destination,
    required this.dateRange,
    required this.durationLabel,
    required this.imageAsset,
    required this.progress,
    required this.itinerary,
    required this.checklist,
    this.coverLabel,
    this.accentColor,
    this.documents = const <WaypointTripDocument>[],
  });

  final String id;
  final String title;
  final String destination;
  final String dateRange;
  final String durationLabel;
  final String imageAsset;
  final double progress;
  final List<WaypointItineraryItem> itinerary;
  final List<WaypointChecklistItem> checklist;
  final String? coverLabel;
  final String? accentColor;
  final List<WaypointTripDocument> documents;

  int get completedItems => (progress * checklist.length).round();
}
