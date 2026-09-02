import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';
import '../waypoint_theme.dart';
import '../widgets/waypoint_logo.dart';
import '../widgets/waypoint_surface.dart';

final class WaypointNavigationRail extends ConsumerWidget {
  const WaypointNavigationRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(waypointUiProvider).section;
    final notifier = ref.read(waypointUiProvider.notifier);
    return Container(
      width: 238,
      padding: const EdgeInsets.fromLTRB(20, 26, 16, 22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const WaypointLogo(),
          const SizedBox(height: 54),
          Text(
            'Your journey',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: WaypointColors.muted),
          ),
          const SizedBox(height: 12),
          for (final section in WaypointSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: selected == section
                    ? WaypointColors.mint
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(15)),
                child: InkWell(
                  key: ValueKey<String>('waypoint-nav-${section.name}'),
                  onTap: () => notifier.selectSection(section),
                  borderRadius: const BorderRadius.all(Radius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _iconFor(section),
                          size: 20,
                          color: selected == section
                              ? WaypointColors.ink
                              : WaypointColors.muted,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _labelFor(section),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected == section
                                    ? WaypointColors.ink
                                    : WaypointColors.muted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          const WaypointSurface(
            padding: EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Icon(Icons.explore_outlined, size: 19),
                SizedBox(width: 9),
                Expanded(child: Text('Leave space for the unexpected.')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(WaypointSection section) => switch (section) {
    WaypointSection.discover => Icons.travel_explore_outlined,
    WaypointSection.trips => Icons.luggage_outlined,
    WaypointSection.saved => Icons.bookmark_border_rounded,
    WaypointSection.activity => Icons.bolt_outlined,
    WaypointSection.settings => Icons.tune_rounded,
  };

  String _labelFor(WaypointSection section) => switch (section) {
    WaypointSection.discover => 'Discover',
    WaypointSection.trips => 'Trips',
    WaypointSection.saved => 'Saved',
    WaypointSection.activity => 'Activity',
    WaypointSection.settings => 'Settings',
  };
}
