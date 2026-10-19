// De `<!-- spacer -->`-marker (#2464): bewuste witruimte van één tekstregel,
// atomair in de editor en ter hoogte van een regel in elke export.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/docx/markdown_to_docx.dart';
import 'package:ocideck/services/epub/markdown_to_xhtml.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';
import 'package:ocideck/services/odt/markdown_to_odt.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';
import 'package:ocideck/utils/spacer_embed_syntax.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart'
    show DocumentMarkdownView, documentForcedPageBreaks;

void main() {
  group('codec', () {
    test('de marker wordt een embed en komt er byte-getrouw weer uit', () {
      const source = 'Eerste alinea.\n\n<!-- spacer -->\n\nTweede alinea.\n';

      final document = MarkdownQuillCodec.documentFromMarkdown(source);

      final embeds = document
          .toDelta()
          .toList()
          .where((op) => op.data is Map)
          .map((op) => (op.data as Map).keys.first)
          .toList();
      expect(
        embeds,
        contains(EmbeddableSpacer.spacerType),
        reason: 'de marker moet als embed in het document staan',
      );

      final restored = MarkdownQuillCodec.markdownFromDocument(document);

      // Byte-getrouw: posities én hoeveelheid overleven opslaan en heropenen.
      expect(restored, source.trimRight());
    });

    test('meerdere markers geven meerdere regels ruimte', () {
      const source =
          'A.\n\n<!-- spacer -->\n\n<!-- spacer -->\n\n<!-- spacer -->\n\nB.\n';
      final document = MarkdownQuillCodec.documentFromMarkdown(source);
      final embeds = document
          .toDelta()
          .toList()
          .where((op) => op.data is Map)
          .toList();
      expect(embeds.length, 3);
      expect(
        MarkdownQuillCodec.markdownFromDocument(document),
        source.trimRight(),
      );
    });

    test('de marker verandert niets aan de blokken eromheen', () {
      // Een spacer tussen lijst, tabel en kop mag die niet afbreken of hun
      // inhoud aanraken.
      const source =
          '- een\n- twee\n\n<!-- spacer -->\n\n## Kop\n\n'
          '| a | b |\n| - | - |\n| 1 | 2 |\n';
      final document = MarkdownQuillCodec.documentFromMarkdown(source);
      final restored = MarkdownQuillCodec.markdownFromDocument(document);
      expect(restored, contains('- een'));
      expect(restored, contains('## Kop'));
      expect(restored, contains('| a | b |'));
      expect(restored, contains('<!-- spacer -->'));
    });
  });

  group('visuele verenigbaarheid', () {
    test('de marker dwingt niet terug naar bronmodus', () {
      const source = 'A\n\n<!-- spacer -->\n\nB\n';
      expect(markdownVisualLimitations(source), isEmpty);
    });
  });

  group('leesweergave', () {
    test('de marker levert geen doorzoekbare tekst op', () {
      final texts = DocumentMarkdownView.blockTexts(
        'Voor.\n\n<!-- spacer -->\n\nNa.\n',
      );
      expect(texts.where((t) => t.contains('spacer')), isEmpty);
      expect(texts.any((t) => t.contains('Voor.')), isTrue);
      expect(texts.any((t) => t.contains('Na.')), isTrue);
    });

    test('een spacer na een scheiding geeft geen leeg vel', () {
      // `---` + spacer + kop mocht niet uiteenvallen naar een pagina met
      // alleen witruimte: de spacer is ruimte, geen inhoud.
      final breaks = documentForcedPageBreaks(
        'Pagina een.\n\n---\n\n<!-- spacer -->\n\n# Hoofdstuk\n\nTekst.\n',
        chapterBreak: true,
      );
      // Eén breuk (de ---), niet twee: spacer en kop staan samen op het vel.
      expect(breaks.length, 1);
    });

    test('een spacer aan het begin geeft geen lege eerste pagina', () {
      final breaks = documentForcedPageBreaks(
        '<!-- spacer -->\n\n# Hoofdstuk\n\nTekst.\n',
        chapterBreak: true,
      );
      expect(breaks, isEmpty);
    });
  });

  group('exports', () {
    const source = 'Voor.\n\n<!-- spacer -->\n\nNa.\n';

    test('pdf: de marker wordt een eigen spacerblok', () {
      final blocks = markdownToPdfBlocks(source);
      expect(blocks.any((b) => b is PdfSpacerBlock), isTrue);
      // De sentinel lekt niet als tekst het document in.
      for (final block in blocks.whereType<PdfParagraphBlock>()) {
        for (final span in block.spans) {
          expect(span.text, isNot(contains('OCIDECK')));
          expect(span.text, isNot(contains('spacer')));
        }
      }
    });

    test('latex: de marker wordt verticale ruimte van een regel', () {
      final out = markdownToLatex(source);
      expect(out, contains(r'\vspace{\baselineskip}'));
      expect(out, isNot(contains('OCIDECK')));
      expect(out, isNot(contains('<!--')));
    });

    test('odt: de marker wordt een lege alinea, geen tekst', () {
      final conv = markdownToOdtBody(source);
      expect(conv.body, isNot(contains('OCIDECK')));
      expect(conv.body, isNot(contains('spacer')));
      expect(conv.body, isNot(contains('<!--')));
      // De lege alinea blijft staan als de regel extra ruimte.
      expect(conv.body, contains('<text:p'));
    });

    test('docx: de marker wordt een lege alinea, geen tekst', () {
      final conv = markdownToDocxBody(source);
      expect(conv.body, isNot(contains('OCIDECK')));
      expect(conv.body, isNot(contains('spacer')));
      expect(conv.body, isNot(contains('<!--')));
    });

    test('epub: de marker wordt een lege alinea die niet samenvouwt', () {
      final out = markdownToXhtml(source);
      expect(out, contains('<p>&#160;</p>'));
      expect(out, isNot(contains('OCIDECK')));
      expect(out, isNot(contains('<!-- spacer -->')));
    });
  });
}
