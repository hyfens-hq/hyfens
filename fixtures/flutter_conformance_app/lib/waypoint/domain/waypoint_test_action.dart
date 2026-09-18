import 'waypoint_note_field.dart';
import 'waypoint_planner_field.dart';

final class WaypointTestAction {
  const WaypointTestAction({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    this.noteField,
    this.assetPath,
    this.plannerFields = const <WaypointPlannerField>[],
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String submitLabel;
  final WaypointNoteField? noteField;
  final String? assetPath;
  final List<WaypointPlannerField> plannerFields;
}
