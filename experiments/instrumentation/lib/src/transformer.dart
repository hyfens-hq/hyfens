import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
import 'package:package_config/package_config.dart';

import '../e0_runtime.dart';
import 'compiler.dart';
import 'identity.dart';
import 'manifest.dart';
import 'offset_map.dart';

final class E0TransformResult {
  const E0TransformResult({
    required this.source,
    required this.manifest,
    required this.offsetMap,
    required this.exclusions,
  });

  final String source;
  final E0ReleaseManifest manifest;
  final E0OffsetMap offsetMap;
  final List<String> exclusions;
}

final class E0SourceTransformer {
  E0SourceTransformer({E0Identity? identity})
    : identity = identity ?? E0Identity();

  final E0Identity identity;

  E0TransformResult transform({
    required String source,
    required String packageName,
    required String logicalLibraryPath,
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    String? canonicalLibraryUri,
    List<E0AsyncCapabilityDescriptor> capabilities =
        const <E0AsyncCapabilityDescriptor>[],
    List<E0WidgetFactoryDescriptor> widgetFactories =
        const <E0WidgetFactoryDescriptor>[],
    Set<String> widgetBuildClasses = const <String>{},
    bool allowSyntheticWidgetTypes = false,
    bool requireMain = true,
    bool installRuntime = true,
    Map<String, int>? assignedSlots,
    List<E0FunctionManifest>? releaseFunctions,
    String? runtimeBootstrapImport,
    String? runtimeBootstrapInvocation,
  }) {
    if (buildFingerprint.isEmpty) {
      throw const FormatException('Build fingerprint must not be empty');
    }
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
    final libraryUri =
        canonicalLibraryUri ??
        identity.canonicalLibraryUri(packageName, logicalLibraryPath);
    E0Identity.validateCanonicalLibraryUri(libraryUri);
    final canonicalLogicalLibraryPath =
        'lib/${Uri.parse(libraryUri).pathSegments.skip(1).join('/')}';
    final parsed = parseString(
      content: source,
      path: logicalLibraryPath,
      throwIfDiagnostics: false,
    );
    final errors = parsed.errors.where(
      (error) => error.diagnosticCode.name != 'TODO',
    );
    if (errors.isNotEmpty) {
      throw FormatException('Input does not parse: ${errors.first}');
    }
    if (parsed.unit.directives.any(
      (directive) => directive is PartDirective || directive is PartOfDirective,
    )) {
      throw const FormatException(
        'Part files and part directives are unsupported',
      );
    }
    final candidates = <_Candidate>[];
    final exclusions = <String>[];
    FunctionDeclaration? mainDeclaration;
    final classes = <String, ClassDeclaration>{
      for (final declaration
          in parsed.unit.declarations.whereType<ClassDeclaration>())
        declaration.name.lexeme: declaration,
    };
    final hasFlutterWidgetImport = _hasCanonicalFlutterWidgetImport(
      parsed.unit,
    );
    final hasWidgetAbiShadows = classes.keys.any(
      <String>{
        'Widget',
        'BuildContext',
        'StatelessWidget',
        ...widgetFactories.map((factory) => factory.sourceName),
      }.contains,
    );
    for (final declaration in parsed.unit.declarations) {
      if (declaration is FunctionDeclaration) {
        if (declaration.name.lexeme == 'main') {
          mainDeclaration = declaration;
          continue;
        }
        final reason = _unsupportedReason(declaration);
        if (reason != null) {
          exclusions.add('${declaration.name.lexeme}: $reason');
          continue;
        }
        final signature = e0SignatureForDeclaration(declaration);
        final declarationIdentity = identity.declaration(
          canonicalLibraryUri: libraryUri,
          declarationName: declaration.name.lexeme,
        );
        candidates.add(
          _Candidate(
            name: declaration.name.lexeme,
            ownerClass: null,
            body: declaration.functionExpression.body as BlockFunctionBody,
            parameters: declaration.functionExpression.parameters!,
            returnType: declaration.returnType!,
            signature: signature,
            receiver: E0ReceiverDescriptor.none,
            identity: declarationIdentity,
            id: identity.idFor(declarationIdentity),
          ),
        );
        continue;
      }
      if (declaration is! ClassDeclaration) continue;
      for (final method in declaration.members.whereType<MethodDeclaration>()) {
        final qualifiedName =
            '${declaration.name.lexeme}.${method.name.lexeme}';
        final requestedWidgetBuild =
            widgetBuildClasses.contains(declaration.name.lexeme) &&
            e0IsWidgetBuildMethod(method);
        if (requestedWidgetBuild &&
            (!allowSyntheticWidgetTypes &&
                (!hasFlutterWidgetImport || hasWidgetAbiShadows))) {
          exclusions.add(
            '$qualifiedName: widget ABI requires canonical unshadowed package:flutter types',
          );
          continue;
        }
        final selectedWidgetBuild =
            requestedWidgetBuild && _extendsStatelessWidget(declaration);
        final reason = e0UnsupportedMethodReason(
          method,
          allowWidgetBuild: selectedWidgetBuild,
        );
        if (reason != null) {
          exclusions.add('$qualifiedName: $reason');
          continue;
        }
        E0ReceiverDescriptor receiver;
        try {
          receiver = _receiverDescriptor(
            method: method,
            owner: declaration,
            classes: classes,
            canonicalLibraryUri: libraryUri,
          );
        } on FormatException catch (error) {
          exclusions.add('$qualifiedName: ${error.message}');
          continue;
        }
        final signature = e0SignatureForMethodDeclaration(
          method,
          allowWidgetBuild: selectedWidgetBuild,
        );
        final declarationIdentity = identity.declaration(
          canonicalLibraryUri: libraryUri,
          declarationName: method.name.lexeme,
          declarationClass: declaration.name.lexeme,
        );
        candidates.add(
          _Candidate(
            name: method.name.lexeme,
            ownerClass: declaration.name.lexeme,
            body: method.body as BlockFunctionBody,
            parameters: method.parameters!,
            returnType: method.returnType!,
            signature: signature,
            receiver: receiver,
            identity: declarationIdentity,
            id: identity.idFor(declarationIdentity),
          ),
        );
      }
    }
    if (requireMain &&
        (mainDeclaration == null ||
            mainDeclaration.functionExpression.body is! BlockFunctionBody)) {
      throw const FormatException('E0 requires a block-bodied main function');
    }
    if (installRuntime && mainDeclaration == null) {
      throw const FormatException(
        'Runtime installation requires a block-bodied main function',
      );
    }
    candidates.sort((left, right) => left.id.compareTo(right.id));
    if (assignedSlots != null) {
      final candidateIds = candidates.map((candidate) => candidate.id).toSet();
      if (assignedSlots.keys.toSet().difference(candidateIds).isNotEmpty ||
          candidateIds.difference(assignedSlots.keys.toSet()).isNotEmpty ||
          assignedSlots.values.any((slot) => slot < 0) ||
          assignedSlots.values.toSet().length != assignedSlots.length) {
        throw const FormatException(
          'Assigned slots do not match library functions',
        );
      }
    }
    final usedIdentifiers = _sourceIdentifiers(parsed.unit);
    final runtimePrefix = _freshIdentifier('e0_runtime', usedIdentifiers);
    final patchLocal = _freshIdentifier(r'$e0Patch', usedIdentifiers);
    final resultLocal = _freshIdentifier(r'$e0Result', usedIdentifiers);
    final candidateSlots = <String, int>{
      for (var index = 0; index < candidates.length; index++)
        candidates[index].id: assignedSlots?[candidates[index].id] ?? index,
    };
    final adapterNames = <int, String>{
      for (final candidate in candidates)
        if (candidate.ownerClass != null)
          candidateSlots[candidate.id]!: _freshIdentifier(
            '_E0ReceiverAdapter${candidateSlots[candidate.id]}',
            usedIdentifiers,
          ),
    };
    final seen = <String, String>{};
    for (final candidate in candidates) {
      final material = candidate.identity.encode();
      final prior = seen[candidate.id];
      if (prior != null) {
        throw StateError(
          prior == material
              ? 'Duplicate stable identity: $material'
              : 'Stable ID collision: $prior / $material',
        );
      }
      seen[candidate.id] = material;
    }
    final functions = <E0FunctionManifest>[];
    final edits = <_Edit>[];
    final importOffset = parsed.unit.directives.isEmpty
        ? 0
        : parsed.unit.directives.last.end;
    for (final candidate in candidates) {
      final slot = candidateSlots[candidate.id]!;
      functions.add(
        E0FunctionManifest(
          name: candidate.name,
          receiver: candidate.receiver,
          identity: candidate.identity,
          id: candidate.id,
          slot: slot,
          signature: candidate.signature,
        ),
      );
      final body = candidate.body;
      final receiverArgument = candidate.ownerClass == null
          ? ''
          : ', receiver: ${adapterNames[slot]}(this)';
      final isWidgetBuild = candidate.signature == e0WidgetBuildSignature;
      final invocationArguments = isWidgetBuild
          ? '<Object?>[]'
          : '<Object?>[${_parameterNames(candidate.parameters).join(', ')}]';
      final namedInvocationArguments = isWidgetBuild
          ? ''
          : _namedParameterArguments(candidate.parameters);
      final guard = candidate.signature.isAsync
          ? '\n  final $patchLocal = $runtimePrefix.E0PatchRuntime.lookup($slot);'
                '\n  if ($patchLocal != null) {'
                '\n    final $resultLocal = '
                '$runtimePrefix.E0PatchRuntime.invokeAsync<${candidate.signature.returnSchema.toDartSource()}>('
                '$patchLocal, '
                '$invocationArguments'
                '$receiverArgument'
                '$namedInvocationArguments);'
                '\n    if ($resultLocal != null) {'
                '\n      return $resultLocal;'
                '\n    }'
                '\n  }'
          : '\n  final $patchLocal = $runtimePrefix.E0PatchRuntime.lookup($slot);'
                '\n  if ($patchLocal != null) {'
                '\n    final $resultLocal = '
                '$runtimePrefix.E0PatchRuntime.${isWidgetBuild ? 'invokeWidget<${candidate.returnType.toSource()}>' : 'invoke'}($patchLocal, '
                '$invocationArguments'
                '$receiverArgument'
                '$namedInvocationArguments);'
                '\n    if ($resultLocal.isSuccess) {'
                '\n      return $resultLocal.value as '
                '${candidate.returnType.toSource()};'
                '\n    }'
                '\n    if ($resultLocal.isGuestThrow) {'
                '\n      $resultLocal.rethrowGuest();'
                '\n    }'
                '\n  }';
      edits.add(_Edit(body.block.leftBracket.end, 'callee-guard', guard));
    }
    if (installRuntime) {
      final mainBody =
          mainDeclaration!.functionExpression.body as BlockFunctionBody;
      final runtimeFunctions = releaseFunctions ?? functions;
      final functionMap = <String, int>{
        for (final function in runtimeFunctions) function.id: function.slot,
      };
      final signatureMap = <String, String>{
        for (final function in runtimeFunctions)
          function.id: function.signature.encode(),
      };
      final receiverMap = <String, String>{
        for (final function in runtimeFunctions)
          function.id: function.receiver.encode(),
      };
      final bootstrapPrefix = runtimeBootstrapImport == null
          ? null
          : _freshIdentifier('_hyfens_bootstrap', usedIdentifiers);
      final bootstrapImport = runtimeBootstrapImport?.replaceAll(
        '{prefix}',
        'as $bootstrapPrefix',
      );
      final bootstrapInvocation = runtimeBootstrapInvocation?.replaceAll(
        '{prefix}',
        bootstrapPrefix!,
      );
      final runtimeInit = StringBuffer(
        '\n  $runtimePrefix.E0PatchRuntime.installFromArguments('
        '${_mainArguments(mainDeclaration)}, '
        "appId: ${jsonEncode(appId)}, "
        "releaseId: ${jsonEncode(releaseId)}, "
        "buildFingerprint: ${jsonEncode(buildFingerprint)}, "
        "functions: ${_dartMap(functionMap)}, "
        "signatures: ${_dartStringMap(signatureMap)}, "
        "receivers: ${_dartStringMap(receiverMap)});",
      );
      if (bootstrapInvocation != null) {
        runtimeInit.write('\n  ');
        runtimeInit.write(bootstrapInvocation);
      }
      edits.add(
        _Edit(
          mainBody.block.leftBracket.end,
          'runtime-init',
          runtimeInit.toString(),
        ),
      );
      if (bootstrapImport != null) {
        edits.add(
          _Edit(
            importOffset,
            'runtime-bootstrap-import',
            '${bootstrapImport.trim()}\n',
          ),
        );
      }
    }
    final receiverAdapters = StringBuffer();
    for (final candidate in candidates) {
      if (candidate.ownerClass == null) continue;
      final slot = candidateSlots[candidate.id]!;
      receiverAdapters.write(
        _receiverAdapterSource(
          adapterName: adapterNames[slot]!,
          runtimePrefix: runtimePrefix,
          candidate: candidate,
        ),
      );
    }
    if (receiverAdapters.isNotEmpty) {
      edits.add(
        _Edit(
          source.length,
          'receiver-adapter',
          '\n${receiverAdapters.toString()}',
        ),
      );
    }
    edits.add(
      _Edit(
        importOffset,
        'runtime-import',
        "${importOffset == 0 ? '' : '\n'}import "
            "'package:instrumentation_e0/e0_runtime.dart' as "
            '$runtimePrefix;\n',
      ),
    );
    edits.sort((left, right) => left.offset.compareTo(right.offset));
    final transformedBuffer = StringBuffer();
    final segments = <E0OffsetSegment>[];
    var originalCursor = 0;
    var generatedCursor = 0;
    for (final edit in edits) {
      if (edit.offset < originalCursor) {
        throw StateError('Overlapping source edits at ${edit.offset}');
      }
      final unchanged = source.substring(originalCursor, edit.offset);
      if (unchanged.isNotEmpty) {
        transformedBuffer.write(unchanged);
        segments.add(
          E0OffsetSegment(
            generatedStart: generatedCursor,
            length: unchanged.length,
            originalStart: originalCursor,
            syntheticKind: null,
            anchorOriginalOffset: originalCursor,
          ),
        );
        generatedCursor += unchanged.length;
      }
      transformedBuffer.write(edit.text);
      segments.add(
        E0OffsetSegment(
          generatedStart: generatedCursor,
          length: edit.text.length,
          originalStart: null,
          syntheticKind: edit.kind,
          anchorOriginalOffset: edit.offset,
        ),
      );
      generatedCursor += edit.text.length;
      originalCursor = edit.offset;
    }
    final tail = source.substring(originalCursor);
    if (tail.isNotEmpty) {
      transformedBuffer.write(tail);
      segments.add(
        E0OffsetSegment(
          generatedStart: generatedCursor,
          length: tail.length,
          originalStart: originalCursor,
          syntheticKind: null,
          anchorOriginalOffset: originalCursor,
        ),
      );
      generatedCursor += tail.length;
    }
    final transformed = transformedBuffer.toString();
    final offsetMap = E0OffsetMap(
      originalUri: libraryUri,
      generatedUri: 'e0-overlay:$logicalLibraryPath',
      originalLength: source.length,
      generatedLength: transformed.length,
      segments: List.unmodifiable(segments),
    );
    E0OffsetMap.decode(offsetMap.encode());
    final outputParse = parseString(content: transformed);
    if (outputParse.errors.isNotEmpty) {
      throw StateError(
        'Transformer emitted invalid Dart: ${outputParse.errors}',
      );
    }
    return E0TransformResult(
      source: transformed,
      manifest: E0ReleaseManifest(
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        canonicalLibraryUri: libraryUri,
        logicalLibraryPath: canonicalLogicalLibraryPath,
        functions: functions,
        capabilities: List.unmodifiable(capabilities),
        widgetFactories: List.unmodifiable(widgetFactories),
      ),
      offsetMap: offsetMap,
      exclusions: List.unmodifiable(exclusions),
    );
  }

