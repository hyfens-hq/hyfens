import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../e0_runtime.dart';
import 'identity.dart';
import 'manifest.dart';

final class E0PatchCompiler {
  Uint8List compile({
    required String source,
    required E0ReleaseManifest manifest,
    required String functionName,
    String? className,
    String? canonicalLibraryUri,
    int patchSequence = 1,
    bool allowSyntheticWidgetTypes = false,
  }) {
    if (patchSequence <= 0) {
      throw const FormatException('Patch sequence must be positive');
    }
    if (canonicalLibraryUri != null) {
      E0Identity.validateCanonicalLibraryUri(canonicalLibraryUri);
    }
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty) {
      throw FormatException(
        'Patch source does not parse: ${parsed.errors.first}',
      );
    }
    late final E0FunctionSignature signature;
    late final FormalParameterList parameterList;
    late final FunctionBody body;
    if (className == null) {
      final declarations = parsed.unit.declarations
          .whereType<FunctionDeclaration>()
          .where((item) => item.name.lexeme == functionName)
          .toList();
      if (declarations.length != 1) {
        throw FormatException('Expected one $functionName declaration');
      }
      final declaration = declarations.single;
      signature = e0SignatureForDeclaration(declaration);
      parameterList = declaration.functionExpression.parameters!;
      body = declaration.functionExpression.body;
    } else {
      final classes = parsed.unit.declarations
          .whereType<ClassDeclaration>()
          .where((item) => item.name.lexeme == className)
          .toList();
      if (classes.length != 1) {
        throw FormatException('Expected one $className class declaration');
      }
      final methods = classes.single.members
          .whereType<MethodDeclaration>()
          .where((item) => item.name.lexeme == functionName)
          .toList();
      if (methods.length != 1) {
        throw FormatException(
          'Expected one $className.$functionName method declaration',
        );
      }
      final method = methods.single;
      final isWidgetBuild = e0IsWidgetBuildMethod(method);
      final unsupported = e0UnsupportedMethodReason(
        method,
        allowWidgetBuild: isWidgetBuild,
      );
      if (unsupported != null) {
        throw FormatException(
          'Unsupported patch method $className.$functionName: $unsupported',
        );
      }
      signature = e0SignatureForMethodDeclaration(
        method,
        allowWidgetBuild: isWidgetBuild,
      );
      parameterList = method.parameters!;
      body = method.body;
    }
    final matchingFunctions = manifest.functions
        .where(
          (item) =>
              item.name == functionName &&
              item.receiver.ownerClass == className &&
              (canonicalLibraryUri == null ||
                  item.identity.libraryUri == canonicalLibraryUri),
        )
        .toList();
    if (matchingFunctions.length != 1) {
      throw FormatException(
        '${className == null ? functionName : '$className.$functionName'} '
        'is not uniquely patchable',
      );
    }
    final function = matchingFunctions.single;
    if (signature != function.signature) {
      throw FormatException(
        'Patch signature $signature does not match release '
        '${function.signature}',
      );
    }
    if (body is! BlockFunctionBody ||
        body.isGenerator ||
        body.isAsynchronous != signature.isAsync) {
      throw const FormatException(
        'Patch body async marker must match its explicit return type',
      );
    }
    final arguments = <String, (int, E0ValueSchema)>{};
    final parameters = parameterList.parameters;
    final isWidgetBuild = signature == e0WidgetBuildSignature;
    if (isWidgetBuild && !allowSyntheticWidgetTypes) {
      _validateFlutterWidgetPatchLibrary(
        parsed.unit,
        manifest.widgetFactories.map((factory) => factory.sourceName).toSet(),
      );
    }
    if (isWidgetBuild && function.name != 'build') {
      throw const FormatException('Widget ABI is reserved for build methods');
    }
    for (var index = 0; index < parameters.length; index++) {
      if (isWidgetBuild) break;
      arguments[parameters[index].name!.lexeme] = (
        index,
        signature.parameters[index],
      );
    }
    final receiverMembers = <String, (int, E0ValueSchema)>{
      for (final member in function.receiver.members)
        member.name: (member.slot, member.schema),
    };
    final emitter = _Emitter(
      arguments,
      signature.returnSchema,
      receiverMembers,
      receiver: function.receiver,
      isInstanceMethod: function.receiver.isInstance,
      isAsync: signature.isAsync,
      declaredCapabilities: manifest.capabilities,
      declaredWidgetFactories: manifest.widgetFactories,
      isWidgetBuild: isWidgetBuild,
    );
    if (!_blockDefinitelyReturns(body.block)) {
      throw const FormatException(
        'Patch body must return a value on every reachable path',
      );
    }
    for (final statement in body.block.statements) {
      emitter.statement(statement);
    }
    final program = E0PatchProgram(
      functionId: function.id,
      slot: function.slot,
      signature: signature,
      receiver: function.receiver,
      constants: emitter.constants,
      code: emitter.code,
      locals: emitter.locals,
      handlers: emitter.handlers,
      capabilities: emitter.capabilities,
      asyncPoints: emitter.asyncPoints,
      widgetFactories: emitter.widgetFactories,
      closures: emitter.closures,
      patchSequence: patchSequence,
    );
    E0Interpreter.validate(program);
    return E0PatchContainer.encode(
      appId: manifest.appId,
      releaseId: manifest.releaseId,
      buildFingerprint: manifest.buildFingerprint,
      program: program,
    );
  }
}

void _validateFlutterWidgetPatchLibrary(
  CompilationUnit unit,
  Set<String> factoryNames,
) {
  final flutterImports = unit.directives.whereType<ImportDirective>().where(
    (directive) =>
        directive.uri.stringValue?.startsWith('package:flutter/') ?? false,
  );
  if (flutterImports.length != 1 ||
      flutterImports.single.prefix != null ||
      flutterImports.single.combinators.isNotEmpty) {
    throw const FormatException(
      'Widget patches require one unprefixed, unfiltered package:flutter import',
    );
  }
  final forbidden = <String>{
    'Widget',
    'BuildContext',
    'StatelessWidget',
    ...factoryNames,
  };
  for (final declaration in unit.declarations) {
    final String? name = switch (declaration) {
      ClassDeclaration item => item.name.lexeme,
      EnumDeclaration item => item.name.lexeme,
      MixinDeclaration item => item.name.lexeme,
      FunctionDeclaration item => item.name.lexeme,
      GenericTypeAlias item => item.name.lexeme,
      _ => null,
    };
    if (name != null && forbidden.contains(name)) {
      throw FormatException(
        'Widget patch declaration $name shadows the bounded Flutter ABI',
      );
    }
  }
}

bool e0IsWidgetBuildMethod(MethodDeclaration declaration) {
  final parameters = declaration.parameters?.parameters;
  return declaration.name.lexeme == 'build' &&
      declaration.returnType?.toSource() == 'Widget' &&
      parameters?.length == 1 &&
      parameters!.single is SimpleFormalParameter &&
      (parameters.single as SimpleFormalParameter).type?.toSource() ==
          'BuildContext';
}

E0FunctionSignature e0SignatureForMethodDeclaration(
  MethodDeclaration declaration, {
  bool allowWidgetBuild = false,
}) {
  if (allowWidgetBuild && e0IsWidgetBuildMethod(declaration)) {
    return e0WidgetBuildSignature;
  }
  return _signatureFor(
    returnType: declaration.returnType,
    typeParameters: declaration.typeParameters,
    parameters: declaration.parameters,
  );
}

String? e0UnsupportedMethodReason(
  MethodDeclaration declaration, {
  bool allowWidgetBuild = false,
}) {
  if (declaration.isStatic) return 'static method target';
  if (declaration.isGetter || declaration.isSetter) return 'accessor target';
  if (declaration.isOperator) return 'operator target';
  if (declaration.body is EmptyFunctionBody) return 'abstract method target';
  if (declaration.body is! BlockFunctionBody) return 'non-block body';
  final body = declaration.body as BlockFunctionBody;
  if (body.isGenerator) {
    return 'generator body';
  }
  try {
    final signature = e0SignatureForMethodDeclaration(
      declaration,
      allowWidgetBuild: allowWidgetBuild,
    );
    if (body.isAsynchronous != signature.isAsync) {
      return 'async body must declare Future<T>, and Future<T> patches must use async';
    }
  } on FormatException catch (error) {
    return error.message.toString();
  }
  return null;
}

E0FunctionSignature e0SignatureForDeclaration(FunctionDeclaration declaration) {
  if (declaration.isGetter || declaration.isSetter) {
    throw const FormatException('Unsupported patch declaration: accessor');
  }
  return _signatureFor(
    returnType: declaration.returnType,
    typeParameters: declaration.functionExpression.typeParameters,
    parameters: declaration.functionExpression.parameters,
  );
}

