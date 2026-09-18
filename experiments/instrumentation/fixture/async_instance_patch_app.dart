external Future<int> hostImmediate(int value);

class AsyncService {
  const AsyncService(this.delta);

  final int delta;

  Future<int> calculate(int value) async {
    final int result = await hostImmediate(value);
    // ignore: unnecessary_this
    return result + this.delta + 20;
  }
}
