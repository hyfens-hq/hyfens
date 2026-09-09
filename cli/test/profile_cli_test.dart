import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('managed endpoint is hidden only in public profile projections', () {
    final profile = CliProfile(
      name: managedCloudProfileName,
      endpoint: Uri.parse(managedCloudApiBase),
      managed: true,
    );
    final publicMetadata = profile.toPublicMetadataJson();

    expect(profile.toMetadataJson()['endpoint'], managedCloudApiBase);
    expect(publicMetadata['endpoint'], managedCloudDisplayName);
    expect(publicMetadata['endpoint'], isNot(contains('api.hyfens.com')));
    expect(
      displayControlPlaneUri(
        Uri.parse('https://api.hyfens.com/p2/v1/organizations/org_1'),
      ),
      managedCloudDisplayName,
    );
    expect(
      displayControlPlaneUri(Uri.parse('https://self-host.example/p2/v1')),
      'https://self-host.example/p2/v1',
    );
    expect(
      Profile(endpoint: Uri.parse(managedCloudApiBase))
          .toPublicJson()['endpoint'],
      managedCloudDisplayName,
    );
  });

  test(
    'profiles select host-bound sessions without cross-host fallback',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-profile-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);
      final first = Uri.parse('https://one.example/p2/');
      final second = Uri.parse('https://two.example/p2/');

      await storage.writeNamedProfile(
        CliProfile(
          name: 'one',
          endpoint: first,
          managed: false,
          organizationId: 'org_one',
          applicationId: 'app_one',
          environmentId: 'env_one',
        ),
      );
      await storage.writeNamedProfile(
        CliProfile(
          name: 'two',
          endpoint: second,
          managed: false,
          organizationId: 'org_two',
          applicationId: 'app_two',
          environmentId: 'env_two',
        ),
        makeActive: false,
      );
      await storage.writeSession(
        const AuthSession(
          accessToken: 'access-one',
          sessionToken: 'session-one',
        ),
        endpoint: first,
      );
      await storage.writeSession(
        const AuthSession(
          accessToken: 'access-two',
          sessionToken: 'session-two',
        ),
        endpoint: second,
      );

      await storage.useProfile('two');
      expect((await storage.readActiveProfile()).name, 'two');
      expect(
        (await storage.readSession(endpoint: first))!.accessToken,
        'access-one',
      );
      expect(
        (await storage.readSession(endpoint: second))!.accessToken,
        'access-two',
      );

      await storage.removeNamedProfile('two');
      expect(await storage.readNamedProfile('two'), isNull);
      expect(
        (await storage.readSession(endpoint: first))!.accessToken,
        'access-one',
      );
      expect(await storage.readSession(endpoint: second), isNull);
      expect(storage.sessionFile.existsSync(), isFalse);

      final profileText = await storage.profilesFile.readAsString();
      final credentialText = await storage.credentialsFile.readAsString();
      expect(profileText, isNot(contains('access-one')));
      expect(profileText, isNot(contains('session-one')));
      expect(credentialText, contains('access-one'));
      expect(credentialText, isNot(contains('two.example')));
    },
  );

  test(
    'profile list exposes the managed Cloud default without writing secrets',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-profile-cli-');
      addTearDown(() => root.delete(recursive: true));
      final outputDirectory = await Directory.systemTemp.createTemp(
        'hyfens-profile-cli-output-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));
      final storage = AuthStorage(root: root);
      final outputFile = File('${outputDirectory.path}/stdout');
      final errorFile = File('${outputDirectory.path}/stderr');
      final output = outputFile.openWrite();
      final error = errorFile.openWrite();
      try {
        await HyfensCommandRunner(
          authStorage: storage,
          out: output,
          err: error,
        ).run(const <String>['profile', 'list', '--json']);
      } finally {
        await output.close();
        await error.close();
      }
      final result =
          jsonDecode(await outputFile.readAsString()) as Map<String, Object?>;
      expect(result['active_profile'], 'hyfens-cloud');
      final profiles = result['profiles']! as List<Object?>;
      final firstProfile = profiles.single as Map<String, Object?>;
      expect(firstProfile['endpoint'], managedCloudDisplayName);
      expect(firstProfile['endpoint'], isNot(contains('api.hyfens.com')));
      final persisted = await storage.readProfileCatalog();
      expect(persisted.active.toJson()['endpoint'], managedCloudApiBase);
      expect(File('${root.path}/credentials').existsSync(), isFalse);
    },
  );

  test(
    'profile bind persists customer resource context without secrets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-profile-bind-',
      );
      addTearDown(() => root.delete(recursive: true));
      final outputFile = File('${root.path}/stdout');
      final errorFile = File('${root.path}/stderr');
      final output = outputFile.openWrite();
      final error = errorFile.openWrite();
      try {
        await HyfensCommandRunner(
          authStorage: AuthStorage(root: root),
          out: output,
          err: error,
        ).run(const <String>[
          'profile',
          'bind',
          '--organization-id',
          'org_customer',
          '--application-id',
          'app_flutter',
          '--environment-id',
          'env_free',
          '--json',
        ]);
      } finally {
        await output.close();
        await error.close();
      }

      final result =
          jsonDecode(await outputFile.readAsString()) as Map<String, Object?>;
      expect(result['result'], 'PROFILE_BOUND');
      final profile = result['profile']! as Map<String, Object?>;
      expect(profile['organization'], 'org_customer');
      expect(profile['application'], 'app_flutter');
      expect(profile['environment'], 'env_free');
      expect(
        (await AuthStorage(root: root).readActiveProfile()).organizationId,
        'org_customer',
      );
      expect(File('${root.path}/credentials').existsSync(), isFalse);
    },
  );
}
