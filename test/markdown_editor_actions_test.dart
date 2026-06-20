import 'package:flutter/material.dart';
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
}
