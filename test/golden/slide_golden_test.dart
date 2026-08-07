@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import '../slide_fixtures.dart';

/// Visual-regression goldens for the slide renderer (`SlidePreviewWidget`) — the
/// same widget that drives the editor preview, presenter, thumbnails and the
/// PDF/PPTX rasterisation, so a layout regression here ships everywhere.
///
/// These render with the default flutter-test font (text as boxes), so they
/// catch LAYOUT / structure / colour regressions (elements moving, resizing,
/// disappearing, wrong theme colours) without depending on glyph rendering.
/// They are pixel- and platform-specific — see `make test-golden`.
Future<void> _match(
  WidgetTester tester,
  String name,
  Slide slide, {
  ThemeProfile profile = const ThemeProfile(),
  TlpLevel tlp = TlpLevel.none,
  bool watermark = false,
  int? slideNumber,
  int? slideCount,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1280,
            height: 720,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: profile,
              tlp: tlp,
              showClassificationWatermark: watermark,
              organization: watermark ? 'OciDeck BV' : '',
              slideNumber: slideNumber,
              slideCount: slideCount,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await expectLater(
    find.byType(SlidePreviewWidget),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('title', (tester) async {
    await _match(
      tester,
      'title',
      Slide.create(
        SlideType.title,
      ).copyWith(title: 'OciDeck', subtitle: 'Een ondertitel'),
    );
  });

  testWidgets('section', (tester) async {
    await _match(
      tester,
      'section',
      Slide.create(
        SlideType.section,
      ).copyWith(title: 'Deel 1', subtitle: 'De inleiding'),
    );
  });

  testWidgets('bullets', (tester) async {
    await _match(
      tester,
      'bullets',
      Slide.create(SlideType.bullets).copyWith(
        title: 'Agenda',
        bullets: ['Eerste punt', '\tSubpunt', 'Tweede punt', 'Derde punt'],
      ),
    );
  });

  testWidgets('twoBullets', (tester) async {
    await _match(
      tester,
      'two_bullets',
      Slide.create(SlideType.twoBullets).copyWith(
        title: 'Vergelijking',
        columnTitle1: 'Voor',
        columnTitle2: 'Na',
        bullets: ['Links een', 'Links twee'],
        bullets2: ['Rechts een', 'Rechts twee'],
      ),
    );
  });

  testWidgets('table', (tester) async {
    await _match(
      tester,
      'table',
      Slide.create(SlideType.table).copyWith(
        title: 'Prijzen',
        tableRows: const [
          ['Functie', 'Gratis', 'Pro'],
          ['Export', 'Nee', 'Ja'],
          ['Support', 'E-mail', '24/7'],
        ],
      ),
    );
  });

  // De vorm waarin de kolomverdeling omviel: één brede tekstkolom naast vier
  // korte, met koppen die langer zijn dan hun inhoud, plus het bijschrift van
  // een weergavelimiet. Op tekenaantal verdeeld brak elke korte kop letter voor
  // letter af en werd de rangnummerkolom een kwart slide breed.
  testWidgets('table with narrow headers and a view limit', (tester) async {
    await _match(
      tester,
      'table_narrow_headers',
      Slide.create(SlideType.table).copyWith(
        title: 'Top-5 issues',
        viewLimit: const DisplayWindowSpec(limit: 5),
        tableRows: const [
          ['#', 'Finding', 'Ernst', 'Systemen', 'Orgs'],
          ['1', 'SSL/TLS Certificate expired', 'critical', '6', '1'],
          ['2', 'Unencrypted website traffic', 'high', '31', '1'],
          ['3', 'Open database port(s) detected', 'high', '3', '1'],
          ['4', 'Uncommon open port(s) detected', 'medium', '34', '1'],
          [
            '5',
            'Missing Content Security Policy (CSP) header',
            'medium',
            '31',
            '3',
          ],
          ['6', 'DNSSEC not enabled', 'medium', '16', '3'],
          ['7', 'No DMARC records found', 'medium', '13', '2'],
        ],
      ),
    );
  });

  testWidgets('quote', (tester) async {
    await _match(
      tester,
      'quote',
      Slide.create(SlideType.quote).copyWith(
        quote:
            'De beste manier om de toekomst te voorspellen is haar te maken.',
        quoteAuthor: 'Peter Drucker',
      ),
    );
  });

  testWidgets('code', (tester) async {
    await _match(
      tester,
      'code',
      Slide.create(SlideType.code).copyWith(
        title: 'Voorbeeld',
        codeLanguage: 'dart',
        customMarkdown: "void main() {\n  print('hallo');\n}",
      ),
    );
  });

  testWidgets('finding with CVSS score card', (tester) async {
    await _match(
      tester,
      'finding_cvss',
      Slide.create(SlideType.finding).copyWith(
        customMarkdown:
            '# F-03 · SQL injection in the login form\n'
            '\n'
            '**Scope object:** `https://app.client.example/login`\n'
            '**CVSS 4.0:** 9.3 (Critical) · '
            '`CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/'
            'SC:N/SI:N/SA:N`\n'
            '**CWE:** [CWE-89](https://cwe.mitre.org/data/definitions/89.html)\n'
            '\n'
            '## Description\n\n'
            'The login endpoint accepts unsanitized SQL input.\n',
      ),
    );
  });

  testWidgets('image placeholder', (tester) async {
    await _match(
      tester,
      'image_placeholder',
      Slide.create(
        SlideType.image,
      ).copyWith(imagePath: 'images/ontbreekt.png', imageCaption: 'Bijschrift'),
    );
  });

  testWidgets('bullets with TLP marking and watermark', (tester) async {
    await _match(
      tester,
      'bullets_tlp_amber',
      Slide.create(SlideType.bullets).copyWith(
        title: 'Vertrouwelijk',
        bullets: ['Geheim punt', 'Nog een punt'],
      ),
      tlp: TlpLevel.amber,
      watermark: true,
      slideNumber: 3,
      slideCount: 10,
    );
  });

  // #617: de negen tests hierboven dekken acht van de 24 slidetypes. Elk type
  // dat ná de eerste ronde gebouwd is — chart, cockpit, timeline, scorecard,
  // finding, checklist, scopeMatrix, discoveries, findingsSummary, question —
  // had géén visuele regressietest. Een themawijziging of een aanpassing in
  // `SlidePreviewWidget` kon hun layout verschuiven zonder dat er iets rood
  // werd.
  //
  // Uitputtend over het enum dus, met dezelfde fixture die de
  // markdown-ronde-trip en de rasterizer gebruiken: één lijst, want twee
  // lijsten lopen uiteen. De negen hierboven blijven — die dragen rijkere
  // inhoud (een TLP-markering, een ontbrekende afbeelding) dan een
  // standaardfixture kan.
  // De mermaid-gedreven types (gantt, flow) tekenen hun diagram op een verborgen
  // WebView die onder `flutter test` niet draait; hun golden legt daarom de
  // scaffold (kader, titel, laadstaat) vast, niet het diagram zelf — dat wordt
  // gedekt door `mermaid_diagram_test.dart` en de DSL-omzettoetsen. De golden
  // blijft deterministisch (vaste pump), dus bewaakt nog steeds of de
  // type-scaffold heel blijft.
  group('elk slidetype heeft een golden', () {
    for (final type in SlideType.values) {
      testWidgets(type.name, (tester) async {
        await _match(tester, 'type_${type.name}', slideMetInhoud(type));
      });
    }
  });
}
