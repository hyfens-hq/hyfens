import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';

final _immediate = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.immediate',
  sourceName: 'hostImmediate',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);
final _delayed = E0AsyncCapabilityDescriptor(
  id: 'e0.test.future.delayed',
  sourceName: 'hostDelayed',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);

Future<int> hostImmediate(int value) async => value;

Future<int> hostDelayed(int value) async => value;

Future<int> calculateAsync(int value) async {
  return value + 1;
}

class AsyncService {
  const AsyncService(this.delta);

  final int delta;

  Future<int> calculate(int value) async {
    // ignore: unnecessary_this
    return value + this.delta;
  }
}

void _registerCapabilities() {
  E0PatchRuntime.configureCapabilities(
    E0CapabilityAuthority(
      shipped: <E0AsyncCapabilityDescriptor>[_immediate, _delayed],
      registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
        E0CapabilityRegistration(
          _immediate,
          (arguments) => Future<Object?>.value((arguments.single! as int) + 1),
        ),
        E0CapabilityRegistration(
          _delayed,
          (arguments) => Future<Object?>.delayed(
            const Duration(milliseconds: 15),
            () => (arguments.single! as int) * 2,
          ),
        ),
      ]),
    ),
  );
}

Future<void> main(List<String> arguments) async {
  _registerCapabilities();
  var eventLoopTicked = false;
  Timer.run(() => eventLoopTicked = true);
  final result = await calculateAsync(3);
  final instanceResult = await const AsyncService(4).calculate(3);
  await Future<void>.delayed(Duration.zero);
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'result': result,
      'instanceResult': instanceResult,
      'eventLoopTicked': eventLoopTicked,
    }),
  );
}
