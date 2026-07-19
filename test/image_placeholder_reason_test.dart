import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De placeholder dekte vier wezenlijk verschillende situaties af met exact
/// hetzelfde grijze vlak: leeg veld, ontbrekend bestand, pad buiten de
/// presentatie, decodeerfout. Wie de presentatie doorstuurde, kon dus niet zien
/// of er nog werk lag of dat er iets stuk was. Deze tests leggen dat verschil
/// vast.
Widget _host(Slide slide, {String? projectPath}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 450,
      child: SlidePreviewWidget(slide: slide, projectPath: projectPath),
    ),
  ),
);

Slide _imageSlide(String path) =>
    Slide(id: 'x', type: SlideType.image, title: 'Titel', imagePath: path);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('een leeg veld blijft neutraal', (tester) async {
    await tester.pumpWidget(_host(_imageSlide('')));
    await tester.pump();

    expect(find.text('Afbeelding'), findsOneWidget);
    expect(find.text('Bestand niet gevonden'), findsNothing);
  });

  testWidgets('een ontbrekend bestand heet een ontbrekend bestand', (
    tester,
  ) async {
    // Het laden van het bestand loopt echt over de schijf; de errorBuilder komt
    // pas een paar frames later. Begrensd doorpompen tot de placeholder er is,
    // in plaats van gokken met één pump.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _host(_imageSlide('images/weg.png'), projectPath: '/deck'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(find.text('Bestand niet gevonden'), findsOneWidget);
    expect(find.text('Afbeelding'), findsNothing);
  });

  testWidgets('een pad buiten de presentatie wordt als zodanig benoemd', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_imageSlide('/elders/foto.png'), projectPath: '/deck'),
    );
    await tester.pump();

    expect(find.text('Buiten de presentatie'), findsOneWidget);
    expect(find.text('Bestand niet gevonden'), findsNothing);
  });

  testWidgets('een verlopen geheugenverwijzing noemt het herladen', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_imageSlide('mem:er-is-niets-meer')));
    await tester.pump();

    expect(find.text('Weg na herladen'), findsOneWidget);
  });

  group('geredigeerde media', () {
    testWidgets('een weggeredigeerde foto is geen leeg veld', (tester) async {
      // De melding die deze tak heeft opgeleverd: een geredigeerde foto toonde
      // hetzelfde grijze "Afbeelding"-vak als een slide waar de auteur nog
      // niets had gekozen. Op een geredigeerde slide leest dat als een vergeten
      // plaatje in plaats van als een ingreep — terwijl de tekst ernaast wél
      // zwarte blokken laat zien.
      await tester.pumpWidget(
        _host(_imageSlide('').copyWith(mediaRedacted: true)),
      );
      await tester.pump();

      expect(find.text('Geredigeerd'), findsOneWidget);
      expect(find.text('Afbeelding'), findsNothing);
      expect(find.byIcon(Icons.block), findsOneWidget);
    });

    testWidgets('het vlak is zwart, ook in donkere modus', (tester) async {
      // Het slate-palet keert om in donkere modus. Zou het redactievlak dat
      // volgen, dan werd het daar bijna wit — en een wit "redactie"-vlak is
      // geen redactie. Daarom vaste inkt, en daarom deze test in beide modi.
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: SlidePreviewWidget(
                  slide: _imageSlide('').copyWith(mediaRedacted: true),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final box = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(SlidePreviewWidget),
                matching: find.byType(ColoredBox),
              )
              .last,
        );
        // Donker genoeg om als redactie te lezen, in beide modi.
        expect(
          box.color.computeLuminance(),
          lessThan(0.1),
          reason: 'redactievlak niet donker bij $brightness',
        );
      }
    });

    testWidgets('een weggeredigeerde video krijgt hetzelfde vlak', (
      tester,
    ) async {
      // Video en audio liepen langs een ándere placeholder, met exact dezelfde
      // fout: een grijs vak met het woord "Video".
      await tester.pumpWidget(
        _host(
          Slide(
            id: 'v',
            type: SlideType.video,
            title: 'Titel',
          ).copyWith(mediaRedacted: true),
        ),
      );
      await tester.pump();

      expect(find.text('Geredigeerd'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
    });
  });
}
