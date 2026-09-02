import 'package:alphax/alphax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waypoint_activity.dart';
import 'waypoint_providers.dart';

final class WaypointActivityNotifier
    extends AsyncNotifier<List<WaypointActivity>> {
  AlphaXCancellationToken? _cancellationToken;
  bool isStreaming = false;

  @override
  Future<List<WaypointActivity>> build() async {
    ref.onDispose(() => stop(notify: false));
    final home = await ref.watch(waypointHomeProvider.future);
    return home.activities;
  }

  Future<void> start() async {
    if (isStreaming) {
      return;
    }
    isStreaming = true;
    _cancellationToken = AlphaXCancellationToken();
    state = const AsyncData<List<WaypointActivity>>(<WaypointActivity>[]);
    final repository = ref.read(waypointRepositoryProvider);
    var streamFailed = false;
    try {
      await for (final activity in repository.watchActivities(
        cancellationToken: _cancellationToken,
      )) {
        final existing = state.value ?? const <WaypointActivity>[];
        state = AsyncData<List<WaypointActivity>>(<WaypointActivity>[
          activity,
          ...existing,
        ]);
      }
    } catch (error, stackTrace) {
      if (error is! AlphaXCancellationException) {
        streamFailed = true;
        state = AsyncError<List<WaypointActivity>>(error, stackTrace);
      }
    } finally {
      isStreaming = false;
      _cancellationToken = null;
      if (ref.mounted && !streamFailed) {
        state = AsyncData<List<WaypointActivity>>(
          state.value ?? const <WaypointActivity>[],
        );
      }
    }
  }

  void stop({bool notify = true}) {
    _cancellationToken?.cancel('Activity stream stopped by the user');
    _cancellationToken = null;
    isStreaming = false;
    if (notify) {
      state = AsyncData<List<WaypointActivity>>(
        state.value ?? const <WaypointActivity>[],
      );
    }
  }
}
