import 'dart:io';

import 'package:instrumentation_e0/instrumentation_e0.dart';

void main(List<String> arguments) {
  if ((arguments.length != 3 && arguments.length != 4) ||
      (arguments.first != 'overlay' && arguments.first != 'compile-patch')) {
    stderr.writeln(
      'usage: dart run bin/e0.dart overlay INPUT OUTPUT_DIR\n'
      '   or: dart run bin/e0.dart compile-patch SOURCE OVERLAY_DIR '
      '[FUNCTION_NAME]',
    );
    exitCode = 64;
    return;
  }
  if (arguments.first == 'overlay') {
    final result = E0OverlayBuilder(E0SourceTransformer()).build(
      input: File(arguments[1]),
      outputDirectory: Directory(arguments[2]),
      packageName: 'instrumentation_fixture',
      logicalLibraryPath: 'lib/app.dart',
      appId: 'dev.hyfens.instrumentation-e0',
      releaseId: 'release-1',
      buildFingerprint: 'instrumentation-cli-build-1',
    );
    stdout.writeln(
      'instrumented=${result.manifest.functions.length} '
      'excluded=${result.exclusions.length}',
    );
    return;
  }
  final overlay = Directory(arguments[2]);
  final manifest = E0ReleaseManifest.decode(
    File('${overlay.path}/manifest.json').readAsStringSync(),
  );
  final bytes = E0PatchCompiler().compile(
    source: File(arguments[1]).readAsStringSync(),
    manifest: manifest,
    functionName: arguments.length == 4 ? arguments[3] : 'calculate',
  );
  File('${overlay.path}/patch.e0.json').writeAsBytesSync(bytes);
  stdout.writeln('patchBytes=${bytes.length}');
}