E0FunctionSignature _signatureFor({
  required TypeAnnotation? returnType,
  required TypeParameterList? typeParameters,
  required FormalParameterList? parameters,
}) {
  if (returnType == null) {
    throw const FormatException('Patch return type must be explicit');
  }
  if (typeParameters != null) {
    throw const FormatException('Generic patch functions are unsupported');
  }
  final formalParameters = parameters?.parameters;
  if (formalParameters == null || formalParameters.length > 16) {
    throw const FormatException('Invalid patch parameter list');
  }
  final schemas = <E0ValueSchema>[];
  final details = <E0ParameterDescriptor>[];
  for (final parameter in formalParameters) {
    final normal = parameter is DefaultFormalParameter
        ? parameter.parameter
        : parameter;
    if (normal is! SimpleFormalParameter || normal.type == null) {
      throw const FormatException(
        'Patch parameters must be explicitly typed simple parameters',
      );
    }
    final schema = e0HostSchemaForType(normal.type!.toSource(), 'parameter');
    schemas.add(schema);
    final kind = switch (parameter) {
      _ when parameter.isRequiredPositional =>
        E0ParameterKind.requiredPositional,
      _ when parameter.isOptionalPositional =>
        E0ParameterKind.optionalPositional,
      _ when parameter.isRequiredNamed => E0ParameterKind.requiredNamed,
      _ when parameter.isOptionalNamed => E0ParameterKind.optionalNamed,
      _ => throw const FormatException('Unsupported parameter kind'),
    };
    final defaultExpression = parameter is DefaultFormalParameter
        ? parameter.defaultValue
        : null;
    final hasDefault = defaultExpression != null;
    final defaultValue = hasDefault
        ? _parseParameterDefault(defaultExpression)
        : null;
    final name = parameter.name?.lexeme;
    if (name == null || name.isEmpty) {
      throw const FormatException('Patch parameters must be named');
    }
    details.add(
      E0ParameterDescriptor(
        name: name,
        schema: schema,
        kind: kind,
        hasDefault: hasDefault,
        defaultValue: defaultValue,
      ),
    );
  }
  final returnSource = returnType.toSource();
  final asyncElement = _futureElementSource(returnSource);
  final returnSchema = e0HostSchemaForType(
    asyncElement ?? returnSource,
    asyncElement == null ? 'return' : 'Future element return',
  );
  final signature = E0FunctionSignature(
    parameters: List.unmodifiable(schemas),
    returnSchema: returnSchema,
    isAsync: asyncElement != null,
    parameterDetails:
        details.any(
          (item) =>
              item.kind != E0ParameterKind.requiredPositional ||
              item.hasDefault,
        )
        ? List.unmodifiable(details)
        : const <E0ParameterDescriptor>[],
  );
  signature.validate();
  return signature;
}

Object? _parseParameterDefault(Expression expression) {
  if (expression is IntegerLiteral) return expression.value;
  if (expression is DoubleLiteral) return expression.value;
  if (expression is BooleanLiteral) return expression.value;
  if (expression is NullLiteral) return null;
  if (expression is SimpleStringLiteral) return expression.value;
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    final operand = expression.operand;
    if (operand is IntegerLiteral && operand.value != null) {
      return -operand.value!;
    }
    if (operand is DoubleLiteral) return -operand.value;
  }
  throw FormatException(
    'Unsupported parameter default ${expression.toSource()}; use a bounded literal',
  );
}

String? _futureElementSource(String source) {
  final compact = source.replaceAll(RegExp(r'\s+'), '');
  if (!compact.startsWith('Future<') || !compact.endsWith('>')) return null;
  final element = compact.substring(7, compact.length - 1);
  if (element.isEmpty) {
    throw FormatException(
      'Unsupported async return type $source: use Future<T> with a bounded E0 value schema',
    );
  }
  return element;
}

E0ValueSchema e0HostSchemaForType(String source, String position) {
  E0ValueSchema schema;
  try {
    schema = E0ValueSchema.parseDartType(source);
  } on FormatException catch (error) {
    throw FormatException('Unsupported $position type $source: $error');
  }
  if (!schema.isSupportedHostSignature) {
    throw FormatException(
      'Unsupported $position type $source: use an explicit supported schema',
    );
  }
  return schema;
}

bool _blockDefinitelyReturns(Block block) =>
    block.statements.any(_statementDefinitelyReturns);

bool _statementDefinitelyReturns(Statement statement) {
  if (statement is ReturnStatement) return true;
  if (statement is ExpressionStatement &&
      (statement.expression is ThrowExpression ||
          statement.expression is RethrowExpression)) {
    return true;
  }
  if (statement is Block) return _blockDefinitelyReturns(statement);
  if (statement is IfStatement) {
    final otherwise = statement.elseStatement;
    return otherwise != null &&
        _statementDefinitelyReturns(statement.thenStatement) &&
        _statementDefinitelyReturns(otherwise);
  }
  if (statement is SwitchStatement) {
    return statement.members.any((member) => member is SwitchDefault) &&
        statement.members.every(
          (member) => member.statements.any(_statementDefinitelyReturns),
        );
  }
  if (statement is TryStatement) {
    final finallyBlock = statement.finallyBlock;
    if (finallyBlock != null && _blockDefinitelyReturns(finallyBlock)) {
      return true;
    }
    if (!_blockDefinitelyReturns(statement.body)) return false;
    return statement.catchClauses.every(
      (clause) => _blockDefinitelyReturns(clause.body),
    );
  }
  return false;
}

bool _statementTerminatesSwitchMember(Statement statement) {
  if (statement is ReturnStatement || statement is BreakStatement) return true;
  if (statement is ExpressionStatement &&
      (statement.expression is ThrowExpression ||
          statement.expression is RethrowExpression)) {
    return true;
  }
  if (statement is Block) {
    return statement.statements.isNotEmpty &&
        _statementTerminatesSwitchMember(statement.statements.last);
  }
  if (statement is IfStatement) {
    final otherwise = statement.elseStatement;
    return otherwise != null &&
        _statementTerminatesSwitchMember(statement.thenStatement) &&
        _statementTerminatesSwitchMember(otherwise);
  }
  return false;
}

final class _ClosureReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> references = <String>{};
  final Set<String> declared = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    references.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    declared.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    declared.add(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }
}

final class _Local {
  _Local(this.slot, this.schema, {required this.isMutable})
    : isReceiverOrigin = false;

  final int slot;
  final E0ValueSchema schema;
  final bool isMutable;
  bool isReceiverOrigin;
}

final class _Emitter {
  _Emitter(
    this.arguments,
    this.returnSchema,
    this.receiverMembers, {
    this.receiver = E0ReceiverDescriptor.none,
    required this.isInstanceMethod,
    required this.isAsync,
    required List<E0AsyncCapabilityDescriptor> declaredCapabilities,
    required List<E0WidgetFactoryDescriptor> declaredWidgetFactories,
    required this.isWidgetBuild,
  }) : _declaredCapabilities = List.unmodifiable(declaredCapabilities),
       _declaredWidgetFactories = List.unmodifiable(declaredWidgetFactories);

  final Map<String, (int, E0ValueSchema)> arguments;
  final E0ValueSchema returnSchema;
  final Map<String, (int, E0ValueSchema)> receiverMembers;
  final E0ReceiverDescriptor receiver;
  final bool isInstanceMethod;
  final bool isAsync;
  final bool isWidgetBuild;
  final List<E0AsyncCapabilityDescriptor> _declaredCapabilities;
  final List<E0WidgetFactoryDescriptor> _declaredWidgetFactories;
  final List<E0Value> constants = <E0Value>[];
  final List<int> code = <int>[];
  final List<E0ValueSchema> locals = <E0ValueSchema>[];
  final List<E0ExceptionHandler> handlers = <E0ExceptionHandler>[];
  final List<E0AsyncCapabilityDescriptor> capabilities =
      <E0AsyncCapabilityDescriptor>[];
  final List<E0AsyncPoint> asyncPoints = <E0AsyncPoint>[];
  final List<E0WidgetFactoryDescriptor> widgetFactories =
      <E0WidgetFactoryDescriptor>[];
  final List<E0ClosureProgram> closures = <E0ClosureProgram>[];
  final List<Map<String, _Local>> _scopes = <Map<String, _Local>>[{}];
  final List<List<int>> _breakTargets = <List<int>>[];
  final List<Set<String>> _unsupportedCatchBindings = <Set<String>>[];
  int _nextHandlerId = 0;
  int _handlerDepth = 0;

  void statement(Statement statement) {
    if (statement is ExpressionStatement &&
        statement.expression is AssignmentExpression) {
      final assignment = statement.expression as AssignmentExpression;
      final target = assignment.leftHandSide;
      if (target is PropertyAccess && target.target is ThisExpression) {
        _rejectReceiverWrite();
      }
    }
    if (statement is ReturnStatement) {
      final expression = statement.expression;
      if (expression == null) {
        throw const FormatException('Missing return value');
      }
      if (expression is ThrowExpression) {
        _emitThrow(expression.expression);
        return;
      }
      final actual = emitExpression(expression, context: returnSchema);
      if (!returnSchema.accepts(actual)) {
        throw FormatException(
          'Return expression type $actual does not match $returnSchema',
        );
      }
      code.add(E0Opcode.returnValue.code);
      return;
    }
    if (statement is TryStatement) {
      _emitTry(statement);
      return;
    }
    if (statement is Block) {
      _withScope(() {
        for (final nested in statement.statements) {
          this.statement(nested);
        }
      });
      return;
    }
    if (statement is VariableDeclarationStatement) {
      _emitVariables(statement.variables);
      return;
    }
    if (statement is ExpressionStatement) {
      _emitExpressionStatement(statement.expression);
      return;
    }
    if (statement is IfStatement) {
      final condition = emitExpression(statement.expression);
      if (condition != E0ValueSchema.boolean) {
        throw const FormatException('If condition must be bool');
      }
      code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
      final targetIndex = code.length - 1;
      this.statement(statement.thenStatement);
      final otherwise = statement.elseStatement;
      if (otherwise == null) {
        code[targetIndex] = code.length;
        return;
      }
      if (_statementDefinitelyReturns(statement.thenStatement)) {
        code[targetIndex] = code.length;
        this.statement(otherwise);
        return;
      }
      code.addAll(<int>[E0Opcode.jump.code, 0]);
      final endTarget = code.length - 1;
      code[targetIndex] = code.length;
      this.statement(otherwise);
      code[endTarget] = code.length;
      return;
    }
    if (statement is WhileStatement) {
      final conditionTarget = code.length;
      final condition = emitExpression(statement.condition);
      if (condition != E0ValueSchema.boolean) {
        throw const FormatException('While condition must be bool');
      }
      code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
      final endTarget = code.length - 1;
      final breaks = <int>[];
      _breakTargets.add(breaks);
      this.statement(statement.body);
      _breakTargets.removeLast();
      code.addAll(<int>[E0Opcode.jump.code, conditionTarget]);
      code[endTarget] = code.length;
      _patchTargets(breaks, code.length);
      return;
    }
    if (statement is ForStatement) {
      _emitFor(statement);
      return;
    }
    if (statement is SwitchStatement) {
      _emitSwitch(statement);
      return;
    }
    if (statement is BreakStatement) {
      if (_handlerDepth > 0) {
        throw const FormatException(
          'break crossing a try/catch/finally boundary is unsupported in v6',
        );
      }
      if (_breakTargets.isEmpty) {
        throw const FormatException('break is only supported in a loop/switch');
      }
      code.addAll(<int>[E0Opcode.jump.code, 0]);
      _breakTargets.last.add(code.length - 1);
      return;
    }
    throw FormatException(
      'Unsupported statement ${statement.runtimeType}; '
      'v6 supports typed locals, structured control flow, bounded exceptions, and typed async capabilities',
    );
  }