  static String? _unsupportedReason(FunctionDeclaration declaration) {
    final expression = declaration.functionExpression;
    if (expression.body is! BlockFunctionBody) return 'non-block body';
    final body = expression.body as BlockFunctionBody;
    if (body.isGenerator) {
      return 'generator body';
    }
    try {
      final signature = e0SignatureForDeclaration(declaration);
      if (body.isAsynchronous != signature.isAsync) {
        return 'async body must declare Future<T>, and Future<T> patches must use async';
      }
    } on FormatException catch (error) {
      return error.message.toString();
    }
    return null;
  }

  static bool _extendsStatelessWidget(ClassDeclaration declaration) =>
      declaration.extendsClause?.superclass.toSource() == 'StatelessWidget';

  static bool _hasCanonicalFlutterWidgetImport(CompilationUnit unit) {
    final imports = unit.directives.whereType<ImportDirective>().where(
      (directive) =>
          directive.uri.stringValue?.startsWith('package:flutter/') ?? false,
    );
    return imports.length == 1 &&
        imports.single.prefix == null &&
        imports.single.combinators.isEmpty;
  }

  E0ReceiverDescriptor _receiverDescriptor({
    required MethodDeclaration method,
    required ClassDeclaration owner,
    required Map<String, ClassDeclaration> classes,
    required String canonicalLibraryUri,
  }) {
    if (owner.typeParameters != null) {
      throw const FormatException('generic owner class');
    }
    final referencedNames = <String>{};
    method.body.accept(_ThisPropertyReadVisitor(referencedNames));
    final unresolved = <String>[];
    final resolved = <({String id, String name, E0ValueSchema schema})>[];
    for (final name in referencedNames) {
      final property = _resolveProperty(
        owner: owner,
        name: name,
        classes: classes,
      );
      if (property == null) {
        unresolved.add(name);
        continue;
      }
      final schema = e0HostSchemaForType(
        property.type.toSource(),
        'receiver property ${property.declaringClass}.$name',
      );
      final material = identity.receiverMemberMaterial(
        canonicalLibraryUri: canonicalLibraryUri,
        declarationClass: property.declaringClass,
        memberName: name,
      );
      resolved.add((
        id: identity.idForMaterial(material),
        name: name,
        schema: schema,
      ));
    }
    if (unresolved.isNotEmpty) {
      unresolved.sort();
      throw FormatException(
        'unresolved explicit receiver property ${unresolved.join(', ')}',
      );
    }
    resolved.sort((left, right) => left.id.compareTo(right.id));
    final members = <E0ReceiverMember>[
      for (var slot = 0; slot < resolved.length; slot++)
        E0ReceiverMember(
          id: resolved[slot].id,
          name: resolved[slot].name,
          slot: slot,
          schema: resolved[slot].schema,
        ),
    ];
    final descriptorMaterial = StringBuffer(
      'e0-receiver-descriptor-v1\u0000${owner.name.lexeme}',
    );
    for (final member in members) {
      descriptorMaterial
        ..write('\u0000${member.id}\u0000')
        ..write(jsonEncode(member.schema.toJson()));
    }
    return E0ReceiverDescriptor(
      id: identity.idForMaterial(descriptorMaterial.toString()),
      ownerClass: owner.name.lexeme,
      members: List.unmodifiable(members),
    );
  }

