import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('public repository foundation exists', () {
    const requiredPaths = <String>[
      'README.md',
      'LICENSE',
      'CONTRIBUTING.md',
      'THIRD_PARTY_NOTICES.md',
      'TRADEMARKS.md',
      'docs/ASSET_PROVENANCE.md',
      'deploy/self-hosted/README.md',
      'deploy/self-hosted/docker-compose.yml',
    ];

    for (final path in requiredPaths) {
      expect(File(path).existsSync(), isTrue, reason: '$path is required');
    }
  });
}
