List<int> revise(List<int> values) {
  List<int> output = values;
  for (int index = 0; index < output.length; index++) {
    output[index] = output[index] * 2;
  }
  output.add(7);
  return output;
}
