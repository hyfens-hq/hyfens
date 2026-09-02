import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waypoint_destination.dart';
import 'waypoint_ui_state.dart';

final class WaypointUiNotifier extends Notifier<WaypointUiState> {
  @override
  WaypointUiState build() => const WaypointUiState();

  void selectSection(WaypointSection section) {
    state = state.copyWith(
      section: section,
      clearLastAction: true,
      clearSelectedDestination: section != WaypointSection.discover,
    );
  }

  void openDiscoverForDestination(String destinationId) {
    state = state.copyWith(
      section: WaypointSection.discover,
      selectedDestinationId: destinationId,
      clearLastAction: true,
    );
  }

  void setThemeChoice(WaypointThemeChoice choice) {
    state = state.copyWith(themeChoice: choice);
  }

  void setFilter(WaypointDestinationFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void toggleSaved(WaypointDestination destination) {
    final current = state.savedOverrides[destination.id] ?? destination.isSaved;
    final overrides = <String, bool>{
      ...state.savedOverrides,
      destination.id: !current,
    };
    state = state.copyWith(
      savedOverrides: overrides,
      lastAction: !current
          ? '${destination.name} saved'
          : '${destination.name} removed from saved',
    );
  }

  bool isSaved(WaypointDestination destination) =>
      state.savedOverrides[destination.id] ?? destination.isSaved;

  void dismissOffer(String offerId) {
    state = state.copyWith(dismissedOfferId: offerId);
  }

  void restoreOffer() {
    state = state.copyWith(clearDismissedOffer: true);
  }

  void markPlanSubmitted() {
    state = state.copyWith(
      planSubmitted: true,
      lastAction: 'Your planning brief is ready to review',
    );
  }

  void clearAction() {
    state = state.copyWith(clearLastAction: true);
  }
}
