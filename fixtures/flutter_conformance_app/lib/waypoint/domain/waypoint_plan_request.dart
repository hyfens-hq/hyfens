final class WaypointPlanRequest {
  const WaypointPlanRequest({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.travelers,
    required this.travelStyle,
  });

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final int travelers;
  final String travelStyle;

  bool get isValid =>
      destination.trim().isNotEmpty &&
      !endDate.isBefore(startDate) &&
      travelers > 0;
}
