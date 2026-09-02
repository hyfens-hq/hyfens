import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';

void main(List<String> arguments) {
  final iterations = _integerArgument(arguments, '--iterations=', 1);
  final slot = _integerArgument(arguments, '--slot=', 0);
  final patchPath = _stringArgument(arguments, '--patch=');
  if (patchPath != null) {
    final installed = E0PatchRuntime.installBytes(
      File(patchPath).readAsBytesSync(),
      appId: _stringArgument(arguments, '--app-id=')!,
      releaseId: _stringArgument(arguments, '--release-id=')!,
      buildFingerprint: _stringArgument(arguments, '--build-fingerprint=')!,
      functions:
          (jsonDecode(_stringArgument(arguments, '--functions=')!)
                  as Map<String, Object?>)
              .map((key, value) => MapEntry(key, value! as int)),
      signatures:
          (jsonDecode(_stringArgument(arguments, '--signatures=')!)
                  as Map<String, Object?>)
              .map((key, value) => MapEntry(key, value! as String)),
      receivers:
          (jsonDecode(_stringArgument(arguments, '--receivers=')!)
                  as Map<String, Object?>)
              .map((key, value) => MapEntry(key, value! as String)),
    );
    if (!installed) {
      throw StateError(E0PatchRuntime.lastRejection ?? 'Patch install failed');
    }
  }
  var hits = 0;
  final watch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    if (E0PatchRuntime.lookup(slot) != null) hits++;
  }
  watch.stop();
  print(
    jsonEncode(<String, Object>{
      'slot': slot,
      'hits': hits,
      'checksum': hits ^ iterations,
      'elapsedMicros': watch.elapsedMicroseconds,
    }),
  );
}

int _integerArgument(List<String> arguments, String prefix, int fallback) {
  final values = arguments.where((value) => value.startsWith(prefix));
  if (values.isEmpty) return fallback;
  if (values.length != 1) throw FormatException('Duplicate $prefix argument');
  return int.parse(values.single.substring(prefix.length));
}

String? _stringArgument(List<String> arguments, String prefix) {
  final values = arguments.where((value) => value.startsWith(prefix));
  if (values.isEmpty) return null;
  if (values.length != 1) throw FormatException('Duplicate $prefix argument');
  return values.single.substring(prefix.length);
}
