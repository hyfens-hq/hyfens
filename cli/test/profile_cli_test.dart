import 'dart:convert';
import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
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
      final outputFile = File('${outputDirectory.path}/stdout');
      final errorFile = File('${outputDirectory.path}/stderr');
      final output = outputFile.openWrite();
      final error = errorFile.openWrite();
      try {
        await HyfensCommandRunner(
          authStorage: AuthStorage(root: root),
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
      expect(firstProfile['endpoint'], managedCloudApiBase);
      expect(File('${root.path}/credentials').existsSync(), isFalse);
    },
  );
}
