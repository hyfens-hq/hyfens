final class WaypointPlannerField {
  const WaypointPlannerField({
    required this.id,
    required this.type,
    required this.label,
    this.placeholder,
    this.initialValue,
    this.min,
    this.max,
  });

  final String id;
  final String type;
  final String label;
  final String? placeholder;
  final int? initialValue;
  final int? min;
  final int? max;
}
