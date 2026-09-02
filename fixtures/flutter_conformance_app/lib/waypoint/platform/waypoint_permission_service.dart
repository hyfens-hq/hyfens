import 'waypoint_permission.dart';
import 'waypoint_permission_result.dart';

abstract interface class WaypointPermissionService {
  Future<WaypointPermissionResult> read(WaypointPermission permission);

  Future<WaypointPermissionResult> request(WaypointPermission permission);

  Future<bool> openAppSettings();
}
