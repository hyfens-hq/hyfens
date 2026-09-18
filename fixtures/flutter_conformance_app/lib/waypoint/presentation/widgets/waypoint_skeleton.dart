import 'package:flutter/material.dart';

import 'waypoint_surface.dart';

final class WaypointSkeletonBox extends StatefulWidget {
  const WaypointSkeletonBox({
    super.key,
    this.height = 20,
    this.width,
    this.borderRadius = 12,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  State<WaypointSkeletonBox> createState() => _WaypointSkeletonBoxState();
}

final class _WaypointSkeletonBoxState extends State<WaypointSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final alignment = reduceMotion
          ? Alignment.center
          : Alignment(-1.4 + (_controller.value * 2.8), 0);
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: alignment,
            end: Alignment(alignment.x + 1.1, alignment.y),
            colors: <Color>[
              Theme.of(context).colorScheme.surfaceContainerHighest,
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
      );
    },
  );
}

final class WaypointDestinationSkeleton extends StatelessWidget {
  const WaypointDestinationSkeleton({super.key});

  @override
  Widget build(BuildContext context) => WaypointSurface(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WaypointSkeletonBox(height: 150, width: double.infinity),
        const SizedBox(height: 14),
        const WaypointSkeletonBox(width: 150),
        const SizedBox(height: 8),
        const WaypointSkeletonBox(width: 100),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            const WaypointSkeletonBox(width: 54, height: 14),
            const Spacer(),
            const WaypointSkeletonBox(width: 45, height: 14),
          ],
        ),
      ],
    ),
  );
}
