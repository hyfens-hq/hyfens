import 'dart:convert';

int hotLeaf(int a, int b) {
  if (a < 0) return b - a;
  return a + b;
}

int unrelatedLeaf(int value) {
  return value + 1;
}

final hotLeafTearOff = hotLeaf;

void main(List<String> arguments) {
  final iterations = _integerArgument(arguments, '--iterations=', 1);
  var accumulator = 0;
  final watch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    accumulator ^= hotLeaf(index % 31 - 15, index % 17);
  }
  watch.stop();
  print(
    jsonEncode(<String, Object>{
      'hotDirect': hotLeaf(4, 3),
      'hotTearOff': hotLeafTearOff(4, 3),
      'unrelated': unrelatedLeaf(5),
      'checksum': accumulator,
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
