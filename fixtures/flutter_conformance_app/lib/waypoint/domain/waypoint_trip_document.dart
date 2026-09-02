final class WaypointTripDocument {
  const WaypointTripDocument({
    required this.name,
    required this.kind,
    required this.sizeLabel,
    this.icon,
  });

  final String name;
  final String kind;
  final String sizeLabel;
  final String? icon;
}