  static ({String declaringClass, TypeAnnotation type})? _resolveProperty({
    required ClassDeclaration owner,
    required String name,
    required Map<String, ClassDeclaration> classes,
    Set<String>? seen,
  }) {
    final visited = seen ?? <String>{};
    if (!visited.add(owner.name.lexeme)) return null;
    for (final member in owner.members) {
      if (member is FieldDeclaration) {
        if (member.isStatic) continue;
        final type = member.fields.type;
        if (type != null &&
            member.fields.variables.any(
              (variable) => variable.name.lexeme == name,
            )) {
          return (declaringClass: owner.name.lexeme, type: type);
        }
      }
      if (member is MethodDeclaration &&
          member.isGetter &&
          !member.isStatic &&
          member.name.lexeme == name &&
          member.returnType != null) {
        return (declaringClass: owner.name.lexeme, type: member.returnType!);
      }
    }
    final parentName = owner.extendsClause?.superclass.name.lexeme;
    final parent = parentName == null ? null : classes[parentName];
    if (parent == null) return null;
    return _resolveProperty(
      owner: parent,
      name: name,
      classes: classes,
      seen: visited,
    );
  }

  static String _receiverAdapterSource({
    required String adapterName,
    required String runtimePrefix,
    required _Candidate candidate,
  }) {
    final cases = candidate.receiver.members
        .map(
          (member) =>
              '      case ${member.slot}: return _receiver.${member.name};\n',
        )
        .join();
    return '\nfinal class $adapterName '
        'implements $runtimePrefix.E0ReceiverCapability {\n'
        '  const $adapterName(this._receiver);\n'
        '  final ${candidate.ownerClass} _receiver;\n'
        '  @override\n'
        '  String get descriptorId => ${jsonEncode(candidate.receiver.id)};\n'
        '  @override\n'
        '  Object? read(int slot) {\n'
        '    switch (slot) {\n'
        '$cases'
        "      default: throw RangeError.range(slot, 0, ${candidate.receiver.members.length - 1}, 'slot');\n"
        '    }\n'
        '  }\n'
        '}\n';
  }

