import 'package:flutter/material.dart';

import '../waypoint_theme.dart';

final class WaypointLogo extends StatelessWidget {
  const WaypointLogo({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: compact ? 34 : 40,
        height: compact ? 34 : 40,
        decoration: const BoxDecoration(
          color: WaypointColors.ink,
          borderRadius: BorderRadius.all(Radius.circular(13)),
        ),
        child: const Icon(
          Icons.explore_rounded,
          color: WaypointColors.mint,
          size: 22,
        ),
      ),
      if (!compact) ...<Widget>[
        const SizedBox(width: 10),
        Text(
          'waypoint',
          style: TextStyle(
            color: WaypointColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    ],
  );
}
