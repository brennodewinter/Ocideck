import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;

import '../../utils/deck_text_search.dart';
import 'editor_text_controller.dart';
import 'deck_search_target.dart';
import '../reader/document_search_overlay.dart';

/// De zoekmarkering blijft zichtbaar terwijl het zoekveld de toetsen ontvangt.
class DeckSearchHighlight extends StatelessWidget {
  const DeckSearchHighlight({
    super.key,
    required this.match,
    required this.child,
  });

  final DeckTextMatch? match;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _SearchPainter(
      context: context,
      match: match,
      color: Theme.of(context).colorScheme.primary,
    ),
    child: child,
  );
}

class _SearchPainter extends CustomPainter {
  const _SearchPainter({
    required this.context,
    required this.match,
    required this.color,
  });

  final BuildContext context;
  final DeckTextMatch? match;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final target = match;
    final root = context.findRenderObject();
    if (target == null || root is! RenderBox) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    void visit(Element element) {
      if (element.widget case Offstage(offstage: true)) return;
      if (element.widget case ExcludeDocumentSearch(exclude: true)) return;
      if (element.widget case EditableText(:final controller)) {
        if ((controller is EditorTextController
                    ? controller.searchFieldId
                    : SearchFieldAnchor.fieldOf(element)) ==
                target.fieldId &&
            controller.text == target.text) {
          final state = (element as StatefulElement).state as EditableTextState;
          final editable = state.renderEditable;
          final selection = TextSelection(
            baseOffset: target.range.start,
            extentOffset: target.range.end,
          );
          final origin = root.globalToLocal(
            editable.localToGlobal(Offset.zero),
          );
          canvas.save();
          canvas.clipRect(editable.paintBounds.shift(origin));
          for (final box in editable.getBoxesForSelection(selection)) {
            final rect = box.toRect().shift(origin).inflate(1);
            canvas.drawRect(
              rect,
              Paint()..color = color.withValues(alpha: 0.16),
            );
            canvas.drawRect(
              rect,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
          canvas.restore();
        }
      }
      if (element.widget case RichText(:final text)) {
        if (SearchFieldAnchor.fieldOf(element) == target.fieldId) {
          final plain = text.toPlainText();
          final start = plain.indexOf(target.text);
          final paragraph = element.findRenderObject();
          if (start >= 0 && paragraph is RenderParagraph && paragraph.hasSize) {
            final origin = root.globalToLocal(
              paragraph.localToGlobal(Offset.zero),
            );
            final selection = TextSelection(
              baseOffset: start + target.range.start,
              extentOffset: start + target.range.end,
            );
            for (final box in paragraph.getBoxesForSelection(selection)) {
              final rect = box.toRect().shift(origin).inflate(1);
              canvas.drawRect(
                rect,
                Paint()..color = color.withValues(alpha: 0.16),
              );
              canvas.drawRect(
                rect,
                Paint()
                  ..color = color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5,
              );
            }
          }
        }
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SearchPainter oldDelegate) => true;
}