  static List<String> _parameterNames(FormalParameterList parameters) =>
      parameters.parameters
          .where((parameter) => !parameter.isNamed)
          .map((parameter) => parameter.name!.lexeme)
          .toList();

  static String _namedParameterArguments(FormalParameterList parameters) {
    final named = parameters.parameters.where((parameter) => parameter.isNamed);
    if (named.isEmpty) return '';
    return ', namedArguments: <String, Object?>{${named.map((parameter) => '${jsonEncode(parameter.name!.lexeme)}: ${parameter.name!.lexeme}').join(', ')}}';
  }

  static Set<String> _sourceIdentifiers(CompilationUnit unit) {
    final identifiers = <String>{};
    var token = unit.beginToken;
    while (true) {
      identifiers.add(token.lexeme);
      if (identical(token, unit.endToken)) break;
      token = token.next!;
    }
    return identifiers;
  }

  static String _freshIdentifier(String base, Set<String> used) {
    var candidate = base;
    var suffix = 1;
    while (used.contains(candidate)) {
      candidate = '${base}_${suffix++}';
    }
    used.add(candidate);
    return candidate;
  }

  static String _mainArguments(FunctionDeclaration declaration) {
    final parameters = declaration.functionExpression.parameters?.parameters;
    return parameters != null && parameters.length == 1
        ? parameters.single.name!.lexeme
        : 'const <String>[]';
  }

  static String _dartMap(Map<String, int> value) =>
      '<String, int>{${value.entries.map((entry) => '${jsonEncode(entry.key)}: ${entry.value}').join(', ')}}';

  static String _dartStringMap(Map<String, String> value) =>
      '<String, String>{${value.entries.map((entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value)}').join(', ')}}';
}

final class E0OverlayBuilder {
  const E0OverlayBuilder(this.transformer);

  final E0SourceTransformer transformer;

