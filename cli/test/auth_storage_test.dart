import 'dart:io';

import 'package:hyfens_tool/src/auth_storage.dart';
import 'package:hyfens_tool/src/diagnostics.dart';
import 'package:hyfens_tool/src/profile.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fallback remains authoritative after the native store recovers',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-authority-');
      addTearDown(() => root.delete(recursive: true));
      final native = _FakeCredentialStore();
      final endpoint = Uri.parse('https://authority.example/');
      await AuthStorage(root: root, credentialStore: native).writeSession(
        const AuthSession(accessToken: 'old-account'),
        endpoint: endpoint,
      );
      native.failWrites = true;
      await AuthStorage(root: root, credentialStore: native).writeSession(
        const AuthSession(accessToken: 'new-account'),
        endpoint: endpoint,
      );
      native.failWrites = false;
      final reopened = AuthStorage(root: root, credentialStore: native);
      expect(
        (await reopened.readSession(endpoint: endpoint))?.accessToken,
        'new-account',
      );
    },
  );

  test('logout remains authoritative after failed native deletion', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-logout-');
    addTearDown(() => root.delete(recursive: true));
    final native = _FakeCredentialStore();
    final endpoint = Uri.parse('https://logout.example/');
    final storage = AuthStorage(root: root, credentialStore: native);
    await storage.writeSession(
      const AuthSession(accessToken: 'old-account'),
      endpoint: endpoint,
    );
    native.failDeletes = true;
    await storage.clearSession(endpoint: endpoint);
    native.failDeletes = false;
    final reopened = AuthStorage(root: root, credentialStore: native);
    expect(await reopened.readSession(endpoint: endpoint), isNull);
    await reopened.writeSession(
      const AuthSession(accessToken: 'new-login'),
      endpoint: endpoint,
    );
    expect(
      (await reopened.readSession(endpoint: endpoint))?.accessToken,
      'new-login',
    );
  });

  test(
    'an explicit auth root uses the portable endpoint-bound file store',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-storage-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(root: root);

      expect(storage.platform, defaultAuthStoragePlatform);
      await storage.writeSession(
        const AuthSession(accessToken: 'access-secret'),
        endpoint: Uri.parse('http://127.0.0.1:43111/p2'),
      );
      expect(storage.credentialsFile.existsSync(), isTrue);

      if (!Platform.isWindows) {
        expect((await storage.root.stat()).mode & 0x1ff, 0x1c0);
        expect((await storage.credentialsFile.stat()).mode & 0x1ff, 0x180);
      }
    },
  );

  test('default auth storage prefers a native store on supported hosts', () {
    final storage = AuthStorage();
    final supported =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    expect(storage.prefersNativeCredentialStore, supported);
  });

  test(
    'native credentials stay endpoint-bound and out of fallback files',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-native-');
      addTearDown(() => root.delete(recursive: true));
      final native = _FakeCredentialStore();
      final storage = AuthStorage(root: root, credentialStore: native);
      final first = Uri.parse('https://one.example/p2/');
      final second = Uri.parse('https://two.example/p2/');

      await storage.writeSession(
        const AuthSession(
          accessToken: 'first-access-secret',
          sessionToken: 'first-session-secret',
        ),
        endpoint: first,
      );
      await storage.writeSession(
        const AuthSession(accessToken: 'second-access-secret'),
        endpoint: second,
      );

      expect(
        (await storage.readSession(endpoint: first))?.accessToken,
        'first-access-secret',
      );
      expect(
        (await storage.readSession(endpoint: second))?.accessToken,
        'second-access-secret',
      );
      expect(storage.credentialsFile.existsSync(), isFalse);
      expect(storage.sessionFile.existsSync(), isFalse);
      expect(
        native.values.keys,
        containsAll(<String>{
          controlPlaneEndpointKey(first),
          controlPlaneEndpointKey(second),
        }),
      );

      await storage.clearSession(endpoint: first);

      expect(await storage.readSession(endpoint: first), isNull);
      expect(await storage.readSession(endpoint: second), isNotNull);
      expect(native.values, isNot(contains(controlPlaneEndpointKey(first))));
    },
  );

  test('native-store failure uses the locked file fallback', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-native-fallback-',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = AuthStorage(
      root: root,
      credentialStore: _FakeCredentialStore(failWrites: true),
    );
    final endpoint = Uri.parse('http://127.0.0.1:43111/p2');

    await storage.writeSession(
      const AuthSession(
        accessToken: 'fallback-access-secret',
        sessionToken: 'fallback-session-secret',
      ),
      endpoint: endpoint,
    );

    expect(storage.prefersNativeCredentialStore, isFalse);
    expect(storage.credentialsFile.existsSync(), isTrue);
    expect(storage.sessionFile.existsSync(), isFalse);
    expect(
      (await storage.readSession(endpoint: endpoint))?.accessToken,
      'fallback-access-secret',
    );
    if (!Platform.isWindows) {
      expect((await storage.root.stat()).mode & 0x1ff, 0x1c0);
      expect((await storage.credentialsFile.stat()).mode & 0x1ff, 0x180);
      expect(storage.sessionFile.existsSync(), isFalse);
    }
  });

  test(
    'native-store fallback stays endpoint-bound and logout removes its secret',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-native-fallback-bound-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(
        root: root,
        credentialStore: _FakeCredentialStore(failWrites: true),
      );
      final first = Uri.parse('https://one.example/p2/');
      final second = Uri.parse('https://two.example/p2/');
      final other = Uri.parse('https://other.example/p2/');

      await storage.writeSession(
        const AuthSession(
          accessToken: 'first-access-secret',
          sessionToken: 'first-session-secret',
        ),
        endpoint: first,
      );
      await storage.writeSession(
        const AuthSession(accessToken: 'second-access-secret'),
        endpoint: second,
      );

      expect(storage.sessionFile.existsSync(), isFalse);
      expect(
        (await storage.readSession(endpoint: first))?.accessToken,
        'first-access-secret',
      );
      expect(
        (await storage.readSession(endpoint: second))?.accessToken,
        'second-access-secret',
      );
      expect(await storage.readSession(endpoint: other), isNull);

      await storage.clearSession(endpoint: first);
      expect(await storage.readSession(endpoint: first), isNull);
      expect(
        (await storage.readSession(endpoint: second))?.accessToken,
        'second-access-secret',
      );

      await storage.clearSession(endpoint: second);
      expect(storage.credentialsFile.existsSync(), isFalse);
      expect(storage.sessionFile.existsSync(), isFalse);
    },
  );

  test(
    'native fallback migrates a matching legacy session without duplicating it',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-native-fallback-migration-',
      );
      addTearDown(() => root.delete(recursive: true));
      final storage = AuthStorage(
        root: root,
        credentialStore: _FakeCredentialStore(failWrites: true),
      );
      final endpoint = Uri.parse('https://legacy.example/p2/');

      await storage.writeSession(
        const AuthSession(
          accessToken: 'legacy-access-secret',
          sessionToken: 'legacy-session-secret',
        ),
      );
      await storage.writeProfile(Profile(endpoint: endpoint));
      expect(storage.sessionFile.existsSync(), isTrue);
      expect(
        (await storage.readSession(endpoint: endpoint))?.accessToken,
        'legacy-access-secret',
      );
      expect(
        await storage.readSession(
          endpoint: Uri.parse('https://other.example/p2/'),
        ),
        isNull,
      );

      await storage.writeSession(
        const AuthSession(
          accessToken: 'migrated-access-secret',
          sessionToken: 'migrated-session-secret',
        ),
        endpoint: endpoint,
      );

      expect(storage.credentialsFile.existsSync(), isTrue);
      expect(storage.sessionFile.existsSync(), isFalse);
      expect(
        (await storage.readSession(endpoint: endpoint))?.accessToken,
        'migrated-access-secret',
      );

      await storage.writeSession(
        const AuthSession(accessToken: 'updated-without-endpoint-secret'),
      );
      expect(storage.sessionFile.existsSync(), isFalse);
      expect(
        (await storage.readSession(endpoint: endpoint))?.accessToken,
        'updated-without-endpoint-secret',
      );
    },
  );

  test('Windows storage policy applies a current-account ACL', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-windows-storage-',
    );
    addTearDown(() => root.delete(recursive: true));
    final commands = <_Command>[];
    final storage = FileAuthStorage(
      root: root,
      platform: AuthStoragePlatform.windows,
      environment: const <String, String>{
        'USERNAME': 'alice',
        'USERDOMAIN': 'WORKSTATION',
      },
      processRunner: (executable, arguments) async {
        commands.add(_Command(executable, List<String>.from(arguments)));
        return ProcessResult(pid, 0, '', '');
      },
    );

    await storage.writeSession(
      const AuthSession(accessToken: 'access-secret'),
      endpoint: Uri.parse('http://127.0.0.1:43111/p2'),
    );

    expect(commands, isNotEmpty);
    expect(commands.every((command) => command.executable == 'icacls'), isTrue);
    expect(
      commands.any(
        (command) => command.arguments.contains('WORKSTATION\\alice:(OI)(CI)F'),
      ),
      isTrue,
    );
    expect(
      commands.any(
        (command) => command.arguments.contains('WORKSTATION\\alice:F'),
      ),
      isTrue,
    );
    expect(
      commands.every((command) => command.arguments.contains('/reset')),
      isTrue,
    );
  });

  test(
    'Windows storage fails closed when the current account is unavailable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-windows-storage-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      var processCalls = 0;
      final storage = FileAuthStorage(
        root: root,
        platform: AuthStoragePlatform.windows,
        environment: const <String, String>{},
        processRunner: (executable, arguments) async {
          processCalls++;
          return ProcessResult(pid, 0, '', '');
        },
      );

      await expectLater(
        storage.writeSession(
          const AuthSession(accessToken: 'access-secret'),
          endpoint: Uri.parse('http://127.0.0.1:43111/p2'),
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'A1006',
          ),
        ),
      );
      expect(processCalls, 0);
      expect(storage.credentialsFile.existsSync(), isFalse);
    },
  );
}

final class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class _FakeCredentialStore implements AuthCredentialStore {
  _FakeCredentialStore({this.failWrites = false});

  bool failWrites;
  bool failDeletes = false;
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String endpointKey) async => values[endpointKey];

  @override
  Future<void> write(String endpointKey, String value) async {
    if (failWrites) throw const AuthCredentialStoreUnavailable();
    values[endpointKey] = value;
  }

  @override
  Future<void> delete(String endpointKey) async {
    if (failDeletes) throw const AuthCredentialStoreUnavailable();
    values.remove(endpointKey);
  }
}
