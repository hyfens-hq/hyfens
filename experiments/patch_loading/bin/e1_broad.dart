import 'dart:convert';
import 'dart:io';

import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:instrumentation_e0/instrumentation_e0.dart';

final E0AsyncCapabilityDescriptor _hostImmediate = E0AsyncCapabilityDescriptor(
  id: 'hyfens.e1.host.immediate',
  sourceName: 'hostImmediate',
  version: 1,
  arguments: <E0ValueSchema>[E0ValueSchema.integer],
  result: E0ValueSchema.integer,
);

final List<E0WidgetFactoryDescriptor> _widgetFactories =
    <E0WidgetFactoryDescriptor>[
      E0WidgetFactoryDescriptor(
        id: 'flutter.text.v1',
        sourceName: 'Text',
        properties: const <E0WidgetPropertyDescriptor>[
          E0WidgetPropertyDescriptor(
            name: 'data',
            schema: E0ValueSchema.string,
            required: true,
          ),
          E0WidgetPropertyDescriptor(
            name: 'fontSize',
            schema: E0ValueSchema.doubleValue,
          ),
        ],
        minChildren: 0,
        maxChildren: 0,
      ),
      E0WidgetFactoryDescriptor(
        id: 'flutter.column.v1',
        sourceName: 'Column',
        properties: const <E0WidgetPropertyDescriptor>[
          E0WidgetPropertyDescriptor(
            name: 'mainAxisSize',
            schema: E0ValueSchema.string,
            allowedValues: <String>['min', 'max'],
          ),
        ],
        minChildren: 0,
        maxChildren: E0WidgetFactoryRegistry.maxChildren,
      ),
      E0WidgetFactoryDescriptor(
        id: 'flutter.elevated-button.v1',
        sourceName: 'ElevatedButton',
        properties: const <E0WidgetPropertyDescriptor>[],
        minChildren: 1,
        maxChildren: 1,
      ),
    ];

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3 || arguments.first != 'overlay') {
    stderr.writeln(
      'usage: dart run bin/e1_broad.dart overlay INPUT OUTPUT_DIR',
    );
    exitCode = 64;
    return;
  }
  final input = File(arguments[1]);
  final output = Directory(arguments[2]);
  final result = E0OverlayBuilder(E0SourceTransformer()).build(
    input: input,
    outputDirectory: output,
    packageName: 'conformance',
    logicalLibraryPath: 'lib/main.dart',
    appId: 'dev.hyfens.conformance',
    releaseId: 'android-e1-release-1',
    buildFingerprint: 'conformance-build-1',
    capabilities: <E0AsyncCapabilityDescriptor>[_hostImmediate],
    widgetFactories: _widgetFactories,
    widgetBuildClasses: const <String>{'PricingCard'},
  );
  File('${output.path}/patch_bootstrap.dart')
      .writeAsStringSync(_bootstrap(result.manifest));
  stdout.writeln(
    'instrumented=${result.manifest.functions.length} '
    'excluded=${result.exclusions.length} '
    'functionIds=${result.manifest.functions.map((item) => item.id).join(',')}',
  );
}

