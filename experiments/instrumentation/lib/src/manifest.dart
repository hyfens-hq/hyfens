import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../e0_runtime.dart';
import 'identity.dart';

final class E0FunctionManifest {
  const E0FunctionManifest({
    required this.name,
    required this.identity,
    required this.id,
    required this.slot,
    required this.signature,
    required this.receiver,
  });

  final String name;
  final E0DeclarationIdentity identity;
  final String id;
  final int slot;
  final E0FunctionSignature signature;
  final E0ReceiverDescriptor receiver;

  Map<String, Object> toJson() => <String, Object>{
    'name': name,
    'identity': identity.toJson(),
    'id': id,
    'slot': slot,
    'signature': signature.toJson(),
    'signatureDigest': signatureDigest,
    'receiver': receiver.toJson(),
  };

  String get signatureDigest =>
      sha256.convert(utf8.encode(signature.encode())).toString();

  static E0FunctionManifest fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'name',
      'identity',
      'id',
      'slot',
      'signature',
      'signatureDigest',
      'receiver',
    };
    final actual = value.keys.toSet();
    if (actual.difference(keys).isNotEmpty ||
        keys.difference(actual).isNotEmpty ||
        value['name'] is! String ||
        value['identity'] is! Map<String, Object?> ||
        value['id'] is! String ||
        value['slot'] is! int ||
        value['signature'] is! Map<String, Object?> ||
        value['signatureDigest'] is! String ||
        value['receiver'] is! Map<String, Object?>) {
      throw const FormatException('Invalid function manifest fields');
    }
    final result = E0FunctionManifest(
      name: value['name']! as String,
      identity: E0DeclarationIdentity.fromJson(
        value['identity']! as Map<String, Object?>,
      ),
      id: value['id']! as String,
      slot: value['slot']! as int,
      signature: E0FunctionSignature.fromJson(
        value['signature']! as Map<String, Object?>,
      ),
      receiver: E0ReceiverDescriptor.fromJson(
        value['receiver']! as Map<String, Object?>,
      ),
    );
    if (value['signatureDigest'] != result.signatureDigest) {
      throw const FormatException('Function signature digest mismatch');
    }
    if (result.id != result.identity.expectedId ||
        result.name != result.identity.memberName) {
      throw const FormatException('Function identity cross-field mismatch');
    }
    final owner = result.identity.ownerName;
    if ((owner == null && result.receiver != E0ReceiverDescriptor.none) ||
        (owner != null && result.receiver.ownerClass != owner)) {
      throw const FormatException('Function receiver owner mismatch');
    }
    return result;
  }
}

final class E0ReleaseManifest {
  E0ReleaseManifest({
    required this.appId,
    required this.releaseId,
    required this.buildFingerprint,
    required this.canonicalLibraryUri,
    required this.logicalLibraryPath,
    required List<E0FunctionManifest> functions,
    List<String>? libraryUris,
    List<E0AsyncCapabilityDescriptor> capabilities =
        const <E0AsyncCapabilityDescriptor>[],
    List<E0WidgetFactoryDescriptor> widgetFactories =
        const <E0WidgetFactoryDescriptor>[],
  }) : functions = List.unmodifiable(functions),
       libraryUris = List.unmodifiable(
         libraryUris ?? <String>[canonicalLibraryUri],
       ),
       capabilities = List.unmodifiable(capabilities),
       widgetFactories = List.unmodifiable(widgetFactories);

  final String appId;
  final String releaseId;
  final String buildFingerprint;
  final String canonicalLibraryUri;
  final String logicalLibraryPath;
  final List<E0FunctionManifest> functions;
  final List<String> libraryUris;
  final List<E0AsyncCapabilityDescriptor> capabilities;
  final List<E0WidgetFactoryDescriptor> widgetFactories;

  String encode() => jsonEncode(<String, Object>{
    'manifestVersion': 8,
    'appId': appId,
    'releaseId': releaseId,
    'buildFingerprint': buildFingerprint,
    'canonicalLibraryUri': canonicalLibraryUri,
    'logicalLibraryPath': logicalLibraryPath,
    'libraryUris': libraryUris,
    'functions': functions.map((item) => item.toJson()).toList(),
    'capabilities': capabilities.map((item) => item.toJson()).toList(),
    'widgetFactories': widgetFactories.map((item) => item.toJson()).toList(),
  });