  void _emitTry(TryStatement statement) {
    if (statement.catchClauses.length > 1) {
      throw const FormatException(
        'v6 supports at most one catch-all clause per try statement',
      );
    }
    final catchClause = statement.catchClauses.firstOrNull;
    if (catchClause != null && catchClause.exceptionType != null) {
      throw const FormatException(
        'Typed and user-defined catch clauses are unsupported in v6; use catch-all catch',
      );
    }
    if (catchClause?.stackTraceParameter != null) {
      throw const FormatException(
        'Catch stack-trace bindings are unsupported; E0 exposes only a bounded synthetic trace at the AOT boundary',
      );
    }
    if (catchClause == null && statement.finallyBlock == null) {
      throw const FormatException('try requires catch or finally');
    }
    final id = _nextHandlerId++;
    code.addAll(<int>[E0Opcode.enterTry.code, id]);
    final tryStart = code.length;
    _handlerDepth++;
    try {
      for (final nested in statement.body.statements) {
        this.statement(nested);
      }
    } finally {
      _handlerDepth--;
    }
    final tryEnd = code.length;
    code.addAll(<int>[E0Opcode.completeTry.code, id]);

    int? catchStart;
    int? catchEnd;
    if (catchClause != null) {
      catchStart = code.length;
      final binding = catchClause.exceptionParameter?.name.lexeme;
      _unsupportedCatchBindings.add(
        binding == null ? const <String>{} : <String>{binding},
      );
      _handlerDepth++;
      try {
        _withScope(() {
          for (final nested in catchClause.body.statements) {
            this.statement(nested);
          }
        });
      } finally {
        _handlerDepth--;
        _unsupportedCatchBindings.removeLast();
      }
      catchEnd = code.length;
      code.addAll(<int>[E0Opcode.completeCatch.code, id]);
    }

    int? finallyStart;
    int? finallyEnd;
    final finallyBlock = statement.finallyBlock;
    if (finallyBlock != null) {
      finallyStart = code.length;
      _handlerDepth++;
      try {
        _withScope(() {
          for (final nested in finallyBlock.statements) {
            this.statement(nested);
          }
        });
      } finally {
        _handlerDepth--;
      }
      finallyEnd = code.length;
      code.addAll(<int>[E0Opcode.completeFinally.code, id]);
    }
    final afterPc = code.length;
    handlers.add(
      E0ExceptionHandler(
        id: id,
        tryStart: tryStart,
        tryEnd: tryEnd,
        catchStart: catchStart,
        catchEnd: catchEnd,
        finallyStart: finallyStart,
        finallyEnd: finallyEnd,
        afterPc: afterPc,
      ),
    );
    handlers.sort((left, right) => left.id.compareTo(right.id));
  }

  void _emitVariables(VariableDeclarationList declarations) {
    final type = declarations.type;
    for (final declaration in declarations.variables) {
      final initializer = declaration.initializer;
      final schema = type == null
          ? initializer == null
                ? (throw const FormatException(
                    'Inferred locals require an initializer',
                  ))
                : null
          : _localSchema(type.toSource());
      if (schema == null) {
        final inferred = emitExpression(initializer!);
        if (!inferred.isSupportedHostSignature) {
          throw FormatException(
            'Inferred local ${declaration.name.lexeme} has unsupported type $inferred',
          );
        }
        final local = _declare(
          declaration.name.lexeme,
          inferred,
          isMutable: !declarations.isFinal && !declarations.isConst,
        );
        local.isReceiverOrigin = _isReceiverOrigin(initializer);
        code.addAll(<int>[E0Opcode.storeLocal.code, local.slot]);
        continue;
      }
      final local = _declare(
        declaration.name.lexeme,
        schema,
        isMutable: !declarations.isFinal && !declarations.isConst,
      );
      if (initializer != null) {
        local.isReceiverOrigin = _isReceiverOrigin(initializer);
        final actual = emitExpression(initializer, context: schema);
        if (!schema.accepts(actual)) {
          throw FormatException(
            'Initializer type $actual does not match local $schema',
          );
        }
        code.addAll(<int>[E0Opcode.storeLocal.code, local.slot]);
      }
    }
  }

  void _emitExpressionStatement(Expression expression) {
    if (expression is ThrowExpression) {
      _emitThrow(expression.expression);
      return;
    }
    if (expression is RethrowExpression) {
      if (_unsupportedCatchBindings.isEmpty) {
        throw const FormatException('rethrow is only valid inside catch');
      }
      code.add(E0Opcode.rethrowValue.code);
      return;
    }
    if (expression is AssignmentExpression) {
      _emitAssignment(expression);
      return;
    }
    if (expression is PrefixExpression || expression is PostfixExpression) {
      final operand = expression is PrefixExpression
          ? expression.operand
          : (expression as PostfixExpression).operand;
      final operator = expression is PrefixExpression
          ? expression.operator.lexeme
          : (expression as PostfixExpression).operator.lexeme;
      if (operand is SimpleIdentifier &&
          (operator == '++' || operator == '--')) {
        final local = _lookupLocal(operand.name);
        if (!local.isMutable) {
          throw FormatException('Cannot modify final local ${operand.name}');
        }
        if (local.schema != E0ValueSchema.integer) {
          throw const FormatException('Increment requires an int local');
        }
        _loadLocal(local);
        _emitConstant(1, E0ValueSchema.integer);
        code.add(
          operator == '++' ? E0Opcode.addInt.code : E0Opcode.subtractInt.code,
        );
        code.addAll(<int>[E0Opcode.storeLocal.code, local.slot]);
        return;
      }
    }
    if (expression is MethodInvocation) {
      final name = expression.methodName.name;
      if (_higherOrderNames.contains(name)) _rejectClosureApi(name);
      if (name == 'add' && expression.target != null) {
        if (_isReceiverOrigin(expression.target!)) _rejectReceiverWrite();
        final target = emitExpression(expression.target!);
        if (target.kind != E0ValueKind.list && target.kind != E0ValueKind.set) {
          throw FormatException('add is unsupported for $target');
        }
        if (expression.argumentList.arguments.length != 1) {
          throw const FormatException('add requires one argument');
        }
        final value = emitExpression(
          expression.argumentList.arguments.single,
          context: target.elementSchema,
        );
        if (!target.elementSchema!.accepts(value)) {
          throw FormatException('add value $value does not match $target');
        }
        code.add(E0Opcode.collectionAdd.code);
        return;
      }
    }
    emitExpression(expression);
    code.add(E0Opcode.pop.code);
  }

  void _emitThrow(Expression expression) {
    final schema = emitExpression(expression);
    if (schema.nullable || schema.kind == E0ValueKind.nullValue) {
      throw const FormatException(
        'Guest throw operands must be statically non-null bounded E0 values',
      );
    }
    code.add(E0Opcode.throwValue.code);
  }

