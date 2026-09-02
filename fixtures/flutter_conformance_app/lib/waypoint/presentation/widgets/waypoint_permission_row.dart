import 'package:flutter/material.dart';

import '../../domain/waypoint_permission_action.dart';
import '../../platform/waypoint_permission.dart';
import '../../platform/waypoint_permission_result.dart';

final class WaypointPermissionRow extends StatelessWidget {
  const WaypointPermissionRow({
    super.key,
    required this.permission,
    required this.result,
    required this.onRequest,
    this.permissionAction,
  });

  final WaypointPermission permission;
  final WaypointPermissionResult? result;
  final VoidCallback onRequest;
  final WaypointPermissionAction? permissionAction;

  @override
  Widget build(BuildContext context) {
    final action = _validPermissionAction;
    final statusLabel = result?.statusLabel ?? 'Not checked';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(permission)),
      title: Text(action?.label ?? _labelFor(permission)),
      subtitle: action == null
          ? Text(statusLabel)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[Text(action.reason), Text(statusLabel)],
            ),
      trailing: FilledButton.tonal(
        key: ValueKey<String>('waypoint-permission-${permission.name}'),
        onPressed: onRequest,
        child: Text(_actionLabel(result)),
      ),
    );
  }

  WaypointPermissionAction? get _validPermissionAction {
    final action = permissionAction;
    if (action == null ||
        action.id != permission.name ||
        action.label.trim().isEmpty ||
        action.reason.trim().isEmpty) {
      return null;
    }
    return action;
  }

  IconData _iconFor(WaypointPermission value) => switch (value) {
    WaypointPermission.location => Icons.location_on_outlined,
    WaypointPermission.notifications => Icons.notifications_none_rounded,
    WaypointPermission.camera => Icons.camera_alt_outlined,
    WaypointPermission.photos => Icons.photo_library_outlined,
  };

  String _labelFor(WaypointPermission value) => switch (value) {
    WaypointPermission.location => 'Location',
    WaypointPermission.notifications => 'Notifications',
    WaypointPermission.camera => 'Camera',
    WaypointPermission.photos => 'Photo library',
  };

  String _actionLabel(WaypointPermissionResult? value) =>
      value?.status == WaypointPermissionStatus.permanentlyDenied
      ? 'Settings'
      : 'Test';
}
