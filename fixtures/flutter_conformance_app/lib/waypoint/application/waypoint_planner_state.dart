import '../domain/waypoint_plan_request.dart';

final class WaypointPlannerState {
  WaypointPlannerState({
    this.destination = '',
    DateTime? startDate,
    DateTime? endDate,
    this.travelers = 2,
    this.travelStyle = 'Unhurried',
  }) : startDate = startDate ?? DateTime.now().add(const Duration(days: 28)),
       endDate = endDate ?? DateTime.now().add(const Duration(days: 35));

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final int travelers;
  final String travelStyle;

  bool get isValid => WaypointPlanRequest(
    destination: destination,
    startDate: startDate,
    endDate: endDate,
    travelers: travelers,
    travelStyle: travelStyle,
  ).isValid;

  WaypointPlannerState copyWith({
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    int? travelers,
    String? travelStyle,
  }) => WaypointPlannerState(
    destination: destination ?? this.destination,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    travelers: travelers ?? this.travelers,
    travelStyle: travelStyle ?? this.travelStyle,
  );

  WaypointPlanRequest toRequest() => WaypointPlanRequest(
    destination: destination,
    startDate: startDate,
    endDate: endDate,
    travelers: travelers,
    travelStyle: travelStyle,
  );
}
