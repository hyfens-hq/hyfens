import 'dart:convert';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'canonical.dart';
import 'discovery.dart';

/// Computes bounded semantic fingerprints for declaration-sized regions.
///
/// Release metadata stores these digests rather than source snapshots. A
/// changed source unit can therefore distinguish a supported function edit
/// from an unrelated edit to an unsupported declaration without retaining the
/// application's source code.
final class SourceDeclarationFingerprints {
  const SourceDeclarationFingerprints._();

  static const maxSourceLength = 16 * 1024 * 1024;

  static Map<String, String> collect(
    String source, {
    String path = 'source.dart',
  }) {
    if (source.length > maxSourceLength) {
      throw const FormatException(
        'Source file exceeds the declaration fingerprint limit',
      );
    }
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      throw FormatException('Source does not parse: ${parsed.errors.first}');
    }

    final result = <String, String>{};
    for (final directive in parsed.unit.directives) {
      final key = 'directive|${directive.runtimeType}|${directive.offset}';
      result[key] = _fingerprint(source, directive);
    }
    for (final declaration in parsed.unit.declarations) {
      _collectTopLevel(result, source, declaration);
    }
    final entries = result.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, String>{
      for (final entry in entries) entry.key: entry.value,
    };
  }

  static void _collectTopLevel(
    Map<String, String> result,
    String source,
    CompilationUnitMember declaration,
  ) {
    if (declaration is FunctionDeclaration) {
      result['function|${declaration.name.lexeme}'] = _fingerprint(
        source,
        declaration,
      );
      return;
    }
    if (declaration is ClassDeclaration) {
      _collectClassLike(
        result,
        source,
        declaration.name.lexeme,
        declaration,
        declaration.members,
        declaration.leftBracket.offset,
      );
      return;
    }
    if (declaration is MixinDeclaration) {
      _collectClassLike(
        result,
        source,
        declaration.name.lexeme,
        declaration,
        declaration.members,
        declaration.leftBracket.offset,
      );
      return;
    }
    if (declaration is EnumDeclaration) {
      _collectClassLike(
        result,
        source,
        declaration.name.lexeme,
        declaration,
        declaration.members,
        declaration.leftBracket.offset,
      );
      return;
    }
    if (declaration is ExtensionDeclaration) {
      final name = declaration.name?.lexeme ?? '<unnamed>';
      _collectClassLike(
        result,
        source,
        name,
        declaration,
        declaration.members,
        declaration.leftBracket.offset,
      );
      return;
    }
    result['topLevel|${declaration.runtimeType}|${declaration.offset}'] =
        _fingerprint(source, declaration);
  }

  static void _collectClassLike(
    Map<String, String> result,
    String source,
    String owner,
    CompilationUnitMember declaration,
    Iterable<ClassMember> members,
    int leftBracketOffset,
  ) {
    result['classHeader|${declaration.runtimeType}|$owner'] = sha256Hex(
      utf8.encode(
        stripDartCommentsAndWhitespace(
          source.substring(declaration.offset, leftBracketOffset),
        ),
      ),
    );
    var fieldIndex = 0;
    var constructorIndex = 0;
    for (final member in members) {
      if (member is MethodDeclaration) {
        final kind = member.isGetter
            ? 'getter'
            : member.isSetter
            ? 'setter'
            : member.isOperator
            ? 'operator'
            : member.isStatic
            ? 'staticMethod'
            : 'instanceMethod';
        result['method|$owner|$kind|${member.name.lexeme}'] = _fingerprint(
          source,
          member,
        );
      } else if (member is ConstructorDeclaration) {
        final name = member.name?.lexeme ?? '<unnamed>';
        result['constructor|$owner|$name|$constructorIndex'] = _fingerprint(
          source,
          member,
        );
        constructorIndex++;
      } else if (member is FieldDeclaration) {
        final names =
            member.fields.variables.map((item) => item.name.lexeme).toList()
              ..sort();
        result['field|$owner|${names.join(',')}|$fieldIndex'] = _fingerprint(
          source,
          member,
        );
        fieldIndex++;
      } else {
        result['member|$owner|${member.runtimeType}|$fieldIndex'] =
            _fingerprint(source, member);
        fieldIndex++;
      }
    }
  }

  static String _fingerprint(String source, AstNode node) => sha256Hex(
    utf8.encode(
      stripDartCommentsAndWhitespace(source.substring(node.offset, node.end)),
    ),
  );
}
