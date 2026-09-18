int hotLeaf(int a, int b) {
  if (a < 0) return b - a;
  if (a == b) return a * 10;
  return a * b + 7;
}
