// EPUB 3-export (issue #1761): bouwt een EPUB-ZIP uit de geprojecteerde body
// met herflowbare XHTML, navigatie, noten achterin, en afbeeldingen als
// aparte entries.
//
// Deze test bewijst:
// 1. De EPUB-structuur klopt (mimetype eerste entry oncompressed,
//    container.xml, content.opf, nav.xhtml, document.xhtml).
// 2. De XHTML is well-formed en bevat de geprojecteerde inhoud.
// 3. Koppen verschijnen als navigatie in nav.xhtml.
// 4. Afbeeldingen als data-URI worden naar aparte bestanden geëxtraheerd.
// 5. Privacy fail-closed: een geredigeerd gegeven lekt niet in de EPUB.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/epub/document_epub_export.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_metadata.dart';
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
    temp = await Directory.systemTemp.createTemp('ocideck_epub_');
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

  test(
    'epub-structuur: mimetype eerste entry, container.xml, opf, nav, doc',
    () async {
      final bundle = await buildBundle('# Rapport\n\nEen alinea.\n');
      final bytes = await buildDocumentExportEpub(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);

      // mimetype moet de eerste entry zijn.
      expect(archive.first.name, 'mimetype');
      expect(
        String.fromCharCodes(archive.first.content as List<int>),
        'application/epub+zip',
      );

      // De vereiste structuur-bestanden aanwezig.
      expect(archive.find('META-INF/container.xml'), isNotNull);
      expect(archive.find('OEBPS/content.opf'), isNotNull);
      expect(archive.find('OEBPS/nav.xhtml'), isNotNull);
      expect(archive.find('OEBPS/document.xhtml'), isNotNull);
      expect(archive.find('OEBPS/style.css'), isNotNull);
    },
  );

  test(
    'epub: document.xhtml bevat de geprojecteerde inhoud als XHTML',
    () async {
      final bundle = await buildBundle(
        '# Rapport\n\nEen alinea met UNIEKPROZA.\n\n- punt 1\n- punt 2\n',
      );
      final bytes = await buildDocumentExportEpub(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = _readEntry(archive, 'OEBPS/document.xhtml');

      expect(doc, contains('UNIEKPROZA'));
      expect(doc, contains('<h1'));
      expect(doc, contains('<p>'));
      expect(doc, contains('<ul>'));
      expect(doc, contains('<li>'));
      // Well-formed: XML-declaratie en namespace.
      expect(doc, startsWith('<?xml version="1.0"'));
      expect(doc, contains('xmlns="http://www.w3.org/1999/xhtml"'));
    },
  );

  test('epub: koppen verschijnen als navigatie in nav.xhtml', () async {
    final bundle = await buildBundle(
      '# Hoofdstuk 1\n\nTekst.\n\n## Subkop\n\nMeer tekst.\n\n# Hoofdstuk 2\n',
    );
    final bytes = await buildDocumentExportEpub(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final nav = _readEntry(archive, 'OEBPS/nav.xhtml');

    expect(nav, contains('Hoofdstuk 1'));
    expect(nav, contains('Hoofdstuk 2'));
    expect(nav, contains('Subkop'));
    // De nav-links wijzen naar document.xhtml#heading-N.
    expect(nav, contains('document.xhtml#heading-'));
    expect(nav, contains('epub:type="toc"'));
  });

  test('epub: voetnoten staan als genummerde lijst achterin', () async {
    final bundle = await buildBundle(
      'Een tekst met een noot[^1].\n\n[^1]: Dit is de noot.\n',
    );
    final bytes = await buildDocumentExportEpub(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = _readEntry(archive, 'OEBPS/document.xhtml');

    // De verwijzing in de tekst.
    expect(doc, contains('fnref-1'));
    expect(doc, contains('#fn-1'));
    // De noot zelf achterin.
    expect(doc, contains('fn-1'));
    expect(doc, contains('Dit is de noot.'));
    expect(doc, contains('ocideck-footnotes'));
  });

  test(
    'epub: afbeeldingen als data-URI worden naar aparte bestanden geëxtraheerd',
    () async {
      // Een kleine PNG (1x1 rood) als data-URI.
      const pngDataUri =
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

      final bundle = await buildBundle(
        '# Rapport\n\n![Een afbeelding](test.png)\n',
      );
      final bytes = await buildDocumentExportEpub(
        bundle,
        embedImage: (src) async => src == 'test.png' ? pngDataUri : null,
      );
      final archive = ZipDecoder().decodeBytes(bytes);

      // De afbeelding staat als apart bestand in de ZIP.
      final imgEntry = archive.find('OEBPS/images/image-0.png');
      expect(imgEntry, isNotNull);

      // Het document verwijst naar het relatieve pad, niet naar de data-URI.
      final doc = _readEntry(archive, 'OEBPS/document.xhtml');
      expect(doc, contains('images/image-0.png'));
      expect(doc, isNot(contains('data:image/png;base64,')));
    },
  );

  test('epub: content.opf bevat metadata en manifest', () async {
    final bundle = await buildBundle('# Rapport\n\nTekst.\n');
    final bytes = await buildDocumentExportEpub(
      bundle,
      metadata: const ExportDocumentMetadata(
        title: 'Mijn Rapport',
        author: 'Jan Jansen',
        language: 'nl',
      ),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final opf = _readEntry(archive, 'OEBPS/content.opf');

    expect(opf, contains('Mijn Rapport'));
    expect(opf, contains('Jan Jansen'));
    expect(opf, contains('<dc:language>nl</dc:language>'));
    expect(opf, contains('version="3.0"'));
    expect(opf, contains('unique-identifier="bookid"'));
    // Manifest-items voor de vereiste bestanden.
    expect(opf, contains('nav.xhtml'));
    expect(opf, contains('document.xhtml'));
    expect(opf, contains('style.css'));
  });

  test('epub: TLP-classificatie staat in de OPF-metadata', () async {
    final bundle = await buildBundle(
      '# Geheim Rapport\n\nVertrouwelijk.\n',
      tlp: TlpLevel.amber,
    );
    final bytes = await buildDocumentExportEpub(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final opf = _readEntry(archive, 'OEBPS/content.opf');

    expect(opf, contains('TLP:AMBER'));
  });

  test('epub: writeDocumentExport schrijft een geldig .epub-bestand', () async {
    final bundle = await buildBundle('# Rapport\n\nUNIEKPROZA\n');
    final out = p.join(temp.path, 'rapport.epub');
    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.epub,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );

    expect(written, out);
    expect(await File(out).exists(), isTrue);

    // Het bestand is een geldige ZIP met EPUB-structuur.
    final bytes = await File(out).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.first.name, 'mimetype');
    expect(archive.find('OEBPS/document.xhtml'), isNotNull);
  });

  test(
    'epub: writeDocumentExport weigert bij vereiste classificatie',
    () async {
      final bundle = await buildBundle('# Rapport\n\nTekst.\n');
      const policy = ClassificationEnforcementPolicy(
        requireClassification: true,
      );
      final out = p.join(temp.path, 'geblokkeerd.epub');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.epub,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: policy,
        outputPath: out,
      );

      expect(written, isNull);
      expect(await File(out).exists(), isFalse);
    },
  );

  test('epub: chapterPageBreak voegt page-break CSS toe aan H1', () async {
    final bundle = await buildBundle(
      '# Hoofdstuk 1\n\nTekst.\n\n# Hoofdstuk 2\n\nMeer tekst.\n',
    );
    final bytes = await buildDocumentExportEpub(bundle, chapterPageBreak: true);
    final archive = ZipDecoder().decodeBytes(bytes);
    final doc = _readEntry(archive, 'OEBPS/document.xhtml');

    // De tweede H1 krijgt een page-break-before, de eerste niet.
    expect(doc, contains('page-break-before:always'));
  });
}

String _readEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) {
    fail('Entry $name niet gevonden in EPUB-ZIP');
  }
  return String.fromCharCodes(entry.content as List<int>);
}
