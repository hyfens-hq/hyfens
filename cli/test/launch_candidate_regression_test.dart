import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('profile selection stays within a persisted catalog', () {
    final catalog = ProfileSet(
      profiles: <CliProfile>[
        CliProfile(
          name: 'self-hosted',
          endpoint: Uri.parse('https://acme.example/p2/'),
          managed: false,
        ),
      ],
    );

    expect(catalog.active.name, 'self-hosted');
    expect(catalog.active.endpoint.host, 'acme.example');
  });

  test(
    'removing another host does not clear the active legacy session',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-remove-host-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);
      final activeEndpoint = Uri.parse('https://active.example/p2/');
      final otherEndpoint = Uri.parse('https://other.example/p2/');

      await storage.writeNamedProfile(
        CliProfile(
          name: 'active',
          endpoint: activeEndpoint,
          managed: false,
          organizationId: 'org_active',
        ),
      );
      await storage.writeNamedProfile(
        CliProfile(
          name: 'other',
          endpoint: otherEndpoint,
          managed: false,
          organizationId: 'org_other',
        ),
        makeActive: false,
      );
      await storage.writeProfile(
        Profile(
          endpoint: activeEndpoint,
          email: 'operator@example.com',
          profiles: const <ProfileScope>[
            ProfileScope(
              name: 'active',
              organizationId: 'org_active',
              role: 'owner',
            ),
          ],
        ),
      );
      await storage.writeSession(
        const AuthSession(
          accessToken: 'active-access',
          sessionToken: 'active-session',
        ),
      );

      await storage.removeNamedProfile('other');

      expect(
        (await storage.readSession(endpoint: activeEndpoint))?.accessToken,
        'active-access',
      );
      expect(storage.sessionFile.existsSync(), isTrue);
    },
  );

  test('removing one profile preserves a shared endpoint session', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-remove-shared-');
    addTearDown(() => root.delete(recursive: true));
    final storage = AuthStorage(root: root);
    final endpoint = Uri.parse('https://shared.example/p2/');

    await storage.writeNamedProfile(
      CliProfile(
        name: 'first-scope',
        endpoint: endpoint,
        managed: false,
        organizationId: 'org_first',
      ),
    );
    await storage.writeNamedProfile(
      CliProfile(
        name: 'second-scope',
        endpoint: endpoint,
        managed: false,
        organizationId: 'org_second',
      ),
      makeActive: false,
    );
    await storage.writeSession(
      const AuthSession(
        accessToken: 'shared-access',
        sessionToken: 'shared-session',
      ),
      endpoint: endpoint,
    );

    await storage.removeNamedProfile('second-scope');

    expect(
      (await storage.readSession(endpoint: endpoint))?.accessToken,
      'shared-access',
    );
  });

  test(
    'auth status reads local session state without refreshing access',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-auth-status-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);
      final endpoint = Uri.parse('http://127.0.0.1:1/p2/');

      await storage.writeProfile(
        Profile(
          endpoint: endpoint,
          email: 'operator@example.com',
          profiles: const <ProfileScope>[
            ProfileScope(
              name: 'local',
              organizationId: 'org_local',
              role: 'owner',
            ),
          ],
        ),
      );
      await storage.writeSession(
        AuthSession(
          accessToken: 'expired-access',
          sessionToken: 'refresh-secret',
          expiresAt: DateTime.utc(2020),
          sessionExpiresAt: DateTime.now().toUtc().add(
            const Duration(hours: 1),
          ),
        ),
        endpoint: endpoint,
      );

      final profile = await AuthClient(storage: storage).status();

      expect(profile?.email, 'operator@example.com');
      expect(profile?.endpoint, endpoint);
    },
  );
}
