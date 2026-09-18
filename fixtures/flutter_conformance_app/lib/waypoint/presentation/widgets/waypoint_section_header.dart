import 'package:flutter/material.dart';

import '../waypoint_theme.dart';

final class WaypointSectionHeader extends StatelessWidget {
  const WaypointSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.action,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            if (description != null) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: WaypointColors.muted),
              ),
            ],
          ],
        ),
      ),
      if (action != null) ...<Widget>[const SizedBox(width: 12), action!],
    ],
  );
}
