// Tests voor de documentimport: DOCX → Markdown en ODT → Markdown.
//
// De fixtures zijn echte minimale archieven (geen namaak), zodat de tests
// door dezelfde parser gaan als de gebruiker.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/document_import_service.dart';
import 'package:ocideck/services/import/importers/docx/docx_document_importer.dart';
import 'package:ocideck/services/import/importers/odt/odt_document_importer.dart';
import 'package:ocideck/services/web_asset_store.dart';

import 'helpers/docx_fixture.dart';
import 'helpers/odt_fixture.dart';

/// Een PNG-handtekening met een beetje rommel erachter — genoeg voor de
/// magic-bytecontrole, nooit bedoeld om echt te decoden.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
  2,
  3,
  4,
]);

/// Een `w:drawing`-run die relatie [rid] aanhaalt; [inner] kiest inline of
/// geankerd en [docPr] levert de alt-tekst.
String _docxDrawingRun(
  String rid, {
  bool anchored = false,
  String? descr,
  String inner = '',
}) {
  final docPr =
      '<wp:docPr id="1" name="Afbeelding 1"'
      '${descr == null ? '' : ' descr="$descr"'}/>';
  final graphic =
      '<a:graphic><a:graphicData>'
      '<pic:pic><pic:blipFill><a:blip r:embed="$rid"/></pic:blipFill></pic:pic>'
      '</a:graphicData></a:graphic>';
  return '<w:p><w:r><w:drawing>'
      '${anchored ? '<wp:anchor>$docPr$graphic</wp:anchor>' : '<wp:inline>$docPr$graphic</wp:inline>'}'
      '$inner'
      '</w:drawing></w:r></w:p>';
}

