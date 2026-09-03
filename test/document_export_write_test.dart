// writeDocumentExport (DOCUMENT_MODE.md §11.2): schrijft de GEPROJECTEERDE body
// weg — nooit de rauwe bron — als plat `.md` of als één doorlopend HTML-document.
// Deze test bewijst dat beide formaten een bestand op schijf zetten met de
// geredigeerde inhoud, en dat de HTML-vorm de doorlopende (continuous) route
// neemt.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_style.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
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

  Future<void> withBundle(
    Future<void> Function(ExportBundle bundle) fn, {
    TlpLevel tlp = TlpLevel.none,
  }) async {
    final bundle = await buildDocumentExportBundle(
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
    await fn(bundle);
  }

  test('md-export schrijft de geprojecteerde platte body', () async {
    await withBundle((bundle) async {
      final out = p.join(temp.path, 'rapport.md');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: const ClassificationEnforcementPolicy(),
        outputPath: out,
      );
      expect(written, out);
      final content = await File(out).readAsString();
      expect(content.contains('UNIEKPROZA'), isTrue);
      // Geen deck-scaffold: een document-export draagt geen `marp:`-kop.
      expect(content.contains('marp: true'), isFalse);
    });
  });

  test(
    'document-TLP blijft deckbreed en reist één keer mee in Markdown',
    () async {
      await withBundle((bundle) async {
        expect(bundle.audience.deck.tlp, TlpLevel.amber);
        expect(
          bundle.audience.deck.slides.every(
            (slide) => slide.tlp == TlpLevel.none,
          ),
          isTrue,
          reason:
              'documentsecties zijn geen afzonderlijk geclassificeerde slides',
        );

        final out = p.join(temp.path, 'rapport.md');
        await writeDocumentExport(
          bundle,
          DocumentExportFormat.md,
          html: MarpHtmlService(loadAsset: _diskLoader),
          enforcementPolicy: const ClassificationEnforcementPolicy(),
          outputPath: out,
        );
        final content = await File(out).readAsString();

        expect(content, startsWith('---\ntlp: amber\n---\n\n# Rapport'));
        expect(
          RegExp(r'^tlp:', multiLine: true).allMatches(content),
          hasLength(1),
        );
        expect(content, isNot(contains('<!-- tlp:')));
      }, tlp: TlpLevel.amber);
    },
  );

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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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
          enforcementPolicy: const ClassificationEnforcementPolicy(),
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
      enforcementPolicy: const ClassificationEnforcementPolicy(),
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
          enforcementPolicy: const ClassificationEnforcementPolicy(),
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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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
        enforcementPolicy: const ClassificationEnforcementPolicy(),
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

  test(
    'HTML-export neemt de bundel-TLP over in documentkop en -voet',
    () async {
      await withBundle((bundle) async {
        final out = p.join(temp.path, 'rapport-tlp.html');
        await writeDocumentExport(
          bundle,
          DocumentExportFormat.html,
          html: MarpHtmlService(loadAsset: _diskLoader),
          enforcementPolicy: const ClassificationEnforcementPolicy(),
          // Een aanroeper mag de classificatie uit de bundel niet per ongeluk
          // wissen met een onvolledig metadata-object.
          metadata: const ExportDocumentMetadata(
            title: 'Rapport',
            tlp: TlpLevel.none,
          ),
          outputPath: out,
        );
        final html = await File(out).readAsString();

        expect(html, contains('name="classification" content="TLP:RED"'));
        expect(html, contains('class="document-header"'));
        expect(html, contains('class="document-footer"'));
        expect('<span class="document-tlp"'.allMatches(html), hasLength(2));
        expect(html, isNot(contains('<div class="tlp-export-banner"')));
      }, tlp: TlpLevel.red);
    },
  );

  test('Markdown-export schrijft bekende en vrije documentvelden', () async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Terugvaltitel',
      fields: const {
        'title': 'Kwartaalaudit',
        'subtitle': 'Bestuurlijke samenvatting',
        'author': 'Ada Lovelace',
        'project-id': 'P-42',
      },
    );
    final out = p.join(temp.path, 'velden.md');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.md,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final content = await File(out).readAsString();

    expect(documentFields(content), {
      'title': 'Kwartaalaudit',
      'subtitle': 'Bestuurlijke samenvatting',
      'author': 'Ada Lovelace',
      'project-id': 'P-42',
    });
    for (final key in ['title', 'subtitle', 'author', 'project-id']) {
      expect(
        RegExp('^$key:', multiLine: true).allMatches(content),
        hasLength(1),
        reason: key,
      );
    }
    expect(documentBody(content), contains('UNIEKPROZA'));
    expect(content, isNot(contains('theme:')));
  });

  test('HTML-export vult documentvelden in kop en voet in', () async {
    const theme = ThemeProfile(
      documentHeaderText: '{title} · {project-id}',
      documentFooterText: '{author} — {subtitle}',
    );
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      theme: theme,
      fields: const {
        'title': 'Kwartaalaudit',
        'subtitle': 'Bestuurlijk',
        'author': 'Ada Lovelace',
        'project-id': 'P-42',
      },
    );
    final out = p.join(temp.path, 'velden.html');

    await writeDocumentExport(
      bundle,
      DocumentExportFormat.html,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      outputPath: out,
    );
    final html = await File(out).readAsString();

    expect(html, contains('Kwartaalaudit · P-42'));
    expect(html, contains('Ada Lovelace — Bestuurlijk'));
    expect(html, isNot(contains('{title}')));
    expect(html, isNot(contains('{project-id}')));
  });

  test(
    'geredigeerde documentexport lekt geen rauwe metadata, velden of templates',
    () async {
      const rawTitle = 'titel.geheim@andersbureau.nl';
      const rawCustom = 'klant.geheim@andersbureau.nl';
      const rawTemplate = 'sjabloon.geheim@andersbureau.nl';
      const theme = ThemeProfile(
        documentHeaderText: '$rawTemplate · {title}',
        documentFooterText: '{client}',
      );
      final bundle = await buildDocumentExportBundle(
        body,
        projectPath: null,
        profile: PrivacyExportProfile.redacted,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
        theme: theme,
        fields: const {'title': rawTitle, 'client': rawCustom},
      );

      final projected = bundle.audience.deck;
      expect(projected.title, kRedactionToken);
      expect(projected.documentFields['client'], kRedactionToken);
      expect(
        projected.themeProfile.documentHeaderText,
        contains(kRedactionToken),
      );
      expect(projected.themeProfile.documentFooterText, kRedactionToken);

      for (final format in [
        DocumentExportFormat.md,
        DocumentExportFormat.html,
        DocumentExportFormat.latex,
      ]) {
        final out = p.join(temp.path, 'geredigeerd.${format.name}');
        await writeDocumentExport(
          bundle,
          format,
          html: MarpHtmlService(loadAsset: _diskLoader),
          enforcementPolicy: const ClassificationEnforcementPolicy(),
          // De schrijver mag deze ongeprojecteerde metadata niet vertrouwen.
          metadata: const ExportDocumentMetadata(title: rawTitle),
          outputPath: out,
        );
        final content = await File(out).readAsString();
        for (final secret in [rawTitle, rawCustom, rawTemplate]) {
          expect(
            content,
            isNot(contains(secret)),
            reason: '$secret lekt in ${format.name}',
          );
        }
        expect(content, contains(kRedactionToken), reason: format.name);
      }
    },
  );

  test(
    'de schrijver weigert ieder formaat vóór een bestand ontstaat',
    () async {
      await withBundle((bundle) async {
        const policy = ClassificationEnforcementPolicy(
          requireClassification: true,
        );
        for (final format in DocumentExportFormat.values) {
          final out = p.join(temp.path, 'geblokkeerd.${format.name}');
          final written = await writeDocumentExport(
            bundle,
            format,
            html: MarpHtmlService(loadAsset: _diskLoader),
            enforcementPolicy: policy,
            outputPath: out,
          );
          expect(written, isNull, reason: format.name);
          expect(await File(out).exists(), isFalse, reason: format.name);
        }
      });
    },
  );

  test('geredigeerde bestandsnaam bevat nooit de rauwe titel', () async {
    const rawTitle = 'Dossier 728398242';
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: PrivacyExportProfile.redacted,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: rawTitle,
    );
    final fileName = suggestedDocumentExportFileName(
      title: bundle.audience.deck.title,
      format: DocumentExportFormat.md,
      profile: PrivacyExportProfile.redacted,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );

    expect(fileName, isNot(contains('728398242')));
    expect(fileName, endsWith('-geredigeerd.md'));
  });

  test('een lange exportnaam blijft deterministisch binnen de bytegrens', () {
    final first = suggestedDocumentExportFileName(
      title: List.filled(400, 'A').join(),
      format: DocumentExportFormat.pdf,
      profile: PrivacyExportProfile.redacted,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );
    final second = suggestedDocumentExportFileName(
      title: List.filled(400, 'A').join(),
      format: DocumentExportFormat.pdf,
      profile: PrivacyExportProfile.redacted,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );

    expect(first, second);
    expect(
      first.codeUnits.length,
      lessThanOrEqualTo(maxSuggestedDocumentExportFileNameBytes),
    );
    expect(first, endsWith('-geredigeerd.pdf'));
  });

  test('exportnaam behoudt accenten en niet-Latijnse schriften', () {
    final withAccents = suggestedDocumentExportFileName(
      title: 'Résumé',
      format: DocumentExportFormat.md,
      profile: PrivacyExportProfile.full,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );
    expect(withAccents, contains('Résumé'));
    expect(withAccents, endsWith('-volledig.md'));

    final chinese = suggestedDocumentExportFileName(
      title: '中文标题',
      format: DocumentExportFormat.pdf,
      profile: PrivacyExportProfile.full,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );
    expect(chinese, contains('中文标题'));
    expect(chinese, endsWith('-volledig.pdf'));

    final arabic = suggestedDocumentExportFileName(
      title: 'العربية',
      format: DocumentExportFormat.html,
      profile: PrivacyExportProfile.redacted,
      redactedLabel: 'geredigeerd',
      fullLabel: 'volledig',
      fallbackLabel: 'document',
    );
    expect(arabic, contains('العربية'));
  });

  test('export weigert het geopende brondocument te overschrijven', () async {
    await withBundle((bundle) async {
      final source = File(p.join(temp.path, 'bron.md'));
      await source.writeAsString('ORIGINELE BRON');
      final written = await writeDocumentExport(
        bundle,
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
        enforcementPolicy: const ClassificationEnforcementPolicy(),
        outputPath: source.path,
        sourcePath: source.path,
      );

      expect(written, isNull);
      expect(await source.readAsString(), 'ORIGINELE BRON');
    });
  });

  group('rebaseImagePathsForTesting (#1673)', () {
    // Een Markdown-verwijzing is een URL. Op Windows leverde `p.relative` een
    // pad met backslashes, dat één op één in de link belandde: geen renderer
    // volgt `..\map\foto.png`, en LaTeX leest de backslash als
    // ontsnappingsteken. Deze twee toetsen rekenen de Windows-padstijl door op
    // elke machine, zodat de macOS-poort de Windows-uitkomst bewaakt.
    final windows = p.Context(style: p.Style.windows);

    test('een Windows-pad levert schuine strepen, geen backslashes', () {
      const md = '![Alt](images/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        r'C:\project\bron.md',
        r'C:\output\rapport.md',
        pathContext: windows,
      );
      expect(result, contains('![Alt](../project/images/foto.png)'));
      expect(result, isNot(contains('\\')));
    });

    test('een ander station wordt een file-URL, geen half pad', () {
      const md = '![Alt](images/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        r'C:\project\bron.md',
        r'D:\uitvoer\rapport.md',
        pathContext: windows,
      );
      expect(result, contains('![Alt](file:///C:/project/images/foto.png)'));
    });

    test('relatief pad wordt gerebased naar uitvoermap', () {
      const md = '![Alt](images/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        '/project/bron.md',
        '/output/rapport.md',
      );
      expect(result, contains('![Alt](../project/images/foto.png)'));
    });

    test('zelfde map → geen rebasing', () {
      const md = '![Alt](images/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        '/project/bron.md',
        '/project/rapport.md',
      );
      expect(result, md);
    });

    test('URL blijft ongewijzigd', () {
      const md = '![Alt](https://example.com/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        '/project/bron.md',
        '/output/rapport.md',
      );
      expect(result, md);
    });

    test('data-URI blijft ongewijzigd', () {
      const md = '![Alt](data:image/png;base64,abc123)\n';
      final result = rebaseImagePathsForTesting(
        md,
        '/project/bron.md',
        '/output/rapport.md',
      );
      expect(result, md);
    });

    test('absoluut pad blijft ongewijzigd', () {
      const md = '![Alt](/abs/foto.png)\n';
      final result = rebaseImagePathsForTesting(
        md,
        '/project/bron.md',
        '/output/rapport.md',
      );
      expect(result, md);
    });

    test('sourcePath null → geen rebasing', () {
      const md = '![Alt](images/foto.png)\n';
      final result = rebaseImagePathsForTesting(md, null, '/output/rapport.md');
      expect(result, md);
    });
  });

  // #1720: buildDocumentExportBytes is de headless byte-bouwer die op web
  // rechtstreeks naar FilePicker.saveFile gaat en op desktop door
  // writeDocumentExport atomisch wordt weggeschreven. De bytes moeten in beide
  // paden identiek zijn — de split mag geen inhoudelijke wijziging zijn.
  group('buildDocumentExportBytes (#1720)', () {
    test(
      'md-bytes komen overeen met wat writeDocumentExport schrijft',
      () async {
        await withBundle((bundle) async {
          final out = p.join(temp.path, 'rapport.md');
          await writeDocumentExport(
            bundle,
            DocumentExportFormat.md,
            html: MarpHtmlService(loadAsset: _diskLoader),
            enforcementPolicy: const ClassificationEnforcementPolicy(),
            outputPath: out,
          );
          final onDisk = await File(out).readAsBytes();

          final bytes = await buildDocumentExportBytes(
            bundle,
            DocumentExportFormat.md,
            html: MarpHtmlService(loadAsset: _diskLoader),
            outputPath: out,
          );
          expect(bytes, onDisk);
        });
      },
    );

    test(
      'html-bytes bevatten dezelfde inhoud als wat writeDocumentExport schrijft',
      () async {
        await withBundle((bundle) async {
          final out = p.join(temp.path, 'rapport.html');
          await writeDocumentExport(
            bundle,
            DocumentExportFormat.html,
            html: MarpHtmlService(loadAsset: _diskLoader),
            enforcementPolicy: const ClassificationEnforcementPolicy(),
            outputPath: out,
          );
          final onDisk = utf8.decode(await File(out).readAsBytes());

          final bytes = await buildDocumentExportBytes(
            bundle,
            DocumentExportFormat.html,
            html: MarpHtmlService(loadAsset: _diskLoader),
            outputPath: out,
          );
          // HTML kan niet-deterministische elementen bevatten (bijv. een
          // cache-buster in een asset-URL), dus vergelijken we de inhoud
          // die door de projectie komt, niet de exacte bytes.
          final decoded = utf8.decode(bytes);
          expect(decoded, contains('<section class="document"'));
          expect(decoded, contains('UNIEKPROZA'));
          expect(onDisk, contains('UNIEKPROZA'));
        });
      },
    );

    test(
      'latex-bytes komen overeen met wat writeDocumentExport schrijft',
      () async {
        await withBundle((bundle) async {
          final out = p.join(temp.path, 'rapport.tex');
          await writeDocumentExport(
            bundle,
            DocumentExportFormat.latex,
            html: MarpHtmlService(loadAsset: _diskLoader),
            enforcementPolicy: const ClassificationEnforcementPolicy(),
            outputPath: out,
          );
          final onDisk = await File(out).readAsBytes();

          final bytes = await buildDocumentExportBytes(
            bundle,
            DocumentExportFormat.latex,
            html: MarpHtmlService(loadAsset: _diskLoader),
            outputPath: out,
          );
          expect(bytes, onDisk);
        });
      },
    );

    test(
      'pdf-bytes zijn een geldige PDF met de geprojecteerde inhoud',
      () async {
        await withBundle((bundle) async {
          final out = p.join(temp.path, 'rapport.pdf');
          await writeDocumentExport(
            bundle,
            DocumentExportFormat.pdf,
            html: MarpHtmlService(loadAsset: _diskLoader),
            enforcementPolicy: const ClassificationEnforcementPolicy(),
            outputPath: out,
          );
          final onDisk = await File(out).readAsBytes();

          final bytes = await buildDocumentExportBytes(
            bundle,
            DocumentExportFormat.pdf,
            html: MarpHtmlService(loadAsset: _diskLoader),
            outputPath: out,
          );
          // Een PDF kan niet-deterministische object-IDs en timestamps
          // bevatten, dus vergelijken we structuur, niet exacte bytes.
          expect(bytes, isNotEmpty);
          expect(bytes.sublist(0, 5), [37, 80, 68, 70, 45]); // %PDF-
          expect(onDisk.sublist(0, 5), [37, 80, 68, 70, 45]); // %PDF-
          expect(bytes.length, closeTo(onDisk.length, onDisk.length * 0.1));
        });
      },
    );

    test('pdf-callbacks vuren vanuit buildDocumentExportBytes', () async {
      await withBundle((bundle) async {
        final unsupported = <Set<int>>[];
        final coarse = <LogoResolution>[];
        final tooWide = <int>[];
        await buildDocumentExportBytes(
          bundle,
          DocumentExportFormat.pdf,
          html: MarpHtmlService(loadAsset: _diskLoader),
          onPdfUnsupportedCharacters: unsupported.add,
          onPdfCoarseLogo: coarse.add,
          onPdfTablesTooWide: tooWide.add,
        );
        // Gewone Nederlandse tekst zonder exotische tekens → geen melding.
        expect(unsupported, isEmpty);
        expect(coarse, isEmpty);
        expect(tooWide, isEmpty);
      });
    });

    test('pdf-callbacks vuren bij niet-ondersteunde tekens', () async {
      final bundle = await buildDocumentExportBundle(
        '# Verslag\n\n日本語 in de tekst.\n',
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      final unsupported = <Set<int>>[];
      await buildDocumentExportBytes(
        bundle,
        DocumentExportFormat.pdf,
        html: MarpHtmlService(loadAsset: _diskLoader),
        onPdfUnsupportedCharacters: unsupported.add,
      );
      expect(unsupported, hasLength(1));
      expect(unsupported.single.map(String.fromCharCode).join(), contains('日'));
    });

    test('pdf-callback vuurt bij een tabel die niet op het blad past', () async {
      // Dat de renderer zo'n tabel telt staat vast in
      // pdf_table_column_widths_test. Hier staat vast dat het getal ook
      // wérkelijk de schil bereikt. Die schakel was alleen bewaakt met een
      // greep in de brontekst van het bewerkscherm, en die blijft groen als de
      // doorgifte in deze dienst wegvalt: met `onPdfTablesTooWide` uitgezet
      // bleven alle 153 tests in test/pdf/ staan (#1789).
      //
      // 64 plus 128 hexadecimale tekens naast elkaar passen op geen enkele
      // maat — dezelfde vorm als de renderertoets, nu door de hele keten.
      final bundle = await buildDocumentExportBundle(
        '# Verslag\n\n'
        '| Bestandstype | Bestandsnaam | SHA-256 | SHA-512 |\n'
        '|---|---|---|---|\n'
        '| EVTX | `RD01-SecurityLogs.evtx` | `${'a' * 64}` | `${'b' * 128}` |\n',
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      final tooWide = <int>[];
      await buildDocumentExportBytes(
        bundle,
        DocumentExportFormat.pdf,
        html: MarpHtmlService(loadAsset: _diskLoader),
        onPdfTablesTooWide: tooWide.add,
      );
      expect(tooWide, [1]);
    });

    test('sourcePath null → geen rebasing in md-bytes', () async {
      await withBundle((bundle) async {
        final bytes = await buildDocumentExportBytes(
          bundle,
          DocumentExportFormat.md,
          html: MarpHtmlService(loadAsset: _diskLoader),
          sourcePath: null,
          outputPath: null,
        );
        final content = utf8.decode(bytes);
        expect(content, contains('UNIEKPROZA'));
      });
    });
  });
}
