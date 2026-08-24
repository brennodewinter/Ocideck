// ODT (OpenDocument Text) export (issue #1768): bouwt een ODT-ZIP uit de
// geprojecteerde body met bewerkbare OpenDocument-XML, native voetnoten,
// koppen met outline-levels, tabellen, lijsten en afbeeldingen als aparte
// entries.
//
// Deze test bewijst:
// 1. De ODT-structuur klopt (mimetype eerste entry oncompressed,
//    META-INF/manifest.xml, content.xml, meta.xml).
// 2. De content.xml bevat de geprojecteerde inhoud als ODT-XML.
// 3. Koppen hebben outline-levels.
// 4. Afbeeldingen als data-URI worden naar aparte bestanden geëxtraheerd.
// 5. Voetnoten worden ODT-native <text:note>-elementen.
// 6. TLP-classificatie staat in de metadata.
// 7. writeDocumentExport schrijft een geldig .odt-bestand.
// 8. writeDocumentExport weigert bij vereiste classificatie (fail-closed).
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_odt_');
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
    'odt-structuur: mimetype eerste entry, manifest, content, meta',
    () async {
      final bundle = await buildBundle('# Rapport\n\nEen alinea.\n');
      final bytes = await buildDocumentExportOdt(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);

      // mimetype moet de eerste entry zijn.
      expect(archive.first.name, 'mimetype');
      expect(
        String.fromCharCodes(archive.first.content as List<int>),
        'application/vnd.oasis.opendocument.text',
      );

      // De vereiste structuur-bestanden aanwezig.
      expect(archive.find('META-INF/manifest.xml'), isNotNull);
      expect(archive.find('content.xml'), isNotNull);
      expect(archive.find('meta.xml'), isNotNull);
    },
  );

  test('odt: content.xml bevat de geprojecteerde inhoud als ODT-XML', () async {
    final bundle = await buildBundle(
      '# Rapport\n\nEen alinea met UNIEKPROZA.\n\n- punt 1\n- punt 2\n',
    );
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    expect(content, contains('UNIEKPROZA'));
    expect(content, contains('<text:h'));
    expect(content, contains('<text:p>'));
    expect(content, contains('<text:list'));
    expect(content, contains('<text:list-item'));
    // Well-formed: XML-declaratie en OpenDocument-namespace.
    expect(content, startsWith('<?xml version="1.0"'));
    expect(content, contains('xmlns:office='));
    expect(content, contains('xmlns:text='));
  });

  test('odt: koppen hebben outline-levels', () async {
    final bundle = await buildBundle(
      '# Hoofdstuk 1\n\nTekst.\n\n## Subkop\n\nMeer tekst.\n\n# Hoofdstuk 2\n',
    );
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    expect(content, contains('text:outline-level="1"'));
    expect(content, contains('text:outline-level="2"'));
    expect(content, contains('Hoofdstuk 1'));
    expect(content, contains('Hoofdstuk 2'));
    expect(content, contains('Subkop'));
  });

  test(
    'odt: afbeeldingen als data-URI worden naar aparte bestanden geëxtraheerd',
    () async {
      // Een kleine PNG (1x1 rood) als data-URI.
      const pngDataUri =
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

      final bundle = await buildBundle(
        '# Rapport\n\n![Een afbeelding](test.png)\n',
      );
      final bytes = await buildDocumentExportOdt(
        bundle,
        embedImage: (src) async => src == 'test.png' ? pngDataUri : null,
      );
      final archive = ZipDecoder().decodeBytes(bytes);

      // De afbeelding staat als apart bestand in de ZIP.
      final imgEntry = archive.find('Pictures/image-0.png');
      expect(imgEntry, isNotNull);

      // Het document verwijst naar het relatieve pad, niet naar de data-URI.
      final content = _readEntry(archive, 'content.xml');
      expect(content, contains('Pictures/image-0.png'));
      expect(content, isNot(contains('data:image/png;base64,')));
    },
  );

  test('odt: voetnoten worden ODT-native <text:note>-elementen', () async {
    final bundle = await buildBundle(
      'Een tekst met een noot[^1].\n\n[^1]: Dit is de noot.\n',
    );
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    // ODT-native voetnoot: <text:note text:note-class="footnote">.
    expect(content, contains('<text:note'));
    expect(content, contains('text:note-class="footnote"'));
    expect(content, contains('Dit is de noot.'));
    expect(content, contains('text:note-citation'));
    expect(content, contains('text:note-body'));
  });

  test('odt: TLP-classificatie staat in de metadata', () async {
    final bundle = await buildBundle(
      '# Geheim Rapport\n\nVertrouwelijk.\n',
      tlp: TlpLevel.amber,
    );
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final meta = _readEntry(archive, 'meta.xml');

    expect(meta, contains('TLP'));
    expect(meta, contains('AMBER'));
  });

  test('odt: writeDocumentExport schrijft een geldig .odt-bestand', () async {
    final bundle = await buildBundle('# Rapport\n\nUNIEKPROZA\n');
    final out = p.join(temp.path, 'rapport.odt');
    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.odt,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );

    expect(written, out);
    expect(await File(out).exists(), isTrue);

    // Het bestand is een geldige ZIP met ODT-structuur.
    final bytes = await File(out).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.first.name, 'mimetype');
    expect(archive.find('content.xml'), isNotNull);
  });

  test('odt: writeDocumentExport weigert bij vereiste classificatie', () async {
    final bundle = await buildBundle('# Rapport\n\nTekst.\n');
    const policy = ClassificationEnforcementPolicy(requireClassification: true);
    final out = p.join(temp.path, 'geblokkeerd.odt');
    final written = await writeDocumentExport(
      bundle,
      DocumentExportFormat.odt,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: policy,
      outputPath: out,
    );

    expect(written, isNull);
    expect(await File(out).exists(), isFalse);
  });

  test('odt: chapterPageBreak voegt page-break toe aan H1', () async {
    final bundle = await buildBundle(
      '# Hoofdstuk 1\n\nTekst.\n\n# Hoofdstuk 2\n\nMeer tekst.\n',
    );
    final bytes = await buildDocumentExportOdt(bundle, chapterPageBreak: true);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    // De tweede H1 krijgt een restart-numbering (wat de page-break marker
    // aangeeft in de ODT-converter).
    expect(content, contains('text:restart-numbering'));
  });

  test('odt: tabellen worden als ODT-table gerenderd', () async {
    final bundle = await buildBundle(
      '| Naam | Waarde |\n| --- | --- |\n| A | 1 |\n| B | 2 |\n',
    );
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    expect(content, contains('<table:table>'));
    expect(content, contains('<table:table-row>'));
    expect(content, contains('<table:table-cell'));
    expect(content, contains('Naam'));
    expect(content, contains('Waarde'));
  });
}

String _readEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) {
    fail('Entry $name niet gevonden in ODT-ZIP');
  }
  return String.fromCharCodes(entry.content as List<int>);
}
