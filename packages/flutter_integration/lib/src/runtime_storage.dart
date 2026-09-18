import 'dart:io';

import 'runtime_storage_platform.dart'
    if (dart.library.ui) 'runtime_storage_platform_flutter.dart'
    as platform;

typedef RuntimeStorageRootProvider = Future<Directory> Function();

/// Resolves the private, app-owned root used by the E1 controller.
///
/// This file is an internal package seam. The Flutter implementation obtains
/// the host-provided application-support directory; host tests can supply a
/// temporary directory without loading Flutter or a platform plugin.
Future<Directory> runtimeStorageDirectory({
  required String appId,
  required String releaseId,
  RuntimeStorageRootProvider? rootProvider,
}) async {
  _validateComponent(appId, 'appId');
  _validateComponent(releaseId, 'releaseId');

  final root = await (rootProvider ?? platform.applicationSupportDirectory)();
  final storage = Directory(
    _join(root.path, <String>['hyfens', appId, releaseId]),
  );
  _assertWithinRoot(root, storage);
  return storage;
}

void _validateComponent(String value, String name) {
  if (value.isEmpty || value == '.' || value == '..') {
    throw ArgumentError.value(value, name, 'must be a single path component');
  }
  if (value.contains('/') || value.contains(r'\')) {
    throw ArgumentError.value(value, name, 'must not contain path separators');
  }
  if (value.codeUnits.any((unit) => unit == 0 || unit < 0x20)) {
    throw ArgumentError.value(
      value,
      name,
      'must not contain control characters',
    );
  }
}

String _join(String root, List<String> components) {
  final separator = Platform.pathSeparator;
  var result = root;
  while (result.length > 1 && result.endsWith(separator)) {
    result = result.substring(0, result.length - separator.length);
  }
  for (final component in components) {
    result = '$result$separator$component';
  }
  return result;
}

void _assertWithinRoot(Directory root, Directory child) {
  final separator = Platform.pathSeparator;
  final rootPath = root.absolute.path;
  final childPath = child.absolute.path;
  final rootPrefix = rootPath.endsWith(separator)
      ? rootPath
      : '$rootPath$separator';
  if (!childPath.startsWith(rootPrefix)) {
    throw StateError('Runtime storage escaped the application support root');
  }
}
