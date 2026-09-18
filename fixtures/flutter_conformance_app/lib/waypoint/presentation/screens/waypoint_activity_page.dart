import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/waypoint_providers.dart';
import '../../domain/waypoint_home_data.dart';
import '../widgets/waypoint_activity_tile.dart';
import '../widgets/waypoint_section_header.dart';
import '../widgets/waypoint_surface.dart';

final class WaypointActivityPage extends ConsumerWidget {
  const WaypointActivityPage({super.key, required this.data});

  final WaypointHomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(waypointActivityProvider);
    final notifier = ref.read(waypointActivityProvider.notifier);
    final activities = feed.maybeWhen(
      data: (value) => value,
      orElse: () => data.activities,
    );
    return SingleChildScrollView(
      key: const ValueKey<String>('waypoint-activity-page'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              WaypointSectionHeader(
                title: 'A living plan.',
                description:
                    'Watch local response events become useful travel updates.',
                action: FilledButton.icon(
                  key: const ValueKey<String>('waypoint-activity-toggle'),
                  onPressed: notifier.isStreaming
                      ? notifier.stop
                      : notifier.start,
                  icon: Icon(
                    notifier.isStreaming
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    notifier.isStreaming ? 'Stop feed' : 'Start feed',
                  ),
                ),
              ),
              const SizedBox(height: 22),
              WaypointSurface(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.bolt_rounded,
                      size: 28,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            notifier.isStreaming
                                ? 'Listening for changes'
                                : 'The group is in sync',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'The demo stream can be cancelled without leaving an orphaned request.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (notifier.isStreaming)
                      const Padding(
                        padding: EdgeInsets.only(left: 12, top: 4),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              WaypointSurface(
                child: feed.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, stackTrace) => Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Activity failed: $error')),
                      TextButton(
                        key: const ValueKey<String>('waypoint-activity-retry'),
                        onPressed: notifier.start,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                  data: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Latest updates',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      for (final activity in activities)
                        WaypointActivityTile(activity: activity),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
