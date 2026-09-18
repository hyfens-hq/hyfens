import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/waypoint_permission.dart';
import '../platform/waypoint_permission_result.dart';
import 'waypoint_permission_state.dart';
import 'waypoint_providers.dart';

final class WaypointPermissionNotifier
    extends Notifier<WaypointPermissionState> {
  @override
  WaypointPermissionState build() => const WaypointPermissionState();

  Future<void> refresh() async {
    final service = ref.read(waypointPermissionServiceProvider);
    final next = <WaypointPermission, WaypointPermissionResult>{};
    for (final permission in WaypointPermission.values) {
      final result = await service.read(permission);
      next[permission] = result;
    }
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(next);
  }

  Future<void> request(WaypointPermission permission) async {
    final service = ref.read(waypointPermissionServiceProvider);
    final result = await service.request(permission);
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(<WaypointPermission, WaypointPermissionResult>{
      ...state.results,
      permission: result,
    });
  }

  Future<bool> openAppSettings() =>
      ref.read(waypointPermissionServiceProvider).openAppSettings();
}
