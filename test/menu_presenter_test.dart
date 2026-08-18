import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

// Fase 3 van #1162: een keuze-menublok aantikken tijdens presenteren springt naar
// de doeldia, via dezelfde navigatiestack als de sprong-uit.
Widget _host(List<Slide> slides) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: FullscreenPresenter(
    slides: slides,
    projectPath: null,
    themeProfile: const ThemeProfile(),
    initialIndex: 0,
  ),
);

void main() {
  testWidgets('een menublok aantikken springt naar de doeldia', (tester) async {
    await tester.pumpWidget(
      _host([
        Slide.create(SlideType.menu).copyWith(
          title: 'Hoofdmenu',
          bullets: ['[Naar prijzen](#prijzen)', '[Naar demo](#demo)'],
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hoofdmenu'), findsOneWidget);

    // Tik het eerste blok — spring naar de dia met anker 'prijzen'.
    await tester.tap(find.text('Naar prijzen'));
    await tester.pumpAndSettle();
    expect(find.text('Prijzen'), findsOneWidget);
    expect(find.text('Demo'), findsNothing);

    // Terug volgt de route: retour naar het menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Hoofdmenu'), findsOneWidget);
  });

  testWidgets('de categoriebalk wisselt welke blokken er staan', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        Slide.create(SlideType.menu).copyWith(
          title: 'Hoofdmenu',
          bullets: [
            groupHeadingBullet('Producten'),
            '[Naar prijzen](#prijzen)',
            groupHeadingBullet('Over ons'),
            '[Naar het team](#team)',
          ],
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Team', anchor: 'team', bullets: ['y']),
      ]),
    );
    await tester.pumpAndSettle();

    // De eerste categorie staat open; de blokken van de tweede zijn er niet.
    expect(find.text('Producten'), findsOneWidget);
    expect(find.text('Naar prijzen'), findsOneWidget);
    expect(find.text('Naar het team'), findsNothing);

    await tester.tap(find.text('Over ons'));
    await tester.pumpAndSettle();
    expect(find.text('Naar het team'), findsOneWidget);
    expect(find.text('Naar prijzen'), findsNothing);

    // En een blok uit de tweede categorie springt gewoon.
    await tester.tap(find.text('Naar het team'));
    await tester.pumpAndSettle();
    expect(find.text('Team'), findsOneWidget);

    // Terug naar het menu begint weer bij de eerste categorie: een dia die je
    // opnieuw opent, hoort er hetzelfde uit te zien als de eerste keer.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Naar prijzen'), findsOneWidget);
  });
}
