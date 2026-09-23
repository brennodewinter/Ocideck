import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_typing_shortcuts.dart';

/// Zet [text] in een verse Quill-document met de cursor achter [caretAt]
/// (standaard: meteen ná de tekst, zoals na de getypte spatie).
QuillController controllerWith(String text, {int? caretAt}) {
  final controller = QuillController(
    document: Document(),
    selection: const TextSelection.collapsed(offset: 0),
  );
  if (text.isNotEmpty) {
    controller.replaceText(
      0,
      0,
      text,
      TextSelection.collapsed(offset: caretAt ?? text.length),
    );
  }
  return controller;
}

String asMarkdown(QuillController controller) =>
    MarkdownQuillCodec.markdownFromDocument(controller.document);

void main() {
  group('applyMarkdownLineShortcut', () {
    test('`- [ ] ` wordt een open checklistitem', () {
      final controller = controllerWith('- [ ] ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(controller.document.toPlainText(), '\n');
      expect(
        controller.document.toDelta().toList().last.attributes,
        Attribute.unchecked.toJson(),
      );
      expect(asMarkdown(controller), '- [ ]');
    });

    test('`- [x] ` wordt een afgevinkt checklistitem', () {
      final controller = controllerWith('- [x] ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(asMarkdown(controller), '- [x]');
    });

    test('`- ` wordt een opsomming', () {
      final controller = controllerWith('- ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(asMarkdown(controller), '-');
    });

    test('`1. ` wordt een genummerde lijst', () {
      final controller = controllerWith('1. ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(asMarkdown(controller), '1.');
    });

    test('`> ` wordt een citaat', () {
      final controller = controllerWith('> ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(asMarkdown(controller), '>');
    });

    test('`## ` wordt een kop op het juiste niveau', () {
      final controller = controllerWith('## ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(asMarkdown(controller), '##');
    });

    test('`--- ` wordt een scheiding, geen tekst', () {
      final controller = controllerWith('--- ');

      expect(applyMarkdownLineShortcut(controller), isTrue);
      expect(
        controller.document.toDelta().toList().first.data,
        isA<Map<dynamic, dynamic>>(),
        reason: 'de regel moet een divider-embed dragen',
      );
      expect(asMarkdown(controller), contains('---'));
    });

    test('een trigger midden in een zin doet niets', () {
      final controller = controllerWith('tekst - [ ] ');

      expect(applyMarkdownLineShortcut(controller), isFalse);
      expect(controller.document.toPlainText(), 'tekst - [ ] \n');
    });

    test('een regel met blokopmaak verandert niet', () {
      final controller = controllerWith('- item');
      // Regel 2: `- [ ] ` getypt op een regel die al een bullet is — in een
      // lijst is dat letterlijke tekst, geen nieuwe trigger.
      controller.formatText(0, 5, Attribute.ul);
      controller.replaceText(
        6,
        0,
        '\n- [ ] ',
        const TextSelection.collapsed(offset: 13),
      );

      expect(applyMarkdownLineShortcut(controller), isFalse);
    });

    test('zonder trigger gebeurt niets', () {
      final controller = controllerWith('gewone tekst ');

      expect(applyMarkdownLineShortcut(controller), isFalse);
      expect(controller.document.toPlainText(), 'gewone tekst \n');
    });
  });
}
