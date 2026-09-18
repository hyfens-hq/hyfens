import 'package:flutter/material.dart';

import '../../domain/waypoint_destination.dart';
import '../waypoint_theme.dart';
import 'waypoint_asset_artwork.dart';
import 'waypoint_surface.dart';

final class WaypointDestinationCard extends StatelessWidget {
  const WaypointDestinationCard({
    super.key,
    required this.destination,
    required this.isSaved,
    required this.onTap,
    required this.onSave,
  });

  final WaypointDestination destination;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final distance = destination.distance;
    return Semantics(
      button: true,
      label: 'Open ${destination.name}',
      child: InkWell(
        key: ValueKey<String>('waypoint-destination-${destination.id}'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: WaypointSurface(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 1.22,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      WaypointAssetArtwork(
                        assetPath: destination.imageAsset,
                        semanticsLabel: '${destination.name} destination',
                      ),
                      if (destination.emoji != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: DecoratedBox(
                            key: ValueKey<String>(
                              'waypoint-destination-emoji-${destination.id}',
                            ),
                            decoration: BoxDecoration(
                              color: WaypointColors.paper.withValues(
                                alpha: 0.88,
                              ),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(100),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                destination.emoji!,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: WaypointColors.ink),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          key: ValueKey<String>(
                            'waypoint-save-${destination.id}',
                          ),
                          onPressed: onSave,
                          tooltip: isSaved
                              ? 'Remove saved place'
                              : 'Save place',
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                destination.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                destination.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (distance != null && distance.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  distance,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.star_rounded,
                    size: 17,
                    color: waypointColor(destination.accentColor),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    destination.rating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      destination.durationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
