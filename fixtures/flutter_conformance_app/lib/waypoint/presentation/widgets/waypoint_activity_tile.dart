import 'package:flutter/material.dart';

import '../../domain/waypoint_activity.dart';
import '../waypoint_theme.dart';

final class WaypointActivityTile extends StatelessWidget {
  const WaypointActivityTile({super.key, required this.activity});

  final WaypointActivity activity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: waypointColor(activity.accentColor),
            borderRadius: const BorderRadius.all(Radius.circular(15)),
          ),
          child: Icon(
            _iconFor(activity.iconName),
            color: WaypointColors.ink,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                activity.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                activity.detail,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          activity.timeLabel,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );

  IconData _iconFor(String name) => switch (name.toLowerCase()) {
    'flight' || 'plane' => Icons.flight_takeoff_rounded,
    'stay' || 'hotel' => Icons.hotel_rounded,
    'food' || 'restaurant' => Icons.restaurant_rounded,
    'photo' || 'camera' => Icons.photo_camera_rounded,
    'spark' => Icons.auto_awesome_rounded,
    'bookmark' => Icons.bookmark_rounded,
    _ => Icons.explore_rounded,
  };
}
