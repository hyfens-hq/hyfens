enum WaypointSection { discover, trips, saved, activity, settings }

enum WaypointThemeChoice { system, light, dark }

enum WaypointDestinationFilter { all, stay, food, nature, culture }

final class WaypointUiState {
  const WaypointUiState({
    this.section = WaypointSection.discover,
    this.themeChoice = WaypointThemeChoice.system,
    this.filter = WaypointDestinationFilter.all,
    this.query = '',
    this.savedOverrides = const <String, bool>{},
    this.selectedDestinationId,
    this.dismissedOfferId,
    this.planSubmitted = false,
    this.lastAction,
  });

  final WaypointSection section;
  final WaypointThemeChoice themeChoice;
  final WaypointDestinationFilter filter;
  final String query;
  final Map<String, bool> savedOverrides;
  final String? selectedDestinationId;
  final String? dismissedOfferId;
  final bool planSubmitted;
  final String? lastAction;

  WaypointUiState copyWith({
    WaypointSection? section,
    WaypointThemeChoice? themeChoice,
    WaypointDestinationFilter? filter,
    String? query,
    Map<String, bool>? savedOverrides,
    String? selectedDestinationId,
    bool clearSelectedDestination = false,
    String? dismissedOfferId,
    bool clearDismissedOffer = false,
    bool? planSubmitted,
    String? lastAction,
    bool clearLastAction = false,
  }) => WaypointUiState(
    section: section ?? this.section,
    themeChoice: themeChoice ?? this.themeChoice,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    savedOverrides: savedOverrides ?? this.savedOverrides,
    selectedDestinationId: clearSelectedDestination
        ? null
        : selectedDestinationId ?? this.selectedDestinationId,
    dismissedOfferId: clearDismissedOffer
        ? null
        : dismissedOfferId ?? this.dismissedOfferId,
    planSubmitted: planSubmitted ?? this.planSubmitted,
    lastAction: clearLastAction ? null : lastAction ?? this.lastAction,
  );
}