  void _emitAssignment(AssignmentExpression expression) {
    if (_isReceiverProperty(expression.leftHandSide)) _rejectReceiverWrite();
    final operator = expression.operator.lexeme;
    final target = expression.leftHandSide;
    if (_isReceiverOrigin(target)) _rejectReceiverWrite();
    if (target is SimpleIdentifier) {
      if (_findLocal(target.name) == null &&
          arguments.containsKey(target.name)) {
        throw FormatException(
          'Reassignment of function parameter ${target.name} is unsupported; '
          'copy it to an explicitly typed local first',
        );
      }
      final local = _lookupLocal(target.name);
      if (!local.isMutable) {
        throw FormatException('Cannot assign final local ${target.name}');
      }
      if (operator == '=') {
        local.isReceiverOrigin =
            local.isReceiverOrigin ||
            _isReceiverOrigin(expression.rightHandSide);
        final actual = emitExpression(
          expression.rightHandSide,
          context: local.schema,
        );
        if (!local.schema.accepts(actual)) {
          throw FormatException(
            'Assignment $actual does not match ${local.schema}',
          );
        }
      } else if (operator == '+=' || operator == '-=' || operator == '*=') {
        _loadLocal(local);
        final right = emitExpression(expression.rightHandSide);
        if (right != local.schema) {
          throw FormatException('Compound assignment requires ${local.schema}');
        }
        code.add(switch (operator) {
          '+=' => E0Opcode.addInt.code,
          '-=' => E0Opcode.subtractInt.code,
          _ => E0Opcode.multiplyInt.code,
        });
      } else {
        throw FormatException('Unsupported assignment operator $operator');
      }
      code.addAll(<int>[E0Opcode.storeLocal.code, local.slot]);
      return;
    }
    if (target is IndexExpression && operator == '=') {
      final collection = emitExpression(target.realTarget);
      final index = emitExpression(target.index);
      final expected = switch (collection.kind) {
        E0ValueKind.list when index == E0ValueSchema.integer =>
          collection.elementSchema!,
        E0ValueKind.map when index == E0ValueSchema.string =>
          collection.mapValueSchema!,
        _ => throw FormatException(
          'Unsupported indexed assignment on $collection',
        ),
      };
      final actual = emitExpression(
        expression.rightHandSide,
        context: expected,
      );
      if (!expected.accepts(actual)) {
        throw FormatException(
          'Indexed assignment $actual does not match $expected',
        );
      }
      code.add(E0Opcode.indexSet.code);
      return;
    }
    throw FormatException(
      'Unsupported assignment target ${target.runtimeType}',
    );
  }

  void _emitFor(ForStatement statement) {
    if (statement.awaitKeyword != null) {
      throw const FormatException('await for is unsupported in v6');
    }
    _withScope(() {
      final parts = statement.forLoopParts;
      if (parts is ForPartsWithDeclarations) {
        _emitVariables(parts.variables);
        final conditionTarget = code.length;
        final condition = parts.condition;
        if (condition != null) {
          if (emitExpression(condition) != E0ValueSchema.boolean) {
            throw const FormatException('For condition must be bool');
          }
        } else {
          _emitConstant(true, E0ValueSchema.boolean);
        }
        code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
        final endTarget = code.length - 1;
        final breaks = <int>[];
        _breakTargets.add(breaks);
        this.statement(statement.body);
        _breakTargets.removeLast();
        for (final updater in parts.updaters) {
          _emitExpressionStatement(updater);
        }
        code.addAll(<int>[E0Opcode.jump.code, conditionTarget]);
        code[endTarget] = code.length;
        _patchTargets(breaks, code.length);
        return;
      }
      if (parts is ForEachPartsWithDeclaration) {
        _emitForEach(parts, statement.body);
        return;
      }
      throw const FormatException(
        'Only declaration-based C-style for and typed for-in are supported',
      );
    });
  }

  void _emitForEach(ForEachPartsWithDeclaration parts, Statement body) {
    final declared = parts.loopVariable;
    if (declared.type == null) {
      throw const FormatException('for-in variables require an explicit type');
    }
    final iterableSchema = emitExpression(parts.iterable);
    if (iterableSchema.kind != E0ValueKind.list &&
        iterableSchema.kind != E0ValueKind.set) {
      throw const FormatException(
        'for-in supports List, Set, and Map.keys only',
      );
    }
    final source = _declareHidden(iterableSchema);
    code.addAll(<int>[E0Opcode.storeLocal.code, source.slot]);
    final index = _declareHidden(E0ValueSchema.integer);
    _emitConstant(0, E0ValueSchema.integer);
    code.addAll(<int>[E0Opcode.storeLocal.code, index.slot]);
    final loopSchema = _localSchema(declared.type!.toSource());
    if (!loopSchema.accepts(iterableSchema.elementSchema!)) {
      throw FormatException(
        'for-in element ${iterableSchema.elementSchema} does not match $loopSchema',
      );
    }
    final loop = _declare(
      declared.name.lexeme,
      loopSchema,
      isMutable: !declared.isFinal && !declared.isConst,
    );
    final conditionTarget = code.length;
    _loadLocal(index);
    _loadLocal(source);
    code.add(E0Opcode.collectionLength.code);
    code.add(E0Opcode.lessThanInt.code);
    code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
    final endTarget = code.length - 1;
    _loadLocal(source);
    _loadLocal(index);
    code.add(E0Opcode.iterationValue.code);
    code.addAll(<int>[E0Opcode.storeLocal.code, loop.slot]);
    final breaks = <int>[];
    _breakTargets.add(breaks);
    statement(body);
    _breakTargets.removeLast();
    _loadLocal(index);
    _emitConstant(1, E0ValueSchema.integer);
    code.add(E0Opcode.addInt.code);
    code.addAll(<int>[E0Opcode.storeLocal.code, index.slot]);
    code.addAll(<int>[E0Opcode.jump.code, conditionTarget]);
    code[endTarget] = code.length;
    _patchTargets(breaks, code.length);
  }

  void _emitSwitch(SwitchStatement statement) {
    final schema = emitExpression(statement.expression);
    if (!_isScalar(schema)) {
      throw FormatException(
        'switch supports non-null scalar values, got $schema',
      );
    }
    final value = _declareHidden(schema);
    code.addAll(<int>[E0Opcode.storeLocal.code, value.slot]);
    final endTargets = <int>[];
    _breakTargets.add(endTargets);
    SwitchDefault? defaultMember;
    for (final member in statement.members) {
      if (member is SwitchDefault) {
        _requireTerminatedSwitchMember(member);
        defaultMember = member;
        continue;
      }
      if (member.statements.isEmpty) {
        throw const FormatException(
          'Grouped empty switch cases are unsupported in v6; '
          'each scalar case must have its own statements',
        );
      }
      _requireTerminatedSwitchMember(member);
      final Expression caseExpression;
      if (member is SwitchCase) {
        caseExpression = member.expression;
      } else if (member is SwitchPatternCase &&
          member.guardedPattern.whenClause == null &&
          member.guardedPattern.pattern is ConstantPattern) {
        caseExpression =
            (member.guardedPattern.pattern as ConstantPattern).expression;
      } else {
        throw const FormatException(
          'Only scalar constant switch cases are supported in v6; '
          'destructuring and guards are unsupported',
        );
      }
      _loadLocal(value);
      final caseSchema = emitExpression(caseExpression);
      if (caseSchema != schema || !_isCompileTimeScalar(caseExpression)) {
        throw const FormatException(
          'switch cases must be matching scalar literals',
        );
      }
      code.add(E0Opcode.equal.code);
      code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
      final nextCase = code.length - 1;
      _withScope(() {
        for (final nested in member.statements) {
          this.statement(nested);
        }
      });
      code[nextCase] = code.length;
    }
    if (defaultMember != null) {
      _withScope(() {
        for (final nested in defaultMember!.statements) {
          this.statement(nested);
        }
      });
    }
    _breakTargets.removeLast();
    _patchTargets(endTargets, code.length);
  }

