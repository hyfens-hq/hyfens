import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path_provider_android/path_provider_android.dart'
    as path_provider_android;
import 'package:path_provider_foundation/path_provider_foundation.dart'
    as path_provider_foundation;

Future<Directory> applicationSupportDirectory() {
  // The generated bootstrap is intentionally started before runApp(). The
  // platform channel used by path_provider still requires the Flutter
  // binding to exist, so initialize only the binding here without delaying
  // the first frame on a patch/network operation.
  WidgetsFlutterBinding.ensureInitialized();
  // The tool's runtime package is added through a build overlay rather than
  // the application's pubspec. Flutter's generated Dart plugin registrant
  // therefore cannot be relied on to discover this transitive implementation
  // when the normal build is invoked with --no-pub. Register only the
  // runtime-owned path provider implementation before using its API. The
  // Android implementation is pinned to the Pigeon variant in pubspec.yaml;
  // the newer JNI-backed variant cannot be initialized during this bootstrap.
  if (Platform.isAndroid) {
    path_provider_android.PathProviderAndroid.registerWith();
  } else if (Platform.isIOS || Platform.isMacOS) {
    path_provider_foundation.PathProviderFoundation.registerWith();
  }
  return path_provider.getApplicationSupportDirectory();
}
