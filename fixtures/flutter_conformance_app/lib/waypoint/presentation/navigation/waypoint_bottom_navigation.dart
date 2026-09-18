import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';

final class WaypointBottomNavigation extends ConsumerWidget {
  const WaypointBottomNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(waypointUiProvider).section;
    return NavigationBar(
      key: const ValueKey<String>('waypoint-bottom-navigation'),
      selectedIndex: section.index,
      onDestinationSelected: (index) => ref
          .read(waypointUiProvider.notifier)
          .selectSection(WaypointSection.values[index]),
      destinations: const <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.travel_explore_outlined),
          selectedIcon: Icon(Icons.travel_explore_rounded),
          label: 'Discover',
        ),
        NavigationDestination(
          icon: Icon(Icons.luggage_outlined),
          selectedIcon: Icon(Icons.luggage_rounded),
          label: 'Trips',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
          label: 'Saved',
        ),
        NavigationDestination(
          icon: Icon(Icons.bolt_outlined),
          selectedIcon: Icon(Icons.bolt_rounded),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune_rounded),
          label: 'Settings',
        ),
      ],
    );
  }
}