  E0ValueSchema emitExpression(
    Expression expression, {
    E0ValueSchema? context,
  }) {
    if (isWidgetBuild &&
        context == E0ValueSchema.string &&
        expression is PrefixedIdentifier &&
        (expression.toSource() == 'MainAxisSize.min' ||
            expression.toSource() == 'MainAxisSize.max')) {
      return _emitConstant(expression.identifier.name, E0ValueSchema.string);
    }
    if (expression is InstanceCreationExpression) {
      if (!isWidgetBuild) {
        throw const FormatException(
          'Object construction is unsupported outside the widget-build ABI',
        );
      }
      return _emitWidgetCreation(expression);
    }
    if (isWidgetBuild &&
        expression is MethodInvocation &&
        expression.target == null &&
        _declaredWidgetFactories.any(
          (factory) => factory.sourceName == expression.methodName.name,
        )) {
      return _emitWidgetCreationParts(
        expression.methodName.name,
        expression.argumentList.arguments,
      );
    }
    if (expression is AwaitExpression) {
      if (!isAsync) {
        throw const FormatException('await requires an async patch function');
      }
      final operand = expression.expression;
      if (operand is MethodInvocation &&
          operand.target is SimpleIdentifier &&
          (operand.target! as SimpleIdentifier).name == 'Future' &&
          operand.methodName.name == 'value') {
        if (operand.argumentList.arguments.length != 1 ||
            operand.argumentList.arguments.single is NamedExpression) {
          throw const FormatException(
            'Future.value requires one positional argument',
          );
        }
        final value = emitExpression(
          operand.argumentList.arguments.single,
          context: context,
        );
        code.add(E0Opcode.futureValue.code);
        return _emitAwaitPoint(value);
      }
      if (operand is! MethodInvocation || operand.target != null) {
        throw const FormatException(
          'await supports Future.value or direct calls to registered async capabilities',
        );
      }
      final matches = _declaredCapabilities
          .where((item) => item.sourceName == operand.methodName.name)
          .toList(growable: false);
      final descriptor = matches.length == 1 ? matches.single : null;
      if (descriptor == null) {
        throw FormatException(
          'Unsupported async capability ${operand.methodName.name}; register a stable typed capability',
        );
      }
      if (descriptor.executionKind != E0CapabilityExecutionKind.async) {
        throw FormatException(
          'Capability ${descriptor.id} is not async and cannot be awaited',
        );
      }
      if (operand.argumentList.arguments.length !=
          descriptor.arguments.length) {
        throw FormatException(
          'Async capability ${descriptor.id} argument count mismatch',
        );
      }
      for (var index = 0; index < descriptor.arguments.length; index++) {
        final actual = emitExpression(
          operand.argumentList.arguments[index],
          context: descriptor.arguments[index],
        );
        if (!descriptor.arguments[index].accepts(actual)) {
          throw FormatException(
            'Async capability ${descriptor.id} argument $index has $actual, expected ${descriptor.arguments[index]}',
          );
        }
      }
      var capabilityIndex = capabilities.indexWhere(
        (item) => item.id == descriptor.id,
      );
      if (capabilityIndex < 0) {
        capabilityIndex = capabilities.length;
        capabilities.add(descriptor);
      } else if (capabilities[capabilityIndex] != descriptor) {
        throw FormatException('Conflicting async capability ${descriptor.id}');
      }
      code.addAll(<int>[
        E0Opcode.callAsyncCapability.code,
        capabilityIndex,
        descriptor.arguments.length,
      ]);
      return _emitAwaitPoint(descriptor.result);
    }
    if (expression is AssignmentExpression &&
        _isReceiverProperty(expression.leftHandSide)) {
      _rejectReceiverWrite();
    }
    if (expression is PrefixExpression &&
        _isReceiverOrigin(expression.operand)) {
      _rejectReceiverWrite();
    }
    if (expression is PostfixExpression &&
        _isReceiverOrigin(expression.operand)) {
      _rejectReceiverWrite();
    }
    if (expression is IntegerLiteral) {
      final value = expression.value;
      if (value == null) throw const FormatException('Invalid integer literal');
      return _emitConstant(value, E0ValueSchema.integer);
    }
    if (expression is DoubleLiteral) {
      return _emitConstant(expression.value, E0ValueSchema.doubleValue);
    }
    if (expression is BooleanLiteral) {
      return _emitConstant(expression.value, E0ValueSchema.boolean);
    }
    if (expression is NullLiteral) {
      return _emitConstant(null, E0ValueSchema.nullValue);
    }
    if (expression is SimpleStringLiteral) {
      return _emitConstant(expression.value, E0ValueSchema.string);
    }
    if (expression is StringInterpolation) {
      var hasValue = false;
      for (final element in expression.elements) {
        E0ValueSchema schema;
        if (element is InterpolationString) {
          schema = _emitConstant(element.value, E0ValueSchema.string);
        } else if (element is InterpolationExpression) {
          schema = emitExpression(element.expression);
          if (schema != E0ValueSchema.string) {
            throw const FormatException(
              'Only String interpolation expressions are supported',
            );
          }
        } else {
          throw FormatException(
            'Unsupported interpolation element ${element.runtimeType}',
          );
        }
        if (schema != E0ValueSchema.string) {
          throw const FormatException('Interpolation must produce String');
        }
        if (hasValue) code.add(E0Opcode.addInt.code);
        hasValue = true;
      }
      return E0ValueSchema.string;
    }
    if (expression is SimpleIdentifier) {
      if (_unsupportedCatchBindings.any(
        (bindings) => bindings.contains(expression.name),
      )) {
        throw FormatException(
          'Catch binding ${expression.name} cannot be read in v6; only rethrow is supported',
        );
      }
      final local = _findLocal(expression.name);
      if (local != null) {
        _loadLocal(local);
        return local.schema;
      }
      final argument = arguments[expression.name];
      if (argument == null) {
        if (isInstanceMethod) {
          throw FormatException(
            'Unknown identifier ${expression.name}; unqualified receiver '
            'access is unsupported. Use an explicitly release-selected '
            'this.property read',
          );
        }
        throw FormatException('Unknown identifier ${expression.name}');
      }
      code.addAll(<int>[E0Opcode.loadArgument.code, argument.$1]);
      return argument.$2;
    }
    if (expression is PrefixedIdentifier) {
      final target = emitExpression(expression.prefix);
      return _emitProperty(target, expression.identifier.name);
    }
    if (expression is PropertyAccess && expression.target is ThisExpression) {
      final name = expression.propertyName.name;
      final member = receiverMembers[name];
      if (member == null) {
        throw FormatException(
          'Receiver property this.$name was not selected by the release '
          'descriptor',
        );
      }
      code.addAll(<int>[E0Opcode.loadReceiver.code, member.$1]);
      return member.$2;
    }
    if (expression is PropertyAccess && expression.target != null) {
      final name = expression.propertyName.name;
      final target = emitExpression(expression.target!);
      return _emitProperty(target, name);
    }
    if (expression is ThisExpression) {
      throw const FormatException(
        'Raw this is unsupported; use an explicitly selected this.property read',
      );
    }
    if (expression is MethodInvocation && expression.target is ThisExpression) {
      throw FormatException(
        'Receiver method invocation this.${expression.methodName.name}(...) '
        'is unsupported',
      );
    }
    if (expression is FunctionExpression) {
      return _emitClosure(
        expression,
        expectedParameters: null,
        returnSchema: context,
      );
    }
    if (expression is FunctionExpressionInvocation) {
      return _emitFunctionInvocation(expression, context: context);
    }
    if (expression is MethodInvocation && expression.target == null) {
      final localClosure = _findLocal(expression.methodName.name);
      if (localClosure != null &&
          localClosure.schema.kind == E0ValueKind.closure) {
        return _emitLocalClosureInvocation(
          expression,
          localClosure,
          context: context,
        );
      }
      final matches = _declaredCapabilities
          .where((item) => item.sourceName == expression.methodName.name)
          .toList(growable: false);
      if (matches.length == 1 &&
          matches.single.executionKind == E0CapabilityExecutionKind.sync) {
        if (isAsync) {
          throw FormatException(
            'Sync capability ${matches.single.id} is not enabled in async patches',
          );
        }
        final descriptor = matches.single;
        if (expression.argumentList.arguments.length !=
            descriptor.arguments.length) {
          throw FormatException(
            'Capability ${descriptor.id} argument count mismatch',
          );
        }
        for (var index = 0; index < descriptor.arguments.length; index++) {
          final actual = emitExpression(
            expression.argumentList.arguments[index],
            context: descriptor.arguments[index],
          );
          if (!descriptor.arguments[index].accepts(actual)) {
            throw FormatException(
              'Capability ${descriptor.id} argument $index mismatch',
            );
          }
        }
        var capabilityIndex = capabilities.indexWhere(
          (item) => item.id == descriptor.id,
        );
        if (capabilityIndex < 0) {
          capabilityIndex = capabilities.length;
          capabilities.add(descriptor);
        }
        code.addAll(<int>[
          E0Opcode.callSyncCapability.code,
          capabilityIndex,
          descriptor.arguments.length,
        ]);
        return descriptor.result;
      }
      if (isWidgetBuild) {
        throw FormatException(
          'Unknown widget factory source ${expression.methodName.name}',
        );
      }
    }
    if (expression is MethodInvocation) {
      final name = expression.methodName.name;
      if (expression.target != null &&
          (name == 'map' ||
              name == 'where' ||
              name == 'fold' ||
              name == 'sort' ||
              name == 'toList')) {
        return _emitCollectionMethod(expression, context: context);
      }
      final source = expression.toSource();
      for (final higherOrder in _higherOrderNames) {
        if (name == higherOrder || source.contains('.$higherOrder(')) {
          _rejectClosureApi(higherOrder);
        }
      }
      if (name == 'contains' && expression.target != null) {
        final target = emitExpression(expression.target!);
        if (target.kind != E0ValueKind.list &&
            target.kind != E0ValueKind.map &&
            target.kind != E0ValueKind.set &&
            target.kind != E0ValueKind.string) {
          throw FormatException('contains is unsupported for $target');
        }
        if (expression.argumentList.arguments.length != 1) {
          throw const FormatException('contains requires one argument');
        }
        emitExpression(expression.argumentList.arguments.single);
        code.add(E0Opcode.collectionContains.code);
        return E0ValueSchema.boolean;
      }
    }
    if (expression is ParenthesizedExpression) {
      return emitExpression(expression.expression, context: context);
    }
    if (expression is PrefixExpression) {
      final operator = expression.operator.lexeme;
      if (operator == '-') {
        _emitConstant(0, E0ValueSchema.integer);
        final operand = emitExpression(expression.operand);
        if (operand != E0ValueSchema.integer) {
          throw const FormatException('Unary - requires int in v6');
        }
        code.add(E0Opcode.subtractInt.code);
        return E0ValueSchema.integer;
      }
      if (operator == '!') {
        final operand = emitExpression(expression.operand);
        if (operand != E0ValueSchema.boolean) {
          throw const FormatException('Unary ! requires bool');
        }
        _emitConstant(false, E0ValueSchema.boolean);
        code.add(E0Opcode.equal.code);
        return E0ValueSchema.boolean;
      }
    }
    if (expression is BinaryExpression) {
      final operator = expression.operator.lexeme;
      if (operator == '&&' || operator == '||') {
        final left = emitExpression(expression.leftOperand);
        if (left != E0ValueSchema.boolean) {
          throw FormatException(
            'Operator $operator requires bool operands, got $left on the left',
          );
        }
        code.addAll(<int>[E0Opcode.jumpIfFalse.code, 0]);
        final branchTargetIndex = code.length - 1;
        if (operator == '||') {
          _emitConstant(true, E0ValueSchema.boolean);
          code.addAll(<int>[E0Opcode.jump.code, 0]);
          final endTarget = code.length - 1;
          code[branchTargetIndex] = code.length;
          final right = emitExpression(expression.rightOperand);
          if (right != E0ValueSchema.boolean) {
            throw const FormatException('Operator || requires bool operands');
          }
          code[endTarget] = code.length;
          return E0ValueSchema.boolean;
        }
        final right = emitExpression(expression.rightOperand);
        if (right != E0ValueSchema.boolean) {
          throw FormatException(
            'Operator && requires bool operands, got $right on the right',
          );
        }
        code.addAll(<int>[E0Opcode.jump.code, 0]);
        final endTargetIndex = code.length - 1;
        code[branchTargetIndex] = code.length;
        _emitConstant(false, E0ValueSchema.boolean);
        code[endTargetIndex] = code.length;
        return E0ValueSchema.boolean;
      }
      final left = emitExpression(expression.leftOperand);
      final right = emitExpression(expression.rightOperand);
      if (left != right && operator != '==') {
        throw FormatException(
          'Operator $operator requires matching operand types, got '
          '$left and $right',
        );
      }
      final (opcode, result) = switch (operator) {
        '+' when _supportsAddition(left) => (E0Opcode.addInt, left),
        '-' when _isNumeric(left) => (E0Opcode.subtractInt, left),
        '*' when _isNumeric(left) => (E0Opcode.multiplyInt, left),
        '<' when _isNumeric(left) => (
          E0Opcode.lessThanInt,
          E0ValueSchema.boolean,
        ),
        '>=' when _isNumeric(left) => (
          E0Opcode.greaterThanOrEqual,
          E0ValueSchema.boolean,
        ),
        '<=' when _isNumeric(left) => (
          E0Opcode.lessThanOrEqual,
          E0ValueSchema.boolean,
        ),
        '>' when _isNumeric(left) => (
          E0Opcode.greaterThan,
          E0ValueSchema.boolean,
        ),
        '==' => (E0Opcode.equal, E0ValueSchema.boolean),
        '!=' => (E0Opcode.equal, E0ValueSchema.boolean),
        _ => throw FormatException(
          'Unsupported operator $operator for $left and $right',
        ),
      };
      code.add(opcode.code);
      if (operator == '!=') {
        _emitConstant(false, E0ValueSchema.boolean);
        code.add(E0Opcode.equal.code);
      }
      return result;
    }
    if (expression is IndexExpression && !expression.isNullAware) {
      final target = emitExpression(expression.realTarget);
      final index = emitExpression(expression.index);
      if (target.kind == E0ValueKind.list && index == E0ValueSchema.integer) {
        code.add(E0Opcode.indexValue.code);
        return target.elementSchema!;
      }
      if (target.kind == E0ValueKind.map && index == E0ValueSchema.string) {
        code.add(E0Opcode.indexValue.code);
        return target.mapValueSchema!;
      }
      throw FormatException('Unsupported index expression $target[$index]');
    }
    if (expression is ListLiteral) {
      final expected = context;
      if (expected == null || expected.kind != E0ValueKind.list) {
        throw const FormatException(
          'List literals require an explicit List return schema',
        );
      }
      for (final element in expression.elements) {
        if (element is! Expression) {
          throw FormatException(
            'Unsupported List element ${element.runtimeType}',
          );
        }
        final actual = emitExpression(element, context: expected.elementSchema);
        if (!expected.elementSchema!.accepts(actual)) {
          throw FormatException(
            'List element $actual does not match ${expected.elementSchema}',
          );
        }
      }
      code.addAll(<int>[E0Opcode.makeList.code, expression.elements.length]);
      return expected;
    }
    if (expression is SetOrMapLiteral) {
      final expected = context;
      if (expected?.kind == E0ValueKind.set) {
        for (final element in expression.elements) {
          if (element is! Expression) {
            throw const FormatException(
              'Set spreads/control elements are unsupported',
            );
          }
          final actual = emitExpression(
            element,
            context: expected!.elementSchema,
          );
          if (!expected.elementSchema!.accepts(actual)) {
            throw FormatException(
              'Set element $actual does not match ${expected.elementSchema}',
            );
          }
        }
        code.addAll(<int>[E0Opcode.makeSet.code, expression.elements.length]);
        return expected!;
      }
      if (expected == null || expected.kind != E0ValueKind.map) {
        throw const FormatException(
          'Map literals require an explicit Map return schema',
        );
      }
      for (final element in expression.elements) {
        if (element is! MapLiteralEntry) {
          throw FormatException(
            'Unsupported Map element ${element.runtimeType}',
          );
        }
        final key = emitExpression(element.key);
        if (key != E0ValueSchema.string) {
          throw const FormatException('Map literal keys must be String');
        }
        final value = emitExpression(
          element.value,
          context: expected.mapValueSchema,
        );
        if (!expected.mapValueSchema!.accepts(value)) {
          throw FormatException(
            'Map value $value does not match ${expected.mapValueSchema}',
          );
        }
      }
      code.addAll(<int>[E0Opcode.makeMap.code, expression.elements.length]);
      return expected;
    }
    throw FormatException(
      'Unsupported expression ${expression.runtimeType} in v6 subset',
    );
  }

