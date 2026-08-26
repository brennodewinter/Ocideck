// Toetst de kolombreedte-keuze van de PDF-tabel: welke kolommen op hun inhoud
// passen (intrinsic) en welke de resterende ruimte nemen (flex).
//
// De oude standaard — alles intrinsic — perste smalle kolommen plat zodra een
// prozakolom de tabel breder dreigde te maken dan het blad: de tekst kwam er
// verticaal in te staan. Deze test bewaakt dat er dan minstens één flex-kolom
// is en dat de smalle kolommen intrinsic blijven.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_table_widths.dart';

List<List<List<PdfSpan>>> _table(List<List<String>> cells) => [
  for (final row in cells)
    [
      for (final cell in row) [PdfSpan(cell)],
    ],
];

void main() {
  // Bladspiegel van A4 (210 mm) met standaardranden, in punten — de maat die
  // de renderer als `maxImageWidth` meegeeft.
  const tableWidth = 481.9;
  const fontSize = 10.0;
  const cellPadding = 4.0;

  test('een korte tabel past alles intrinsic — geen flex nodig', () {
    final widths = pdfTableColumnWidths(
      rows: _table([
        ['Maatregel', 'Score'],
        ['Logging', '61'],
      ]),
      colCount: 2,
      tableWidth: tableWidth,
      fontSize: fontSize,
      cellPadding: cellPadding,
    );
    expect(widths.length, 2);
    expect(widths[0], isA<pw.IntrinsicColumnWidth>());
    expect(widths[1], isA<pw.IntrinsicColumnWidth>());
  });

  test('een prozakolom krijgt flex, smalle kolommen blijven intrinsic — '
      'geen verticale stapeling meer', () {
    // De vorm van de RWM-zorgplichttabel: een smalle nr-kolom, een
    // oordeel-kolom met een kort label, en een prozakolom die op één regel
    // veel breder is dan het blad.
    final widths = pdfTableColumnWidths(
      rows: _table([
        ['Nr', 'Oordeel', 'Toelichting'],
        [
          '1',
          'Onvoldoende',
          'Een zeer lange zin die de kolom op één regel breder maakt dan de '
              'hele bladspiegel, zodat de smalle kolommen onder de oude '
              'standaard werden samengeperst tot één teken per regel.',
        ],
      ]),
      colCount: 3,
      tableWidth: tableWidth,
      fontSize: fontSize,
      cellPadding: cellPadding,
    );
    // De prozakolom flext; de smalle kolommen passen op hun inhoud.
    expect(widths[0], isA<pw.IntrinsicColumnWidth>());
    expect(widths[1], isA<pw.IntrinsicColumnWidth>());
    expect(widths[2], isA<pw.FlexColumnWidth>());
    // Minstens één flex-kolom is precies wat de pro rato-samendrukking
    // uitschakelt — de stapeling van vroeger.
    expect(
      widths.values.whereType<pw.FlexColumnWidth>().length,
      greaterThanOrEqualTo(1),
    );
  });

  test(
    'het flex-gewicht volgt de geschatte woordbreedte, niet het tekenaantal',
    () {
      // Twee flex-kolommen: de ene met een lang woord, de andere met korte
      // woorden in een lange cel. De kolom met het lange woord moet zwaarder
      // wegen — anders breekt dat woord midden in af. Kunstmatig smal blad
      // zodat beide kolommen flex worden.
      final widths = pdfTableColumnWidths(
        rows: _table([
          ['Zorgplichtmaatregel', 'korte woorden in een lange zin'],
          ['Bedrijfscontinuïteit', 'nog meer korte woorden hier'],
        ]),
        colCount: 2,
        tableWidth: 60,
        fontSize: fontSize,
        cellPadding: cellPadding,
      );
      final w0 = widths[0] as pw.FlexColumnWidth;
      final w1 = widths[1] as pw.FlexColumnWidth;
      // "Bedrijfscontinuïteit" (brede tekens) moet zwaarder wegen dan "woorden"
      // (smalle tekens), zelfs als het tekenaantal verschilt.
      expect(w0.flex, greaterThan(w1.flex));
    },
  );

  test('vetgedrukte tekst krijgt meer flex-gewicht dan gewone tekst', () {
    // Twee identieke kolommen, maar de ene is vetgedrukt. Vet is ~10 % breder
    // per teken, dus de vetgedrukte kolom moet zwaarder wegen.
    final widths = pdfTableColumnWidths(
      rows: [
        [
          [PdfSpan('Onvoldoende', bold: true)],
          [PdfSpan('Onvoldoende')],
        ],
      ],
      colCount: 2,
      tableWidth: 50, // kunstmatig smal blad → beide kolommen flex
      fontSize: fontSize,
      cellPadding: cellPadding,
    );
    final wBold = widths[0] as pw.FlexColumnWidth;
    final wRegular = widths[1] as pw.FlexColumnWidth;
    expect(wBold.flex, greaterThan(wRegular.flex));
  });

  test('een tabel waar elke kolom breed is flext er meer dan één', () {
    final widths = pdfTableColumnWidths(
      rows: _table([
        ['Eerste kolom', 'Tweede kolom'],
        [
          List<String>.filled(120, 'a').join(),
          List<String>.filled(120, 'b').join(),
        ],
      ]),
      colCount: 2,
      tableWidth: tableWidth,
      fontSize: fontSize,
      cellPadding: cellPadding,
    );
    expect(
      widths.values.whereType<pw.FlexColumnWidth>().length,
      greaterThanOrEqualTo(1),
    );
    // Geen enkele kolom mag intrinsic blijven als ze in haar eentje het blad
    // al vult — anders drukt ze de flex-buren alsnog plat.
    expect(widths[0], isA<pw.FlexColumnWidth>());
    expect(widths[1], isA<pw.FlexColumnWidth>());
  });

  test('een tabel met alleen smalle kolommen flext allebei', () {
    // Alle kolommen zijn smal maar samen breder dan het kunstmatig smalle
    // blad: de iteratieve lus maakt ze allebei flex, want de 40 %-grens wordt
    // niet gehaald voordat alle kolommen flex zijn. Dat is correct — op een
    // smal blad moet elke kolom afbreken, anders past de tabel niet.
    final widths = pdfTableColumnWidths(
      rows: _table([
        ['Nr', 'OK'],
        ['1', 'Ja'],
        ['2', 'Nee'],
      ]),
      colCount: 2,
      tableWidth: 30, // kunstmatig smal blad
      fontSize: fontSize,
      cellPadding: cellPadding,
    );
    expect(widths[0], isA<pw.FlexColumnWidth>());
    expect(widths[1], isA<pw.FlexColumnWidth>());
  });

  test('een lege tabel levert geen kolombreedtes op', () {
    expect(
      pdfTableColumnWidths(
        rows: const [],
        colCount: 0,
        tableWidth: tableWidth,
        fontSize: fontSize,
        cellPadding: cellPadding,
      ),
      isEmpty,
    );
  });
}