  static E0ReleaseManifest decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Manifest root must be an object');
    }
    const keys = <String>{
      'manifestVersion',
      'appId',
      'releaseId',
      'buildFingerprint',
      'canonicalLibraryUri',
      'logicalLibraryPath',
      'libraryUris',
      'functions',
      'capabilities',
      'widgetFactories',
    };
    final actual = decoded.keys.toSet();
    if (actual.difference(keys).isNotEmpty ||
        keys.difference(actual).isNotEmpty ||
        decoded['manifestVersion'] != 8 ||
        decoded['appId'] is! String ||
        decoded['releaseId'] is! String ||
        decoded['buildFingerprint'] is! String ||
        (decoded['buildFingerprint']! as String).isEmpty ||
        decoded['canonicalLibraryUri'] is! String ||
        decoded['logicalLibraryPath'] is! String ||
        decoded['libraryUris'] is! List<Object?> ||
        decoded['functions'] is! List<Object?> ||
        decoded['capabilities'] is! List<Object?> ||
        decoded['widgetFactories'] is! List<Object?>) {
      throw const FormatException('Invalid release manifest fields');
    }
    final libraryUri = decoded['canonicalLibraryUri']! as String;
    E0Identity.validateCanonicalLibraryUri(libraryUri);
    final canonicalLogicalPath =
        'lib/${Uri.parse(libraryUri).pathSegments.skip(1).join('/')}';
    if (decoded['logicalLibraryPath'] != canonicalLogicalPath) {
      throw const FormatException('Logical library path is not canonical');
    }
    final packageName = Uri.parse(libraryUri).pathSegments.first;
    final recomputedLibraryUri = E0Identity().canonicalLibraryUri(
      packageName,
      decoded['logicalLibraryPath']! as String,
    );
    if (recomputedLibraryUri != libraryUri) {
      throw const FormatException('Release library routing mismatch');
    }
    final libraryUris = (decoded['libraryUris']! as List<Object?>)
        .map((item) {
          if (item is! String) {
            throw const FormatException('Invalid release library URI');
          }
          E0Identity.validateCanonicalLibraryUri(item);
          return item;
        })
        .toList(growable: false);
    final sortedLibraryUris = libraryUris.toList()..sort();
    if (libraryUris.isEmpty ||
        libraryUris.toSet().length != libraryUris.length ||
        !libraryUris.contains(libraryUri) ||
        !_sameStrings(libraryUris, sortedLibraryUris)) {
      throw const FormatException('Invalid release library routing table');
    }
    final functions = (decoded['functions']! as List<Object?>)
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid function manifest');
          }
          return E0FunctionManifest.fromJson(item);
        })
        .toList(growable: false);
    final ids = <String>{};
    String? previousId;
    for (var index = 0; index < functions.length; index++) {
      final function = functions[index];
      if (function.slot != index ||
          !libraryUris.contains(function.identity.libraryUri) ||
          (previousId != null && previousId.compareTo(function.id) >= 0)) {
        throw const FormatException('Function manifest routing mismatch');
      }
      if (!ids.add(function.id)) {
        throw const FormatException('Duplicate function identity');
      }
      previousId = function.id;
    }
    final capabilities = (decoded['capabilities']! as List<Object?>)
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid manifest capability');
          }
          return E0AsyncCapabilityDescriptor.fromJson(item);
        })
        .toList(growable: false);
    final capabilityIds = <String>{};
    final sourceNames = <String>{};
    for (final capability in capabilities) {
      if (capability.sourceName == null ||
          !capabilityIds.add(capability.id) ||
          !sourceNames.add(capability.sourceName!)) {
        throw const FormatException(
          'Duplicate or unroutable manifest capability',
        );
      }
    }
    final widgetFactories = (decoded['widgetFactories']! as List<Object?>)
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid manifest widget factory');
          }
          return E0WidgetFactoryDescriptor.fromJson(item);
        })
        .toList(growable: false);
    final widgetIds = <String>{};
    final widgetSourceNames = <String>{};
    if (widgetFactories.length > E0WidgetFactoryRegistry.maxFactories ||
        widgetFactories.any(
          (factory) =>
              !widgetIds.add(factory.id) ||
              !widgetSourceNames.add(factory.sourceName),
        )) {
      throw const FormatException('Duplicate or oversized widget factories');
    }
    return E0ReleaseManifest(
      appId: decoded['appId']! as String,
      releaseId: decoded['releaseId']! as String,
      buildFingerprint: decoded['buildFingerprint']! as String,
      canonicalLibraryUri: libraryUri,
      logicalLibraryPath: decoded['logicalLibraryPath']! as String,
      functions: List.unmodifiable(functions),
      libraryUris: List.unmodifiable(libraryUris),
      capabilities: List.unmodifiable(capabilities),
      widgetFactories: List.unmodifiable(widgetFactories),
    );
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
