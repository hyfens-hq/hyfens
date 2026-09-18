import 'dart:convert';

List<int> revise(List<int> values) {
  return values;
}

void main(List<String> arguments) {
  final input = <int>[2, 3];
  final result = revise(input);
  print(jsonEncode(<String, Object?>{'input': input, 'result': result}));
}
