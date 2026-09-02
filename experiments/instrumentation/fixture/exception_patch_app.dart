int scenario(int value) {
  try {
    throw value + 72;
  } catch (_) {
    rethrow;
  } finally {
    value;
  }
}
