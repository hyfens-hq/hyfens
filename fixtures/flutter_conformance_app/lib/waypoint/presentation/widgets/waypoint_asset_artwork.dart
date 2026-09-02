import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../waypoint_theme.dart';

final class WaypointAssetArtwork extends StatelessWidget {
  const WaypointAssetArtwork({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.cover,
    this.semanticsLabel,
  });

  final String assetPath;
  final BoxFit fit;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (assetPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        assetPath,
        fit: fit,
        semanticsLabel: semanticsLabel,
        placeholderBuilder: (_) => const _ArtworkPlaceholder(),
      );
    }
    return Image.asset(
      assetPath,
      fit: fit,
      semanticLabel: semanticsLabel,
      errorBuilder: (context, error, stackTrace) => const _ArtworkPlaceholder(),
    );
  }
}

final class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: <Color>[
          Theme.of(context).colorScheme.secondaryContainer,
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: const Center(
      child: Icon(Icons.landscape_outlined, color: WaypointColors.muted),
    ),
  );
}
