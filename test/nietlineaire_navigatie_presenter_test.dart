import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

// Fase 2 van #1162: de sprong-uit werkend in de presentator, met de
// navigatiestack als "terug". Getoetst zoals de gebruiker het bedient — pijltjes
// sturen, kijken welke dia in beeld staat.
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
  testWidgets('een sprong-uit springt naar het doelanker i.p.v. lineair', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Menu',
          bullets: ['x'],
          anchor: 'menu',
        ),
        Slide.create(SlideType.bullets).copyWith(
          title: 'Tak A',
          bullets: ['y'],
          nextAnchor: 'menu',
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Slot', bullets: ['z']),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);

    // Menu -> Tak A (lineair vooruit).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Tak A'), findsOneWidget);

    // Tak A heeft een sprong-uit naar 'menu' -> terug naar Menu, niet naar Slot.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Slot'), findsNothing);
  });

  testWidgets('"terug" retraced de werkelijke route na een sprong', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Menu',
          bullets: ['x'],
          anchor: 'menu',
        ),
        Slide.create(SlideType.bullets).copyWith(
          title: 'Tak A',
          bullets: ['y'],
          nextAnchor: 'menu',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    // Menu -> Tak A -> (sprong) Menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Menu'), findsOneWidget);

    // Terug volgt de route: naar Tak A (waarvandaan we sprongen), niet lineair
    // naar de eerste brondia.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Tak A'), findsOneWidget);
  });

  testWidgets('een sprong naar een onvindbaar anker valt terug op lineair', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Eerste',
          bullets: ['x'],
          nextAnchor: 'bestaat-niet',
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Tweede', bullets: ['y']),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Eerste'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Tweede'), findsOneWidget);
  });
}
