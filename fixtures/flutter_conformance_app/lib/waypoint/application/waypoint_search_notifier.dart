import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waypoint_destination.dart';
import 'waypoint_providers.dart';

final class WaypointSearchNotifier
    extends AsyncNotifier<List<WaypointDestination>> {
  int _generation = 0;

  @override
  Future<List<WaypointDestination>> build() async {
    final home = await ref.watch(waypointHomeProvider.future);
    return home.destinations;
  }

  Future<void> search(String query) async {
    final normalized = query.trim();
    final generation = ++_generation;
    if (normalized.isEmpty) {
      final home = await ref.read(waypointHomeProvider.future);
      if (generation == _generation) {
        state = AsyncData<List<WaypointDestination>>(home.destinations);
      }
      return;
    }
    state = const AsyncLoading<List<WaypointDestination>>();
    final repository = ref.read(waypointRepositoryProvider);
    final result = await AsyncValue.guard(
      () => repository.searchDestinations(normalized),
    );
    if (generation == _generation) {
      state = result;
    }
  }
}
