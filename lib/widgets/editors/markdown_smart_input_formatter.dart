import 'package:flutter/services.dart';

/// Small source-preserving Markdown conveniences applied only to direct typing.
/// Paste and programmatic edits pass through unchanged.
class MarkdownSmartInputFormatter extends TextInputFormatter {
  const MarkdownSmartInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isCollapsed || !newValue.selection.isCollapsed) {
      return newValue;
    }
    final inserted = _insertedText(oldValue, newValue);
    if (inserted == '\n') return _continueLine(oldValue, newValue);
    final cursor = newValue.selection.extentOffset;
    if (const {']', ')', '}'}.contains(inserted) &&
        cursor < newValue.text.length &&
        newValue.text.substring(cursor, cursor + 1) == inserted) {
      return TextEditingValue(
        text: newValue.text.replaceRange(cursor - 1, cursor, ''),
        selection: TextSelection.collapsed(offset: cursor),
      );
    }
    if (inserted == '`') {
      final before = newValue.text.substring(0, cursor);
      final fenceStart = cursor - 3;
      if (before.endsWith('```') &&
          (fenceStart == 0 || newValue.text[fenceStart - 1] == '\n')) {
        const closingFence = '\n\n```';
        return TextEditingValue(
          text: newValue.text.replaceRange(cursor, cursor, closingFence),
          selection: TextSelection.collapsed(offset: cursor + 1),
        );
      }
      return newValue;
    }
    final closing = switch (inserted) {
      '[' => ']',
      '(' => ')',
      '{' => '}',
      _ => null,
    };
    if (closing == null) return newValue;
    return TextEditingValue(
      text: newValue.text.replaceRange(cursor, cursor, closing),
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  String? _insertedText(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length != oldValue.text.length + 1) return null;
    final cursor = newValue.selection.extentOffset;
    if (cursor <= 0 || cursor > newValue.text.length) return null;
    return newValue.text.substring(cursor - 1, cursor);
  }

  TextEditingValue _continueLine(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldCursor = oldValue.selection.extentOffset;
    final lineStart = oldValue.text.lastIndexOf('\n', oldCursor - 1) + 1;
    final line = oldValue.text.substring(lineStart, oldCursor);
    final match = RegExp(r'^(\s*)([-*+] |(\d+)\. |> )').firstMatch(line);
    if (match == null) return newValue;
    final prefix = '${match.group(1)}${match.group(2)}';
    if (line.substring(match.end).trim().isEmpty) {
      final text = newValue.text.replaceRange(lineStart, oldCursor, '');
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart + 1),
      );
    }
    final number = int.tryParse(match.group(3) ?? '');
    final nextPrefix = number == null
        ? prefix
        : '${match.group(1)}${number + 1}. ';
    final cursor = newValue.selection.extentOffset;
    return TextEditingValue(
      text: newValue.text.replaceRange(cursor, cursor, nextPrefix),
      selection: TextSelection.collapsed(offset: cursor + nextPrefix.length),
    );
  }
}
