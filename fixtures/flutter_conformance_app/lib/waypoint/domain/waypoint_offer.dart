final class WaypointOffer {
  const WaypointOffer({
    required this.id,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.action,
    required this.expiresAt,
    required this.accentColor,
    this.isDismissible = true,
  });

  final String id;
  final String title;
  final String message;
  final String actionLabel;
  final String? action;
  final DateTime expiresAt;
  final String accentColor;
  final bool isDismissible;

  bool isActive(DateTime now) => expiresAt.isAfter(now);
}
