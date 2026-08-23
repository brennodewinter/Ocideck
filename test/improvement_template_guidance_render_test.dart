import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

const _profile = ThemeProfile(fontFamily: 'Inter');
const _thumbnailWidths = [180.0, 480.0];

/// De verwachte set maakt deze renderproef ook tot een regressietest voor de
/// invulhulp zelf. Alleen `where((slide) => slide.skipped)` gebruiken zou op een
/// ouder sjabloon zonder hulpdia's vacuüm groen blijven.
const _guidanceTitles = <String, List<String>>{
  'procesverbetering-dmaic': [
    'Zo werk je met dit sjabloon',
    'Wat leg je vast bij Definiëren?',
    'Hoe vul je de SIPOC in?',
    'Wat leg je vast bij Meten?',
    'Wat leg je vast bij Analyseren?',
    'Wat leg je vast bij Verbeteren?',
    'Wat leg je vast bij Beheersen?',
  ],
  'procesverbetering-dmadv': [
    'Zo werk je met dit sjabloon',
    'Wat leg je vast bij Definiëren?',
    'Hoe vul je de SIPOC in?',
    'Wat leg je vast bij Meten?',
    'Wat leg je vast bij Analyseren?',
    'Wat leg je vast bij Ontwerp?',
    'Wat leg je vast bij Verifiëren?',
  ],
  'procesverbetering-kaizen': [
    'Zo werk je met dit sjabloon',
    'Wat leg je vast bij Plan?',
    'Hoe vul je de SIPOC in?',
    'Wat leg je vast bij Uitvoeren?',
    'Wat leg je vast bij Controleren?',
  ],
  'procesverbetering-a3': [
    'Zo werk je met dit sjabloon',
    'Wat leg je vast bij Achtergrond?',
    'Hoe vul je de SIPOC in?',
    'Wat leg je vast bij de Huidige toestand?',
    'Wat leg je vast bij de Doelconditie?',
    'Wat leg je vast bij de Oorzaakanalyse?',
    'Wat leg je vast bij Tegenmaatregelen?',
    'Wat leg je vast bij het Implementatieplan?',
    'Wat leg je vast bij Vervolg?',
  ],
  'procesverbetering-8d': [
    'Zo werk je met dit sjabloon',
    'Wat leg je vast bij D0?',
    'Hoe vul je de SIPOC in?',
    'Wat leg je vast bij D1?',
    'Wat leg je vast bij D2?',
    'Wat leg je vast bij D3?',
    'Wat leg je vast bij D4?',
    'Wat leg je vast bij D5?',
    'Wat leg je vast bij D6?',
    'Wat leg je vast bij D7?',
    'Wat leg je vast bij D8?',
  ],
  'procesverbetering-sipoc': [
    'Zo werk je met dit sjabloon',
    'Wanneer zijn de grenzen duidelijk genoeg?',
    'Invullen van rechts naar links',
    'Voorbeeld van één samenhangende rij',
  ],
};

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
  FlutterQuillLocalizations.delegate,
];

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('nl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: _delegates,
  home: home,
);

List<Slide> _guidanceFor(String templateId) {
  final path = 'assets/templates/$templateId.nl.md';
  final deck = MarkdownService().parseDeck(File(path).readAsStringSync());
  expect(deck, isNotNull, reason: path);
  final guidance = deck!.slides.where((slide) => slide.skipped).toList();
  expect(
    guidance.map((slide) => slide.title),
    orderedEquals(
      _guidanceTitles[templateId]!.map(
        (title) => title == 'Zo werk je met dit sjabloon'
            ? title
            : 'Checklist — $title',
      ),
    ),
    reason: '$path moet precies de verwachte overgeslagen invulhulp bevatten',
  );
  return guidance;
}

Future<void> _pumpFullPreview(WidgetTester tester, Slide slide) async {
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 960,
            height: 540,
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: _profile,
              reportLanguage: 'nl',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpThumbnail(
  WidgetTester tester,
  Slide slide,
  double width,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SlideThumbnail(
                slide: slide,
                index: 0,
                slideCount: 1,
                reportLanguage: 'nl',
                themeProfile: _profile,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Inter-Variable.ttf').readAsBytesSync();
    await (FontLoader(
      'Inter',
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  });

  testWidgets('alle Nederlandse invulhulp rendert op 960×540', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final templateId in _guidanceTitles.keys) {
      for (final slide in _guidanceFor(templateId)) {
        final label = '$templateId — ${slide.title}';
        expect(slide.skipped, isTrue, reason: label);

        await _pumpFullPreview(tester, slide);

        expect(find.byType(SlidePreviewWidget), findsOneWidget, reason: label);
        final preview = tester.widget<SlidePreviewWidget>(
          find.byType(SlidePreviewWidget),
        );
        expect(preview.slide, same(slide), reason: label);
        expect(preview.slide.skipped, isTrue, reason: label);
        expect(
          tester.getSize(find.byType(SlidePreviewWidget)),
          const Size(960, 540),
          reason: label,
        );
        expect(find.text(slide.title), findsOneWidget, reason: label);
        if (slide.title == 'Checklist — Voorbeeld van één samenhangende rij') {
          expect(slide.type, SlideType.table, reason: label);
          expect(
            slide.tableRows.expand((row) => row),
            contains('Verkoop'),
            reason: label,
          );
          expect(find.byType(Table), findsOneWidget, reason: label);
        }
        expect(tester.takeException(), isNull, reason: label);
      }
    }
  });

  testWidgets('alle Nederlandse invulhulp rendert in smalle slidestroken', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in _thumbnailWidths) {
      for (final templateId in _guidanceTitles.keys) {
        for (final slide in _guidanceFor(templateId)) {
          final label = '${width.toInt()} px — $templateId — ${slide.title}';
          expect(slide.skipped, isTrue, reason: label);

          await _pumpThumbnail(tester, slide, width);

          expect(find.byType(SlideThumbnail), findsOneWidget, reason: label);
          final thumbnail = tester.widget<SlideThumbnail>(
            find.byType(SlideThumbnail),
          );
          expect(thumbnail.slide, same(slide), reason: label);
          expect(thumbnail.slide.skipped, isTrue, reason: label);
          final preview = tester.widget<SlidePreviewWidget>(
            find.byType(SlidePreviewWidget),
          );
          expect(preview.slide, same(slide), reason: label);
          expect(preview.slide.skipped, isTrue, reason: label);
          expect(find.text('Overgeslagen'), findsOneWidget, reason: label);
          if (slide.title ==
              'Checklist — Voorbeeld van één samenhangende rij') {
            expect(slide.type, SlideType.table, reason: label);
            expect(
              slide.tableRows.expand((row) => row),
              contains('Verkoop'),
              reason: label,
            );
            expect(find.byType(Table), findsOneWidget, reason: label);
          }
          expect(tester.takeException(), isNull, reason: label);
        }
      }
    }
  });
}
