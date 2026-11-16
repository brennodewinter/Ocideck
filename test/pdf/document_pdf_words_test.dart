import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_widgets.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/pdf/document_pdf_words.dart';

import 'pdf_text_probe.dart';

void main() {
  for (final word in ['thema’s', "foto's", 'Piskorz-Ryńs']) {
    test('$word verhuist als heel woord naar de volgende regel', () async {
      final fonts = DocumentPdfFonts.forFamily(
        '',
        fallbackFonts: [
          File(
            'assets/fonts/Roboto-Variable.ttf',
          ).readAsBytesSync().buffer.asByteData(),
        ],
      );
      final style = pw.TextStyle(
        font: fonts.base,
        fontFallback: fonts.fallback,
        fontBold: fonts.bold,
        fontItalic: fonts.italic,
        fontSize: 12,
        lineSpacing: 3,
      );
      final apostrophe = word.indexOf(RegExp("['’]"));
      final split = apostrophe < 0 ? word.length - 1 : apostrophe + 1;
      final parts = [
        const PdfSpan('WWWW WWWW '),
        PdfSpan(word.substring(0, split)),
        PdfSpan(word.substring(split), bold: true, href: 'https://librekat.nl'),
      ];
      final spans = pdfApostropheWords(
        parts,
        style: style,
        render: (s) => pw.TextSpan(
          text: s.text,
          style: pw.TextStyle(fontWeight: s.bold ? pw.FontWeight.bold : null),
          annotation: s.href == null ? null : pw.AnnotationUrl(s.href!),
        ),
      );
      // Ook een bezitsvorm zonder apostrof blijft een gewoon woord; alleen
      // de apostrofgevallen hebben een afzonderlijk inline-kader nodig.
      if (apostrophe < 0) {
        expect(spans.whereType<pw.WidgetSpan>(), isEmpty);
        return;
      }
      final atomic = spans.whereType<pw.WidgetSpan>().single.child;
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(130, 200, marginAll: 10),
          build: (_) => pw.RichText(
            text: pw.TextSpan(style: style, children: spans),
          ),
        ),
      );
      final bytes = await document.save();
      expect(pdfPageCount(bytes), 1);
      expect(
        atomic.box!.left,
        closeTo(10, .01),
        reason: 'Heel woord begint links op de volgende regel',
      );
      expect(atomic.box!.width, lessThanOrEqualTo(110));
      expect(
        atomic.box!.height,
        lessThan(20),
        reason: 'Het woord is zelf niet afgebroken',
      );
    });
  }

  test(
    'lange apostroftoken behoudt noodafbreking en export blijft eindig',
    () async {
      final text = "${'woord' * 80}'s";
      final spans = pdfApostropheWords(
        [PdfSpan(text)],
        style: const pw.TextStyle(fontSize: 10),
        render: (s) => pw.TextSpan(text: s.text),
      );
      expect(spans.whereType<pw.WidgetSpan>(), isEmpty);
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: const PdfPageFormat(200, 200, marginAll: 15),
          maxPages: 20,
          build: (_) => [
            pw.RichText(
              overflow: pw.TextOverflow.span,
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 10),
                children: spans,
              ),
            ),
          ],
        ),
      );
      final bytes = await document.save();
      expect(pdfPageCount(bytes), lessThan(10));
      expect(pdfVisibleText(bytes).replaceAll(' ', ''), contains(text));
    },
  );

  test('normale link behoudt een gedeelde annotatie en onderstreping', () {
    const input = [
      PdfSpan('Vier woorden lange link', href: 'https://librekat.nl'),
    ];
    final spans = pdfApostropheWords(
      input,
      style: const pw.TextStyle(),
      render: (s) =>
          pw.TextSpan(text: s.text, annotation: pw.AnnotationUrl(s.href!)),
    );
    expect(spans, hasLength(1));
  });
  test(
    'export houdt opgemaakte apostrofwoorden op dezelfde basislijn',
    () async {
      final fonts = DocumentPdfFonts.forFamily(
        '',
        fallbackFonts: [
          File(
            'assets/fonts/Roboto-Variable.ttf',
          ).readAsBytesSync().buffer.asByteData(),
        ],
      );
      final builder = DocumentPdfWidgets(
        style: DocumentPdfStyle.fromTheme(
          const ThemeProfile(documentBodyFontSize: 12),
        ),
        fonts: fonts,
        headings: const [],
        verbatimLabel: (kind) => kind.name,
        maxImageWidth: 110,
        maxImageHeight: 180,
      );
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: const PdfPageFormat(130, 200, marginAll: 10),
          build: (_) => builder.build(const [
            PdfParagraphBlock([
              PdfSpan('WWWWWW thema’'),
              PdfSpan('s', bold: true),
              PdfSpan(' slot'),
            ]),
          ]),
        ),
      );
      final bytes = await document.save();
      final thema = pdfTextBaselines(bytes, 'thema').single;
      expect(pdfTextBaselines(bytes, 's').single, closeTo(thema, .01));
      expect(pdfTextBaselines(bytes, 'slot').single, closeTo(thema, .01));
    },
  );
}
