import 'dart:convert';

String greet(String name) {
  return 'Hello, $name';
}

bool isEligible(int age, bool verified) {
  return age >= 18 && verified;
}

double calculate(double amount, double rate) {
  return amount + rate;
}

Map<String, dynamic> transform(Map<String, dynamic> input) {
  return input;
}

List<int> filterValues(List<int> values) {
  return values;
}

void main(List<String> arguments) {
  print(
    jsonEncode(<String, dynamic>{
      'greet': greet('Ada'),
      'eligible': isEligible(20, true),
      'calculate': calculate(12.5, 0.2),
      'transform': transform(<String, dynamic>{'name': 'Ada'}),
      'filter': filterValues(<int>[3, 4, 9]),
    }),
  );
}
