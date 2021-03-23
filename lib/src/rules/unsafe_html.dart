// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../analyzer.dart';
import '../util/dart_type_utilities.dart';

const _descPrefix = r'Avoid unsafe HTML APIs';
const _desc = '$_descPrefix.';

const _details = r'''

**AVOID**

* assigning directly to the `href` field of an AnchorElement
* assigning directly to the `src` field of an EmbedElement, IFrameElement,
  ImageElement, or ScriptElement
* assigning directly to the `srcdoc` field of an IFrameElement
* calling the `createFragment` method of Element
* calling the `open` method of Window
* calling the `setInnerHtml` method of Element
* calling the `Element.html` constructor
* calling the `DocumentFragment.html` constructor


**BAD:**
```dart
var script = ScriptElement()..src = 'foo.js';
```
''';

extension on DartType? {
  /// Returns whether this type extends [className] from the dart:html library.
  bool extendsDartHtmlClass(String className) =>
      DartTypeUtilities.extendsClass(this, className, 'dart.dom.html');
}

class UnsafeHtml extends LintRule implements NodeLintRule {
  UnsafeHtml()
      : super(
            name: 'unsafe_html',
            description: _desc,
            details: _details,
            group: Group.errors);

  @override
  void registerNodeProcessors(
      NodeLintRegistry registry, LinterContext context) {
    var visitor = _Visitor(this);
    registry.addAssignmentExpression(this, visitor);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addFunctionExpressionInvocation(this, visitor);
    registry.addMethodInvocation(this, visitor);
  }

  @override
  List<LintCode> get lintCodes => [
        _Visitor.unsafeAttributeCode,
        _Visitor.unsafeMethodCode,
        _Visitor.unsafeConstructorCode
      ];
}

class _Visitor extends SimpleAstVisitor<void> {
  // TODO(srawlins): Reference attributes ('href', 'src', and 'srcdoc') with
  // single-quotes to match the convention in the analyzer and linter packages.
  // This requires some coordination within Google, as various allow-lists are
  // keyed on the exact text of the LintCode message.
  // ignore: deprecated_member_use
  static const unsafeAttributeCode = SecurityLintCodeWithUniqueName(
      'unsafe_html',
      'LintCode.unsafe_html_attribute',
      '$_descPrefix (assigning "{0}" attribute).');
  // ignore: deprecated_member_use
  static const unsafeMethodCode = SecurityLintCodeWithUniqueName(
      'unsafe_html',
      'LintCode.unsafe_html_method',
      "$_descPrefix (calling the '{0}' method of {1}).");
  // ignore: deprecated_member_use
  static const unsafeConstructorCode = SecurityLintCodeWithUniqueName(
      'unsafe_html',
      'LintCode.unsafe_html_constructor',
      "$_descPrefix (calling the '{0}' constructor of {1}).");

  final LintRule rule;

  _Visitor(this.rule);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    var leftPart = node.leftHandSide.unParenthesized;
    if (leftPart is SimpleIdentifier) {
      var leftPartElement = node.writeElement;
      if (leftPartElement == null) return;
      var enclosingElement = leftPartElement.enclosingElement;
      if (enclosingElement is ClassElement) {
        _checkAssignment(enclosingElement.thisType, leftPart, node);
      }
    } else if (leftPart is PropertyAccess) {
      _checkAssignment(
          leftPart.realTarget.staticType, leftPart.propertyName, node);
    } else if (leftPart is PrefixedIdentifier) {
      _checkAssignment(leftPart.prefix.staticType, leftPart.identifier, node);
    }
  }

  void _checkAssignment(DartType? type, SimpleIdentifier property,
      AssignmentExpression assignment) {
    if (type == null) return;

    // It is more efficient to check the setter's name before checking whether
    // the target is an interesting type.
    if (property.name == 'href') {
      if (type.isDynamic || type.extendsDartHtmlClass('AnchorElement')) {
        rule.reportLint(assignment,
            arguments: ['href'], errorCode: unsafeAttributeCode);
      }
    } else if (property.name == 'src') {
      if (type.isDynamic ||
          type.extendsDartHtmlClass('EmbedElement') ||
          type.extendsDartHtmlClass('IFrameElement') ||
          type.extendsDartHtmlClass('ImageElement') ||
          type.extendsDartHtmlClass('ScriptElement')) {
        rule.reportLint(assignment,
            arguments: ['src'], errorCode: unsafeAttributeCode);
      }
    } else if (property.name == 'srcdoc') {
      if (type.isDynamic || type.extendsDartHtmlClass('IFrameElement')) {
        rule.reportLint(assignment,
            arguments: ['srcdoc'], errorCode: unsafeAttributeCode);
      }
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    var type = node.staticType;
    if (type == null) return;

    var constructorName = node.constructorName;
    if (constructorName.name?.name == 'html') {
      if (type.extendsDartHtmlClass('DocumentFragment')) {
        rule.reportLint(node,
            arguments: ['html', 'DocumentFragment'],
            errorCode: unsafeConstructorCode);
      } else if (type.extendsDartHtmlClass('Element')) {
        rule.reportLint(node,
            arguments: ['html', 'Element'], errorCode: unsafeConstructorCode);
      }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    var methodName = node.methodName.name;

    // The static type of the target.
    DartType? type;
    if (node.realTarget == null) {
      // Implicit `this` target.
      var methodElement = node.methodName.staticElement;
      if (methodElement == null) return;
      var enclosingElement = methodElement.enclosingElement;
      if (enclosingElement is ClassElement) {
        type = enclosingElement.thisType;
      } else {
        return;
      }
    } else {
      type = node.realTarget?.staticType;
      if (type == null) return;
    }

    if (methodName == 'createFragment' &&
        (type.isDynamic || type.extendsDartHtmlClass('Element'))) {
      rule.reportLint(node,
          arguments: ['createFragment', 'Element'],
          errorCode: unsafeMethodCode);
    } else if (methodName == 'setInnerHtml' &&
        (type.isDynamic || type.extendsDartHtmlClass('Element'))) {
      rule.reportLint(node,
          arguments: ['setInnerHtml', 'Element'], errorCode: unsafeMethodCode);
    } else if (methodName == 'open' &&
        (type.isDynamic || type.extendsDartHtmlClass('Window'))) {
      rule.reportLint(node,
          arguments: ['open', 'Window'], errorCode: unsafeMethodCode);
    }
  }
}
