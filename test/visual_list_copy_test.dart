import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/visual_paste_delta.dart';
import 'package:ocideck/utils/visual_selection_markdown.dart';

/// Regressie #2439: kopiëren binnen de visuele editor verloor de bullets en
/// de nummering van volledig geselecteerde lijstitems zodra de selectie niet
/// exact op een regelbegin startte. De plakroute kreeg dan platte tekst, en
/// die is één alinea.
Document _doc(String markdown) =>
    MarkdownQuillCodec.documentFromMarkdown(markdown);

/// Het attribuut [key] van elke regel, in volgorde (`null` = niet gezet).
/// Een regel eindigt op een `\n`; alleen die afsluiter draagt blokopmaak.
List<Object?> _lineAttrs(Document doc, String key) {
  final out = <Object?>[];
  for (final op in doc.toDelta().toList()) {
    final data = op.data;
    if (data is! String) continue;
    for (var i = 0; i < data.length; i++) {
      if (data[i] == '\n') out.add(op.attributes?[key]);
    }
  }
  return out;
}

List<Object?> _listKinds(Document doc) => _lineAttrs(doc, 'list');

/// Kopieer `start..end` uit [source] en plak het resultaat achter in een
/// leeg document, zoals de editor doet: klembord-Markdown → plak-delta.
Document _copyAndPaste(Document source, int start, int end) {
  final payload = visualClipboardPayload(source, start, end)!;
  final ops = operationsForVisualPaste(payload.markdown);
  final controller = QuillController(
    document: Document(),
    selection: const TextSelection.collapsed(offset: 0),
  );
  controller.replaceText(
    0,
    0,
    Delta.fromOperations(ops),
    const TextSelection.collapsed(offset: 0),
  );
  return controller.document;
}

/// Opslaan en heropenen: Document → Markdown → Document.
Document _reopen(Document d) => MarkdownQuillCodec.documentFromMarkdown(
  MarkdownQuillCodec.markdownFromDocument(d),
);

void main() {
  group('selectie die niet op een regelbegin start', () {
    test(
      'bullets: volgende volledig geselecteerde items houden hun bullet',
      () {
        final doc = _doc('- eerste\n- tweede\n- derde\n');
        // Vanaf het tweede teken van "eerste" tot het einde van het document.
        final payload = visualClipboardPayload(doc, 1, doc.length - 1)!;
        expect(payload.markdown, contains('- tweede'));
        expect(payload.markdown, contains('- derde'));
        expect(payload.markdown, startsWith('erste'));
      },
    );

    test('na plakken én opslaan/heropenen blijven de items bullets', () {
      final doc = _doc('- eerste\n- tweede\n- derde\n');
      final pasted = _copyAndPaste(doc, 1, doc.length - 1);
      expect(_listKinds(pasted).take(3), [null, 'bullet', 'bullet']);
      expect(_listKinds(_reopen(pasted)), [null, 'bullet', 'bullet']);
    });

    test('nummering blijft nummering, ook na heropenen', () {
      final doc = _doc('1. eerste\n2. tweede\n3. derde\n');
      final pasted = _copyAndPaste(doc, 2, doc.length - 1);
      expect(_listKinds(pasted).take(3), [null, 'ordered', 'ordered']);
      expect(_listKinds(_reopen(pasted)), [null, 'ordered', 'ordered']);
    });

    test('een takenlijst houdt de vinkjes van de volgende regels', () {
      final doc = _doc('- [ ] een\n- [x] twee\n- [ ] drie\n');
      final pasted = _copyAndPaste(doc, 1, doc.length - 1);
      expect(_listKinds(pasted).take(3), [null, 'checked', 'unchecked']);
    });

    test('genest: het inspringniveau van de volgende regels blijft', () {
      final doc = _doc('- eerste\n  - kind\n    - kleinkind\n- vierde\n');
      final payload = visualClipboardPayload(doc, 1, doc.length - 1)!;
      // Het eerste item begint hier op niveau 0: vier spaties vooraan zou een
      // codeblok zijn. De diepere items blijven relatief genest.
      expect(payload.markdown, 'erste\n\n- kind\n    - kleinkind\n- vierde');
      final pasted = _copyAndPaste(doc, 1, doc.length - 1);
      expect(_lineAttrs(pasted, 'indent').take(4), [null, null, 1, null]);
      expect(_listKinds(pasted).take(4), [null, 'bullet', 'bullet', 'bullet']);
    });

    test('een selectie vanaf een genest item begint geen codeblok', () {
      final doc = _doc('- eerste\n  - kind\n    - kleinkind\n- vierde\n');
      final kindStart = doc.toPlainText().indexOf('kind');
      final payload = visualClipboardPayload(doc, kindStart, doc.length - 1)!;
      expect(payload.markdown, '- kind\n    - kleinkind\n- vierde');
    });

    test(
      'een gedeeltelijke laatste regel houdt de lijst, zonder extra item',
      () {
        final doc = _doc('- eerste\n- tweede\n- derde\n');
        // Tot halverwege "derde".
        final end = doc.toPlainText().indexOf('derde') + 3;
        final pasted = _copyAndPaste(doc, 1, end);
        expect(_listKinds(pasted).take(3), [null, 'bullet', 'bullet']);
        expect(pasted.toPlainText(), startsWith('erste\ntweede\nder\n'));
      },
    );

    test('eindigt de selectie net na het regeleinde, dan komt er geen '
        'leeg lijstitem bij', () {
      final doc = _doc('- eerste\n- tweede\n');
      final firstLineEnd = doc.toPlainText().indexOf('\n');
      final payload = visualClipboardPayload(doc, 1, firstLineEnd + 1)!;
      expect(payload.markdown, 'erste');
    });

    test('gewone alinea’s blijven gescheiden alinea’s', () {
      final doc = _doc('eerste alinea\n\ntweede alinea\n');
      final pasted = _copyAndPaste(doc, 3, doc.length - 1);
      expect(_listKinds(pasted).take(2), [null, null]);
      expect(pasted.toPlainText(), startsWith('ste alinea\ntweede alinea\n'));
    });

    test('knippen wist precies de selectie en plakt niets extra weg', () {
      final doc = _doc('- eerste\n- tweede\n- derde\n');
      final payload = visualClipboardPayload(doc, 1, doc.length - 1)!;
      // Begint midden in de regel: de regelafsluiter van de laatste regel
      // blijft staan, anders plakt "e" aan het begin vast aan een volgende regel.
      expect(payload.start, 1);
      expect(payload.end, doc.length - 1);
    });
  });

  group('naburige gevallen blijven zoals ze waren', () {
    test('een deel van één regel is gewone tekst, zonder lijstteken', () {
      final doc = _doc('- [ ] een twee\n');
      final payload = visualClipboardPayload(doc, 5, 8)!;
      expect(payload.markdown, 'wee');
    });

    test('vanaf het regelbegin blijven de bullets zoals voorheen', () {
      final doc = _doc('- eerste\n- tweede\n');
      final payload = visualClipboardPayload(doc, 0, doc.length - 1)!;
      expect(payload.markdown, '- eerste\n- tweede');
    });

    test('lege of omgekeerde selectie geeft niets of dezelfde uitkomst', () {
      final doc = _doc('- eerste\n- tweede\n');
      expect(visualClipboardPayload(doc, 3, 3), isNull);
      final a = visualClipboardPayload(doc, 1, doc.length - 1)!;
      final b = visualClipboardPayload(doc, doc.length - 1, 1)!;
      expect(b.markdown, a.markdown);
    });
  });
}