  E0ValueSchema _emitAwaitPoint(E0ValueSchema result) {
    final pointIndex = asyncPoints.length;
    final awaitPc = code.length;
    code.addAll(<int>[E0Opcode.awaitValue.code, pointIndex]);
    asyncPoints.add(
      E0AsyncPoint(
        id: pointIndex,
        awaitPc: awaitPc,
        resumePc: code.length,
        result: result,
        handlerDepth: _handlerDepth,
      ),
    );
    return result;
  }

  E0ValueSchema _emitCollectionMethod(
    MethodInvocation expression, {
    E0ValueSchema? context,
  }) {
    final targetExpression = expression.target;
    if (targetExpression == null) {
      throw const FormatException('Collection method requires a target');
    }
    final name = expression.methodName.name;
    final target = emitExpression(
      targetExpression,
      context: name == 'toList' ? context : null,
    );
    final arguments = expression.argumentList.arguments;
    if (name == 'toList') {
      if (arguments.isNotEmpty || target.kind != E0ValueKind.list) {
        throw const FormatException(
          'toList supports only a List with no arguments',
        );
      }
      return target;
    }
    if (target.kind != E0ValueKind.list) {
      throw FormatException('$name is supported only for List values');
    }
    if (arguments.any((argument) => argument is NamedExpression)) {
      throw FormatException('$name does not support named callback arguments');
    }
    if (name == 'map' || name == 'where' || name == 'sort') {
      if (arguments.length != 1 || arguments.single is! FunctionExpression) {
        throw FormatException('$name requires one inline closure callback');
      }
      final closure = arguments.single as FunctionExpression;
      final expectedParameters = name == 'sort'
          ? <E0ValueSchema>[target.elementSchema!, target.elementSchema!]
          : <E0ValueSchema>[target.elementSchema!];
      final expectedReturn = switch (name) {
        'where' => E0ValueSchema.boolean,
        'sort' => E0ValueSchema.integer,
        _ => context?.kind == E0ValueKind.list ? context!.elementSchema : null,
      };
      final closureSchema = _emitClosure(
        closure,
        expectedParameters: expectedParameters,
        returnSchema: expectedReturn,
      );
      final closureIndex = closureSchema.closureIndex!;
      if (name == 'map') {
        code.add(E0Opcode.collectionMap.code);
        final result = E0ValueSchema.list(closures[closureIndex].returnSchema);
        if (context != null && !context.accepts(result)) {
          throw FormatException('map result $result does not match $context');
        }
        return result;
      }
      if (name == 'where') {
        code.add(E0Opcode.collectionWhere.code);
        return target;
      }
      code.add(E0Opcode.collectionSort.code);
      return E0ValueSchema.nullValue;
    }
    if (name == 'fold') {
      if (arguments.length != 2 || arguments[1] is! FunctionExpression) {
        throw const FormatException(
          'fold requires an initial value and one inline closure callback',
        );
      }
      final initial = emitExpression(arguments[0], context: context);
      final closureSchema = _emitClosure(
        arguments[1] as FunctionExpression,
        expectedParameters: <E0ValueSchema>[initial, target.elementSchema!],
        returnSchema: context ?? initial,
      );
      code.add(E0Opcode.collectionFold.code);
      final result = closures[closureSchema.closureIndex!].returnSchema;
      if (context != null && !context.accepts(result)) {
        throw FormatException('fold result $result does not match $context');
      }
      return result;
    }
    throw FormatException('Unsupported collection method $name');
  }

