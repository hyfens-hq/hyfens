/// Platform-facing operations used by [HyfensInstallationKeyStore].
///
/// This file intentionally has no Flutter imports so the package can still be
/// tested as a pure Dart package. The conditional Flutter implementation owns
/// the MethodChannel; this implementation is the explicit unsupported-host
/// boundary.

final class HyfensInstallationKeyPlatformException implements Exception {
  const HyfensInstallationKeyPlatformException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() =>
      'HyfensInstallationKeyPlatformException($code): $message';
}

Future<Map<Object?, Object?>> getInstallationIdentity() async {
  throw const HyfensInstallationKeyPlatformException(
    code: 'keyUnavailable',
    message: 'Installation identity is unavailable on this platform.',
  );
}

Future<List<int>> signInstallationMessage(List<int> message) async {
  throw const HyfensInstallationKeyPlatformException(
    code: 'keyUnavailable',
    message: 'Installation signing is unavailable on this platform.',
  );
}
