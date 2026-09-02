import 'dart:async';

import 'package:conformance/waypoint/data/waypoint_asset_paths.dart';
import 'package:conformance/waypoint/presentation/widgets/waypoint_video_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  testWidgets('initializes the local video and toggles playback', (
    tester,
  ) async {
    final VideoPlayerPlatform previousPlatform = VideoPlayerPlatform.instance;
    final _FakeVideoPlayerPlatform fakePlatform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WaypointVideoPreview())),
    );
    await tester.pump();

    expect(fakePlatform.creationOptions, hasLength(1));
    expect(
      fakePlatform.creationOptions.single.dataSource.sourceType,
      DataSourceType.asset,
    );
    expect(
      fakePlatform.creationOptions.single.dataSource.asset,
      WaypointAssetPaths.destinationVideo,
    );

    final Finder playButton = find.byKey(
      const ValueKey<String>('waypoint-video-play'),
    );
    expect(playButton, findsOneWidget);
    expect(
      find.descendant(
        of: playButton,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );

    fakePlatform.commands.clear();
    await tester.tap(playButton);
    await tester.pump();
    expect(fakePlatform.commands, <String>['play']);
    expect(
      find.descendant(
        of: playButton,
        matching: find.byIcon(Icons.pause_rounded),
      ),
      findsOneWidget,
    );

    fakePlatform.commands.clear();
    await tester.tap(playButton);
    await tester.pump();
    expect(fakePlatform.commands, <String>['pause']);
    expect(
      find.descendant(
        of: playButton,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('renders the unavailable state for a video error event', (
    tester,
  ) async {
    final VideoPlayerPlatform previousPlatform = VideoPlayerPlatform.instance;
    final _FakeVideoPlayerPlatform fakePlatform = _FakeVideoPlayerPlatform(
      emitError: true,
    );
    VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VideoPlayerPlatform.instance = previousPlatform;
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WaypointVideoPreview())),
    );
    await tester.pump();

    expect(fakePlatform.creationOptions, hasLength(1));
    expect(
      find.text('Video asset unavailable for this build.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('waypoint-video-play')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.emitError = false});

  final bool emitError;
  final List<VideoCreationOptions> creationOptions = <VideoCreationOptions>[];
  final List<String> commands = <String>[];
  final Map<int, StreamController<VideoEvent>> _eventStreams =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final int playerId = _nextPlayerId++;
    final StreamController<VideoEvent> eventStream =
        StreamController<VideoEvent>();
    creationOptions.add(options);
    _eventStreams[playerId] = eventStream;
    eventStream.onListen = () {
      scheduleMicrotask(() {
        if (eventStream.isClosed) {
          return;
        }
        if (emitError) {
          eventStream.addError(
            PlatformException(
              code: 'VideoError',
              message: 'Video asset unavailable for this build.',
            ),
          );
          unawaited(eventStream.close());
          return;
        }
        eventStream.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 1),
            size: const Size(640, 360),
          ),
        );
      });
    };
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _eventStreams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    commands.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    commands.add('pause');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {
    final StreamController<VideoEvent>? eventStream = _eventStreams.remove(
      playerId,
    );
    if (eventStream != null && !eventStream.isClosed) {
      unawaited(eventStream.close());
    }
  }
}