  E0TransformResult build({
    required File input,
    required Directory outputDirectory,
    required String packageName,
    required String logicalLibraryPath,
    required String appId,
    required String releaseId,
    required String buildFingerprint,
    List<E0AsyncCapabilityDescriptor> capabilities =
        const <E0AsyncCapabilityDescriptor>[],
    List<E0WidgetFactoryDescriptor> widgetFactories =
        const <E0WidgetFactoryDescriptor>[],
    Set<String> widgetBuildClasses = const <String>{},
    bool allowSyntheticWidgetTypes = false,
  }) {
    final before = input.readAsBytesSync();
    final beforeHash = sha256.convert(before);
    final explicitLibraryUri = transformer.identity.canonicalLibraryUri(
      packageName,
      logicalLibraryPath,
    );
    final discovery = _discoverPackageUri(input);
    if (discovery.foundConfig && discovery.packageUri == null) {
      throw const FormatException(
        'Input is outside the configured package URI root',
      );
    }
    final discoveredLibraryUri = discovery.packageUri;
    if (discoveredLibraryUri != null &&
        discoveredLibraryUri != explicitLibraryUri) {
      throw FormatException(
        'Resolved package URI $discoveredLibraryUri does not match '
        'declared $explicitLibraryUri',
      );
    }
    final result = transformer.transform(
      source: utf8.decode(before),
      packageName: packageName,
      logicalLibraryPath: logicalLibraryPath,
      appId: appId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      canonicalLibraryUri: discoveredLibraryUri ?? explicitLibraryUri,
      capabilities: capabilities,
      widgetFactories: widgetFactories,
      widgetBuildClasses: widgetBuildClasses,
      allowSyntheticWidgetTypes: allowSyntheticWidgetTypes,
    );
    outputDirectory.createSync(recursive: true);
    File('${outputDirectory.path}/app.dart').writeAsStringSync(result.source);
    File('${outputDirectory.path}/manifest.json')
        .writeAsStringSync(result.manifest.encode());
    File('${outputDirectory.path}/source-map.json')
        .writeAsStringSync(result.offsetMap.encode());
    if (sha256.convert(input.readAsBytesSync()) != beforeHash) {
      throw StateError('Transformer modified original source');
    }
    return result;
  }

  static ({bool foundConfig, String? packageUri}) _discoverPackageUri(
    File input,
  ) {
    var directory = input.absolute.parent;
    while (true) {
      final configFile = File(
        '${directory.path}/.dart_tool/package_config.json',
      );
      if (configFile.existsSync()) {
        final config = PackageConfig.parseBytes(
          configFile.readAsBytesSync(),
          configFile.uri,
        );
        final uri = config.toPackageUri(input.absolute.uri);
        if (uri == null) return (foundConfig: true, packageUri: null);
        final value = uri.toString();
        E0Identity.validateCanonicalLibraryUri(value);
        return (foundConfig: true, packageUri: value);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return (foundConfig: false, packageUri: null);
      }
      directory = parent;
    }
  }
}

final class E0PackageUnit {
  const E0PackageUnit({required this.input, this.isEntrypoint = false});

  final File input;
  final bool isEntrypoint;
}

/// The reason a candidate source unit was included in or excluded from an E0
/// package overlay.
enum E0InstrumentationSelectionReason {
  applicationDefault,
  packageOptIn,
  explicitExclude,
  dependencyRequiresOptIn,
  generatedDefaultExclude,
  sdkHardExclude,
  flutterHardExclude,
  nativeBoundary,
}

final class E0InstrumentationSelectionDecision {
  const E0InstrumentationSelectionDecision({
    required this.libraryUri,
    required this.included,
    required this.hardExcluded,
    required this.reason,
  });

  final String libraryUri;
  final bool included;
  final bool hardExcluded;
  final E0InstrumentationSelectionReason reason;
}

final class E0InstrumentationSelectionPlan {
  E0InstrumentationSelectionPlan({
    required List<E0PackageUnit> includedUnits,
    required List<E0InstrumentationSelectionDecision> decisions,
  }) : includedUnits = List.unmodifiable(includedUnits),
       decisions = List.unmodifiable(decisions);

  final List<E0PackageUnit> includedUnits;
  final List<E0InstrumentationSelectionDecision> decisions;
}

/// Selects source units before constructing a package overlay.
///
/// Application-owned Dart libraries are included by default. Pure-Dart
/// dependencies are included only when their package name appears in
/// [optedInPackages]. Generated files are excluded by default, while SDK,
/// Flutter, part, and FFI/native boundaries cannot be opted in.
final class E0InstrumentationSelectionPolicy {
  E0InstrumentationSelectionPolicy({
    required this.applicationPackage,
    Set<String> optedInPackages = const <String>{},
    Set<String> excludedLibraryUris = const <String>{},
  }) : optedInPackages = Set.unmodifiable(optedInPackages),
       excludedLibraryUris = Set.unmodifiable(excludedLibraryUris) {
    if (applicationPackage.isEmpty ||
        optedInPackages.contains(applicationPackage)) {
      throw const FormatException(
        'Application package must be non-empty and must not be opted in',
      );
    }
    for (final uri in excludedLibraryUris) {
      E0Identity.validateCanonicalLibraryUri(uri);
    }
  }

  final String applicationPackage;
  final Set<String> optedInPackages;
  final Set<String> excludedLibraryUris;

