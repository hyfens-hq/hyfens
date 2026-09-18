final class WaypointChecklistItem {
  const WaypointChecklistItem({
    required this.title,
    this.detail,
    this.isComplete = false,
  });

  final String title;
  final String? detail;
  final bool isComplete;
}