String _bootstrap(E0ReleaseManifest manifest) {
  final byName = <String, E0FunctionManifest>{
    for (final function in manifest.functions)
      '${function.identity.ownerName ?? ''}.${function.name}': function,
  };
  final calculate = byName['.calculatePrice']!;
  final async = byName['.calculateAsyncPrice']!;
  final build = byName['PricingCard.build']!;
  final receiver = jsonEncode(build.receiver.encode());
  final signature = jsonEncode(build.signature.encode());
  final noReceiver = jsonEncode(calculate.receiver.encode());
  String q(String value) => jsonEncode(value);
  String mapEntry(E0FunctionManifest function) =>
      '${q(function.id)}: ${function.slot}';
  String signatureEntry(E0FunctionManifest function) =>
      '${q(function.id)}: ${q(function.signature.encode())}';
  String receiverEntry(E0FunctionManifest function) =>
      '${q(function.id)}: ${q(function.receiver.encode())}';
  return '''
import 'dart:async';
import 'dart:io';

import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:instrumentation_e0/e0_runtime.dart';
import 'package:conformance/widget_factories.dart';

const String e1AppId = 'dev.hyfens.conformance';
const String e1ReleaseId = 'android-e1-release-1';
const String e1BuildFingerprint = 'conformance-build-1';
const String e1CalculateAsyncPriceId = ${q(async.id)};
const String e1CalculatePriceId = ${q(calculate.id)};
const String e1PricingCardBuildId = ${q(build.id)};
const int e1CalculateAsyncPriceSlot = ${async.slot};
const int e1CalculatePriceSlot = ${calculate.slot};
const int e1PricingCardBuildSlot = ${build.slot};
const String e1CalculateAsyncPriceSignature = ${q(async.signature.encode())};
const String e1CalculatePriceSignature = ${q(calculate.signature.encode())};
const String e1PricingCardBuildSignature = $signature;
const String e1CalculateAsyncPriceReceiver = ${q(async.receiver.encode())};
const String e1CalculatePriceReceiver = ${q(calculate.receiver.encode())};
const String e1PricingCardBuildReceiver = $receiver;
const String e1NoReceiver = $noReceiver;
const String e1SigningKeyId = 'phase0b-rfc8032-test-only';
const List<int> e1SigningPublicKey = <int>[
  0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3,
  0xc9, 0x64, 0x07, 0x3a, 0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25,
  0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
];
final E0AsyncCapabilityDescriptor e1HostImmediateCapability =
    E0AsyncCapabilityDescriptor(
      id: 'hyfens.e1.host.immediate',
      sourceName: 'hostImmediate',
      version: 1,
      arguments: <E0ValueSchema>[E0ValueSchema.integer],
      result: E0ValueSchema.integer,
    );
final E0CapabilityAuthority e1CapabilityAuthority = E0CapabilityAuthority(
  shipped: <E0AsyncCapabilityDescriptor>[e1HostImmediateCapability],
  registry: E0CapabilityRegistry(<E0CapabilityRegistration>[
    E0CapabilityRegistration(
      e1HostImmediateCapability,
      (arguments) => Future<Object?>.delayed(
        const Duration(milliseconds: 2),
        () => (arguments.single as int) * 80,
      ),
    ),
  ]),
);
final Map<String, E1TrustedPublicKey> e1TrustedPublicKeys =
    <String, E1TrustedPublicKey>{
      e1SigningKeyId: E1TrustedPublicKey(
        keyId: e1SigningKeyId,
        bytes: e1SigningPublicKey,
      ),
    };
E1PatchController createPatchController(
  Directory supportDirectory, {
  Uri? patchUri,
}) => E1PatchController(
  storageDirectory: Directory('\${supportDirectory.path}/hyfens-e1'),
  appId: e1AppId,
  releaseId: e1ReleaseId,
  buildFingerprint: e1BuildFingerprint,
  functions: const <String, int>{
    ${mapEntry(async)},
    ${mapEntry(build)},
    ${mapEntry(calculate)},
  },
  signatures: const <String, String>{
    ${signatureEntry(async)},
    ${signatureEntry(build)},
    ${signatureEntry(calculate)},
  },
  receivers: const <String, String>{
    ${receiverEntry(async)},
    ${receiverEntry(build)},
    ${receiverEntry(calculate)},
  },
  runtimeConfiguration: E1RuntimeConfiguration(
    capabilities: e1CapabilityAuthority,
    widgetFactories: createConformanceWidgetRegistry(),
  ),
  trustedPublicKeys: e1TrustedPublicKeys,
  patchUri: patchUri ?? Uri.parse('http://127.0.0.1:18080/patch.e1.signed.json'),
);
''';
}
