// Tests voor de documentimport: DOCX → Markdown en ODT → Markdown.
//
// De fixtures zijn echte minimale archieven (geen namaak), zodat de tests
// door dezelfde parser gaan als de gebruiker.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/document_import_service.dart';
import 'package:ocideck/services/import/importers/docx/docx_document_importer.dart';
import 'package:ocideck/services/import/importers/odt/odt_document_importer.dart';

import 'helpers/docx_fixture.dart';
import 'helpers/odt_fixture.dart';

void main() {
  group('DOCX → Markdown', () {
    test('converteert koppen, vet/cursief, lijst en tabel', () {
      final bytes = docxFixture();
      final md = convertDocxToMarkdown(bytes);

      expect(md, contains('# Titel'));
      expect(md, contains('**vet**'));
      expect(md, contains('_cursief_'));
      expect(md, contains('- Eerste punt'));
      expect(md, contains('- Tweede punt'));
      expect(md, contains('| Kolom | Waarde |'));
      expect(md, contains('| A | 1 |'));
      expect(md, contains('[de site](https://voorbeeld.nl)'));
    });

    test('geordende lijst wordt 1. in plaats van -', () {
      final body =
          '<w:p><w:pPr><w:numPr><w:numId w:val="2"/></w:numPr></w:pPr>'
          '<w:r><w:t>Eerste</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:numPr><w:numId w:val="2"/></w:numPr></w:pPr>'
          '<w:r><w:t>Tweede</w:t></w:r></w:p>';
      final bytes = docxFixture(body: body);
      final md = convertDocxToMarkdown(bytes);

      expect(md, contains('1. Eerste'));
      expect(md, contains('1. Tweede'));
    });

    test('lege document geeft lege markdown', () {
      final bytes = docxFixture(body: '');
      final md = convertDocxToMarkdown(bytes);
      expect(md, '');
    });

    test('H2 wordt ## ', () {
      final body =
          '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr>'
          '<w:r><w:t>Subtitel</w:t></w:r></w:p>';
      final bytes = docxFixture(body: body);
      final md = convertDocxToMarkdown(bytes);
      expect(md, contains('## Subtitel'));
    });
  });

  group('ODT → Markdown', () {
    test('converteert koppen, vet/cursief, lijst en tabel', () {
      final bytes = odtFixture();
      final md = convertOdtToMarkdown(bytes);

      expect(md, contains('# Titel'));
      expect(md, contains('**vet**'));
      expect(md, contains('_cursief_'));
      expect(md, contains('- Eerste punt'));
      expect(md, contains('- Tweede punt'));
      expect(md, contains('| Kolom | Waarde |'));
      expect(md, contains('| A | 1 |'));
      expect(md, contains('[de site](https://voorbeeld.nl)'));
    });

    test('H2 wordt ## ', () {
      final body =
          '<text:h text:style-name="H2" text:outline-level="2">Subtitel</text:h>';
      final bytes = odtFixture(body: body);
      final md = convertOdtToMarkdown(bytes);
      expect(md, contains('## Subtitel'));
    });

    test('lege document geeft lege markdown', () {
      final bytes = odtFixture(body: '');
      final md = convertOdtToMarkdown(bytes);
      expect(md, '');
    });
  });

  group('importDocumentBytes', () {
    test('docx kiest de docx-importer', () {
      final bytes = docxFixture();
      final result = importDocumentBytes(bytes, filename: 'test.docx');
      expect(result.isSuccess, isTrue);
      expect(result.markdown, contains('# Titel'));
    });

    test('odt kiest de odt-importer', () {
      final bytes = odtFixture();
      final result = importDocumentBytes(bytes, filename: 'test.odt');
      expect(result.isSuccess, isTrue);
      expect(result.markdown, contains('# Titel'));
    });

    test('onbekend formaat faalt', () {
      final result = importDocumentBytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'test.pages',
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure!.message, contains('docx'));
      expect(result.failure!.message, contains('odt'));
    });

    test('beschadigd bestand faalt', () {
      final result = importDocumentBytes(
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
        filename: 'test.docx',
      );
      expect(result.isSuccess, isFalse);
    });

    test('isImportableDocumentName', () {
      expect(isImportableDocumentName('rapport.docx'), isTrue);
      expect(isImportableDocumentName('rapport.odt'), isTrue);
      expect(isImportableDocumentName('rapport.DOCX'), isTrue);
      expect(isImportableDocumentName('rapport.pages'), isFalse);
      expect(isImportableDocumentName('rapport.md'), isFalse);
      expect(isImportableDocumentName('rapport'), isFalse);
    });
  });

  group('safety', () {
    test('markdown met script-tag wordt geweigerd', () {
      // Een docx met <script> in de tekst — de importer produceert de tekst
      // letterlijk, en de safety-scanner houdt hem tegen.
      final body =
          '<w:p><w:r><w:t>&lt;script&gt;alert(1)&lt;/script&gt;</w:t></w:r></w:p>';
      final bytes = docxFixture(body: body);
      final result = importDocumentBytes(bytes, filename: 'evil.docx');
      expect(result.isSuccess, isFalse);
      expect(result.failure!.message, contains('uitvoerbare inhoud'));
    });
  });
}
