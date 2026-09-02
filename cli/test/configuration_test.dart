import 'dart:io';

import 'package:hyfens_tool/tool.dart';
import 'package:test/test.dart';

void main() {
  test('tool configuration round-trips defaults and glob policy', () async {
    final directory = await Directory.systemTemp.createTemp('hyfens-config-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tool.yaml');
    await writeDefaultConfig(file, applicationId: 'com.example.app');

    final config = ToolConfig.load(file);
    expect(config.version, 1);
    expect(config.applicationId, 'com.example.app');
    expect(config.includes('lib/main.dart'), isTrue);
    expect(config.includes('lib/generated/model.dart'), isFalse);
    expect(config.includes('test/example.dart'), isFalse);
  });

  test('glob matcher treats double-star and single-star distinctly', () {
    expect(globMatches('lib/**', 'lib/features/cart.dart'), isTrue);
    expect(globMatches('lib/*.dart', 'lib/main.dart'), isTrue);
    expect(globMatches('lib/*.dart', 'lib/features/main.dart'), isFalse);
  });

  test(
    'malformed nested configuration fails instead of falling back',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-config-invalid-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/tool.yaml');
      await file.writeAsString('''
version: 1
instrumentation: false
''');
      expect(
        () => ToolConfig.load(file),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'T1203',
          ),
        ),
      );
    },
  );

  test(
    'hyfens project binding is safe metadata and rejects credentials',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyfens-binding-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/hyfens.yaml');
      await writeHyfensBinding(
        file,
        binding: const HyfensProjectBinding(
          profile: 'acme',
          organizationId: 'org_demo',
          applicationId: 'app_demo',
          environmentId: 'env_demo',
          runtimeApplicationId: 'com.example.demo',
        ),
      );
      final encoded = await file.readAsString();
      expect(encoded, contains('profile: acme'));
      expect(encoded, isNot(contains('token')));
      expect(encoded, isNot(contains('password')));
      expect(HyfensProjectBinding.load(file)!.applicationId, 'app_demo');

      await file.writeAsString('''
version: 1
profile: acme
access_token: should-not-be-here
''');
      expect(
        () => HyfensProjectBinding.load(file),
        throwsA(
          isA<ToolFailure>().having(
            (failure) => failure.diagnostics.single.code,
            'code',
            'H1204',
          ),
        ),
      );
    },
  );
}
