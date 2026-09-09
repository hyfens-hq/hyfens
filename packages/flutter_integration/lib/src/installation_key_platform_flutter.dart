import 'package:flutter/services.dart';

import 'installation_key_platform.dart';

export 'installation_key_platform.dart'
    show HyfensInstallationKeyPlatformException;

const MethodChannel _channel = MethodChannel('hyfens/installation_identity');

Future<Map<Object?, Object?>> getInstallationIdentity() async {
  try {
    final value = await _channel.invokeMethod<Object?>('getIdentity');
    if (value is! Map<Object?, Object?>) {
      throw const HyfensInstallationKeyPlatformException(
        code: 'invalidIdentity',
        message: 'Native installation identity response is not a map.',
      );
    }
    return value;
  } on HyfensInstallationKeyPlatformException {
    rethrow;
  } on MissingPluginException catch (error) {
    throw HyfensInstallationKeyPlatformException(
      code: 'keyUnavailable',
      message: error.message ?? 'Installation identity plugin is unavailable.',
    );
  } on PlatformException catch (error) {
    throw HyfensInstallationKeyPlatformException(
      code: error.code,
      message: error.message ?? 'Native installation identity failed.',
    );
  }
}

Future<List<int>> signInstallationMessage(List<int> message) async {
  try {
    final value = await _channel.invokeMethod<Object?>(
      'sign',
      <String, Object?>{'message': Uint8List.fromList(message)},
    );
    if (value is Uint8List) return List<int>.unmodifiable(value);
    if (value is List && value.every((item) => item is int)) {
      return List<int>.unmodifiable(value.cast<int>());
    }
    throw const HyfensInstallationKeyPlatformException(
      code: 'invalidSignature',
      message: 'Native installation signature response is not bytes.',
    );
  } on HyfensInstallationKeyPlatformException {
    rethrow;
  } on MissingPluginException catch (error) {
    throw HyfensInstallationKeyPlatformException(
      code: 'keyUnavailable',
      message: error.message ?? 'Installation signing plugin is unavailable.',
    );
  } on PlatformException catch (error) {
    throw HyfensInstallationKeyPlatformException(
      code: error.code,
      message: error.message ?? 'Native installation signing failed.',
    );
  }
}
