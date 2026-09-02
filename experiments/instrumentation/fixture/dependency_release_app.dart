import 'dart:convert';

import 'package:pure_dep/pure_dep.dart';

void main(List<String> arguments) {
  final tearOff = decorate;
  print(
    jsonEncode(<String, String>{
      'direct': decorate('direct'),
      'tearOff': tearOff('tear-off'),
    }),
  );
}
