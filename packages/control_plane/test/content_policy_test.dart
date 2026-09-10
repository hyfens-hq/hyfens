import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late ControlPlaneService service;
  late BootstrapResult bootstrap;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-policy-');
    service = ControlPlaneService(store: FileControlPlaneStore(directory));
    bootstrap = await service.bootstrap(
      organizationName: 'Policy organization',
      runtimeApplicationId: 'com.example.policy',
      platformId: 'android-arm64-release',
      environmentName: 'production',
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('policy content is accepted and mutations are audited', () async {
    expect(parseContentKind('policy'), ContentKind.policy);

    final entry = await service.createContent(
      token: bootstrap.controlCredential.token,
      draft: ContentWrite(
        kind: ContentKind.policy,
        title: 'Refund Policy',
        slug: 'refund-policy',
        excerpt: 'Current billing support terms.',
        body: '# Refund Policy\n\nContact support for a billing review.',
      ),
      requestId: 'policy-create-request',
    );
    expect(entry.kind, ContentKind.policy);

    final updated = await service.updateContent(
      token: bootstrap.controlCredential.token,
      contentId: entry.id,
      draft: ContentWrite(
        title: 'Refund Policy',
        slug: 'refund-policy',
        excerpt: 'Updated billing support terms.',
        body: '# Refund Policy\n\nContact support for a billing review.',
      ),
      requestId: 'policy-update-request',
    );
    expect(updated.kind, ContentKind.policy);

    final published = await service.publishContent(
      token: bootstrap.controlCredential.token,
      contentId: entry.id,
      requestId: 'policy-publish-request',
    );
    expect(published.status, ContentStatus.published);

    final archived = await service.archiveContent(
      token: bootstrap.controlCredential.token,
      contentId: entry.id,
      requestId: 'policy-archive-request',
    );
    expect(archived.status, ContentStatus.archived);

    final audit = await service.store.readAuditChain();
    final actions = audit
        .map((record) => (record['body']! as Map)['action'])
        .whereType<String>()
        .toList();
    expect(
      actions,
      containsAll(<String>[
        'content.create',
        'content.update',
        'content.publish',
        'content.archive',
      ]),
    );
  });
}
