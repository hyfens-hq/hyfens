final class WaypointNoteField {
  const WaypointNoteField({
    required this.id,
    required this.type,
    required this.label,
    required this.placeholder,
    required this.isRequired,
  });

  final String id;
  final String type;
  final String label;
  final String placeholder;
  final bool isRequired;
}
