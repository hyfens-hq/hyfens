import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/waypoint_repository.dart';
import '../domain/waypoint_destination.dart';
import '../domain/waypoint_home_data.dart';
import '../domain/waypoint_activity.dart';
import '../platform/permission_handler_service.dart';
import '../platform/waypoint_permission_service.dart';
import 'waypoint_activity_notifier.dart';
import 'waypoint_home_notifier.dart';
import 'waypoint_permission_notifier.dart';
import 'waypoint_permission_state.dart';
import 'waypoint_planner_notifier.dart';
import 'waypoint_planner_state.dart';
import 'waypoint_search_notifier.dart';
import 'waypoint_ui_notifier.dart';
import 'waypoint_ui_state.dart';

final Provider<WaypointRepository> waypointRepositoryProvider =
    Provider<WaypointRepository>((ref) {
      throw StateError('WaypointRepository must be supplied by the app host');
    });

final AsyncNotifierProvider<WaypointHomeNotifier, WaypointHomeData>
waypointHomeProvider =
    AsyncNotifierProvider<WaypointHomeNotifier, WaypointHomeData>(
      WaypointHomeNotifier.new,
    );

final NotifierProvider<WaypointUiNotifier, WaypointUiState> waypointUiProvider =
    NotifierProvider<WaypointUiNotifier, WaypointUiState>(
      WaypointUiNotifier.new,
    );

final NotifierProvider<WaypointPlannerNotifier, WaypointPlannerState>
waypointPlannerProvider =
    NotifierProvider<WaypointPlannerNotifier, WaypointPlannerState>(
      WaypointPlannerNotifier.new,
    );

final AsyncNotifierProvider<WaypointSearchNotifier, List<WaypointDestination>>
waypointSearchProvider =
    AsyncNotifierProvider<WaypointSearchNotifier, List<WaypointDestination>>(
      WaypointSearchNotifier.new,
    );

final AsyncNotifierProvider<WaypointActivityNotifier, List<WaypointActivity>>
waypointActivityProvider =
    AsyncNotifierProvider.autoDispose<
      WaypointActivityNotifier,
      List<WaypointActivity>
    >(WaypointActivityNotifier.new);

final Provider<List<WaypointDestination>> waypointSavedProvider =
    Provider<List<WaypointDestination>>((ref) {
      final home = ref
          .watch(waypointHomeProvider)
          .maybeWhen(data: (value) => value, orElse: () => null);
      final ui = ref.watch(waypointUiProvider);
      if (home == null) {
        return const <WaypointDestination>[];
      }
      return home.destinations
          .where(
            (destination) =>
                ui.savedOverrides[destination.id] ?? destination.isSaved,
          )
          .toList(growable: false);
    });

final Provider<WaypointPermissionService> waypointPermissionServiceProvider =
    Provider<WaypointPermissionService>((ref) => PermissionHandlerService());

final NotifierProvider<WaypointPermissionNotifier, WaypointPermissionState>
waypointPermissionProvider =
    NotifierProvider<WaypointPermissionNotifier, WaypointPermissionState>(
      WaypointPermissionNotifier.new,
    );
