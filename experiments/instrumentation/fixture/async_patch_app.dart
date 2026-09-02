external Future<int> hostImmediate(int value);
external Future<int> hostDelayed(int value);

Future<int> calculateAsync(int value) async {
  final int first = await hostImmediate(value);
  final int second = await hostDelayed(first);
  return second + 10;
}