String _docxImageRel(String rid, String target) =>
    '<Relationship Id="$rid" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
    'Target="$target"/>';

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

    test('houdt een pijp en regeleinde binnen dezelfde tabelcel', () {
      final body =
          '<w:tbl>'
          '<w:tr><w:tc><w:p><w:r><w:t>Kop</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>Waarde</w:t></w:r></w:p></w:tc></w:tr>'
          '<w:tr><w:tc><w:p><w:r><w:t>A|B</w:t><w:br/>'
          '<w:t>vervolg</w:t></w:r></w:p></w:tc>'
          '<w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc></w:tr>'
          '</w:tbl>';

      final md = convertDocxToMarkdown(docxFixture(body: body));

      expect(md, contains(r'| A\|B<br>vervolg | 1 |'));
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

    test('houdt een pijp en regeleinde binnen dezelfde tabelcel', () {
      final body =
          '<table:table table:name="T1">'
          '<table:table-row>'
          '<table:table-cell><text:p>Kop</text:p></table:table-cell>'
          '<table:table-cell><text:p>Waarde</text:p></table:table-cell>'
          '</table:table-row>'
          '<table:table-row>'
          '<table:table-cell><text:p>A|B<text:line-break/>vervolg</text:p>'
          '</table:table-cell>'
          '<table:table-cell><text:p>1</text:p></table:table-cell>'
          '</table:table-row>'
          '</table:table>';

      final md = convertOdtToMarkdown(odtFixture(body: body));

      expect(md, contains(r'| A\|B<br>vervolg | 1 |'));
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

  // ── Afbeeldingen in de body (#2120) ──────────────────────────────────────

  group('DOCX-afbeeldingen', () {
    test('een inline w:drawing wordt ![alt](ref) met de bytes erbij', () {
      final bytes = docxFixture(
        body:
            '<w:p><w:r><w:t>Voor de foto.</w:t></w:r></w:p>'
            '${_docxDrawingRun('rId5', descr: 'Een kat')}'
            '<w:p><w:r><w:t>Na de foto.</w:t></w:r></w:p>',
        extraRels: _docxImageRel('rId5', 'media/foto.png'),
        binaries: {'word/media/foto.png': _png},
      );
      final result = convertDocxDetailed(bytes);

      expect(
        result.markdown,
        contains(
          'Voor de foto.\n\n![Een kat](word/media/foto.png)\n\nNa de foto.',
        ),
      );
      expect(result.images.single.ref, 'word/media/foto.png');
      expect(result.images.single.name, 'foto.png');
      expect(result.images.single.bytes, _png);
      expect(result.images.single.alt, 'Een kat');
      expect(result.notImported, isEmpty);
    });

    test('een geankerde w:drawing gaat net zo mee', () {
      final bytes = docxFixture(
        body: _docxDrawingRun('rId5', anchored: true),
        extraRels: _docxImageRel('rId5', 'media/plaatje.png'),
        binaries: {'word/media/plaatje.png': _png},
      );
      final result = convertDocxDetailed(bytes);

      // docPr/@name is de alt-terugval als @descr ontbreekt.
      expect(
        result.markdown,
        contains('![Afbeelding 1](word/media/plaatje.png)'),
      );
      expect(result.images, hasLength(1));
    });

    test('mc:AlternateContent telt de afbeelding maar één keer', () {
      final body =
          '<w:p><w:r><mc:AlternateContent>'
          '<mc:Choice Requires="wps">'
          '<w:drawing><wp:inline><wp:docPr id="1"/>'
          '<a:graphic><a:graphicData>'
          '<pic:pic><pic:blipFill><a:blip r:embed="rId5"/></pic:blipFill>'
          '</pic:pic></a:graphicData></a:graphic>'
          '</wp:inline></w:drawing>'
          '</mc:Choice>'
          '<mc:Fallback>'
          '<w:pict><v:shape><v:imagedata r:id="rId5"/></v:shape></w:pict>'
          '</mc:Fallback>'
          '</mc:AlternateContent></w:r></w:p>';
      final bytes = docxFixture(
        body: body,
        extraRels: _docxImageRel('rId5', 'media/foto.png'),
        binaries: {'word/media/foto.png': _png},
      );
      final result = convertDocxDetailed(bytes);

      expect(result.images, hasLength(1));
      expect(
        RegExp(r'!\[').allMatches(result.markdown),
        hasLength(1),
        reason: 'keuze én terugval leveren samen één afbeelding',
      );
      expect(result.notImported, isEmpty);
    });

    test('een w:pict met v:imagedata wordt ook meegenomen', () {
      final body =
          '<w:p><w:r><w:pict><v:shape><v:imagedata r:id="rId5"/></v:shape>'
          '</w:pict></w:r></w:p>';
      final bytes = docxFixture(
        body: body,
        extraRels: _docxImageRel('rId5', 'media/oud.png'),
        binaries: {'word/media/oud.png': _png},
      );
      final result = convertDocxDetailed(bytes);

      expect(result.markdown, contains('![](word/media/oud.png)'));
      expect(result.images, hasLength(1));
      expect(result.notImported, isEmpty);
    });

    test(
      'een afbeelding zonder oplosbare relatie telt als niet-overgenomen',
      () {
        final bytes = docxFixture(body: _docxDrawingRun('rId99'));
        final result = convertDocxDetailed(bytes);

        expect(result.markdown, isNot(contains('![')));
        expect(result.images, isEmpty);
        expect(result.notImported, ['afbeelding']);
      },
    );

    test('een relatie zonder bytes telt als niet-overgenomen', () {
      final bytes = docxFixture(
        body: _docxDrawingRun('rId5'),
        extraRels: _docxImageRel('rId5', 'media/weg.png'),
      );
      final result = convertDocxDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['afbeelding']);
    });

    test('een niet-raster deel (SVG) telt als niet-overgenomen', () {
      final bytes = docxFixture(
        body: _docxDrawingRun('rId5'),
        extraRels: _docxImageRel('rId5', 'media/logo.svg'),
        binaries: {'word/media/logo.svg': '<svg/>'.codeUnits},
      );
      final result = convertDocxDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['afbeelding']);
    });

    test('een externe relatie (r:link naar URL) telt als niet-overgenomen', () {
      final bytes = docxFixture(
        body:
            '<w:p><w:r><w:drawing><wp:inline><wp:docPr id="1"/>'
            '<a:graphic><a:graphicData>'
            '<pic:pic><pic:blipFill>'
            '<a:blip r:link="rId5"/>'
            '</pic:blipFill></pic:pic>'
            '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
        extraRels:
            '<Relationship Id="rId5" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
            'Target="https://voorbeeld.nl/foto.png" TargetMode="External"/>',
      );
      final result = convertDocxDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['afbeelding']);
    });

    test('een tekstkader in een tekening telt als tekstkader', () {
      final bytes = docxFixture(
        body: _docxDrawingRun(
          'rId5',
          inner:
              '<wps:txbx><w:txbxContent>'
              '<w:p><w:r><w:t>Kadertekst</w:t></w:r></w:p>'
              '</w:txbxContent></wps:txbx>',
        ),
        extraRels: _docxImageRel('rId5', 'media/foto.png'),
        binaries: {'word/media/foto.png': _png},
      );
      final result = convertDocxDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['tekstkader']);
    });

    test('een gegroepeerde tekening (wpg:wgp) telt als groep', () {
      final body =
          '<w:p><w:r><w:drawing><wp:inline><wp:docPr id="1"/>'
          '<a:graphic><a:graphicData><wpg:wgp/></a:graphicData></a:graphic>'
          '</wp:inline></w:drawing></w:r></w:p>';
      final bytes = docxFixture(body: body);
      final result = convertDocxDetailed(bytes);

      expect(result.notImported, ['groep']);
    });

    test('een OLE-object telt als object', () {
      final bytes = docxFixture(body: '<w:p><w:r><w:object/></w:r></w:p>');
      final result = convertDocxDetailed(bytes);

      expect(result.notImported, ['object']);
    });
  });

  group('ODT-afbeeldingen', () {
    test(
      'een draw:frame met draw:image wordt ![alt](ref) met de bytes erbij',
      () {
        final body =
            '<text:p>Voor de foto.</text:p>'
            '<text:p><draw:frame draw:name="Kat" svg:width="5cm" svg:height="4cm">'
            '<draw:image xlink:href="Pictures/foto.png"/>'
            '</draw:frame></text:p>'
            '<text:p>Na de foto.</text:p>';
        final bytes = odtFixture(
          body: body,
          binaries: {'Pictures/foto.png': _png},
        );
        final result = convertOdtDetailed(bytes);

        expect(
          result.markdown,
          contains('Voor de foto.\n\n![Kat](Pictures/foto.png)\n\nNa de foto.'),
        );
        expect(result.images.single.ref, 'Pictures/foto.png');
        expect(result.images.single.name, 'foto.png');
        expect(result.images.single.bytes, _png);
        expect(result.notImported, isEmpty);
      },
    );

    test('een kader zonder gevonden deel telt als niet-overgenomen', () {
      final body =
          '<text:p><draw:frame><draw:image xlink:href="Pictures/weg.png"/>'
          '</draw:frame></text:p>';
      final bytes = odtFixture(body: body);
      final result = convertOdtDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['afbeelding']);
    });

    test('een externe href telt als niet-overgenomen', () {
      final body =
          '<text:p><draw:frame>'
          '<draw:image xlink:href="https://voorbeeld.nl/foto.png"/>'
          '</draw:frame></text:p>';
      final bytes = odtFixture(body: body);
      final result = convertOdtDetailed(bytes);

      expect(result.images, isEmpty);
      expect(result.notImported, ['afbeelding']);
    });

    test('een kader met tekstkader telt als tekstkader', () {
      final body =
          '<text:p><draw:frame><draw:text-box>'
          '<text:p>Kadertekst</text:p></draw:text-box></draw:frame></text:p>';
      final bytes = odtFixture(body: body);
      final result = convertOdtDetailed(bytes);

      expect(result.notImported, ['tekstkader']);
    });

    test('een draw:g telt als groep', () {
      final bytes = odtFixture(
        body: '<text:p><draw:g><draw:rect/></draw:g></text:p>',
      );
      final result = convertOdtDetailed(bytes);

      expect(result.notImported, ['groep']);
    });

    test('een ingebed object in een kader telt als object', () {
      final body =
          '<text:p><draw:frame><draw:object xlink:href="./Object 1"/>'
          '</draw:frame></text:p>';
      final bytes = odtFixture(body: body);
      final result = convertOdtDetailed(bytes);

      expect(result.notImported, ['object']);
    });
  });

  group('afbeeldingen via importDocumentBytes', () {
    setUp(WebAssetStore.clear);
    tearDown(WebAssetStore.clear);

    String? memPathOf(String markdown) =>
        RegExp(r'!\[[^\]]*\]\((mem:[^)]+)\)').firstMatch(markdown)?.group(1);

    test('de verwijzing wordt mem: en de bytes zitten in de store', () {
      final bytes = docxFixture(
        body: _docxDrawingRun('rId5', descr: 'Een kat'),
        extraRels: _docxImageRel('rId5', 'media/foto.png'),
        binaries: {'word/media/foto.png': _png},
      );
      final result = importDocumentBytes(bytes, filename: 'rapport.docx');

      expect(result.isSuccess, isTrue);
      final mem = memPathOf(result.markdown!);
      expect(mem, isNotNull, reason: result.markdown);
      expect(WebAssetStore.bytesFor(mem!), _png);
      expect(WebAssetStore.nameFor(mem), 'foto.png');
      expect(result.notImported, isEmpty);
    });

    test('odt-afbeeldingen landen net zo in de store', () {
      final bytes = odtFixture(
        body:
            '<text:p><draw:frame><draw:image xlink:href="Pictures/foto.png"/>'
            '</draw:frame></text:p>',
        binaries: {'Pictures/foto.png': _png},
      );
      final result = importDocumentBytes(bytes, filename: 'brief.odt');

      final mem = memPathOf(result.markdown!);
      expect(mem, isNotNull);
      expect(WebAssetStore.bytesFor(mem!), _png);
    });

    test('notImported reist mee naar het resultaat', () {
      final bytes = docxFixture(body: _docxDrawingRun('rId99'));
      final result = importDocumentBytes(bytes, filename: 'kapot.docx');

      expect(result.isSuccess, isTrue);
      expect(result.notImported, ['afbeelding']);
    });

    test('een afbeelding die het webbudget niet past, valt niet stil weg', () {
      WebAssetStore.overrideTotalBudgetForTest(4);
      addTearDown(() => WebAssetStore.overrideTotalBudgetForTest(null));

      final bytes = docxFixture(
        body: _docxDrawingRun('rId5'),
        extraRels: _docxImageRel('rId5', 'media/foto.png'),
        binaries: {'word/media/foto.png': _png},
      );
      final result = importDocumentBytes(bytes, filename: 'groot.docx');

      expect(result.isSuccess, isTrue);
      expect(
        result.markdown,
        isNot(contains('![')),
        reason: 'geen dode verwijzing naar een pad dat er nooit was',
      );
      expect(result.notImported, ['afbeelding']);
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
