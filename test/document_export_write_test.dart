// writeDocumentExport (DOCUMENT_MODE.md §11.2): schrijft de GEPROJECTEERDE body
// weg — nooit de rauwe bron — als plat `.md` of als één doorlopend HTML-document.
// Deze test bewijst dat beide formaten een bestand op schijf zetten met de
// geredigeerde inhoud, en dat de HTML-vorm de doorlopende (continuous) route
// neemt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/services/document_style.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_docexport_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  const body = '# Rapport\n\nEen alinea met UNIEKPROZA.\n';

  Future<void> withBundle(Future<void> Function(ExportBundle bundle) fn) async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Rapport',
    );
    await fn(bundle);
  }

  test('md-export schrijft de geprojecteerde platte body', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      expect(written, out);
      final content = await File(out).readAsString();
      expect(content.contains('UNIEKPROZA'), isTrue);
      // Geen deck-scaffold: een document-export draagt geen `marp:`-kop.
      expect(content.contains('marp: true'), isFalse);
    });
  });

  test('exportbundel bewaart de opgeloste documentstijl', () async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      theme: ThemeProfile.vigilis,
    );

    expect(bundle.audience.deck.themeProfile.name, 'Vigilis');
    expect(bundle.audience.deck.themeProfile.accentColor, '#FFB800');
  });

  // #1536: de geprojecteerde `.md` neemt de geldende paginaopmaak mee. Anders
  // dan de stijl (die als profielnaam alleen hier betekenis heeft) is het vel
  // een maat die overal hetzelfde betekent, en hoort hij bij het drukwerk —
  // FILE_FORMAT.md §14.4.
  test('md-export draagt de geldende maat en marges', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        pageSize: PageSizeSpec.fromId('A5')!,
        pageMargins: const PageMargins(
          topMm: 18,
          bottomMm: 18,
          leftMm: 15,
          rightMm: 15,
        ),
        outputPath: out,
      );
      final content = await File(out).readAsString();
      expect(content.contains('papersize: a5'), isTrue);
      expect(
        content.contains('geometry: top=18mm,bottom=18mm,left=15mm,right=15mm'),
        isTrue,
      );
      // De opmaak staat vóór de inhoud, in een echt frontmatter-blok.
      expect(content.startsWith('---\n'), isTrue);
      expect(content.contains('UNIEKPROZA'), isTrue);
    });
  });

  test('md-export zonder paginaopmaak blijft een kale body', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      final content = await File(out).readAsString();
      expect(content.startsWith('# Rapport'), isTrue);
      expect(content.contains('papersize'), isFalse);
      expect(content.contains('geometry'), isFalse);
    });
  });

  test(
    'md-export met afloop schrijft expliciete maten, geen papiernaam',
    () async {
      await withBundle((bundle) async {
        final out = p.join(temp.path, 'rapport.md');
        await writeDocumentExport(
          bundle,
          DocumentExportFormat.md,
          html: MarpHtmlService(loadAsset: _diskLoader),
          pageSize: PageSizeSpec.a4,
          pageMargins: const PageMargins(bleedMm: 3),
          outputPath: out,
        );
        final content = await File(out).readAsString();
        // Een papiernaam kan een vergroot vel niet beschrijven; die blijft weg.
        expect(content.contains('papersize'), isFalse);
        expect(
          content.contains(
            'geometry: paperwidth=216mm,paperheight=303mm,'
            'top=28mm,bottom=28mm,left=23mm,right=23mm',
          ),
          isTrue,
        );
      });
    },
  );

  test('md-export laat de bron byte-identiek', () async {
    final sourcePath = p.join(temp.path, 'bron.md');
    const source = '---\ntitle: Handmatig\n---\n\n$body';
    await File(sourcePath).writeAsString(source);
    final before = await File(sourcePath).readAsBytes();

    final bundle = await buildDocumentExportBundle(
      documentBody(await File(sourcePath).readAsString()),
      projectPath: temp.path,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Rapport',
    );
    await writeDocumentExport(
      bundle,
      DocumentExportFormat.md,
      html: MarpHtmlService(loadAsset: _diskLoader),
      pageSize: PageSizeSpec.a4,
      pageMargins: const PageMargins(),
      outputPath: p.join(temp.path, 'export.md'),
    );

    expect(await File(sourcePath).readAsBytes(), before);
  });

  // De volgorde van gelden zit in `effectiveDocumentPageSetup`; de export
  // schrijft die uitkomst. Ook wanneer de opmaak alleen in de instellingen
  // stond, want de ontvanger heeft die instellingen niet.
  test(
    'md-export draagt de instelling wanneer het document niets zegt',
    () async {
      final settings = const AppSettings().copyWith(
        documentPageSize: PageSizeSpec.fromId('A3')!,
        documentPageMargins: const PageMargins.uniform(30),
      );
      final setup = effectiveDocumentPageSetup(settings, body);

      await withBundle((bundle) async {
        final out = p.join(temp.path, 'rapport.md');
        await writeDocumentExport(
          bundle,
          DocumentExportFormat.md,
          html: MarpHtmlService(loadAsset: _diskLoader),
          pageSize: setup.size,
          pageMargins: setup.margins,
          outputPath: out,
        );
        final content = await File(out).readAsString();
        expect(content.contains('papersize: a3'), isTrue);
        expect(
          content.contains(
            'geometry: top=30mm,bottom=30mm,left=30mm,right=30mm',
          ),
          isTrue,
        );
      });
    },
  );

  test('html-export schrijft één doorlopend document, geen dia', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.html');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.html,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      expect(written, out);
      final html = await File(out).readAsString();
      expect(html.contains('<section class="document"'), isTrue);
      expect(html.contains('<section class="slide'), isFalse);
      // De body reist door de inerte markdown-poort.
      expect(html.contains('<script type="text/markdown">'), isTrue);
      expect(html.contains('# Rapport'), isTrue);
    });
  });

  // #1569: de plaatsing van de voetnoten reist mee, om dezelfde reden als het
  // vel — `reference-location:` is een instructie die Pandoc en Quarto zelf
  // uitvoeren, geen verwijzing naar iets dat alleen hier bestaat (§14.4). De
  // body komt uit de projectie en draagt geen front matter meer, dus de keuze
  // moet bij het schrijven opnieuw worden gezet.
  test('md-export draagt de keuze noten-achterin mee', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        footnotePlacement: FootnotePlacement.document,
        outputPath: out,
      );
      final content = await File(out).readAsString();
      expect(content.startsWith('---\n'), isTrue);
      expect(content.contains('reference-location: document'), isTrue);
      // En hij is ook echt terug te lezen, niet alleen tekstueel aanwezig.
      expect(documentFootnotePlacement(content), FootnotePlacement.document);
      expect(content.contains('UNIEKPROZA'), isTrue);
    });
  });

  test('md-export met de standaardplaatsing schrijft geen sleutel', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        outputPath: out,
      );
      final content = await File(out).readAsString();
      // Onderaan de bladzijde is wat elke lezer zonder aanwijzing al doet, dus
      // een document dat niets bijzonders wil houdt een kale export (§14.9).
      expect(content.contains('reference-location'), isFalse);
      expect(content.startsWith('# Rapport'), isTrue);
    });
  });

  test('noten-achterin en de paginaopmaak staan samen in één blok', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        pageSize: PageSizeSpec.fromId('A5')!,
        pageMargins: const PageMargins(),
        footnotePlacement: FootnotePlacement.document,
        outputPath: out,
      );
      final content = await File(out).readAsString();
      // Eén front-matterblok, geen twee: de schrijvers zijn byte-chirurgisch
      // en voegen toe aan het blok dat er al staat.
      expect('---\n'.allMatches(content).length, 2);
      expect(content.contains('papersize: a5'), isTrue);
      expect(content.contains('reference-location: document'), isTrue);
    });
  });
}
