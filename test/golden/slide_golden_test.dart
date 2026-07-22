@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
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
  group('elk slidetype heeft een golden', () {
    for (final type in SlideType.values) {
      testWidgets(type.name, (tester) async {
        await _match(tester, 'type_${type.name}', slideMetInhoud(type));
      });
    }
  });
}
