Future<int> calculateAsyncPrice(int quantity, int tier) async {
  final int immediate = await hostImmediate(quantity);
  return immediate + tier;
}
