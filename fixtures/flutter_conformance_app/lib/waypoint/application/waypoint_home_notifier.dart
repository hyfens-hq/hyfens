import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waypoint_home_data.dart';
import 'waypoint_providers.dart';

final class WaypointHomeNotifier extends AsyncNotifier<WaypointHomeData> {
  @override
  Future<WaypointHomeData> build() =>
      ref.watch(waypointRepositoryProvider).loadHome();

  Future<void> reload() async {
    state = const AsyncLoading<WaypointHomeData>();
    state = await AsyncValue.guard(
      () => ref.read(waypointRepositoryProvider).loadHome(),
    );
  }
}
