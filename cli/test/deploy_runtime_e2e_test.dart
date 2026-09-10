import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hyfens_flutter_integration/flutter_integration.dart';
import 'package:hyfens_instrumenter/instrumenter.dart';
import 'package:hyfens_tool/tool.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

void main() {
  test(
    'tool deploy artifact activates through authenticated runtime delivery',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'hyfens-tool-deploy-runtime-',
      );
      final serviceRoot = await Directory.systemTemp.createTemp(
        'hyfens-tool-deploy-service-',
      );
      Process? serviceProcess;
      E1PatchController? controller;
      Directory? runtimeStorage;
      try {
        await _writeProject(projectRoot);
        final release = await _runJson(<String>[
          'init',
          '--project',
          projectRoot.path,
          '--json',
        ]);
        expect(release['dryRun'], isFalse);
        await _runJson(<String>[
          'keys',
          'generate',
          '--project',
          projectRoot.path,
          '--json',
        ]);
        final releaseResult = await _runJson(<String>[
          'release',
          'android',
          '--metadata-only',
          '--project',
          projectRoot.path,
          '--json',
        ]);
        final releaseId = releaseResult['releaseId']! as String;
        await File('${projectRoot.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left - right;
}
''');
        final patchResult = await _runJson(<String>[
          'patch',
          '--release',
          releaseId,
          '--project',
          projectRoot.path,
          '--json',
        ]);
        final patchPath = patchResult['output']! as String;

        final servicePort = await _freePort();
        serviceProcess = await Process.start(
          Platform.resolvedExecutable,
          <String>[
            'run',
            'bin/control_plane.dart',
            '--root',
            serviceRoot.path,
            '--host',
            '127.0.0.1',
            '--port',
            '$servicePort',
            '--bootstrap',
            '--application',
            'cli_service_app',
            '--platform',
            'android-arm64-release',
            '--environment',
            'development',
          ],
          workingDirectory:
              '${Directory.current.parent.path}/packages/control_plane',
        );
        final credentials = await _readBootstrap(serviceProcess);
        final endpoint = 'http://127.0.0.1:$servicePort';
        final deploy = await _runJson(<String>[
          'deploy',
          '--project',
          projectRoot.path,
          '--endpoint',
          endpoint,
          '--token',
          credentials['control_token']!,
          '--organization-id',
          credentials['organization_id']!,
          '--application-id',
          credentials['application_id']!,
          '--environment-id',
          credentials['environment_id']!,
          '--release',
          releaseId,
          '--patch',
          patchPath,
          '--expected-version',
          '0',
          '--json',
        ]);
        expect(deploy['result'], 'DEPLOYED');

        final project = const ProjectDiscovery().discover(
          projectPath: projectRoot.path,
        );
        final store = ToolStore(project);
        final record = store.readRelease(releaseId);
        final publicKey = const KeyStore().readPublic(
          store.resolveConfiguredPath(
            ToolConfig.load(project.configFile).publicKeyPath,
          ),
        );
        final functions = <String, int>{};
        final signatures = <String, String>{};
        final receivers = <String, String>{};
        for (final function in record.functions) {
          final manifest = E0FunctionManifest.fromJson(function.manifest);
          functions[function.id] = function.slot;
          signatures[function.id] = manifest.signature.encode();
          receivers[function.id] = manifest.receiver.encode();
        }
        runtimeStorage = await Directory.systemTemp.createTemp(
          'hyfens-tool-deploy-runtime-state-',
        );
        controller = E1PatchController(
          storageDirectory: runtimeStorage,
          appId: record.applicationId,
          releaseId: record.releaseId,
          buildFingerprint: record.buildFingerprint,
          functions: functions,
          signatures: signatures,
          receivers: receivers,
          patchUri: Uri.parse('$endpoint/unused'),
          trustedPublicKeys: <String, E1TrustedPublicKey>{
            publicKey.keyId: E1TrustedPublicKey(
              keyId: publicKey.keyId,
              bytes: publicKey.publicKey,
            ),
          },
        );
        await controller.initialize();
        final delivery = HyfensControlPlaneDelivery(
          HyfensControlPlaneConfiguration(
            baseUrl: Uri.parse(endpoint),
            deliveryCredential: credentials['delivery_token']!,
            applicationId: credentials['application_id']!,
            environmentId: credentials['environment_id']!,
            platformId: 'plt_android_arm64',
          ),
        );
        final result = await delivery.deliver(controller);
        expect(result.decision, HyfensDeliveryDecision.patchAvailable);
        expect(result.activated, isTrue);
        expect(await controller.markHealthy(), isTrue);
        expect(controller.status.mode, E1PatchMode.patch);
        expect(controller.durableState.highWaterSequence, 1);
      } finally {
        await controller?.close();
        if (serviceProcess != null) {
          serviceProcess.kill(ProcessSignal.sigkill);
          await serviceProcess.exitCode.timeout(const Duration(seconds: 5));
        }
        if (runtimeStorage != null && await runtimeStorage.exists()) {
          await runtimeStorage.delete(recursive: true);
        }
        await projectRoot.delete(recursive: true);
        await serviceRoot.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _writeProject(Directory root) async {
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: cli_service_app
version: 1.0.0
environment:
  sdk: ^3.13.0
flutter: {}
dependencies: {}
''');
  await File('${root.path}/pubspec.lock').writeAsString('''
packages: {}
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
  await File('${root.path}/lib/main.dart').writeAsString('''
void main() {}

int calculate(int left, int right) {
  return left + right;
}
''');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'cli_service_app',
          'rootUri': root.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
}

Future<Map<String, Object?>> _runJson(List<String> arguments) async {
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/tool.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  final decoded = jsonDecode(result.stdout.toString().trim());
  return Map<String, Object?>.from(decoded as Map);
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<Map<String, String>> _readBootstrap(Process process) async {
  final result = <String, String>{};
  final done = Completer<Map<String, String>>();
  final subscription = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final separator = line.indexOf('=');
        if (separator > 0) {
          result[line.substring(0, separator)] = line.substring(separator + 1);
        }
        if (const <String>[
              'organization_id',
              'application_id',
              'environment_id',
              'control_token',
              'delivery_token',
            ].every(result.containsKey) &&
            line.contains('hyfens control plane listening')) {
          if (!done.isCompleted) done.complete(result);
        }
      });
  try {
    return await done.future.timeout(const Duration(seconds: 15));
  } finally {
    await subscription.cancel();
  }
}
