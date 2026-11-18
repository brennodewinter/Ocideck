import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Bewaakt laadvoortgang zonder comments of voorbeeldstrings als code te lezen.
///
/// Lage schedulerprioriteiten kunnen verhongeren zolang een laadindicator of
/// tekstcursor animeert. Frame-afhankelijk werk moet via de gedeelde,
/// begrensde framewacht lopen; gewoon werk wacht alleen op de event loop.
List<String> asyncProgressViolationsIn(String source, {required String path}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _ProgressVisitor(
    allowFrame: path.replaceAll(r'\', '/') == 'lib/utils/ui_frame.dart',
    rasterizer:
        path.replaceAll(r'\', '/') == 'lib/services/slide_rasterizer.dart',
  );
  parsed.unit.accept(visitor);
  return [
    for (final hit in visitor.hits)
      '$path:${parsed.lineInfo.getLocation(hit.offset).lineNumber}: ${hit.rule}',
  ];
}

class _ProgressVisitor extends RecursiveAstVisitor<void> {
  _ProgressVisitor({required this.allowFrame, required this.rasterizer});

  final bool allowFrame;
  final bool rasterizer;
  final hits = <({int offset, String rule})>[];

  @override
  void visitComment(Comment node) {}

  void _property(SimpleIdentifier name) {
    if (name.name == 'endOfFrame' && !allowFrame) {
      hits.add((
        offset: name.offset,
        rule: 'gebruik waitForUiFrame met timeout',
      ));
    }
    if (name.name == 'scheduleTask') {
      hits.add((
        offset: name.offset,
        rule: 'scheduler-tear-off verbergt prioriteit',
      ));
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (rasterizer && node.methodName.name == 'precacheImage') {
      hits.add((
        offset: node.offset,
        rule: 'gebruik preloadExportImage met deadline en listener-opruiming',
      ));
    }
    if (node.methodName.name == 'scheduleTask') {
      final args = node.argumentList.arguments;
      final priority = args.length > 1 ? args[1].toSource() : '';
      if (!RegExp(
        r'^(?:\w+\.)?Priority\.(animation|touch)$',
      ).hasMatch(priority)) {
        hits.add((
          offset: node.offset,
          rule:
              'scheduleTask vereist expliciet animation/touch; '
              'gebruik een event-loop-yield voor laadwerk',
        ));
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _property(node.propertyName);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _property(node.identifier);
    super.visitPrefixedIdentifier(node);
  }
}
