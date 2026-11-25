// De `<!-- spacer -->`-marker (#2464): bewuste witruimte van één tekstregel,
// atomair in de editor en ter hoogte van een regel in elke export.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/utils/document_blank_lines.dart'
    show withDocumentBlankLineSpacers;
import 'package:ocideck/services/docx/markdown_to_docx.dart';
import 'package:ocideck/services/epub/markdown_to_xhtml.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';
import 'package:ocideck/services/odt/markdown_to_odt.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';
import 'package:ocideck/utils/markdown_caret_map.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';
import 'package:ocideck/utils/spacer_embed_syntax.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart'
    show DocumentMarkdownView, documentForcedPageBreaks;

void main() {
  group('extra lege regels tussen documentblokken', () {
    test('de adressering krijgt twee extra regels vóór het onderwerp', () {
      const source = 'Geadresseerde.\n\n\n\n**Onderwerp.**\n';
      const expected =
          'Geadresseerde.\n\n$spacerMarker\n\n$spacerMarker\n\n**Onderwerp.**\n';
      expect(withDocumentBlankLineSpacers(source), expected);
      expect(withDocumentBlankLineSpacers(expected), expected);
      expect(DocumentMarkdownView.blockTexts(source), [
        'Geadresseerde.',
        '',
        '',
        '**Onderwerp.**',
      ]);
      expect(
        withDocumentBlankLineSpacers(source.replaceAll('\n', '\r\n')),
        expected.replaceAll('\n', '\r\n'),
      );
    });

    test('omzetting bewaart lege regels binnen een blok', () {
      const fenced = '~~~text\nA\n\n\nB\n~~~\n';
      const indented = '    A\n\n\n    B\n';
      const math = '\$\$\nA\n\n\nB\n\$\$\n';
      const list = '- A\n\n\n- B\n';
      const metadata =
          '<!-- ocideck:plain_table v1 -->\n\n\n| A |\n| - |\n| B |\n';
      for (final source in [fenced, indented, math, list, metadata]) {
        expect(withDocumentBlankLineSpacers(source), source);
      }
    });

    test('extra ruimte overleeft een kopgrens in alle exports', () async {
      const source = 'Geadresseerde.\n\n\n\n# Onderwerp\n\nDe brief.\n';
      final bundle = await buildDocumentExportBundle(
        source,
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      expect(
        markdownToPdfBlocks(
          projectedDocumentBody(bundle),
        ).whereType<PdfSpacerBlock>(),
        hasLength(2),
      );

      final html = MarpHtmlService(
        loadAsset: (path) => File(path).readAsString(),
      );
      for (final format in DocumentExportFormat.values) {
        final bytes = await buildDocumentExportBytes(
          bundle,
          format,
          html: html,
        );
        final archiveEntry = switch (format) {
          DocumentExportFormat.epub => 'OEBPS/document.xhtml',
          DocumentExportFormat.odt => 'content.xml',
          DocumentExportFormat.docx => 'word/document.xml',
          _ => null,
        };
        final text = archiveEntry == null
            ? String.fromCharCodes(bytes)
            : String.fromCharCodes(
                ZipDecoder().decodeBytes(bytes).findFile(archiveEntry)!.content,
              );
        final pattern = switch (format) {
          DocumentExportFormat.md => spacerMarker,
          DocumentExportFormat.html =>
            'Geadresseerde.\n\n&nbsp;\n\n&nbsp;\n\n# Onderwerp',
          DocumentExportFormat.latex => r'\vspace{\baselineskip}',
          DocumentExportFormat.epub => '<p>&#160;</p>',
          DocumentExportFormat.odt =>
            '<text:p text:style-name="Standard"></text:p>',
          DocumentExportFormat.docx =>
            '<w:p><w:r><w:t xml:space="preserve"></w:t></w:r></w:p>',
          DocumentExportFormat.pdf => '%PDF-',
        };
        final count = switch (format) {
          DocumentExportFormat.html || DocumentExportFormat.pdf => 1,
          _ => 2,
        };
        expect(pattern.allMatches(text), hasLength(count), reason: format.name);
      }
    });
  });

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

    test('een lege regel typen in de visuele editor blijft één lege regel', () {
      final typed = Document.fromDelta(Delta()..insert('A.\n\nB.\n'));
      const expected = 'A.\n\n$spacerMarker\n\nB.';
      final markdown = MarkdownQuillCodec.markdownFromDocument(
        typed,
        preserveDocumentSpacing: true,
      );
      expect(markdown, expected);
      for (final source in [markdown, 'A.\n\n\nB.']) {
        final reopened = MarkdownQuillCodec.documentFromMarkdown(
          source,
          preserveDocumentSpacing: true,
        );
        final caret = MarkdownCaretMap.of(
          source,
          preserveDocumentSpacing: true,
        );
        final sourceOffset = source.indexOf('B.');
        final visualOffset = reopened.toPlainText().indexOf('B.');
        expect(caret.visualOffsetOf(sourceOffset), visualOffset);
        expect(caret.sourceOffsetOf(visualOffset), sourceOffset);
        expect(
          MarkdownQuillCodec.markdownFromDocument(
            reopened,
            preserveDocumentSpacing: true,
          ),
          expected,
        );
      }
      expect(
        MarkdownQuillCodec.markdownFromDocument(typed),
        isNot(contains(spacerMarker)),
      );
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
      expect(sourceFragmentRanges(source), isEmpty);
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
