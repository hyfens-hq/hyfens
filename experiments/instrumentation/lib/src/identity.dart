import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef E0Digest = String Function(List<int> bytes);

final class E0DeclarationIdentity {
  const E0DeclarationIdentity({
    required this.libraryUri,
    required this.ownerKind,
    required this.ownerName,
    required this.memberKind,
    required this.memberName,
  });

  static const int version = 1;
  static const String topLevelOwner = 'library';
  static const String classOwner = 'class';
  static const String topLevelFunction = 'topLevelFunction';
  static const String instanceMethod = 'instanceMethod';

  final String libraryUri;
  final String ownerKind;
  final String? ownerName;
  final String memberKind;
  final String memberName;

  Map<String, Object?> toJson() => <String, Object?>{
    'identityVersion': version,
    'libraryUri': libraryUri,
    'ownerKind': ownerKind,
    'ownerName': ownerName,
    'memberKind': memberKind,
    'memberName': memberName,
  };

  String encode() => jsonEncode(toJson());

  static E0DeclarationIdentity fromJson(Map<String, Object?> value) {
    const keys = <String>{
      'identityVersion',
      'libraryUri',
      'ownerKind',
      'ownerName',
      'memberKind',
      'memberName',
    };
    final actual = value.keys.toSet();
    if (actual.difference(keys).isNotEmpty ||
        keys.difference(actual).isNotEmpty ||
        value['identityVersion'] != version ||
        value['libraryUri'] is! String ||
        value['ownerKind'] is! String ||
        (value['ownerName'] != null && value['ownerName'] is! String) ||
        value['memberKind'] is! String ||
        value['memberName'] is! String ||
        (value['memberName']! as String).isEmpty) {
      throw const FormatException('Invalid declaration identity fields');
    }
    final result = E0DeclarationIdentity(
      libraryUri: value['libraryUri']! as String,
      ownerKind: value['ownerKind']! as String,
      ownerName: value['ownerName'] as String?,
      memberKind: value['memberKind']! as String,
      memberName: value['memberName']! as String,
    );
    result.validateShape();
    return result;
  }

  void validateShape() {
    E0Identity.validateCanonicalLibraryUri(libraryUri);
    switch (memberKind) {
      case topLevelFunction:
        if (ownerKind != topLevelOwner || ownerName != null) {
          throw const FormatException('Invalid top-level function owner');
        }
      case instanceMethod:
        if (ownerKind != classOwner ||
            ownerName == null ||
            ownerName!.isEmpty) {
          throw const FormatException('Invalid instance method owner');
        }
      default:
        throw FormatException(
          'Unsupported declaration member kind $memberKind',
        );
    }
  }

  String get expectedId =>
      'sha256:${sha256.convert(utf8.encode(encode())).toString()}';
}

final class E0Identity {
  E0Identity({E0Digest? digest}) : _digest = digest ?? _sha256;

  final E0Digest _digest;

  E0DeclarationIdentity declaration({
    required String canonicalLibraryUri,
    required String declarationName,
    String? declarationClass,
  }) {
    validateCanonicalLibraryUri(canonicalLibraryUri);
    final result = E0DeclarationIdentity(
      libraryUri: canonicalLibraryUri,
      ownerKind: declarationClass == null
          ? E0DeclarationIdentity.topLevelOwner
          : E0DeclarationIdentity.classOwner,
      ownerName: declarationClass,
      memberKind: declarationClass == null
          ? E0DeclarationIdentity.topLevelFunction
          : E0DeclarationIdentity.instanceMethod,
      memberName: declarationName,
    );
    result.validateShape();
    return result;
  }

  String canonicalLibraryUri(String packageName, String libraryPath) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(packageName)) {
      throw const FormatException('Invalid package name for library identity');
    }
    if (libraryPath.isEmpty ||
        libraryPath.contains(r'\') ||
        libraryPath.contains('?') ||
        libraryPath.contains('#') ||
        libraryPath.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(libraryPath)) {
      throw const FormatException('Invalid logical library path');
    }
    final normalized = Uri(path: libraryPath).normalizePath().path;
    if (!normalized.startsWith('lib/') ||
        normalized == 'lib/' ||
        normalized.startsWith('../') ||
        normalized.split('/').any((segment) => segment.isEmpty)) {
      throw const FormatException(
        'Logical library path must identify a file below lib/',
      );
    }
    final result = 'package:$packageName/${normalized.substring(4)}';
    validateCanonicalLibraryUri(result);
    return result;
  }

  static void validateCanonicalLibraryUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'package' ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length < 2 ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(uri.pathSegments.first) ||
        uri.pathSegments
            .skip(1)
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            ) ||
        uri.toString() != value) {
      throw const FormatException('Invalid canonical package library URI');
    }
  }

  String receiverMemberMaterial({
    required String canonicalLibraryUri,
    required String declarationClass,
    required String memberName,
  }) {
    validateCanonicalLibraryUri(canonicalLibraryUri);
    return jsonEncode(<String, Object>{
      'identityVersion': 1,
      'libraryUri': canonicalLibraryUri,
      'ownerKind': 'class',
      'ownerName': declarationClass,
      'memberKind': 'receiverProperty',
      'memberName': memberName,
    });
  }

  String idFor(E0DeclarationIdentity identity) =>
      'sha256:${_digest(utf8.encode(identity.encode()))}';

  String idForMaterial(String material) =>
      'sha256:${_digest(utf8.encode(material))}';

  static String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
}
