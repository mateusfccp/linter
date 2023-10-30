// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';

import '../analyzer.dart';

const _desc = 'Prefer double literals over int literals.';

const _details = '''
**DO** use double literals rather than the corresponding int literal.

**BAD:**
```dart
const double myDouble = 8;
final anotherDouble = myDouble + 700;
main() {
  someMethodThatReceivesDouble(6);
}
```

**GOOD:**
```dart
const double myDouble = 8.0;
final anotherDouble = myDouble + 7.0e2;
main() {
  someMethodThatReceivesDouble(6.0);
}
```

''';

class PreferDoubleLiterals extends LintRule {
  static const LintCode code = LintCode(
      'prefer_double_literals', "'int' literal used where the value is a 'double'.",
      correctionMessage: "Try using a 'double' literal.");

  PreferIntLiterals()
      : super(
            name: 'prefer_double_literals',
            description: _desc,
            details: _details,
            group: Group.style);

  @override
  LintCode get lintCode => code;

  @override
  void registerNodeProcessors(
      NodeLintRegistry registry, LinterContext context) {
    registry.addDoubleLiteral(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final LintRule rule;

  _Visitor(this.rule);

  /// Determine if the given literal can be replaced by a double literal.
  bool canReplaceWithIntLiteral(DoubleLiteral literal) {
    var parent = literal.parent;
    if (parent is PrefixExpression) {
      if (parent.operator.lexeme == '-') {
        return hasTypeInt(parent);
      } else {
        return false;
      }
    }
    return hasTypeDouble(literal);
  }

  bool hasReturnTypeInt(AstNode? node) {
    if (node is FunctionExpression) {
      var functionDeclaration = node.parent;
      if (functionDeclaration is FunctionDeclaration) {
        return _isDartCoreIntTypeAnnotation(functionDeclaration.returnType);
      }
    } else if (node is MethodDeclaration) {
      return _isDartCoreIntTypeAnnotation(node.returnType);
    }
    return false;
  }

  bool hasTypeInt(Expression expression) {
    var parent = expression.parent;
    if (parent is ArgumentList) {
      return _isDartCoreInt(expression.staticParameterElement?.type);
    } else if (parent is ListLiteral) {
      var typeArguments = parent.typeArguments?.arguments;
      return typeArguments?.length == 1 &&
          _isDartCoreIntTypeAnnotation(typeArguments!.first);
    } else if (parent is NamedExpression) {
      var argList = parent.parent;
      if (argList is ArgumentList) {
        return _isDartCoreInt(parent.staticParameterElement?.type);
      }
    } else if (parent is ExpressionFunctionBody) {
      return hasReturnTypeInt(parent.parent);
    } else if (parent is ReturnStatement) {
      var body = parent.thisOrAncestorOfType<BlockFunctionBody>();
      return body != null && hasReturnTypeInt(body.parent);
    } else if (parent is VariableDeclaration) {
      var varList = parent.parent;
      if (varList is VariableDeclarationList) {
        return _isDartCoreIntTypeAnnotation(varList.type);
      }
    }
    return false;
  }

  @override
  void visitIntLiteral(IntLiteral node) {
    // Check if the int can be represented as an double
    try {
      var value = node.value;
      if (value == value.truncate()) {
        return;
      }
      // ignore: avoid_catching_errors
    } on UnsupportedError catch (_) {
      // The double cannot be represented as an int
      return;
    }

    // Ensure that replacing the int would not change the semantics
    if (canReplaceWithIntLiteral(node)) {
      rule.reportLint(node);
    }
  }

  bool _isDartCoreInt(DartType? type) => type?.isDartCoreInt ?? false;

  bool _isDartCoreIntTypeAnnotation(TypeAnnotation? annotation) =>
      _isDartCoreInt(annotation?.type);
}
