final class WaypointItineraryItem {
  const WaypointItineraryItem({
    required this.timeLabel,
    required this.title,
    required this.detail,
    required this.category,
    this.isComplete = false,
  });

  final String timeLabel;
  final String title;
  final String detail;
  final String category;
  final bool isComplete;
}
