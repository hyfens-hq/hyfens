import 'package:flutter/material.dart';

import '../../domain/waypoint_trip.dart';
import '../waypoint_theme.dart';
import 'waypoint_asset_artwork.dart';

final class WaypointTripCard extends StatelessWidget {
  const WaypointTripCard({super.key, required this.trip, required this.onTap});

  final WaypointTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open ${trip.title}',
    child: InkWell(
      key: ValueKey<String>('waypoint-trip-${trip.id}'),
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(26)),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(26)),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(26)),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: WaypointAssetArtwork(
                  assetPath: trip.imageAsset,
                  semanticsLabel: '${trip.destination} trip',
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: WaypointColors.paper.withValues(alpha: 0.88),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(100),
                            ),
                          ),
                          child: Text(
                            'Upcoming trip',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: WaypointColors.ink),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.arrow_outward_rounded,
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      trip.title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trip.destination,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    if (trip.coverLabel != null &&
                        trip.coverLabel!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        trip.coverLabel!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              minHeight: 7,
                              value: trip.progress,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.25,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                waypointColor(trip.accentColor ?? ''),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(trip.progress * 100).round()}%',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      '${trip.dateRange}  |  ${trip.durationLabel}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
