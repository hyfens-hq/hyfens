import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../application/waypoint_ui_state.dart';
import '../../domain/waypoint_destination.dart';
import '../../domain/waypoint_home_data.dart';
import '../widgets/waypoint_destination_card.dart';
import '../widgets/waypoint_section_header.dart';
import '../widgets/waypoint_surface.dart';

final class WaypointSavedPage extends ConsumerWidget {
  const WaypointSavedPage({super.key, required this.data});

  final WaypointHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(waypointSavedProvider);
    return SingleChildScrollView(
      key: const ValueKey<String>('waypoint-saved-page'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const WaypointSectionHeader(
                title: 'Saved for later.',
                description: 'A short list beats a crowded itinerary.',
              ),
              const SizedBox(height: 22),
              if (saved.isEmpty)
                _EmptySaved(
                  onDiscover: () => ref
                      .read(waypointUiProvider.notifier)
                      .selectSection(WaypointSection.discover),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: saved.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 420,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final destination = saved[index];
                    return WaypointDestinationCard(
                      destination: destination,
                      isSaved: true,
                      onTap: () => _showSaved(context, destination, ref),
                      onSave: () => ref
                          .read(waypointUiProvider.notifier)
                          .toggleSaved(destination),
                    );
                  },
                ),
              if (data.destinations.isNotEmpty && saved.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                Text(
                  'You have ${saved.length} saved place${saved.length == 1 ? '' : 's'}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSaved(
    BuildContext context,
    WaypointDestination destination,
    WidgetRef ref,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              destination.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              destination.summary,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('waypoint-saved-detail-discover'),
              onPressed: () {
                Navigator.of(context).pop();
                ref
                    .read(waypointUiProvider.notifier)
                    .openDiscoverForDestination(destination.id);
              },
              icon: const Icon(Icons.travel_explore_outlined),
              label: const Text(
                'Open Discover to compare this place with the full list.',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _EmptySaved extends StatelessWidget {
  const _EmptySaved({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) => WaypointSurface(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          const Icon(Icons.bookmark_border_rounded, size: 34),
          const SizedBox(height: 12),
          const Text('Nothing saved yet.'),
          const SizedBox(height: 5),
          const Text('Use the bookmark on a destination to keep it here.'),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey<String>('waypoint-saved-discover'),
            onPressed: onDiscover,
            child: const Text('Browse destinations'),
          ),
        ],
      ),
    ),
  );
}
