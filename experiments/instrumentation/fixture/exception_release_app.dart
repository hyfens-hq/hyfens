import 'dart:convert';
import 'dart:io';

int scenario(int value) {
  return value + 1;
}

void main(List<String> arguments) {
  try {
    stdout.writeln(jsonEncode(<String, Object?>{'result': scenario(5)}));
  } catch (error, stack) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'error': error,
        'type': error.runtimeType.toString(),
        'syntheticTrace': stack.toString().contains('E0 guest frame:'),
      }),
    );
  }
}
