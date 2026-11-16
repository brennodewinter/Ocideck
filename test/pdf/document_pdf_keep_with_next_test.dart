import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/document_pdf_widgets.dart';

import 'pdf_text_probe.dart';

const _textStyle = pw.TextStyle(fontSize: 10, lineSpacing: 2);

Future<Uint8List> _paragraphPdf(
  double filler,
  int lines, {
  double height = 200,
}) async {
  return _blocksPdf(
    [
      PdfParagraphBlock([
        PdfSpan(List.generate(lines, (i) => 'regel$i').join('\n')),
      ]),
    ],
    filler: filler,
    height: height,
  );
}

Future<Uint8List> _blocksPdf(
  List<PdfBlock> blocks, {
  double filler = 0,
  double height = 200,
}) async {
  final document = pw.Document();
  final style = DocumentPdfStyle.fromTheme(
    const ThemeProfile(documentBodyFontSize: 10),
  );
  final builder = DocumentPdfWidgets(
    style: style,
    fonts: DocumentPdfFonts.forFamily(''),
    headings: headingEntriesOf(blocks),
    verbatimLabel: (kind) => kind.name,
    maxImageWidth: 260,
    maxImageHeight: height,
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(300, height + 40, marginAll: 20),
      maxPages: 30,
      build: (_) => [
        if (filler > 0) pw.Text('Voor', style: _textStyle),
        if (filler > 0) pw.SizedBox(height: filler - 10),
        ...builder.build(blocks),
      ],
    ),
  );
  return document.save();
}

PdfTableBlock _table(int rows, {bool header = true}) => PdfTableBlock([
  for (var i = 0; i < rows; i++)
    [
      [PdfSpan(i == 0 && header ? 'Kolom' : 'cel$i')],
    ],
], hasHeader: header);

