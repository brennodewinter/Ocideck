// Bewaakt dat de tijdlijn haar tekst *heel* laat: de bestaande
// `timeline_preview_test.dart` controleert of kaarten elkaar niet overlappen,
// maar niet of er nog iets leesbaars in staat. Daardoor kon een tijdlijn met
// zes normale gebeurtenissen stilzwijgend élke titel en beschrijving met een
// ellipsis afkappen zonder dat één test rood werd.
//
// De meting gebeurt met een écht lettertype (het testlettertype rendert elk
// teken als een blok van gelijke breedte en zou de afbreking dus verkeerd
// inschatten) en op de renderboom zelf: `didExceedMaxLines` is precies wat de
// gebruiker als "…" op de dia ziet.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Zes gebeurtenissen met omschrijvingen van de lengte die auteurs werkelijk
/// typen (tot 64 tekens) — geen kunstmatig korte testtekst.
const _realistic = [
  '2017 :: Start normcommissie :: '
      'ISO/IEC JTC 1/SC 42, de commissie voor kunstmatige intelligentie',
  'Dec 2023 :: Publicatie :: '
      'ISO/IEC 42001:2023 verschijnt als eerste AIMS-norm',
  '2024 :: Eerste certificaten :: '
      'Certificerende instellingen starten met accreditatie en audits',
  'Aug 2024 :: EU AI Act van kracht :: '
      'Wetgeving vergroot de vraag naar aantoonbare AI-governance',
  'Begin 2026 :: Honderdste certificaat :: '
      'De teller passeert wereldwijd de honderd',
  'Nu :: Circa 350 certificaten :: '
      'Groei versnelt nu meer instellingen geaccrediteerd zijn',
];

Future<void> _loadFont() async {
  final data = File('assets/fonts/Inter-Variable.ttf').readAsBytesSync();
  await (FontLoader(
    'Inter',
  )..addFont(Future.value(ByteData.view(data.buffer)))).load();
}

/// Alle tekst op de dia die met een ellipsis is ingekort.
List<String> _truncated(WidgetTester tester) {
  final cut = <String>[];
  void walk(RenderObject node) {
    if (node is RenderParagraph && node.didExceedMaxLines) {
      cut.add(node.text.toPlainText());
    }
    node.visitChildren(walk);
  }

  walk(tester.binding.rootElement!.renderObject!);
  return cut;
}

Future<void> _pump(
  WidgetTester tester,
  List<String> bullets,
  double width, {
  TimelineLayout layout = TimelineLayout.auto,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: width * 9 / 16,
            child: SlidePreviewWidget(
              slide: Slide.create(SlideType.timeline).copyWith(
                title: 'Tijdlijn',
                bullets: bullets,
                timelineLayout: layout,
              ),
              themeProfile: const ThemeProfile(fontFamily: 'Inter'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(_loadFont);

  for (final width in [800.0, 1280.0, 1920.0]) {
    testWidgets('zes gebeurtenissen blijven heel op ${width.toInt()}px', (
      tester,
    ) async {
      await _pump(tester, _realistic, width);
      expect(
        _truncated(tester),
        isEmpty,
        reason:
            'Een tijdlijn met zes normale gebeurtenissen hoort volledig te '
            'passen; deze tekst is afgekapt',
      );
    });
  }

  testWidgets('ook staand (verticale opstelling) blijft de tekst heel', (
    tester,
  ) async {
    await _pump(tester, _realistic, 1280, layout: TimelineLayout.vertical);
    expect(_truncated(tester), isEmpty);
  });

  testWidgets('een lange marker duwt de titel niet uit de kaart', (
    tester,
  ) async {
    // De badge zat niet in een begrenzing: een extreem lange marker leverde een
    // echte RenderFlex-overloop op in plaats van een nette inkorting.
    await _pump(tester, [
      'Een buitensporig lange markering die nooit past :: Titel :: Tekst',
      '2024 :: Tweede :: Nog wat tekst',
    ], 1280);
    expect(tester.takeException(), isNull);
  });
}
