import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hyfens_flutter_integration/src/installation_key.dart';
import 'package:test/test.dart';

const _publicKey = <int>[
  0x04,
  0x6b,
  0x17,
  0xd1,
  0xf2,
  0xe1,
  0x2c,
  0x42,
  0x47,
  0xf8,
  0xbc,
  0xe6,
  0xe5,
  0x63,
  0xa4,
  0x40,
  0xf2,
  0x77,
  0x03,
  0x7d,
  0x81,
  0x2d,
  0xeb,
  0x33,
  0xa0,
  0xf4,
  0xa1,
  0x39,
  0x45,
  0xd8,
  0x98,
  0xc2,
  0x96,
  0x4f,
  0xe3,
  0x42,
  0xe2,
  0xfe,
  0x1a,
  0x7f,
  0x9b,
  0x8e,
  0xe7,
  0xeb,
  0x4a,
  0x7c,
  0x0f,
  0x9e,
  0x16,
  0x2b,
  0xce,
  0x33,
  0x57,
  0x6b,
  0x31,
  0x5e,
  0xce,
  0xcb,
  0xb6,
  0x40,
  0x68,
  0x37,
  0xbf,
  0x51,
  0xf5,
];

void main() {
  final installationId = base64Url
      .encode(List<int>.filled(32, 0x2a))
      .replaceAll('=', '');
  final keyId = sha256.convert(_publicKey).toString();

  group('HyfensInstallationIdentity', () {
    test('round-trips validated native metadata and protects byte lists', () {
      final identity = HyfensInstallationIdentity(
        installationId: installationId,
        keyId: keyId,
        publicKey: _publicKey,
        storageProtection: HyfensInstallationStorageProtection.hardwareBacked,
      );

      final map = identity.toMap();
      final decoded = HyfensInstallationIdentity.fromMap(<Object?, Object?>{
        ...map,
        'publicKey': Uint8List.fromList(_publicKey),
      });

      expect(decoded.installationId, installationId);
      expect(decoded.keyId, keyId);
      expect(decoded.publicKey, _publicKey);
      expect(
        decoded.storageProtection,
        HyfensInstallationStorageProtection.hardwareBacked,
      );
      expect(() => decoded.publicKey[0] = 0, throwsUnsupportedError);
    });

    test('rejects malformed IDs, public keys, and key bindings', () {
      expect(
        () => HyfensInstallationIdentity(
          installationId: 'not-an-installation-id',
          keyId: keyId,
          publicKey: _publicKey,
          storageProtection:
              HyfensInstallationStorageProtection.platformProtected,
        ),
        throwsFormatException,
      );
      expect(
        () => HyfensInstallationIdentity(
          installationId: installationId,
          keyId: keyId,
          publicKey: <int>[..._publicKey.sublist(0, 64), 0x05],
          storageProtection:
              HyfensInstallationStorageProtection.platformProtected,
        ),
        throwsFormatException,
      );
      expect(
        () => HyfensInstallationIdentity(
          installationId: installationId,
          keyId: '0' * 64,
          publicKey: _publicKey,
          storageProtection:
              HyfensInstallationStorageProtection.platformProtected,
        ),
        throwsFormatException,
      );
    });
  });

  group('HyfensInstallationKeyStore', () {
    test('unsupported hosts return explicit keyUnavailable', () async {
      final store = HyfensInstallationKeyStore();

      await expectLater(
        store.getIdentity(),
        throwsA(
          isA<HyfensInstallationKeyException>().having(
            (error) => error.code,
            'code',
            HyfensInstallationKeyException.keyUnavailable,
          ),
        ),
      );
      await expectLater(
        store.sign(const <int>[1, 2, 3]),
        throwsA(
          isA<HyfensInstallationKeyException>().having(
            (error) => error.code,
            'code',
            HyfensInstallationKeyException.keyUnavailable,
          ),
        ),
      );
    });

    test(
      'rejects values outside the byte range before platform dispatch',
      () async {
        final store = HyfensInstallationKeyStore();

        await expectLater(store.sign(<int>[256]), throwsFormatException);
        await expectLater(
          store.sign(List<int>.filled(16 * 1024 + 1, 0)),
          throwsFormatException,
        );
      },
    );
  });
}
