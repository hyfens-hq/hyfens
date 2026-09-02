import 'waypoint_permission.dart';

final class WaypointPermissionResult {
  const WaypointPermissionResult({
    required this.permission,
    required this.status,
  });

  final WaypointPermission permission;
  final WaypointPermissionStatus status;

  String get statusLabel => switch (status) {
    WaypointPermissionStatus.granted => 'Granted',
    WaypointPermissionStatus.denied => 'Denied',
    WaypointPermissionStatus.restricted => 'Restricted',
    WaypointPermissionStatus.limited => 'Limited',
    WaypointPermissionStatus.permanentlyDenied => 'Permanently denied',
    WaypointPermissionStatus.provisional => 'Provisional',
    WaypointPermissionStatus.unknown => 'Unknown',
  };
}