  E0ValueSchema _emitFunctionInvocation(
    FunctionExpressionInvocation expression, {
    E0ValueSchema? context,
  }) {
    if (expression.argumentList.arguments.any(
      (argument) => argument is NamedExpression,
    )) {
      throw const FormatException(
        'Closure invocation with named arguments is not supported yet',
      );
    }
    final function = expression.function;
    E0ValueSchema functionSchema;
    E0ClosureProgram? localProgram;
    if (function is FunctionExpression) {
      final expected = _closureParameterSchemas(function);
      if (expected.length != expression.argumentList.arguments.length) {
        throw const FormatException('Closure argument count mismatch');
      }
      for (var index = 0; index < expected.length; index++) {
        final actual = emitExpression(
          expression.argumentList.arguments[index],
          context: expected[index],
        );
        if (!expected[index].accepts(actual)) {
          throw FormatException(
            'Closure argument $actual does not match ${expected[index]}',
          );
        }
      }
      functionSchema = _emitClosure(
        function,
        expectedParameters: expected,
        returnSchema: context,
      );
    } else if (function is SimpleIdentifier) {
      final local = _findLocal(function.name);
      if (local == null || local.schema.kind != E0ValueKind.closure) {
        throw FormatException('Identifier ${function.name} is not a closure');
      }
      localProgram = closures[local.schema.closureIndex!];
      if (localProgram.parameters.length !=
          expression.argumentList.arguments.length) {
        throw const FormatException('Closure argument count mismatch');
      }
      for (var index = 0; index < localProgram.parameters.length; index++) {
        final actual = emitExpression(
          expression.argumentList.arguments[index],
          context: localProgram.parameters[index],
        );
        if (!localProgram.parameters[index].accepts(actual)) {
          throw FormatException(
            'Closure argument $actual does not match ${localProgram.parameters[index]}',
          );
        }
      }
      _loadLocal(local);
      functionSchema = local.schema;
    } else {
      throw const FormatException(
        'Only inline closures and local closure variables can be invoked',
      );
    }
    final index = functionSchema.closureIndex;
    if (index == null) throw const FormatException('Invalid closure reference');
    final program = localProgram ?? closures[index];
    code.addAll(<int>[E0Opcode.invokeClosure.code, program.parameters.length]);
    return program.returnSchema;
  }

  E0ValueSchema _emitLocalClosureInvocation(
    MethodInvocation expression,
    _Local local, {
    E0ValueSchema? context,
  }) {
    final program = closures[local.schema.closureIndex!];
    final arguments = expression.argumentList.arguments;
    if (arguments.any((argument) => argument is NamedExpression) ||
        arguments.length != program.parameters.length) {
      throw const FormatException('Closure argument shape does not match');
    }
    for (var index = 0; index < arguments.length; index++) {
      final actual = emitExpression(
        arguments[index],
        context: program.parameters[index],
      );
      if (!program.parameters[index].accepts(actual)) {
        throw FormatException(
          'Closure argument $actual does not match ${program.parameters[index]}',
        );
      }
    }
    _loadLocal(local);
    code.addAll(<int>[E0Opcode.invokeClosure.code, arguments.length]);
    final result = program.returnSchema;
    if (context != null && !context.accepts(result)) {
      throw FormatException('Closure result $result does not match $context');
    }
    return result;
  }

  E0ValueSchema _emitClosure(
    FunctionExpression expression, {
    required List<E0ValueSchema>? expectedParameters,
    required E0ValueSchema? returnSchema,
  }) {
    if (isAsync) {
      throw const FormatException(
        'Closures inside async patches are deferred until async closure suspension is modeled',
      );
    }
    final parameters = _closureParameterSchemas(
      expression,
      expected: expectedParameters,
    );
    final visitor = _ClosureReferenceVisitor();
    expression.body.accept(visitor);
    final parameterNames =
        expression.parameters?.parameters
            .map((parameter) => parameter.name?.lexeme)
            .whereType<String>()
            .toSet() ??
        const <String>{};
    final captureNames =
        visitor.references
            .where(
              (name) =>
                  !parameterNames.contains(name) &&
                  !visitor.declared.contains(name) &&
                  (_findLocal(name) != null || arguments.containsKey(name)),
            )
            .toList()
          ..sort();
    final captureSchemas = <E0ValueSchema>[];
    final nestedArguments = <String, (int, E0ValueSchema)>{};
    for (var index = 0; index < captureNames.length; index++) {
      final name = captureNames[index];
      final local = _findLocal(name);
      final binding = local == null ? arguments[name] : null;
      final schema = local?.schema ?? binding!.$2;
      if (schema.kind == E0ValueKind.closure ||
          schema.kind == E0ValueKind.supportedValue) {
        throw FormatException(
          'Closure capture $name has an unsupported internal value schema $schema',
        );
      }
      captureSchemas.add(schema);
      nestedArguments[name] = (index, schema);
      if (local != null) {
        _loadLocal(local);
      } else {
        code.addAll(<int>[E0Opcode.loadArgument.code, binding!.$1]);
      }
    }
    final formalParameters =
        expression.parameters?.parameters ?? const <FormalParameter>[];
    for (var index = 0; index < parameters.length; index++) {
      final parameter = formalParameters[index];
      nestedArguments[parameter.name!.lexeme] = (
        captureNames.length + index,
        parameters[index],
      );
    }
    final nestedReturn = returnSchema ?? E0ValueSchema.supportedValue;
    final nested = _Emitter(
      nestedArguments,
      nestedReturn,
      receiverMembers,
      receiver: receiver,
      isInstanceMethod: isInstanceMethod,
      isAsync: false,
      declaredCapabilities: _declaredCapabilities,
      declaredWidgetFactories: _declaredWidgetFactories,
      isWidgetBuild: isWidgetBuild,
    );
    final body = expression.body;
    if (body is ExpressionFunctionBody) {
      final actual = nested.emitExpression(
        body.expression,
        context: nestedReturn,
      );
      if (!nestedReturn.accepts(actual)) {
        throw FormatException(
          'Closure return $actual does not match $nestedReturn',
        );
      }
      nested.code.add(E0Opcode.returnValue.code);
    } else if (body is BlockFunctionBody) {
      if (body.isAsynchronous || body.isGenerator) {
        throw const FormatException(
          'Async and generator closures are unsupported',
        );
      }
      if (!_blockDefinitelyReturns(body.block)) {
        throw const FormatException(
          'Closure must return on every reachable path',
        );
      }
      for (final statement in body.block.statements) {
        nested.statement(statement);
      }
    } else {
      throw const FormatException('Unsupported closure body');
    }
    if (nested.capabilities.isNotEmpty || nested.widgetFactories.isNotEmpty) {
      throw const FormatException(
        'Capability and widget calls from closures are deferred until closure metadata carries host boundaries',
      );
    }
    if (nested.closures.isNotEmpty) {
      throw const FormatException('Nested closures are deferred');
    }
    final index = closures.length;
    closures.add(
      E0ClosureProgram(
        parameters: parameters,
        captures: captureSchemas,
        returnSchema: nestedReturn,
        constants: nested.constants,
        code: nested.code,
        locals: nested.locals,
        handlers: nested.handlers,
        receiver: receiver,
      ),
    );
    code.addAll(<int>[E0Opcode.makeClosure.code, index]);
    return E0ValueSchema.closure(index);
  }

  List<E0ValueSchema> _closureParameterSchemas(
    FunctionExpression expression, {
    List<E0ValueSchema>? expected,
  }) {
    final raw = expression.parameters?.parameters ?? const <FormalParameter>[];
    if (raw.length > 8 || (expected != null && raw.length != expected.length)) {
      throw const FormatException('Invalid closure parameter count');
    }
    final result = <E0ValueSchema>[];
    for (var index = 0; index < raw.length; index++) {
      final parameter = raw[index];
      if (!parameter.isRequiredPositional ||
          parameter is DefaultFormalParameter) {
        throw const FormatException(
          'Closures currently support only required positional parameters',
        );
      }
      final normal = parameter is DefaultFormalParameter
          ? parameter.parameter
          : parameter;
      if (normal is! SimpleFormalParameter) {
        throw const FormatException(
          'Closure parameters must be simple parameters',
        );
      }
      final schema = normal.type == null
          ? expected == null
                ? null
                : expected[index]
          : e0HostSchemaForType(normal.type!.toSource(), 'closure parameter');
      if (schema == null) {
        throw const FormatException(
          'Closure parameters need an expected collection type or explicit type',
        );
      }
      if (expected != null && schema != expected[index]) {
        throw FormatException(
          'Closure parameter $schema does not match expected ${expected[index]}',
        );
      }
      result.add(schema);
    }
    return result;
  }

  E0ValueSchema _emitWidgetCreation(InstanceCreationExpression expression) {
    final sourceName = expression.constructorName.type.toSource();
    if (expression.constructorName.name != null) {
      throw FormatException(
        'Named widget constructors are unsupported for $sourceName',
      );
    }
    return _emitWidgetCreationParts(
      sourceName,
      expression.argumentList.arguments,
    );
  }

