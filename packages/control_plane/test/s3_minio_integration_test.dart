import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  final endpoint = Platform.environment['HYFENS_TEST_S3_ENDPOINT'];
  final accessKey = Platform.environment['HYFENS_TEST_S3_ACCESS_KEY'];
  final secretKey = Platform.environment['HYFENS_TEST_S3_SECRET_KEY'];
  final bucket =
      Platform.environment['HYFENS_TEST_S3_BUCKET'] ?? 'hyfens-artifacts';
  if (endpoint == null || accessKey == null || secretKey == null) {
    test(
      'MinIO integration requires HYFENS_TEST_S3_*',
      () {},
      skip: 'S3-compatible integration environment is not configured',
    );
    return;
  }

  test(
    'standard S3-compatible signing and immutable object flow work',
    () async {
      final store = S3CompatibleArtifactStore(
        endpoint: Uri.parse(endpoint),
        bucket: bucket,
        accessKey: accessKey,
        secretKey: secretKey,
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final bytes = <int>[
        11,
        12,
        13,
        14,
        15,
        stamp & 0xff,
        (stamp >> 8) & 0xff,
        (stamp >> 16) & 0xff,
      ];
      final digest = sha256Digest(bytes);
      await store.putArtifact(digest, bytes);
      await store.putArtifact(digest, bytes);
      expect(await store.readArtifact(digest), bytes);
    },
  );

  test('the endpoint returns a normal response for bad credentials', () async {
    final store = S3CompatibleArtifactStore(
      endpoint: Uri.parse(endpoint),
      bucket: bucket,
      authorization: 'Bearer deliberately-invalid',
    );
    await expectLater(
      store.readArtifact('sha256:${'0' * 64}'),
      throwsA(isA<StorageUnavailable>()),
    );
  });

  final existingDigest = Platform.environment['HYFENS_TEST_S3_EXISTING_DIGEST'];
  if (existingDigest != null) {
    test('reads an existing digest-addressed object', () async {
      final store = S3CompatibleArtifactStore(
        endpoint: Uri.parse(endpoint),
        bucket: bucket,
        accessKey: accessKey,
        secretKey: secretKey,
      );
      final bytes = await store.readArtifact(existingDigest);
      expect(bytes, isNotNull);
      expect(sha256Digest(bytes!), existingDigest);
    });
  }
}
