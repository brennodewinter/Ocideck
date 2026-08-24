// Toetst de keep-with-next logica van de PDF-widgetslaag.
//
// De blokkenlaag beslist wát er op het blad komt; de widgetslaag beslist hoe
// die blokken samen worden gehouden. Een sub-hoofdstuk mag niet als wees
// onderaan een pagina staan — de widgetslaag bindt de kop aan het volgende
// blok in een [pw.Inseparable]. Deze test controleert dat die binding er is
// voor korte alinea's, en dat lange alinea's op woordgrens worden gesplitst
// zodat de kop altijd met minimaal een paar regels meereist (#1758).

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/document_pdf_widgets.dart';

void main() {
  DocumentPdfWidgets makeBuilder() {
    final style = DocumentPdfStyle.fromTheme(const ThemeProfile());
    return DocumentPdfWidgets(
      style: style,
      fonts: DocumentPdfFonts.forFamily(''),
      headings: const [],
      verbatimLabel: (kind) => 'bron: ${kind.name}',
      maxImageWidth: 400,
      maxImageHeight: 600,
    );
  }

  /// Telt hoeveel [pw.Inseparable] widgets in de lijst staan — de widget
  /// die een kop aan zijn volgende blok bindt.
  int inseparableCount(List<pw.Widget> widgets) => widgets
      .where((w) => w.runtimeType.toString().contains('Inseparable'))
      .length;

  test('kop met korte alinea wordt gebonden in Inseparable', () {
    final builder = makeBuilder();
    final blocks = [
      const PdfHeadingBlock(2, [PdfSpan('Sub-kop')], 'Sub-kop'),
      const PdfParagraphBlock([PdfSpan('Korte alinea.')]),
    ];
    final widgets = builder.build(blocks);
    expect(inseparableCount(widgets), 1);
  });

  test(
    'kop met lange alinea wordt gesplitst: kop + eerste deel gebonden, rest los',
    () {
      final builder = makeBuilder();
      // Een alinea van >1200 tekens: de kop wordt gebonden aan het eerste deel,
      // de rest volgt als losse widget.
      final longText = List.generate(
        60,
        (i) => 'regel $i met wat tekst',
      ).join(' ');
      final blocks = [
        const PdfHeadingBlock(2, [PdfSpan('Sub-kop')], 'Sub-kop'),
        PdfParagraphBlock([PdfSpan(longText)]),
      ];
      final widgets = builder.build(blocks);
      // Er moet een Inseparable zijn (kop + eerste deel).
      expect(inseparableCount(widgets), 1);
      // De widget-lijst moet meer widgets bevatten dan alleen de Inseparable +
      // spacing — het tweede deel van de gesplitste alinea staat er los in.
      expect(widgets.length, greaterThan(2));
    },
  );

  test('kop zonder volgend blok wordt niet gebonden', () {
    final builder = makeBuilder();
    final blocks = [
      const PdfHeadingBlock(2, [PdfSpan('Sub-kop')], 'Sub-kop'),
    ];
    final widgets = builder.build(blocks);
    expect(inseparableCount(widgets), 0);
  });

  test('H1-kop wordt ook gebonden aan kort volgend blok', () {
    final builder = makeBuilder();
    final blocks = [
      const PdfHeadingBlock(1, [PdfSpan('Hoofdstuk')], 'Hoofdstuk'),
      const PdfParagraphBlock([PdfSpan('Korte alinea.')]),
    ];
    final widgets = builder.build(blocks);
    expect(inseparableCount(widgets), 1);
  });
}