  E0ValueSchema _emitWidgetCreationParts(
    String sourceName,
    NodeList<Expression> arguments,
  ) {
    final factory = _declaredWidgetFactories
        .where((item) => item.sourceName == sourceName)
        .firstOrNull;
    if (factory == null) {
      throw FormatException('Unknown widget factory source $sourceName');
    }
    final positional = arguments
        .where((item) => item is! NamedExpression)
        .toList();
    final named = <String, Expression>{};
    for (final argument in arguments.whereType<NamedExpression>()) {
      final name = argument.name.label.name;
      if (named.putIfAbsent(name, () => argument.expression) !=
          argument.expression) {
        throw FormatException('Duplicate widget argument $name');
      }
    }
    final properties = <String, (Expression, E0ValueSchema)>{};
    final children = <Expression>[];
    switch (sourceName) {
      case 'Text':
        if (positional.length != 1) {
          throw const FormatException('Text requires one positional String');
        }
        properties['data'] = (positional.single, E0ValueSchema.string);
        final style = named.remove('style');
        if (style != null) {
          final styleProperties = _textStyleProperties(style);
          properties.addAll(styleProperties);
        }
      case 'Column':
        if (positional.isNotEmpty) {
          throw const FormatException(
            'Column positional arguments are unsupported',
          );
        }
        final childrenExpression = named.remove('children');
        if (childrenExpression is! ListLiteral) {
          throw const FormatException(
            'Column requires a literal children list',
          );
        }
        if (childrenExpression.elements.length >
            E0WidgetFactoryRegistry.maxChildren) {
          throw const FormatException('Column children limit exceeded');
        }
        for (final child in childrenExpression.elements) {
          if (child is! Expression) {
            throw const FormatException(
              'Widget spreads and collection controls are unsupported',
            );
          }
          children.add(child);
        }
        final mainAxisSize = named.remove('mainAxisSize');
        if (mainAxisSize != null) {
          final value = mainAxisSize.toSource();
          if (value != 'MainAxisSize.min' && value != 'MainAxisSize.max') {
            throw const FormatException('Unsupported Column.mainAxisSize');
          }
          properties['mainAxisSize'] = (mainAxisSize, E0ValueSchema.string);
        }
      case 'ElevatedButton':
        if (positional.isNotEmpty) {
          throw const FormatException(
            'ElevatedButton positional arguments are unsupported',
          );
        }
        final callback = named.remove('onPressed');
        if (callback is! NullLiteral) {
          throw const FormatException(
            'Patched button callbacks must remain host-owned; only null is supported',
          );
        }
        final child = named.remove('child');
        if (child == null) {
          throw const FormatException('ElevatedButton requires one child');
        }
        children.add(child);
      default:
        throw FormatException('Unsupported widget syntax for $sourceName');
    }
    if (named.isNotEmpty) {
      throw FormatException(
        'Unsupported $sourceName properties: ${named.keys.join(', ')}',
      );
    }
    final definitions = <String, E0WidgetPropertyDescriptor>{
      for (final property in factory.properties) property.name: property,
    };
    if (properties.keys.any((name) => !definitions.containsKey(name)) ||
        definitions.values.any(
          (property) =>
              property.required && !properties.containsKey(property.name),
        ) ||
        children.length < factory.minChildren ||
        children.length > factory.maxChildren) {
      throw FormatException(
        'Widget source does not match factory contract ${factory.id}',
      );
    }

    _emitConstant('factory', E0ValueSchema.string);
    _emitConstant(factory.id, E0ValueSchema.string);
    _emitConstant('properties', E0ValueSchema.string);
    for (final entry in properties.entries) {
      _emitConstant(entry.key, E0ValueSchema.string);
      final expected = definitions[entry.key]!.schema;
      final actual = emitExpression(entry.value.$1, context: expected);
      if (!expected.accepts(actual)) {
        throw FormatException(
          'Widget property ${entry.key} has $actual, expected $expected',
        );
      }
    }
    code.addAll(<int>[E0Opcode.makeMap.code, properties.length]);
    _emitConstant('children', E0ValueSchema.string);
    for (final child in children) {
      final actual = emitExpression(child, context: e0WidgetDescriptionSchema);
      if (!e0WidgetDescriptionSchema.accepts(actual)) {
        throw const FormatException('Widget child is not a description');
      }
    }
    code.addAll(<int>[E0Opcode.makeList.code, children.length]);
    code.addAll(<int>[E0Opcode.makeMap.code, 3]);
    if (!widgetFactories.any((item) => item.id == factory.id)) {
      widgetFactories.add(factory);
    }
    return e0WidgetDescriptionSchema;
  }

  Map<String, (Expression, E0ValueSchema)> _textStyleProperties(
    Expression expression,
  ) {
    final NodeList<Expression> arguments;
    if (expression is InstanceCreationExpression &&
        expression.constructorName.type.toSource() == 'TextStyle' &&
        expression.constructorName.name == null) {
      arguments = expression.argumentList.arguments;
    } else if (expression is MethodInvocation &&
        expression.target == null &&
        expression.methodName.name == 'TextStyle') {
      arguments = expression.argumentList.arguments;
    } else {
      throw const FormatException('Text.style requires a TextStyle literal');
    }
    final result = <String, (Expression, E0ValueSchema)>{};
    for (final argument in arguments) {
      if (argument is! NamedExpression ||
          argument.name.label.name != 'fontSize') {
        throw const FormatException(
          'Only TextStyle.fontSize is supported by the bounded widget ABI',
        );
      }
      result['fontSize'] = (argument.expression, E0ValueSchema.doubleValue);
    }
    if (result.isEmpty) {
      throw const FormatException('Empty TextStyle is unsupported');
    }
    return result;
  }

  E0ValueSchema _localSchema(String source) {
    final schema = E0ValueSchema.parseDartType(source);
    if (schema.kind == E0ValueKind.supportedValue ||
        schema.kind == E0ValueKind.nullValue) {
      throw FormatException('Unsupported local type $source');
    }
    return schema;
  }

  E0ValueSchema _emitProperty(E0ValueSchema target, String name) {
    if (name == 'length' &&
        (target.kind == E0ValueKind.list ||
            target.kind == E0ValueKind.map ||
            target.kind == E0ValueKind.set ||
            target.kind == E0ValueKind.string)) {
      code.add(E0Opcode.collectionLength.code);
      return E0ValueSchema.integer;
    }
    if (name == 'first' && target.kind == E0ValueKind.list) {
      _emitConstant(0, E0ValueSchema.integer);
      code.add(E0Opcode.indexValue.code);
      return target.elementSchema!;
    }
    if (name == 'keys' && target.kind == E0ValueKind.map) {
      code.add(E0Opcode.mapKeys.code);
      return const E0ValueSchema.set(E0ValueSchema.string);
    }
    throw FormatException('Unsupported property $name on $target');
  }

  _Local _declare(String name, E0ValueSchema schema, {bool isMutable = true}) {
    if (_scopes.last.containsKey(name)) {
      throw FormatException('Duplicate local $name in lexical scope');
    }
    final local = _declareHidden(schema, isMutable: isMutable);
    _scopes.last[name] = local;
    return local;
  }

  _Local _declareHidden(E0ValueSchema schema, {bool isMutable = true}) {
    final local = _Local(locals.length, schema, isMutable: isMutable);
    locals.add(schema);
    return local;
  }

  _Local? _findLocal(String name) {
    for (final scope in _scopes.reversed) {
      final local = scope[name];
      if (local != null) return local;
    }
    return null;
  }

  _Local _lookupLocal(String name) =>
      _findLocal(name) ?? (throw FormatException('Unknown local $name'));

  void _loadLocal(_Local local) {
    code.addAll(<int>[E0Opcode.loadLocal.code, local.slot]);
  }

  void _withScope(void Function() action) {
    _scopes.add(<String, _Local>{});
    try {
      action();
    } finally {
      _scopes.removeLast();
    }
  }

  void _patchTargets(List<int> operands, int target) {
    for (final operand in operands) {
      code[operand] = target;
    }
  }

  static void _requireTerminatedSwitchMember(SwitchMember member) {
    if (member.statements.isEmpty ||
        !_statementTerminatesSwitchMember(member.statements.last)) {
      throw const FormatException(
        'Switch case may fall through; end every case with an explicit '
        'break or return',
      );
    }
  }

  static const _higherOrderNames = <String>{'forEach'};

  static Never _rejectClosureApi(String name) => throw FormatException(
    'Collection.$name is not supported by the bounded closure runtime',
  );

  static bool _isScalar(E0ValueSchema schema) =>
      !schema.nullable &&
      (schema.kind == E0ValueKind.boolean ||
          schema.kind == E0ValueKind.integer ||
          schema.kind == E0ValueKind.doubleValue ||
          schema.kind == E0ValueKind.string);

  static bool _isCompileTimeScalar(Expression expression) =>
      expression is IntegerLiteral ||
      expression is DoubleLiteral ||
      expression is BooleanLiteral ||
      expression is SimpleStringLiteral;

  E0ValueSchema _emitConstant(Object? value, E0ValueSchema schema) {
    final constant = E0Value.fromHost(value, schema);
    var index = constants.indexOf(constant);
    if (index < 0) {
      constants.add(constant);
      index = constants.length - 1;
    }
    code.addAll(<int>[E0Opcode.loadConstant.code, index]);
    return constant.schema;
  }

  static bool _supportsAddition(E0ValueSchema schema) =>
      _isNumeric(schema) || schema == E0ValueSchema.string;

  static bool _isNumeric(E0ValueSchema schema) =>
      schema == E0ValueSchema.integer || schema == E0ValueSchema.doubleValue;

  static bool _isReceiverProperty(Expression expression) =>
      expression is PropertyAccess && expression.target is ThisExpression;

  static bool _isReceiverRooted(Expression expression) {
    if (_isReceiverProperty(expression)) return true;
    if (expression is ParenthesizedExpression) {
      return _isReceiverRooted(expression.expression);
    }
    if (expression is IndexExpression) {
      return _isReceiverRooted(expression.realTarget);
    }
    if (expression is PropertyAccess && expression.target != null) {
      return _isReceiverRooted(expression.target!);
    }
    return false;
  }

  bool _isReceiverOrigin(Expression expression) {
    if (_isReceiverRooted(expression)) return true;
    if (expression is ParenthesizedExpression) {
      return _isReceiverOrigin(expression.expression);
    }
    if (expression is IndexExpression) {
      return _isReceiverOrigin(expression.realTarget);
    }
    if (expression is PropertyAccess && expression.target != null) {
      return _isReceiverOrigin(expression.target!);
    }
    if (expression is SimpleIdentifier) {
      return _findLocal(expression.name)?.isReceiverOrigin ?? false;
    }
    return false;
  }

  static Never _rejectReceiverWrite() => throw const FormatException(
    'Receiver setter writes are unsupported: transactional staged/atomic '
    'commit semantics are required',
  );
}