void main() {
  test('een enkele beginregel verhuist met de volgende regel', () async {
    final pages = pdfVisibleTextPerPage(await _paragraphPdf(185, 5));
    expect(pages[0], isNot(contains('regel0')));
    expect(pages[1], contains('regel0 regel1'));
    for (var i = 0; i < 5; i++) {
      expect(pages.join(' ').split('regel$i').length - 1, 1);
    }
  });

  test('een enkele slotregel krijgt een tweede regel mee', () async {
    final pages = pdfVisibleTextPerPage(await _paragraphPdf(158, 4));
    expect(pages[0], contains('regel0 regel1'));
    expect(pages[0], isNot(contains('regel2')));
    expect(pages[1], contains('regel2 regel3'));
  });

  test(
    'korte alinea blijft heel; eenregelige alinea blijft toegestaan',
    () async {
      for (final lines in [1, 2, 3]) {
        final pages = pdfVisibleTextPerPage(await _paragraphPdf(185, lines));
        expect(pages.where((p) => p.contains('regel')).length, 1);
      }
    },
  );

  test('lange alinea blijft volledig over veel paginas', () async {
    final bytes = await _paragraphPdf(0, 80);
    final pages = pdfVisibleTextPerPage(
      bytes,
    ).where((p) => p.trim().isNotEmpty).toList();
    expect(pdfPageCount(bytes), pages.length);
    expect(pages.length, greaterThan(2));
    for (var i = 0; i < 80; i++) {
      expect(RegExp('regel$i(?![0-9])').allMatches(pages.join(' ')).length, 1);
    }
    expect(
      pages.every((p) => RegExp('regel[0-9]+').allMatches(p).length >= 2),
      isTrue,
      reason: pages.toString(),
    );
  });

  test('te laag vers blad blijft voortgang maken', () async {
    final pages = pdfVisibleTextPerPage(await _paragraphPdf(0, 5, height: 18));
    expect(pages.join(' '), contains('regel4'));
    expect(pages.length, lessThan(10));
  });

  for (final level in [1, 2, 3]) {
    test('kop h$level reist met twee vervolgregels', () async {
      final pages = pdfVisibleTextPerPage(
        await _blocksPdf([
          PdfHeadingBlock(level, const [PdfSpan('Kop')], 'Kop'),
          const PdfParagraphBlock([PdfSpan('regel0\nregel1\nregel2\nregel3')]),
        ], filler: 160),
      );
      final page = pages.singleWhere((p) => p.contains('Kop'));
      expect(page, contains('regel0 regel1'));
    });
  }

  test('kop met korte tabel reist als geheel', () async {
    final pages = pdfVisibleTextPerPage(
      await _blocksPdf([
        const PdfHeadingBlock(2, [PdfSpan('Ankerpunten')], 'Ankerpunten'),
        _table(5),
      ], filler: 110),
    );
    final page = pages.singleWhere((p) => p.contains('Ankerpunten'));
    expect(page, contains('Kolom'));
    expect(page, contains('cel4'));
  });

  test('kop bij lange tabel krijgt kolomkop en gegevensrij mee', () async {
    final pages = pdfVisibleTextPerPage(
      await _blocksPdf([
        const PdfHeadingBlock(2, [PdfSpan('Ankerpunten')], 'Ankerpunten'),
        _table(40),
      ], filler: 155),
    );
    final page = pages.singleWhere((p) => p.contains('Ankerpunten'));
    expect(page, contains('Kolom'));
    expect(page, contains('cel1'));
    for (var i = 1; i < 40; i++) {
      expect(RegExp('cel$i(?![0-9])').allMatches(pages.join(' ')).length, 1);
    }
  });

  test('tabel zonder kolomkop houdt eerste gegevensrij bij kop', () async {
    final pages = pdfVisibleTextPerPage(
      await _blocksPdf([
        const PdfHeadingBlock(2, [PdfSpan('Tabel')], 'Tabel'),
        _table(40, header: false),
      ], filler: 165),
    );
    expect(pages.singleWhere((p) => p.contains('Tabel')), contains('cel0'));
  });

  test('kop respecteert expliciet pagina-einde', () async {
    final pages = pdfVisibleTextPerPage(
      await _blocksPdf(const [
        PdfHeadingBlock(2, [PdfSpan('Kop')], 'Kop'),
        PdfPageBreakBlock(),
        PdfParagraphBlock([PdfSpan('Na')]),
      ]),
    );
    expect(pages[0], contains('Kop'));
    expect(pages[0], isNot(contains('Na')));
    expect(pages[1], contains('Na'));
  });
  test(
    'kop blijft staan als twee gemeten regels van een lange alinea passen',
    () async {
      final pages = pdfVisibleTextPerPage(
        await _blocksPdf([
          const PdfHeadingBlock(2, [PdfSpan('Kop')], 'Kop'),
          PdfParagraphBlock([
            PdfSpan('Lange alinea met veel gewone woorden. ' * 70),
          ]),
        ], filler: 145),
      );
      expect(pages[0], contains('Kop'));
      expect(pages[0], contains('Lange alinea'));
    },
  );
  test(
    'opgemaakte apostrofwoorden tellen mee als werkelijk getekende regels',
    () async {
      for (final height in [50.0, 60.0, 75.0]) {
        for (final count in [13, 19, 37, 91]) {
          final bytes = await _blocksPdf([
            PdfParagraphBlock([
              for (var i = 0; i < count; i++) ...[
                const PdfSpan("foto'"),
                const PdfSpan('s', bold: true),
                const PdfSpan(' '),
              ],
            ]),
          ], height: height);
          final lines = pdfLineCountsPerPage(bytes);
          expect(lines.length, pdfPageCount(bytes));
          expect(
            lines.every((n) => n >= 2),
            isTrue,
            reason: '$count woorden op $height punten: $lines',
          );
        }
      }
    },
  );
  test('kop blijft bij een passend codeblok', () async {
    final pages = pdfVisibleTextPerPage(
      await _blocksPdf(const [
        PdfHeadingBlock(2, [PdfSpan('Voorbeeld')], 'Voorbeeld'),
        PdfCodeBlock('eerste\ntweede\nderde'),
      ], filler: 155),
    );
    expect(
      pages.singleWhere((p) => p.contains('Voorbeeld')),
      contains('derde'),
    );
  });
}
