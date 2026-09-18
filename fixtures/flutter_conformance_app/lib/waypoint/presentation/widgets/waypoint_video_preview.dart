import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../data/waypoint_asset_paths.dart';
import 'waypoint_skeleton.dart';

const _defaultVideoTitle = 'A slower morning in Kyoto';

final class WaypointVideoPreview extends StatefulWidget {
  const WaypointVideoPreview({
    super.key,
    this.assetPath,
    this.title,
    this.playLabel,
  });

  final String? assetPath;
  final String? title;
  final String? playLabel;

  @override
  State<WaypointVideoPreview> createState() => _WaypointVideoPreviewState();
}

final class _WaypointVideoPreviewState extends State<WaypointVideoPreview> {
  late final VideoPlayerController _controller;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      _nonEmptyOrDefault(widget.assetPath, WaypointAssetPaths.destinationVideo),
    );
    _ready = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    key: const ValueKey<String>('waypoint-video'),
    borderRadius: const BorderRadius.all(Radius.circular(26)),
    child: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _VideoUnavailable();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const AspectRatio(
            aspectRatio: 1.5,
            child: WaypointSkeletonBox(height: double.infinity),
          );
        }
        final playLabel = _nonEmptyOrNull(widget.playLabel);
        return AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              VideoPlayer(_controller),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  children: <Widget>[
                    IconButton.filled(
                      key: const ValueKey<String>('waypoint-video-play'),
                      tooltip: playLabel,
                      onPressed: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                      icon: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _nonEmptyOrDefault(widget.title, _defaultVideoTitle),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _nonEmptyOrDefault(String? value, String fallback) =>
    value?.trim().isNotEmpty ?? false ? value! : fallback;

String? _nonEmptyOrNull(String? value) =>
    value?.trim().isNotEmpty ?? false ? value : null;

final class _VideoUnavailable extends StatelessWidget {
  const _VideoUnavailable();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.5,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Video asset unavailable for this build.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    ),
  );
}