  E0InstrumentationSelectionPlan plan({
    required List<E0PackageUnit> candidates,
    required File packageConfig,
  }) {
    if (candidates.isEmpty ||
        candidates.where((unit) => unit.isEntrypoint).length != 1) {
      throw const FormatException(
        'Selection requires exactly one candidate entrypoint',
      );
    }
    final config = PackageConfig.parseBytes(
      packageConfig.readAsBytesSync(),
      packageConfig.uri,
    );
    final included = <E0PackageUnit>[];
    final decisions = <E0InstrumentationSelectionDecision>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final packageUri = config.toPackageUri(candidate.input.absolute.uri);
      if (packageUri == null) {
        final decision = E0InstrumentationSelectionDecision(
          libraryUri: candidate.input.absolute.uri.toString(),
          included: false,
          hardExcluded: true,
          reason: E0InstrumentationSelectionReason.sdkHardExclude,
        );
        decisions.add(decision);
        if (candidate.isEntrypoint) {
          throw const FormatException(
            'Application entrypoint must resolve to a package URI',
          );
        }
        continue;
      }
      final libraryUri = packageUri.toString();
      E0Identity.validateCanonicalLibraryUri(libraryUri);
      if (!seen.add(libraryUri)) {
        throw FormatException('Duplicate selection candidate $libraryUri');
      }
      final segments = packageUri.pathSegments;
      final packageName = segments.first;
      final logicalLibraryPath = 'lib/${segments.skip(1).join('/')}';
      final source = candidate.input.readAsStringSync();
      final boundary = E0PackageOverlayBuilder._excludedUnitReason(
        packageName: packageName,
        logicalLibraryPath: logicalLibraryPath,
        source: source,
      );
      late final E0InstrumentationSelectionDecision decision;
      if (boundary != null) {
        decision = E0InstrumentationSelectionDecision(
          libraryUri: libraryUri,
          included: false,
          hardExcluded: true,
          reason: boundary,
        );
      } else if (excludedLibraryUris.contains(libraryUri)) {
        decision = E0InstrumentationSelectionDecision(
          libraryUri: libraryUri,
          included: false,
          hardExcluded: false,
          reason: E0InstrumentationSelectionReason.explicitExclude,
        );
      } else if (packageName == applicationPackage) {
        decision = E0InstrumentationSelectionDecision(
          libraryUri: libraryUri,
          included: true,
          hardExcluded: false,
          reason: E0InstrumentationSelectionReason.applicationDefault,
        );
      } else if (optedInPackages.contains(packageName)) {
        decision = E0InstrumentationSelectionDecision(
          libraryUri: libraryUri,
          included: true,
          hardExcluded: false,
          reason: E0InstrumentationSelectionReason.packageOptIn,
        );
      } else {
        decision = E0InstrumentationSelectionDecision(
          libraryUri: libraryUri,
          included: false,
          hardExcluded: false,
          reason: E0InstrumentationSelectionReason.dependencyRequiresOptIn,
        );
      }
      decisions.add(decision);
      if (decision.included) included.add(candidate);
      if (candidate.isEntrypoint && !decision.included) {
        throw FormatException(
          'Application entrypoint $libraryUri is excluded by ${decision.reason.name}',
        );
      }
    }
    final entrypoint = included.singleWhere((unit) => unit.isEntrypoint);
    final entrypointUri = config.toPackageUri(entrypoint.input.absolute.uri)!;
    if (entrypointUri.pathSegments.first != applicationPackage) {
      throw FormatException(
        'Entrypoint package ${entrypointUri.pathSegments.first} does not match '
        'application package $applicationPackage',
      );
    }
    decisions.sort(
      (left, right) => left.libraryUri.compareTo(right.libraryUri),
    );
    included.sort((left, right) {
      final leftUri = config.toPackageUri(left.input.absolute.uri).toString();
      final rightUri = config.toPackageUri(right.input.absolute.uri).toString();
      return leftUri.compareTo(rightUri);
    });
    return E0InstrumentationSelectionPlan(
      includedUnits: included,
      decisions: decisions,
    );
  }
}

final class E0PackageOverlayResult {
  E0PackageOverlayResult({
    required this.entrypoint,
    required this.packageConfig,
    required this.manifest,
    required Map<String, E0TransformResult> units,
  }) : units = Map.unmodifiable(units);

  final File entrypoint;
  final File packageConfig;
  final E0ReleaseManifest manifest;
  final Map<String, E0TransformResult> units;
}

/// Builds an explicit, source-only multi-package overlay. Every transformed
/// library must be named in [units]; SDK, Flutter, generated, part, and FFI
/// libraries are deliberately outside this experiment.
final class E0PackageOverlayBuilder {
  const E0PackageOverlayBuilder(this.transformer);

  final E0SourceTransformer transformer;

  E0PackageOverlayResult buildSelected({
    required List<E0PackageUnit> candidates,
    required E0InstrumentationSelectionPolicy selectionPolicy,
    required File packageConfig,
    required Directory outputDirectory,
    required String appId,
    required String releaseId,
    required String buildFingerprint,
  }) {
    final plan = selectionPolicy.plan(
      candidates: candidates,
      packageConfig: packageConfig,
    );
    return build(
      units: plan.includedUnits,
      packageConfig: packageConfig,
      outputDirectory: outputDirectory,
      appId: appId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
    );
  }

