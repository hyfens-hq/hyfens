import '../platform/waypoint_permission.dart';
import '../platform/waypoint_permission_result.dart';

final class WaypointPermissionState {
  const WaypointPermissionState({
    this.results = const <WaypointPermission, WaypointPermissionResult>{},
  });

  final Map<WaypointPermission, WaypointPermissionResult> results;

  WaypointPermissionResult? forPermission(WaypointPermission permission) =>
      results[permission];

  WaypointPermissionState copyWith(
    Map<WaypointPermission, WaypointPermissionResult> next,
  ) => WaypointPermissionState(results: next);
}
