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

  group('toggleInlineFormat (#2866)', () {
    TextEditingController ctrl(
      String text, [
      TextSelection sel = const TextSelection.collapsed(offset: -1),
    ]) {
      final c = TextEditingController(text: text);
      c.selection = sel;
      return c;
    }

    test('omhult de selectie en houdt dezelfde inhoud geselecteerd', () {
      final c = ctrl(
        'dat staat volgende maand op het programma',
        const TextSelection(baseOffset: 10, extentOffset: 24),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '*', after: '*');
      expect(c.text, 'dat staat *volgende maand* op het programma');
      expect(c.selection.start, 11);
      expect(c.selection.end, 25);
      expect(c.selection.textInside(c.text), 'volgende maand');
    });

    test('opnieuw toepassen haalt de opmaak weg', () {
      final c = ctrl(
        'dat staat *volgende maand* op het programma',
        const TextSelection(baseOffset: 11, extentOffset: 25),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '*', after: '*');
      expect(c.text, 'dat staat volgende maand op het programma');
      expect(c.selection.textInside(c.text), 'volgende maand');
    });

    test('meegeselecteerde markers gaan ook weg', () {
      final c = ctrl(
        'dit is **vet** zo',
        const TextSelection(baseOffset: 7, extentOffset: 14),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'dit is vet zo');
      expect(c.selection.textInside(c.text), 'vet');
    });

    test('cursief-aan op alleen-vet voegt toe zonder vet te verliezen', () {
      final c = ctrl(
        'dit is **vet** zo',
        const TextSelection(baseOffset: 9, extentOffset: 12),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '*', after: '*');
      expect(c.text, 'dit is ***vet*** zo');
      expect(c.selection.textInside(c.text), 'vet');
    });

    test('cursief-uit op vet+cursief laat vet staan', () {
      final c = ctrl(
        'dit is ***vet*** zo',
        const TextSelection(baseOffset: 10, extentOffset: 13),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '*', after: '*');
      expect(c.text, 'dit is **vet** zo');
      expect(c.selection.textInside(c.text), 'vet');
    });

    test('vet-uit op vet+cursief laat cursief staan', () {
      final c = ctrl(
        'dit is ***vet*** zo',
        const TextSelection(baseOffset: 10, extentOffset: 13),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'dit is *vet* zo');
      expect(c.selection.textInside(c.text), 'vet');
    });

    test('zonder selectie: leeg markerpaar met cursor ertussen', () {
      final c = ctrl('titel', const TextSelection.collapsed(offset: 2));
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'ti****tel');
      expect(c.selection, const TextSelection.collapsed(offset: 4));
    });

    test('onderstrepen gebruikt de <u>-conventie', () {
      final c = ctrl(
        'belangrijk stuk',
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '<u>', after: '</u>');
      expect(c.text, '<u>belangrijk</u> stuk');
      MarkdownEditorActions.toggleInlineFormat(c, before: '<u>', after: '</u>');
      expect(c.text, 'belangrijk stuk');
    });

    test('omgekeerde selectie behoudt zijn richting', () {
      final c = ctrl(
        'een selectie',
        const TextSelection(baseOffset: 12, extentOffset: 4),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'een **selectie**');
      expect(c.selection.baseOffset, greaterThan(c.selection.extentOffset));
      expect(c.selection.textInside(c.text), 'selectie');
    });

    test('unicode en emoji in de selectie blijven intact', () {
      final c = ctrl(
        'dag 🚀 nacht',
        const TextSelection(baseOffset: 4, extentOffset: 6),
      );
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'dag **🚀** nacht');
      expect(c.selection.textInside(c.text), '🚀');
      MarkdownEditorActions.toggleInlineFormat(c, before: '**', after: '**');
      expect(c.text, 'dag 🚀 nacht');
    });
  });
}
