import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Windows key generation applies and verifies a current-account ACL',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-signing-');
      addTearDown(() => root.delete(recursive: true));
      final commands = <_Command>[];
      final privateFile = File('${root.path}/private.key');
      final publicFile = File('${root.path}/public.key');
      final store = KeyStore(
        platform: SigningPlatform.windows,
        processRunner: (executable, arguments) {
          commands.add(_Command(executable, List<String>.from(arguments)));
          if (executable == 'whoami') {
            return ProcessResult(pid, 0, 'WORKSTATION\\alice\r\n', '');
          }
          if (executable == 'icacls' && arguments.length == 1) {
            return ProcessResult(
              pid,
              0,
              '${arguments.single} WORKSTATION\\alice:(F)\r\n',
              '',
            );
          }
          return ProcessResult(pid, 0, '', '');
        },
      );

      final generated = await store.generate(
        privateFile: privateFile,
        publicFile: publicFile,
        random: Random(294),
      );

      expect(commands.map((command) => command.executable), <String>[
        'whoami',
        'icacls',
        'icacls',
      ]);
      expect(
        commands[1].arguments,
        containsAll(<String>[
          '/reset',
          '/inheritance:r',
          '/grant:r',
          'WORKSTATION\\alice:F',
        ]),
      );
      expect(commands[2].arguments.single, endsWith('/private.key'));
      expect(commands[2].arguments.single, isNot(privateFile.path));

      final privateJson = jsonDecode(await privateFile.readAsString());
      final publicJson = jsonDecode(await publicFile.readAsString());
      expect(privateJson, isA<Map>());
      expect(publicJson, isA<Map>());
      final privateMap = privateJson as Map;
      final publicMap = publicJson as Map;
      expect(privateMap['algorithm'], 'ed25519');
      expect(publicMap['algorithm'], 'ed25519');
      expect(publicMap['keyId'], generated.keyId);
      expect(store.readPublic(publicFile).publicKey, hasLength(32));

      final message = utf8.encode('windows signing');
      final signature = await generated.sign(message);
      expect(
        await store.readPublic(publicFile).verify(message, signature),
        isTrue,
      );
    },
  );

  test(
    'Windows private-key reads validate the existing ACL before parsing',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-signing-read-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateFile = await _writePrivateKey(root);
      final commands = <_Command>[];
      final store = KeyStore(
        platform: SigningPlatform.windows,
        processRunner: (executable, arguments) {
          commands.add(_Command(executable, List<String>.from(arguments)));
          if (executable == 'whoami') {
            return ProcessResult(pid, 0, 'WORKSTATION\\alice\r\n', '');
          }
          return ProcessResult(
            pid,
            0,
            '${privateFile.path} WORKSTATION\\alice:(F)\r\n',
            '',
          );
        },
      );

      final key = store.readPrivate(privateFile);

      expect(key.seed, List<int>.filled(32, 7));
      expect(commands.map((command) => command.executable), <String>[
        'whoami',
        'icacls',
      ]);
      expect(commands[1].arguments, <String>[privateFile.path]);
    },
  );

  test(
    'Windows private-key reads fail closed for broad or inherited ACLs',
    () async {
      final root = await Directory.systemTemp.createTemp('hyfens-signing-acl-');
      addTearDown(() => root.delete(recursive: true));
      final privateFile = await _writePrivateKey(root);
      final store = KeyStore(
        platform: SigningPlatform.windows,
        processRunner: (executable, arguments) {
          if (executable == 'whoami') {
            return ProcessResult(pid, 0, 'WORKSTATION\\alice\r\n', '');
          }
          return ProcessResult(
            pid,
            0,
            '${privateFile.path} WORKSTATION\\alice:(I)(F)\r\n'
                'BUILTIN\\Administrators:(F)\r\n',
            '',
          );
        },
      );

      expect(
        () => store.readPrivate(privateFile),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'S4005',
          ),
        ),
      );
    },
  );

  test(
    'Windows key generation fails closed when ACL verification fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyfens-signing-fail-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateFile = File('${root.path}/private.key');
      final store = KeyStore(
        platform: SigningPlatform.windows,
        processRunner: (executable, arguments) {
          if (executable == 'whoami') {
            return ProcessResult(pid, 0, 'WORKSTATION\\alice\r\n', '');
          }
          if (arguments.length == 1) {
            return ProcessResult(
              pid,
              0,
              '${arguments.single} WORKSTATION\\alice:(F)\r\n'
                  'Everyone:(F)\r\n',
              '',
            );
          }
          return ProcessResult(pid, 0, '', '');
        },
      );

      await expectLater(
        store.generate(
          privateFile: privateFile,
          publicFile: File('${root.path}/public.key'),
          random: Random(294),
        ),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'S4005',
          ),
        ),
      );
      expect(privateFile.existsSync(), isFalse);
      expect(root.listSync(), isEmpty);
    },
  );

  test('Windows key generation fails closed when icacls fails', () async {
    final root = await Directory.systemTemp.createTemp(
      'hyfens-signing-command-',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = KeyStore(
      platform: SigningPlatform.windows,
      processRunner: (executable, arguments) {
        if (executable == 'whoami') {
          return ProcessResult(pid, 0, 'WORKSTATION\\alice\r\n', '');
        }
        return ProcessResult(pid, 1, '', 'Access is denied');
      },
    );

    await expectLater(
      store.generate(
        privateFile: File('${root.path}/private.key'),
        publicFile: File('${root.path}/public.key'),
        random: Random(294),
      ),
      throwsA(
        isA<ToolFailure>().having(
          (failure) => failure.diagnostics.single.code,
          'code',
          'S4005',
        ),
      ),
    );
  });

  test('POSIX key generation keeps the chmod 600 path', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-signing-posix-');
    addTearDown(() => root.delete(recursive: true));
    final commands = <_Command>[];
    final store = KeyStore(
      platform: SigningPlatform.posix,
      processRunner: (executable, arguments) {
        commands.add(_Command(executable, List<String>.from(arguments)));
        return ProcessResult(pid, 0, '', '');
      },
    );
    final privateFile = File('${root.path}/private.key');

    await store.generate(
      privateFile: privateFile,
      publicFile: File('${root.path}/public.key'),
      random: Random(294),
    );

    expect(commands, hasLength(1));
    expect(commands.single.executable, 'chmod');
    expect(commands.single.arguments.first, '600');
    expect(commands.single.arguments.last, endsWith('/private.key'));
    expect(commands.single.arguments.last, isNot(privateFile.path));
  });
}

Future<File> _writePrivateKey(Directory root) async {
  final file = File('${root.path}/private.key');
  await file.writeAsString(
    jsonEncode(<String, Object>{
      'algorithm': 'ed25519',
      'keyId': 'ed25519-0000000000000000',
      'seed': base64Encode(List<int>.filled(32, 7)),
    }),
  );
  return file;
}

final class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
