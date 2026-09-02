import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:test/test.dart';

void main() {
  final patchPath = Platform.environment['HYFENS_CLI_PATCH'];
  final releasePath = Platform.environment['HYFENS_CLI_RELEASE'];
  final publicKeyPath = Platform.environment['HYFENS_CLI_PUBLIC_KEY'];
  final configured =
      patchPath != null && releasePath != null && publicKeyPath != null;

  test(
    'CLI-generated Patch Format v1 artifact activates against release metadata',
    () async {
      final release = jsonDecode(
        await File(releasePath!).readAsString(),
      ) as Map<String, Object?>;
      final rawFunctions = release['functions'];
      expect(rawFunctions, isA<List<Object?>>());
      final functions = <String, int>{};
      final signatures = <String, String>{};
      final receivers = <String, String>{};
      int? changedSlot;
      for (final value in rawFunctions! as List<Object?>) {
        final function = value! as Map<String, Object?>;
        final id = function['id']! as String;
        functions[id] = function['slot']! as int;
        final manifest = function['manifest']! as Map<String, Object?>;
        signatures[id] = jsonEncode(manifest['signature']);
        receivers[id] = jsonEncode(manifest['receiver']);
        if (function['name'] == 'calculatePrice' &&
            function['sourcePath'] == 'lib/main.dart') {
          changedSlot = function['slot']! as int;
        }
      }
      expect(changedSlot, isNotNull);

      final key = jsonDecode(
        await File(publicKeyPath!).readAsString(),
      ) as Map<String, Object?>;
      final storage = await Directory.systemTemp.createTemp(
        'hyfens-cli-artifact-runtime-',
      );
      addTearDown(() async {
        E0PatchRuntime.reset();
        await storage.delete(recursive: true);
      });
      final controller = E1PatchController(
        storageDirectory: storage,
        appId: release['applicationId']! as String,
        releaseId: release['releaseId']! as String,
        buildFingerprint: release['buildFingerprint']! as String,
        functions: functions,
        signatures: signatures,
        receivers: receivers,
        patchUri: Uri.parse('http://127.0.0.1:1/v1/patch'),
        trustedPublicKeys: <String, E1TrustedPublicKey>{
          key['keyId']! as String: E1TrustedPublicKey(
            keyId: key['keyId']! as String,
            bytes: base64.decode(key['publicKey']! as String),
          ),
        },
      );
      addTearDown(controller.close);

      await controller.initialize();
      expect(
        await controller.activateBytes(await File(patchPath!).readAsBytes()),
        isTrue,
      );
      expect(await controller.markHealthy(), isTrue);
      expect(controller.status.mode, E1PatchMode.patch);
      expect(
        E0PatchRuntime.invokeInt2(E0PatchRuntime.lookup(changedSlot!)!, 6, 1),
        546,
      );
    },
    skip: configured ? false : 'Set HYFENS_CLI_PATCH, HYFENS_CLI_RELEASE, and HYFENS_CLI_PUBLIC_KEY.',
  );
}
