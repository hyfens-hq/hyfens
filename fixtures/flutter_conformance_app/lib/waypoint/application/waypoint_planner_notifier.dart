import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'waypoint_planner_state.dart';
import 'waypoint_providers.dart';

final class WaypointPlannerNotifier extends Notifier<WaypointPlannerState> {
  @override
  WaypointPlannerState build() => WaypointPlannerState();

  void resetForNewEntry({int? initialTravelers}) {
    state = WaypointPlannerState(travelers: initialTravelers ?? 2);
  }

  void setDestination(String value) {
    state = state.copyWith(destination: value);
  }

  void setStartDate(DateTime value) {
    state = state.copyWith(startDate: value);
    if (state.endDate.isBefore(value)) {
      state = state.copyWith(endDate: value.add(const Duration(days: 1)));
    }
  }

  void setEndDate(DateTime value) {
    state = state.copyWith(endDate: value);
  }

  void incrementTravelers({int? maxTravelers}) {
    if (maxTravelers != null && state.travelers >= maxTravelers) {
      return;
    }
    state = state.copyWith(travelers: state.travelers + 1);
  }

  void decrementTravelers({int minimumTravelers = 1}) {
    if (state.travelers > minimumTravelers) {
      state = state.copyWith(travelers: state.travelers - 1);
    }
  }

  void setTravelStyle(String value) {
    state = state.copyWith(travelStyle: value);
  }

  void submit() {
    if (state.isValid) {
      ref.read(waypointUiProvider.notifier).markPlanSubmitted();
    }
  }
}
