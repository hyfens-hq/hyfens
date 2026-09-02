import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

import 'waypoint_permission.dart';
import 'waypoint_permission_result.dart';
import 'waypoint_permission_service.dart';

final class PermissionHandlerService implements WaypointPermissionService {
  const PermissionHandlerService();

  @override
  Future<WaypointPermissionResult> read(WaypointPermission permission) async =>
      _result(permission, await _permissionFor(permission).status);

  @override
  Future<WaypointPermissionResult> request(
    WaypointPermission permission,
  ) async => _result(permission, await _permissionFor(permission).request());

  @override
  Future<bool> openAppSettings() => permission_handler.openAppSettings();

  permission_handler.Permission _permissionFor(WaypointPermission permission) =>
      switch (permission) {
        WaypointPermission.location =>
          permission_handler.Permission.locationWhenInUse,
        WaypointPermission.notifications =>
          permission_handler.Permission.notification,
        WaypointPermission.camera => permission_handler.Permission.camera,
        WaypointPermission.photos => permission_handler.Permission.photos,
      };

  WaypointPermissionResult _result(
    WaypointPermission permission,
    permission_handler.PermissionStatus status,
  ) => WaypointPermissionResult(
    permission: permission,
    status: switch (status) {
      permission_handler.PermissionStatus.granted =>
        WaypointPermissionStatus.granted,
      permission_handler.PermissionStatus.denied =>
        WaypointPermissionStatus.denied,
      permission_handler.PermissionStatus.restricted =>
        WaypointPermissionStatus.restricted,
      permission_handler.PermissionStatus.limited =>
        WaypointPermissionStatus.limited,
      permission_handler.PermissionStatus.permanentlyDenied =>
        WaypointPermissionStatus.permanentlyDenied,
      permission_handler.PermissionStatus.provisional =>
        WaypointPermissionStatus.provisional,
    },
  );
}
