import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_actions.dart';

void main() {
  test('wrapSelection wraps selected text', () {
    final ctrl = TextEditingController(text: 'hello world');
    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    MarkdownEditorActions.wrapSelection(ctrl, before: '**', after: '**');
    expect(ctrl.text, '**hello** world');
  });

  test('toggleBullet prefixes the current line', () {
    final ctrl = TextEditingController(text: 'item one\nitem two');
    ctrl.selection = const TextSelection.collapsed(offset: 3);
    MarkdownEditorActions.toggleBullet(ctrl);
    expect(ctrl.text, '- item one\nitem two');
  });

  test('indentSelection indents every selected line', () {
    final ctrl = TextEditingController(text: '- een\n- twee');
    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 12);

    MarkdownEditorActions.indentSelection(ctrl);

    expect(ctrl.text, '  - een\n  - twee');
  });

  test('outdentSelection removes up to two spaces', () {
    final ctrl = TextEditingController(text: '  - een\n - twee');
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: ctrl.text.length,
    );

    MarkdownEditorActions.outdentSelection(ctrl);

    expect(ctrl.text, '- een\n- twee');
  });

  test('insertTable inserts a complete valid Markdown table skeleton', () {
    final ctrl = TextEditingController(text: 'ervoor\nerna');
    ctrl.selection = const TextSelection.collapsed(offset: 7);

    MarkdownEditorActions.insertTable(ctrl);

    expect(ctrl.text, contains('| Kolom 1 | Kolom 2 |'));
    expect(ctrl.text, contains('| --- | --- |'));
  });
}
