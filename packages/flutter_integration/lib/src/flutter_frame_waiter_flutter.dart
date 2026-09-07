import 'package:flutter/widgets.dart';

/// Waits for Flutter's next frame without exposing Flutter types to the
/// host-independent integration library.
Future<void> hyfensFlutterFrameWaiter() => WidgetsBinding.instance.endOfFrame;
