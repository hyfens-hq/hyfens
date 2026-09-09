import 'dart:io';

import 'package:hyfens_tool/src/runtime_bundle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('recognizes the packaged runtime package layout', () async {
    final root = await Directory.systemTemp.createTemp('hyfens-runtime-test-');
    addTearDown(() => root.delete(recursive: true));

    for (final name in <String>[
      'instrumentation_e0',
      'hyfens_flutter_integration',
    ]) {
      await Directory(p.join(root.path, name, 'lib')).create(recursive: true);
    }
    await Directory(p.join(root.path, 'unexpected', 'lib'))
        .create(recursive: true);

    final packages = RuntimePackageBundle.packagesAt(root);

    expect(
      packages.keys,
      containsAll(<String>['instrumentation_e0', 'hyfens_flutter_integration']),
    );
    expect(packages.keys, isNot(contains('unexpected')));
  });

  test('keeps the runtime bundle package set bounded', () {
    expect(
      RuntimePackageBundle.packageNames,
      containsAll(<String>[
        'instrumentation_e0',
        'hyfens_flutter_integration',
        'hyfens_patch_format',
        'hyfens_runtime',
        'patch_loading_e1',
        'cryptography',
      ]),
    );
    expect(
      RuntimePackageBundle.packageNames.toSet().length,
      RuntimePackageBundle.packageNames.length,
    );
  });
}