  E0PackageOverlayResult build({
    required List<E0PackageUnit> units,
    required File packageConfig,
    required Directory outputDirectory,
    required String appId,
    required String releaseId,
    required String buildFingerprint,
  }) {
    if (units.isEmpty || units.where((unit) => unit.isEntrypoint).length != 1) {
      throw const FormatException(
        'Package overlay requires exactly one entrypoint unit',
      );
    }
    if (FileSystemEntity.typeSync(
          outputDirectory.absolute.path,
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw const FormatException(
        'Package overlay output directory must be a new ephemeral directory',
      );
    }
    final config = PackageConfig.parseBytes(
      packageConfig.readAsBytesSync(),
      packageConfig.uri,
    );
    final resolved = <_ResolvedPackageUnit>[];
    final canonicalUris = <String>{};
    for (final unit in units) {
      final input = unit.input.absolute;
      final packageUri = config.toPackageUri(input.uri);
      if (packageUri == null) {
        throw FormatException(
          'Overlay input ${input.path} is outside the package configuration',
        );
      }
      final canonicalLibraryUri = packageUri.toString();
      E0Identity.validateCanonicalLibraryUri(canonicalLibraryUri);
      if (!canonicalUris.add(canonicalLibraryUri)) {
        throw FormatException('Duplicate overlay unit $canonicalLibraryUri');
      }
      final segments = packageUri.pathSegments;
      final packageName = segments.first;
      final relativeLibraryPath = segments.skip(1).join('/');
      final logicalLibraryPath = 'lib/$relativeLibraryPath';
      final package = config[packageName];
      if (package == null ||
          package.packageUriRoot.scheme != 'file' ||
          !_isWithinResolvedDirectory(package.packageUriRoot, input)) {
        throw FormatException(
          'Overlay input ${input.path} resolves outside its package URI root',
        );
      }
      final source = input.readAsStringSync();
      _rejectExcludedUnit(
        packageName: packageName,
        logicalLibraryPath: logicalLibraryPath,
        source: source,
      );
      resolved.add(
        _ResolvedPackageUnit(
          input: input,
          source: source,
          sourceHash: sha256.convert(input.readAsBytesSync()),
          packageName: packageName,
          logicalLibraryPath: logicalLibraryPath,
          canonicalLibraryUri: canonicalLibraryUri,
          isEntrypoint: unit.isEntrypoint,
        ),
      );
    }

    final discovered = <String, E0TransformResult>{};
    for (final unit in resolved) {
      discovered[unit.canonicalLibraryUri] = transformer.transform(
        source: unit.source,
        packageName: unit.packageName,
        logicalLibraryPath: unit.logicalLibraryPath,
        canonicalLibraryUri: unit.canonicalLibraryUri,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        requireMain: unit.isEntrypoint,
        installRuntime: false,
      );
    }
    final discoveredFunctions = discovered.values
        .expand((result) => result.manifest.functions)
        .toList();
    discoveredFunctions.sort((left, right) => left.id.compareTo(right.id));
    final identityMaterial = <String, String>{};
    for (final function in discoveredFunctions) {
      final prior = identityMaterial[function.id];
      final material = function.identity.encode();
      if (prior != null) {
        throw StateError(
          prior == material
              ? 'Duplicate stable identity across libraries: $material'
              : 'Stable ID collision across libraries: $prior / $material',
        );
      }
      identityMaterial[function.id] = material;
    }
    final releaseFunctions = <E0FunctionManifest>[
      for (var slot = 0; slot < discoveredFunctions.length; slot++)
        E0FunctionManifest(
          name: discoveredFunctions[slot].name,
          identity: discoveredFunctions[slot].identity,
          id: discoveredFunctions[slot].id,
          slot: slot,
          signature: discoveredFunctions[slot].signature,
          receiver: discoveredFunctions[slot].receiver,
        ),
    ];
    final slots = <String, int>{
      for (final function in releaseFunctions) function.id: function.slot,
    };
    final entryUnit = resolved.singleWhere((unit) => unit.isEntrypoint);
    final libraryUris =
        resolved.map((unit) => unit.canonicalLibraryUri).toList()..sort();
    final manifest = E0ReleaseManifest(
      appId: appId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      canonicalLibraryUri: entryUnit.canonicalLibraryUri,
      logicalLibraryPath: entryUnit.logicalLibraryPath,
      functions: releaseFunctions,
      libraryUris: libraryUris,
    );
    E0ReleaseManifest.decode(manifest.encode());

    outputDirectory.createSync(recursive: true);
    final transformed = <String, E0TransformResult>{};
    File? outputEntrypoint;
    for (final unit in resolved) {
      final localIds = discovered[unit.canonicalLibraryUri]!.manifest.functions
          .map((function) => function.id)
          .toSet();
      final localResult = transformer.transform(
        source: unit.source,
        packageName: unit.packageName,
        logicalLibraryPath: unit.logicalLibraryPath,
        canonicalLibraryUri: unit.canonicalLibraryUri,
        appId: appId,
        releaseId: releaseId,
        buildFingerprint: buildFingerprint,
        requireMain: unit.isEntrypoint,
        installRuntime: unit.isEntrypoint,
        assignedSlots: <String, int>{for (final id in localIds) id: slots[id]!},
        releaseFunctions: releaseFunctions,
      );
      final result = E0TransformResult(
        source: localResult.source,
        manifest: manifest,
        offsetMap: localResult.offsetMap,
        exclusions: localResult.exclusions,
      );
      transformed[unit.canonicalLibraryUri] = result;
      final relativePath = unit.logicalLibraryPath.substring(4);
      final output = File(
        '${outputDirectory.path}/packages/${unit.packageName}/lib/$relativePath',
      )..createSync(recursive: true);
      output.writeAsStringSync(result.source);
      if (unit.isEntrypoint) outputEntrypoint = output;
      final mapFile = File(
        '${outputDirectory.path}/source-maps/${unit.packageName}/$relativePath.json',
      )..createSync(recursive: true);
      mapFile.writeAsStringSync(result.offsetMap.encode());
    }
    final manifestFile = File('${outputDirectory.path}/manifest.json')
      ..writeAsStringSync(manifest.encode());
    final outputPackageConfig = File(
      '${outputDirectory.path}/package_config.json',
    );
    _writePackageConfig(
      outputPackageConfig,
      config,
      resolved.map((unit) => unit.packageName).toSet(),
      outputDirectory,
    );
    for (final unit in resolved) {
      if (sha256.convert(unit.input.readAsBytesSync()) != unit.sourceHash) {
        throw StateError('Transformer modified ${unit.input.path}');
      }
    }
    if (!manifestFile.existsSync()) {
      throw StateError('Package overlay manifest was not written');
    }
    return E0PackageOverlayResult(
      entrypoint: outputEntrypoint!,
      packageConfig: outputPackageConfig,
      manifest: manifest,
      units: transformed,
    );
  }

  static void _rejectExcludedUnit({
    required String packageName,
    required String logicalLibraryPath,
    required String source,
  }) {
    final reason = _excludedUnitReason(
      packageName: packageName,
      logicalLibraryPath: logicalLibraryPath,
      source: source,
    );
    if (reason != null) {
      throw FormatException(
        'SDK, Flutter, generated, part, and native units are excluded: '
        'package:$packageName/${logicalLibraryPath.substring(4)} '
        '(${reason.name})',
      );
    }
  }

  static E0InstrumentationSelectionReason? _excludedUnitReason({
    required String packageName,
    required String logicalLibraryPath,
    required String source,
  }) {
    final fileName = logicalLibraryPath.split('/').last;
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    final importedUris = parsed.unit.directives
        .whereType<NamespaceDirective>()
        .expand(
          (directive) => <String?>[
            directive.uri.stringValue,
            ...directive.configurations.map(
              (configuration) => configuration.uri.stringValue,
            ),
          ],
        )
        .whereType<String>();
    if (!logicalLibraryPath.endsWith('.dart')) {
      return E0InstrumentationSelectionReason.sdkHardExclude;
    }
    if (fileName.endsWith('.g.dart') ||
        fileName.endsWith('.freezed.dart') ||
        fileName.endsWith('.gen.dart')) {
      return E0InstrumentationSelectionReason.generatedDefaultExclude;
    }
    if (packageName == 'flutter' ||
        importedUris.any((uri) => uri.startsWith('package:flutter/'))) {
      return E0InstrumentationSelectionReason.flutterHardExclude;
    }
    if (importedUris.contains('dart:ffi') ||
        parsed.unit.directives.whereType<PartOfDirective>().isNotEmpty) {
      return E0InstrumentationSelectionReason.nativeBoundary;
    }
    return null;
  }

  static bool _isWithinResolvedDirectory(Uri directoryUri, File input) {
    try {
      final root = Directory.fromUri(directoryUri).resolveSymbolicLinksSync();
      final resolvedInput = input.resolveSymbolicLinksSync();
      final rootUri = Directory(root).uri;
      return File(resolvedInput).uri.toString().startsWith(rootUri.toString());
    } on FileSystemException {
      return false;
    }
  }

  static void _writePackageConfig(
    File output,
    PackageConfig baseConfig,
    Set<String> overlayPackages,
    Directory outputDirectory,
  ) {
    if (overlayPackages.contains('instrumentation_e0')) {
      throw const FormatException(
        'The instrumentation runtime package cannot be an overlay input',
      );
    }
    if (baseConfig['instrumentation_e0'] == null) {
      throw const FormatException(
        'Package configuration must include instrumentation_e0',
      );
    }
    final runtimeUri = Uri.parse('package:instrumentation_e0/e0_runtime.dart');
    final configuredRuntime = baseConfig.resolve(runtimeUri);
    final loadedRuntime = Isolate.resolvePackageUriSync(runtimeUri);
    if (configuredRuntime == null ||
        loadedRuntime == null ||
        configuredRuntime.scheme != 'file' ||
        loadedRuntime.scheme != 'file' ||
        !_sameResolvedFile(configuredRuntime, loadedRuntime)) {
      throw const FormatException(
        'Package configuration must preserve the loaded instrumentation runtime',
      );
    }
    final packageNames = overlayPackages.toList()..sort();
    final packages = <Package>[
      for (final package in baseConfig.packages)
        if (!overlayPackages.contains(package.name))
          Package(
            package.name,
            package.root,
            packageUriRoot: package.packageUriRoot,
            languageVersion: package.languageVersion,
            extraData: package.extraData,
            relativeRoot: false,
          ),
      for (final packageName in packageNames)
        Package(
          packageName,
          Directory('${outputDirectory.path}/packages/$packageName')
              .absolute
              .uri,
          packageUriRoot: Uri.parse('lib/'),
          languageVersion: baseConfig[packageName]?.languageVersion,
          relativeRoot: false,
        ),
    ];
    packages.sort((left, right) => left.name.compareTo(right.name));
    output.writeAsStringSync(
      jsonEncode(PackageConfig.toJson(PackageConfig(packages))),
    );
  }

  static bool _sameResolvedFile(Uri left, Uri right) {
    try {
      return File.fromUri(left).resolveSymbolicLinksSync() ==
          File.fromUri(right).resolveSymbolicLinksSync();
    } on FileSystemException {
      return false;
    }
  }
}

final class _ResolvedPackageUnit {
  const _ResolvedPackageUnit({
    required this.input,
    required this.source,
    required this.sourceHash,
    required this.packageName,
    required this.logicalLibraryPath,
    required this.canonicalLibraryUri,
    required this.isEntrypoint,
  });

  final File input;
  final String source;
  final Digest sourceHash;
  final String packageName;
  final String logicalLibraryPath;
  final String canonicalLibraryUri;
  final bool isEntrypoint;
}

final class _Candidate {
  const _Candidate({
    required this.name,
    required this.ownerClass,
    required this.body,
    required this.parameters,
    required this.returnType,
    required this.signature,
    required this.receiver,
    required this.identity,
    required this.id,
  });

  final String name;
  final String? ownerClass;
  final BlockFunctionBody body;
  final FormalParameterList parameters;
  final TypeAnnotation returnType;
  final E0FunctionSignature signature;
  final E0ReceiverDescriptor receiver;
  final E0DeclarationIdentity identity;
  final String id;
}

final class _ThisPropertyReadVisitor extends RecursiveAstVisitor<void> {
  _ThisPropertyReadVisitor(this.names);

  final Set<String> names;

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.target is ThisExpression) names.add(node.propertyName.name);
    super.visitPropertyAccess(node);
  }
}

final class _Edit {
  const _Edit(this.offset, this.kind, this.text);

  final int offset;
  final String kind;
  final String text;
}
