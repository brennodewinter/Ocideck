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
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/odt/markdown_to_odt.dart';
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
    ThemeProfile? theme,
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
    theme: theme,
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
    expect(content, contains('<text:p text:style-name="Standard">'));
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

  group('odt: profielkleuren', () {
    test(
      'kop-, tekst-, link- en tabelkleuren uit het profiel bereiken de export',
      () async {
        const theme = ThemeProfile(
          textColor: '#a1b2c3',
          accentColor: '#aa6600',
          documentHeadingColor: '#003399',
          tableHeaderBackgroundColor: '#445566',
          tableHeaderTextColor: '#eeddcc',
          tableTextColor: '#334455',
        );
        final bundle = await buildBundle(
          '# Kop\n\nTekst.\n\n## Subkop\n\n'
          '| Naam | Waarde |\n| --- | --- |\n| A | 1 |\n\n'
          '[link](https://ocideck.nl)\n',
          theme: theme,
        );
        final bytes = await buildDocumentExportOdt(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);
        final content = _readEntry(archive, 'content.xml');

        // Broodtekstkleur op de default-stijl; kopkleur op de kopstijlen.
        expect(content, contains('fo:color="#A1B2C3"'));
        expect(content, contains('fo:color="#003399"'));
        // Links volgen het accent via de Link-tekststijl.
        expect(content, contains('fo:color="#AA6600"'));
        expect(content, contains('<text:a xlink:href="https://ocideck.nl"'));
        expect(content, contains('text:style-name="Link"'));
        // Tabelkop-vulling en -tekstkleur; de cel refereert de stijl.
        expect(content, contains('fo:background-color="#445566"'));
        expect(content, contains('fo:color="#EEDDCC"'));
        expect(content, contains('fo:color="#334455"'));
        expect(content, contains('table:style-name="Table_Header_Cell"'));
      },
    );

    test(
      'zonder documentHeadingColor volgt h1 de tekstkleur en h2+ het accent',
      () async {
        const theme = ThemeProfile(
          textColor: '#102030',
          accentColor: '#607080',
        );
        final bundle = await buildBundle('# Kop\n\n## Sub\n', theme: theme);
        final bytes = await buildDocumentExportOdt(bundle);
        final archive = ZipDecoder().decodeBytes(bytes);
        final content = _readEntry(archive, 'content.xml');

        final h1 = RegExp(
          r'<style:style style:name="Heading_20_1".*?</style:style>',
          dotAll: true,
        ).firstMatch(content)!.group(0)!;
        final h2 = RegExp(
          r'<style:style style:name="Heading_20_2".*?</style:style>',
          dotAll: true,
        ).firstMatch(content)!.group(0)!;
        expect(h1, contains('fo:color="#102030"'));
        expect(h2, contains('fo:color="#607080"'));
      },
    );
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

  // Issue #1917: de ODT-export plakte alles tegen elkaar — geen alinea- of
  // hoofdstukruimte. Deze test bewijst dat de stijlen die dat oplossen
  // aanwezig zijn in content.xml.
  test(
    'odt: alinea- en kopruimte — default-paragraph, Standard, keep-with-next',
    () async {
      final bundle = await buildBundle(
        '# Hoofdstuk\n\nEerste alinea.\n\nTweede alinea.\n',
      );
      final bytes = await buildDocumentExportOdt(bundle);
      final archive = ZipDecoder().decodeBytes(bytes);
      final content = _readEntry(archive, 'content.xml');

      // Default-paragraph-stijl met marge: kale <text:p> erft nu ruimte.
      expect(content, contains('style:default-style'));
      expect(content, contains('style:family="paragraph"'));
      expect(content, contains('fo:margin-bottom="0.3cm"'));

      // Expliciete Standard-body-stijl die body-alinea's refereren.
      expect(content, contains('style:name="Standard"'));

      // Body-alinea's refereren de Standard-stijl, niet kale <text:p>.
      expect(content, contains('<text:p text:style-name="Standard">'));

      // Koppen hebben keep-with-next zodat ze niet wees onderaan een pagina.
      expect(content, contains('fo:keep-with-next="true"'));

      // Koppen hebben alineamarges (top + bottom).
      expect(content, contains('fo:margin-top="0.8cm"'));
      expect(content, contains('fo:margin-bottom="0.3cm"'));
    },
  );

  test("odt: list-item-alinea's refereren de Standard-stijl", () async {
    final bundle = await buildBundle('- punt 1\n- punt 2\n');
    final bytes = await buildDocumentExportOdt(bundle);
    final archive = ZipDecoder().decodeBytes(bytes);
    final content = _readEntry(archive, 'content.xml');

    expect(
      content,
      contains('<text:list-item><text:p text:style-name="Standard">'),
    );
  });

  test(
    'odt: codeblok lekt niet door naar volgende inline code (regressie #2095)',
    () {
      // Een codeblok mag de visitor-stack niet beïnvloeden: inline code ná een
      // codeblok moet een span blijven, geen Preformatted_Text-alinea.
      final body = markdownToOdtBody(
        '```\nfoo\n```\n\nAlinea met `code` erin.\n',
      );
      // Inline code is een span, geen eigen Preformatted_Text-alinea.
      expect(
        body,
        contains('<text:span text:style-name="Source_Text">code</text:span>'),
      );
      expect(body, isNot(contains('Preformatted_Text>code</text:p>')));
    },
  );
}

String _readEntry(Archive archive, String name) {
  final entry = archive.find(name);
  if (entry == null) {
    fail('Entry $name niet gevonden in ODT-ZIP');
  }
  return String.fromCharCodes(entry.content as List<int>);
}
