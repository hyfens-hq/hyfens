import 'dart:convert';
import 'dart:io';

import 'package:conformance/physical_ios_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokenA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _tokenB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _tokenC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _tokenD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  test('physical iOS evidence is disabled by default', () async {
    final support = await Directory.systemTemp.createTemp('e1-ios-disabled-');
    addTearDown(() => support.delete(recursive: true));

    expect(await PhysicalIosEvidenceSession.open(support), isNull);
    expect(await support.list().toList(), isEmpty);
  });

  test('new evidence run clears only its patch storage', () async {
    final support = await Directory.systemTemp.createTemp('e1-ios-reset-');
    addTearDown(() => support.delete(recursive: true));
    final patchDirectory = Directory('${support.path}/hyfens-e1')..createSync();
    File('${patchDirectory.path}/old-state').writeAsStringSync('stale');
    final sibling = File('${support.path}/unrelated')
      ..writeAsStringSync('preserve');

    final session = await PhysicalIosEvidenceSession.open(
      support,
      enabled: true,
      runId: 'ios-test-1',
      serverUrl: 'http://192.168.1.2:18080',
      token: _tokenA,
    );

    expect(session, isNotNull);
    expect(session!.stage, 0);
    expect(
      session.patchUri.toString(),
      'http://192.168.1.2:18080/$_tokenA/patch.e1.signed.json',
    );
    expect(patchDirectory.existsSync(), isFalse);
    expect(sibling.readAsStringSync(), 'preserve');
    final state = jsonDecode(
      File('${support.path}/hyfens-e1-ios-evidence-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(state, <String, Object?>{'runId': 'ios-test-1', 'stage': 0});
  });

  test(
    'same run resumes its recorded stage without clearing patch storage',
    () async {
      final support = await Directory.systemTemp.createTemp('e1-ios-resume-');
      addTearDown(() => support.delete(recursive: true));
      File('${support.path}/hyfens-e1-ios-evidence-v1.json').writeAsStringSync(
        jsonEncode(<String, Object>{'runId': 'ios-test-2', 'stage': 2}),
      );
      final patchDirectory = Directory('${support.path}/hyfens-e1')
        ..createSync();
      final retained = File('${patchDirectory.path}/state-v3-a.json')
        ..writeAsStringSync('retained');

      final session = await PhysicalIosEvidenceSession.open(
        support,
        enabled: true,
        runId: 'ios-test-2',
        serverUrl: 'http://192.168.1.2:18080/',
        token: _tokenB,
      );

      expect(session!.stage, 2);
      expect(retained.readAsStringSync(), 'retained');
    },
  );

  test('invalid run identity fails before touching storage', () async {
    final support = await Directory.systemTemp.createTemp('e1-ios-invalid-');
    addTearDown(() => support.delete(recursive: true));
    final retained = File('${support.path}/retained')
      ..writeAsStringSync('retained');

    await expectLater(
      PhysicalIosEvidenceSession.open(
        support,
        enabled: true,
        runId: '../escape',
        serverUrl: 'http://192.168.1.2:18080',
        token: _tokenC,
      ),
      throwsFormatException,
    );
    expect(retained.readAsStringSync(), 'retained');
  });

  test('non-local server and malformed bearer token fail closed', () async {
    final support = await Directory.systemTemp.createTemp('e1-ios-uri-');
    addTearDown(() => support.delete(recursive: true));

    await expectLater(
      PhysicalIosEvidenceSession.open(
        support,
        enabled: true,
        runId: 'ios-public-host',
        serverUrl: 'http://203.0.113.1:18080',
        token: _tokenD,
      ),
      throwsFormatException,
    );
    await expectLater(
      PhysicalIosEvidenceSession.open(
        support,
        enabled: true,
        runId: 'ios-bad-token',
        serverUrl: 'http://127.0.0.1:18080',
        token: '../not-a-token',
      ),
      throwsFormatException,
    );
    expect(await support.list().toList(), isEmpty);
  });

  test('USB evidence mode uses app Documents without a network URL', () async {
    final support = await Directory.systemTemp.createTemp('e1-ios-usb-');
    final documents = await Directory.systemTemp.createTemp('e1-ios-docs-');
    addTearDown(() => support.delete(recursive: true));
    addTearDown(() => documents.delete(recursive: true));

    final session = await PhysicalIosEvidenceSession.open(
      support,
      enabled: true,
      usbMode: true,
      usbDirectory: documents,
      runId: 'ios-usb-1',
    );

    expect(session, isNotNull);
    expect(session!.patchUri.toString(), startsWith('http://127.0.0.1:18080/'));
    expect(Directory('${documents.path}/hyfens-e1').existsSync(), isTrue);
  });

  test('USB evidence mode requires an app Documents directory', () async {
    final support = await Directory.systemTemp.createTemp(
      'e1-ios-usb-missing-',
    );
    addTearDown(() => support.delete(recursive: true));

    await expectLater(
      PhysicalIosEvidenceSession.open(
        support,
        enabled: true,
        usbMode: true,
        runId: 'ios-usb-2',
      ),
      throwsFormatException,
    );
    expect(await support.list().toList(), isEmpty);
  });
}
