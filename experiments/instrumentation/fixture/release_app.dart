int calculate(int a, int b) {
  if (a < 0) return b - a;
  return a + b;
}

final operation = calculate;

void main(List<String> arguments) {
  final iterationsArgument = arguments
      .where((value) => value.startsWith('--iterations='))
      .firstOrNull;
  final iterations = iterationsArgument == null
      ? 1
      : int.parse(iterationsArgument.substring('--iterations='.length));
  var accumulator = 0;
  final watch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    accumulator ^= calculate(index % 31 - 15, index % 17);
  }
  watch.stop();
  print(
    'direct=${calculate(4, 3)} tearoff=${operation(4, 3)} '
    'accumulator=$accumulator elapsedMicros=${watch.elapsedMicroseconds}',
  );
}
