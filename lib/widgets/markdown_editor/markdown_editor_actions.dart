import 'package:material_ui/material_ui.dart';

/// Text-editing helpers for wrapping selections and toggling line prefixes.
class MarkdownEditorActions {
  MarkdownEditorActions._();

  static void wrapSelection(
    TextEditingController controller, {
    required String before,
    required String after,
    String placeholder = '',
  }) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final text = controller.text;
    final selected = sel.textInside(text);
    final inner = selected.isEmpty ? placeholder : selected;
    final replacement = '$before$inner$after';
    final newText = text.replaceRange(sel.start, sel.end, replacement);
    final cursor = sel.start + before.length + inner.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static void insertLink(TextEditingController controller) {
    wrapSelection(
      controller,
      before: '[',
      after: '](url)',
      placeholder: 'tekst',
    );
  }

  static void insertImage(TextEditingController controller) {
    wrapSelection(
      controller,
      before: '![',
      after: '](pad-of-url)',
      placeholder: 'beschrijving',
    );
  }

  static void insertTable(TextEditingController controller) {
    _replaceSelection(
      controller,
      '| Kolom 1 | Kolom 2 |\n| --- | --- |\n| Waarde | Waarde |',
    );
  }

  static void insertTask(TextEditingController controller) {
    toggleLinePrefix(
      controller,
      '- [ ] ',
      stripLeading: RegExp(r'^(- \[[ xX]\] |- |\d+\.\s+)'),
    );
  }

  static void _replaceSelection(
    TextEditingController controller,
    String replacement,
  ) {
    final selection = controller.selection;
    if (!selection.isValid) return;
    final updated = controller.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
  }

  static void toggleLinePrefix(
    TextEditingController controller,
    String prefix, {
    RegExp? stripLeading,
  }) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final text = controller.text;
    final start = _lineStart(text, sel.start);
    final end = _lineEnd(text, sel.end);
    final block = text.substring(start, end);
    final lines = block.split('\n');
    final strip = stripLeading ?? RegExp(r'^(- |\d+\.\s+|#{1,6}\s+)');
    final togglingOff = lines.every((line) => line.startsWith(prefix));
    final updated = lines
        .map((line) {
          if (togglingOff && line.startsWith(prefix)) {
            return line.substring(prefix.length);
          }
          if (togglingOff) return line;
          final stripped = line.replaceFirst(strip, '');
          return '$prefix$stripped';
        })
        .join('\n');
    final newText = text.replaceRange(start, end, updated);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + updated.length,
      ),
    );
  }

  static void toggleHeading(TextEditingController controller, int level) {
    final prefix = '${'#' * level.clamp(1, 6)} ';
    toggleLinePrefix(controller, prefix, stripLeading: RegExp(r'^#{1,6}\s+'));
  }

  static void toggleBullet(TextEditingController controller) {
    toggleLinePrefix(controller, '- ');
  }

  static void toggleNumbered(TextEditingController controller) {
    toggleLinePrefix(
      controller,
      '1. ',
      stripLeading: RegExp(r'^(\d+\.\s+|- )'),
    );
  }

  static void toggleQuote(TextEditingController controller) {
    toggleLinePrefix(
      controller,
      '> ',
      stripLeading: RegExp(r'^(> |#{1,6}\s+|[-*]\s+)'),
    );
  }

  static void insertCodeBlock(TextEditingController controller) {
    wrapSelection(
      controller,
      before: '```\n',
      after: '\n```',
      placeholder: 'code',
    );
  }

  /// Indents every selected source line without changing its Markdown content.
  static void indentSelection(
    TextEditingController controller, {
    String indentation = '  ',
  }) {
    _transformSelectedLines(
      controller,
      (line) => '$indentation$line',
      cursorDelta: indentation.length,
    );
  }

  /// Removes one tab or up to [spaces] leading spaces from selected lines.
  static void outdentSelection(
    TextEditingController controller, {
    int spaces = 2,
  }) {
    final selection = controller.selection;
    var removedAtCursor = 0;
    if (selection.isValid && selection.isCollapsed) {
      final start = _lineStart(controller.text, selection.extentOffset);
      final line = controller.text.substring(start);
      if (line.startsWith('\t')) {
        removedAtCursor = 1;
      } else {
        while (removedAtCursor < spaces &&
            removedAtCursor < line.length &&
            line[removedAtCursor] == ' ') {
          removedAtCursor++;
        }
      }
    }
    _transformSelectedLines(controller, (line) {
      if (line.startsWith('\t')) return line.substring(1);
      var remove = 0;
      while (remove < spaces && remove < line.length && line[remove] == ' ') {
        remove++;
      }
      return line.substring(remove);
    }, cursorDelta: -removedAtCursor);
  }

  static void _transformSelectedLines(
    TextEditingController controller,
    String Function(String) transform, {
    int cursorDelta = 0,
  }) {
    final selection = controller.selection;
    if (!selection.isValid) return;
    final text = controller.text;
    final start = _lineStart(text, selection.start);
    final end = _lineEnd(text, selection.end);
    final replacement = text
        .substring(start, end)
        .split('\n')
        .map(transform)
        .join('\n');
    final updated = text.replaceRange(start, end, replacement);
    final collapsed = selection.isCollapsed;
    controller.value = TextEditingValue(
      text: updated,
      selection: collapsed
          ? TextSelection.collapsed(
              offset: (selection.extentOffset + cursorDelta).clamp(
                0,
                updated.length,
              ),
            )
          : TextSelection(
              baseOffset: start,
              extentOffset: start + replacement.length,
            ),
    );
  }

  static int _lineStart(String text, int offset) {
    final clamped = offset.clamp(0, text.length);
    if (clamped == 0) return 0;
    final index = text.lastIndexOf('\n', clamped - 1);
    return index < 0 ? 0 : index + 1;
  }

  static int _lineEnd(String text, int offset) {
    final clamped = offset.clamp(0, text.length);
    final index = text.indexOf('\n', clamped);
    return index < 0 ? text.length : index;
  }
}
