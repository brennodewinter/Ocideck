// DOCX (WordprocessingML / OOXML) export (issue #1916): bouwt een .docx-ZIP
// uit de geprojecteerde body met bewerkbare Word-XML, native voetnoten,
// koppen met outline-levels, tabellen, lijsten, afbeeldingen als aparte
// entries, en Mermaid-diagrammen als hoogwaardige PNG-afbeeldingen.
//
// Deze test bewijst:
// 1. De DOCX-structuur klopt ([Content_Types].xml, _rels/.rels,
//    word/document.xml, word/styles.xml, word/numbering.xml, docProps/core.xml).
// 2. document.xml bevat de geprojecteerde inhoud als WordprocessingML.
// 3. Koppen hebben outline-levels (in styles.xml).
// 4. Afbeeldingen als data-URI worden naar aparte bestanden geëxtraheerd.
// 5. Voetnoten worden footnoteReference + footnotes.xml.
// 6. TLP-classificatie staat in de metadata (core.xml keywords).
// 7. writeDocumentExport schrijft een geldig .docx-bestand.
// 8. writeDocumentExport weigert bij vereiste classificatie (fail-closed).
// 9. chapterPageBreak voegt pageBreakBefore toe aan H1.
// 10. Tabellen worden als w:tbl gerenderd.
// 11. Mermaid-blok met renderer → PNG in word/media/.
// 12. Mermaid-blok zonder renderer → terugval op bron.
// 13. Bestandsnaam met .docx-extensie.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/docx/markdown_to_docx.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_docx_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<ExportBundle> buildBundle(
    String body, {
    TlpLevel tlp = TlpLevel.none,
  }) async => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
    title: 'Rapport',
    tlp: tlp,
  );

  group('docx-structuur', () {
    test(
      '[Content_Types].xml, rels, document, styles, numbering, core',
      () async {
        final bundle = await buildBundle('# Rapport\n\nEen alinea.\n');
        final bytes = await buildDocumentExportDocx(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);

        expect(archive.find('[Content_Types].xml'), isNotNull);
        expect(archive.find('_rels/.rels'), isNotNull);
        expect(archive.find('word/document.xml'), isNotNull);
        expect(archive.find('word/styles.xml'), isNotNull);
        expect(archive.find('word/numbering.xml'), isNotNull);
        expect(archive.find('docProps/core.xml'), isNotNull);
        expect(archive.find('docProps/app.xml'), isNotNull);
      },
    );

    test(
      'document.xml bevat de geprojecteerde inhoud als WordprocessingML',
      () async {
        final bundle = await buildBundle(
          '# Rapport\n\nEen alinea met UNIEKPROZA.\n\n- punt 1\n- punt 2\n',
        );
        final bytes = await buildDocumentExportDocx(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);
        final doc = _readEntry(archive, 'word/document.xml');

        expect(doc, contains('UNIEKPROZA'));
        expect(doc, contains('<w:p'));
        expect(doc, contains('<w:t'));
        expect(doc, contains('Heading1'));
        expect(doc, contains('ListParagraph'));
        // Well-formed: XML-declaratie en WordprocessingML-namespace.
        expect(doc, startsWith('<?xml version="1.0"'));
        expect(doc, contains('xmlns:w='));
      },
    );
  });

  group('docx: koppen', () {
    test('koppen hebben outline-levels in styles.xml', () async {
      final bundle = await buildBundle(
        '# Hoofdstuk 1\n\nTekst.\n\n## Subkop\n\nMeer tekst.\n\n# Hoofdstuk 2\n',
      );
      final bytes = await buildDocumentExportDocx(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final styles = _readEntry(archive, 'word/styles.xml');
      final doc = _readEntry(archive, 'word/document.xml');

      expect(styles, contains('outlineLvl'));
      expect(styles, contains('Heading1'));
      expect(styles, contains('Heading2'));
      expect(doc, contains('Hoofdstuk 1'));
      expect(doc, contains('Hoofdstuk 2'));
      expect(doc, contains('Subkop'));
    });

    test('chapterPageBreak voegt pageBreakBefore toe aan tweede H1', () async {
      final bundle = await buildBundle(
        '# Hoofdstuk 1\n\nTekst.\n\n# Hoofdstuk 2\n\nMeer tekst.\n',
      );
      final bytes = await buildDocumentExportDocx(
        bundle,
        chapterPageBreak: true,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = _readEntry(archive, 'word/document.xml');

      expect(doc, contains('pageBreakBefore'));
    });
  });

  group('docx: afbeeldingen', () {
    test(
      'data-URI wordt naar apart bestand in word/media/ geëxtraheerd',
      () async {
        // Een kleine PNG (1x1 rood) als data-URI.
        const pngDataUri =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

        final bundle = await buildBundle(
          '# Rapport\n\n![Een afbeelding](test.png)\n',
        );
        final bytes = await buildDocumentExportDocx(
          bundle,
          embedImage: (src) async => src == 'test.png' ? pngDataUri : null,
        );
        final archive = ZipDecoder().decodeBytes(bytes);

        final imgEntry = archive.find('word/media/image0.png');
        expect(imgEntry, isNotNull);

        // DOCX verwijst naar afbeeldingen via relatie-ID's (r:embed), niet
        // via directe paden — het pad staat in document.xml.rels.
        final doc = _readEntry(archive, 'word/document.xml');
        expect(doc, contains('r:embed="rId1"'));
        expect(doc, isNot(contains('data:image/png;base64,')));

        final rels = _readEntry(archive, 'word/_rels/document.xml.rels');
        expect(rels, contains('media/image0.png'));
      },
    );
  });

  group('docx: voetnoten', () {
    test('voetnoten worden footnoteReference + footnotes.xml', () async {
      final bundle = await buildBundle(
        'Een tekst met een noot[^1].\n\n[^1]: Dit is de noot.\n',
      );
      final bytes = await buildDocumentExportDocx(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = _readEntry(archive, 'word/document.xml');

      expect(doc, contains('footnoteReference'));
      expect(doc, contains('w:id="1"'));
      final fn = archive.find('word/footnotes.xml');
      expect(fn, isNotNull);
      expect(
        _readEntry(archive, 'word/footnotes.xml'),
        contains('Dit is de noot.'),
      );
    });

    test('FootnotePlacement.document → endnotes.xml', () async {
      final bundle = await buildBundle(
        'Een tekst met een noot[^1].\n\n[^1]: Dit is de noot.\n',
      );
      final bytes = await buildDocumentExportDocx(
        bundle,
        footnotePlacement: FootnotePlacement.document,
      );
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.find('word/endnotes.xml'), isNotNull);
      expect(archive.find('word/footnotes.xml'), isNull);
    });
  });

  group('docx: metadata', () {
    test('TLP-classificatie staat in core.xml keywords', () async {
      final bundle = await buildBundle(
        '# Geheim Rapport\n\nVertrouwelijk.\n',
        tlp: TlpLevel.amber,
      );
      final bytes = await buildDocumentExportDocx(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final core = _readEntry(archive, 'docProps/core.xml');

      expect(core, contains('TLP'));
      expect(core, contains('AMBER'));
    });

    test('titel en auteur staan in core.xml', () async {
      final bundle = await buildBundle('# Rapport\n\nTekst.\n');
      final bytes = await buildDocumentExportDocx(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final core = _readEntry(archive, 'docProps/core.xml');

      expect(core, contains('<dc:title>'));
      expect(core, contains('Rapport'));
    });
  });

  group('docx: tabellen', () {
    test('tabellen worden als w:tbl gerenderd', () async {
      final bundle = await buildBundle(
        '| Naam | Waarde |\n| --- | --- |\n| A | 1 |\n| B | 2 |\n',
      );
      final bytes = await buildDocumentExportDocx(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = _readEntry(archive, 'word/document.xml');

      expect(doc, contains('<w:tbl>'));
      expect(doc, contains('<w:tr>'));
      expect(doc, contains('<w:tc>'));
      expect(doc, contains('Naam'));
      expect(doc, contains('Waarde'));
    });
  });

  group('docx: mermaid', () {
    test('mermaid-blok met renderer → PNG in word/media/', () async {
      final bundle = await buildBundle('```mermaid\ngraph TD\nA-->B\n```\n');
      final bytes = await buildDocumentExportDocx(
        bundle,
        renderMermaid: (source) async => _minimalSvg,
      );
      final archive = ZipDecoder().decodeBytes(bytes);

      // Er staat een PNG in word/media/.
      final mediaNames = archive.files
          .where((f) => f.name.startsWith('word/media/'))
          .map((f) => f.name)
          .toList();
      expect(mediaNames, isNotEmpty);
      expect(mediaNames.first, endsWith('.png'));

      final doc = _readEntry(archive, 'word/document.xml');
      expect(doc, contains('<w:drawing>'));
    });

    test(
      'mermaid-blok zonder renderer → terugval op bron in codeblok',
      () async {
        final bundle = await buildBundle('```mermaid\ngraph TD\nA-->B\n```\n');
        final bytes = await buildDocumentExportDocx(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);
        final doc = _readEntry(archive, 'word/document.xml');

        // Geen tekening, wel de bron in een PreformattedText-alinea.
        expect(doc, isNot(contains('<w:drawing>')));
        expect(doc, contains('PreformattedText'));
        expect(doc, contains('graph TD'));
      },
    );
  });

  group('docx: writeDocumentExport', () {
    test('schrijft een geldig .docx-bestand', () async {
      final bundle = await buildBundle('# Rapport\n\nUNIEKPROZA\n');
      final out = p.join(temp.path, 'rapport.docx');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.docx,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: const ClassificationEnforcementPolicy(),
        outputPath: out,
      );

      expect(written, out);
      expect(await File(out).exists(), isTrue);

      final bytes = await File(out).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.find('word/document.xml'), isNotNull);
      expect(_readEntry(archive, 'word/document.xml'), contains('UNIEKPROZA'));
    });

    test('weigert bij vereiste classificatie (fail-closed)', () async {
      final bundle = await buildBundle('# Rapport\n\nTekst.\n');
      const policy = ClassificationEnforcementPolicy(
        requireClassification: true,
      );
      final out = p.join(temp.path, 'geblokkeerd.docx');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.docx,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: policy,
        outputPath: out,
      );

      expect(written, isNull);
      expect(await File(out).exists(), isFalse);
    });
  });

  group('docx: bestandsnaam', () {
    test('suggestedDocumentExportFileName met docx → .docx', () {
      final name = suggestedDocumentExportFileName(
        title: 'Rapport',
        format: DocumentExportFormat.docx,
        profile: PrivacyExportProfile.full,
        redactedLabel: 'geredigeerd',
        fullLabel: 'volledig',
        fallbackLabel: 'document',
      );
      expect(name, endsWith('.docx'));
      expect(name, contains('Rapport'));
      expect(name, contains('volledig'));
    });
  });

  group('markdown_to_docx converter', () {
    test('inline vet/cursief/code worden runs met properties', () {
      final conv = markdownToDocxBody('**vet** _cursief_ `code`');
      expect(conv.body, contains('<w:b/>'));
      expect(conv.body, contains('<w:i/>'));
      expect(conv.body, contains('SourceText'));
      expect(conv.body, contains('vet'));
      expect(conv.body, contains('cursief'));
      expect(conv.body, contains('code'));
    });

    test('link wordt een OCIDECKLINK-sentinel met doel', () {
      final conv = markdownToDocxBody('[OciDeck](https://ocideck.nl)');
      expect(conv.linkTargets, contains('https://ocideck.nl'));
      expect(conv.body, contains('OCIDECKLINK'));
    });

    test('mermaid-blok wordt een sentinel + bron verzameld', () {
      final conv = markdownToDocxBody('```mermaid\ngraph TD\nA-->B\n```');
      expect(conv.mermaidSources, hasLength(1));
      expect(conv.mermaidSources.first, contains('graph TD'));
      expect(conv.body, contains('OCIDECKMERMAID'));
    });

    test('lege body → lege conversie', () {
      final conv = markdownToDocxBody('   ');
      expect(conv.body, isEmpty);
      expect(conv.footnotes, isEmpty);
    });
  });
}

String _readEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) {
    fail('Entry $name niet gevonden in DOCX-ZIP');
  }
  return String.fromCharCodes(entry.content as List<int>);
}

/// Een minimale geldige SVG voor de rasterisatie-test (een rode rechthoek).
const String _minimalSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 100 50">'
    '<rect width="100" height="50" fill="red"/></svg>';
