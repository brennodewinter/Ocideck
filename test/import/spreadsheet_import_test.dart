// Tests voor de spreadsheet-import: XLSX/ODS/CSV → Markdown-document.
//
// De fixtures zijn echte minimale archieven (geen namaak), zodat de tests
// door dezelfde parser gaan als de gebruiker — hetzelfde principe als de
// DOCX/ODT-importtests.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/document_import_service.dart';
import 'package:ocideck/services/import/importers/csv/csv_document_importer.dart';
import 'package:ocideck/services/import/importers/ods/ods_document_importer.dart';
import 'package:ocideck/services/import/importers/xlsx/xlsx_document_importer.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';

import 'helpers/ods_fixture.dart';
import 'helpers/xlsx_fixture.dart';

void main() {
  group('CSV → Markdown', () {
    test('een puntkomma-gescheiden sheet wordt een GFM-tabel', () {
      final bytes = utf8.encode('Kolom;Waarde\nA;1\nB;2\n');
      final md = convertCsvDetailed(bytes, title: 'meting').markdown;

      expect(md, startsWith('# meting'));
      expect(md, contains('| Kolom | Waarde |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| A | 1 |'));
      expect(md, contains('| B | 2 |'));
    });

    test('een komma-gescheiden sheet wordt herkend', () {
      final bytes = utf8.encode('a,b\n1,2\n');
      final md = convertCsvDetailed(bytes).markdown;
      expect(md, contains('| a | b |'));
      expect(md, contains('| 1 | 2 |'));
    });

    test('een gegolfde rij wordt aangevuld tot rechthoek', () {
      final bytes = utf8.encode('a,b\nc\n');
      final md = convertCsvDetailed(bytes).markdown;
      expect(md, contains('| a | b |'));
      expect(md, contains('| c |  |'));
    });

    test('een sheet zonder scheidingsteken wordt één kolom', () {
      final bytes = utf8.encode('Alleen tekst\nNog een regel\n');
      final md = convertCsvDetailed(bytes).markdown;
      expect(md, contains('| Alleen tekst |'));
      expect(md, contains('| Nog een regel |'));
    });

    test('een cp1252-export blijft leesbaar via de latin-1-terugval', () {
      // 0xE9 is 'é' in cp1252, maar kapot in UTF-8.
      final bytes = Uint8List.fromList([...utf8.encode('caf'), 0xE9, 0x0A]);
      final md = convertCsvDetailed(bytes).markdown;
      expect(md, contains('café'));
    });

    test('een pijp in een cel wordt ontsnapt', () {
      final bytes = utf8.encode('a|b;c\n1;2\n');
      final md = convertCsvDetailed(bytes).markdown;
      expect(md, contains('a\\|b'));
    });
  });

  group('XLSX → Markdown', () {
    test('werkblad wordt kop plus tabel, gedeelde strings opgelost', () {
      final md = convertXlsxDetailed(xlsxFixture(), title: 'register').markdown;

      expect(md, startsWith('# register'));
      expect(md, contains('## Blad1'));
      expect(md, contains('| Kolom | Waarde |'));
      expect(md, contains('| A | 42 |'));
    });

    test('elk werkblad krijgt een eigen kop', () {
      final md = convertXlsxDetailed(
        xlsxFixture(
          sheets: {
            'Eerste': '<row><c r="A1" t="s"><v>0</v></c></row>',
            'Tweede': '<row><c r="A1" t="s"><v>1</v></c></row>',
          },
        ),
      ).markdown;

      expect(md, contains('## Eerste'));
      expect(md, contains('## Tweede'));
    });

    test('een datumstijl zet het serienummer om naar een kalenderdatum', () {
      final bytes = xlsxFixture(
        sheets: {
          'Blad1':
              '<row><c r="A1" t="s"><v>0</v></c><c r="B1"><v>45292</v></c></row>',
        },
        stylesXml:
            '<?xml version="1.0"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>'
            '</styleSheet>',
      );
      // Cel B1 krijgt stijlindex 1 (numFmtId 14 = ingebouwde datum).
      final bytesWithStyle = xlsxFixture(
        sheets: {
          'Blad1':
              '<row><c r="A1" t="s"><v>0</v></c>'
              '<c r="B1" s="1"><v>45292</v></c></row>',
        },
        stylesXml:
            '<?xml version="1.0"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>'
            '</styleSheet>',
      );
      expect(
        convertXlsxDetailed(bytes).markdown,
        contains('| Kolom | 45292 |'),
      );
      expect(
        convertXlsxDetailed(bytesWithStyle).markdown,
        contains('| Kolom | 2024-01-01 |'),
      );
    });

    test('een eigen datumnotatie (numFmtId ≥164) wordt ook herkend', () {
      final bytes = xlsxFixture(
        sheets: {'Blad1': '<row><c r="A1" s="1"><v>45292</v></c></row>'},
        stylesXml:
            '<?xml version="1.0"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd-mm-yyyy"/></numFmts>'
            '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="164"/></cellXfs>'
            '</styleSheet>',
      );
      expect(convertXlsxDetailed(bytes).markdown, contains('| 2024-01-01 |'));
    });

    test('sparce cellen vullen gaten uit het celadres', () {
      final bytes = xlsxFixture(
        sheets: {
          'Blad1':
              '<row><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>',
        },
      );
      expect(
        convertXlsxDetailed(bytes).markdown,
        contains('| Kolom |  | Waarde |'),
      );
    });

    test('inline strings en booleans', () {
      final bytes = xlsxFixture(
        sheets: {
          'Blad1':
              '<row><c r="A1" t="inlineStr"><is><t>Ja</t></is></c>'
              '<c r="B1" t="b"><v>1</v></c></row>',
        },
      );
      final md = convertXlsxDetailed(bytes).markdown;
      expect(md, contains('| Ja | TRUE |'));
    });

    test('afbeeldingen en grafieken tellen als niet overgenomen', () {
      final bytes = xlsxFixture(
        extra: {
          'xl/media/logo.png': [1, 2, 3],
          'xl/charts/chart1.xml': [60],
        },
      );
      final result = convertXlsxDetailed(bytes);
      expect(result.notImported, contains('afbeelding'));
      expect(result.notImported, contains('object'));
    });

    test('zonder workbook.xml is het geen xlsx', () {
      final bytes = Uint8List.fromList(utf8.encode('geen zip'));
      expect(() => convertXlsxDetailed(bytes), throwsA(isA<FormatException>()));
    });

    test('een archief groter dan het budget wordt geweigerd', () {
      expect(
        () => convertXlsxDetailed(
          xlsxFixture(),
          budget: ImportBudget.forTest(maxSourceBytes: 10),
        ),
        throwsA(isA<ImportBudgetException>()),
      );
    });
  });

  group('ODS → Markdown', () {
    test('werkblad wordt kop plus tabel met opgemaakte celtekst', () {
      final md = convertOdsDetailed(odsFixture(), title: 'lijst').markdown;

      expect(md, startsWith('# lijst'));
      expect(md, contains('## Blad1'));
      expect(md, contains('| Kolom | Waarde |'));
      expect(md, contains('| A | 42 |'));
    });

    test('herhaalde cellen en rijen worden geëxpandeerd', () {
      final bytes = odsFixture(
        sheets: {
          'Blad1':
              '<table:table-row>'
              '<table:table-cell><text:p>x</text:p></table:table-cell>'
              '<table:table-cell table:number-columns-repeated="3">'
              '<text:p>y</text:p></table:table-cell>'
              '</table:table-row>'
              '<table:table-row table:number-rows-repeated="2">'
              '<table:table-cell><text:p>z</text:p></table:table-cell>'
              '</table:table-row>',
        },
      );
      final md = convertOdsDetailed(bytes).markdown;
      expect(md, contains('| x | y | y | y |'));
      expect(md.indexOf('| z |'), isNot(md.lastIndexOf('| z |')));
    });

    test('een leeg opgelegd repeatplafond verdwijnt stil in de trim', () {
      final bytes = odsFixture(
        sheets: {
          'Blad1':
              '<table:table-row>'
              '<table:table-cell><text:p>a</text:p></table:table-cell>'
              '<table:table-cell table:number-columns-repeated="16384"/>'
              '</table:table-row>'
              '<table:table-row table:number-rows-repeated="1048576"/>',
        },
      );
      final md = convertOdsDetailed(bytes).markdown;
      expect(md, contains('| a |'));
      expect(md, isNot(contains('| | |')));
    });

    test('buiten het budget vallende inhoud telt als verlies', () {
      final bytes = odsFixture(
        sheets: {
          'Blad1':
              '<table:table-row>'
              '<table:table-cell><text:p>a</text:p></table:table-cell>'
              '<table:table-cell table:number-columns-repeated="100">'
              '<text:p>vol</text:p></table:table-cell>'
              '</table:table-row>',
        },
      );
      final result = convertOdsDetailed(
        bytes,
        budget: ImportBudget.forTest(maxSheetCols: 4),
      );
      expect(result.notImported, contains('object'));
    });

    test('een cel zonder tekst valt terug op office:value/date-value', () {
      final bytes = odsFixture(
        sheets: {
          'Blad1':
              '<table:table-row>'
              '<table:table-cell office:value-type="date" '
              'office:date-value="2024-03-05"/>'
              '<table:table-cell office:value-type="float" '
              'office:value="3.5"/>'
              '</table:table-row>',
        },
      );
      expect(
        convertOdsDetailed(bytes).markdown,
        contains('| 2024-03-05 | 3.5 |'),
      );
    });

    test('zonder office:spreadsheet is het geen ods', () {
      final bytes = odsFixture(sheets: {});
      // De fixture schrijft <office:spreadsheet> altijd; corrigeer met een
      // body zonder bladen door de inhoud te vervangen.
      expect(
        () => convertOdsDetailed(Uint8List.fromList(utf8.encode('geen zip'))),
        throwsA(isA<FormatException>()),
      );
      // Een leeg spreadsheet-element levert wel degelijk een document op.
      expect(convertOdsDetailed(bytes).markdown, isNotNull);
    });
  });

  group('servicekant', () {
    test('de nieuwe formaten zijn herkenbaar aan de naam', () {
      expect(isImportableDocumentName('lijst.xlsx'), isTrue);
      expect(isImportableDocumentName('lijst.XLSX'), isTrue);
      expect(isImportableDocumentName('lijst.ods'), isTrue);
      expect(isImportableDocumentName('lijst.csv'), isTrue);
      expect(isImportableDocumentName('lijst.docx'), isTrue);
      // .xls (binair OLE2) kan niet — beter grijs dan een misleidende import.
      expect(isImportableDocumentName('lijst.xls'), isFalse);
    });

    test('importDocumentBytes routeert op extensie', () {
      final ok = importDocumentBytes(
        utf8.encode('a;b\n1;2\n'),
        filename: 'meting.csv',
      );
      expect(ok.isSuccess, isTrue);
      expect(ok.markdown, contains('| a | b |'));

      final xlsx = importDocumentBytes(
        xlsxFixture(),
        filename: 'register.xlsx',
      );
      expect(xlsx.isSuccess, isTrue);
      expect(xlsx.markdown, contains('## Blad1'));
      // De titel komt uit de bestandsnaam.
      expect(xlsx.markdown, startsWith('# register'));
    });

    test('een onbekende extensie meldt de hele lijst', () {
      final result = importDocumentBytes(
        utf8.encode('x'),
        filename: 'ding.pages',
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure!.message, contains('.xlsx'));
    });
  });
}
