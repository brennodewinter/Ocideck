import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
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

  // #1162: de blokken waren alleen met de muis te bedienen. Wie met een klikker
  // presenteert of geen muis kan gebruiken, kwam een menudia niet door — en dat
  // is nu juist het diatype dat over navigeren gaat (WCAG 2.1.1).
  group('toetsenbordbediening', () {
    testWidgets('Tab brengt de focus op een blok, Enter springt', (
      tester,
    ) async {
      // De doeldia is bewust níet de dia erna: Enter is in de presentator ook
      // "volgende dia", en met een doel dat toevallig de buurdia is bewijst deze
      // proef niets. Hier gaat het blok naar dia 3 en zou doorbladeren op dia 2
      // uitkomen.
      await tester.pumpWidget(
        _host([
          Slide.create(
            SlideType.menu,
          ).copyWith(title: 'Hoofdmenu', bullets: ['[Naar demo](#demo)']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Tussendia', bullets: ['x']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Demo'), findsOneWidget);
      expect(
        find.text('Tussendia'),
        findsNothing,
        reason: 'Enter volgde de sprong en bladerde niet gewoon door',
      );
    });

    testWidgets('spatie activeert het blok en bladert niet door', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          Slide.create(
            SlideType.menu,
          ).copyWith(title: 'Hoofdmenu', bullets: ['[Naar demo](#demo)']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Tussendia', bullets: ['x']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      // Spatie is in de presentator "volgende dia"; met de focus op een blok
      // hoort het blok voor te gaan, niet de dia erna.
      expect(find.text('Demo'), findsOneWidget);
      expect(find.text('Tussendia'), findsNothing);
    });

    testWidgets('Escape geeft de dia de toetsen terug', (tester) async {
      await tester.pumpWidget(
        _host([
          Slide.create(
            SlideType.menu,
          ).copyWith(title: 'Hoofdmenu', bullets: ['[Naar demo](#demo)']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Tussendia', bullets: ['x']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      // Zonder focus doet spatie weer gewoon wat hij overal doet.
      expect(find.text('Tussendia'), findsOneWidget);
    });

    testWidgets('een blok is voor een schermlezer een knop met zijn uitleg', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host([
          Slide.create(SlideType.menu).copyWith(
            title: 'Hoofdmenu',
            bullets: ['[Prijzen](#prijzen) — Wat het kost'],
          ),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Prijzen. Wat het kost')),
        matchesSemantics(isButton: true, hasEnabledState: false),
      );
      handle.dispose();
    });

    testWidgets('een tekstblok zonder doel is geen knop', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host([
          Slide.create(
            SlideType.menu,
          ).copyWith(title: 'Hoofdmenu', bullets: ['Gewoon tekst']),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Gewoon tekst'), findsNothing);
      handle.dispose();
    });

    testWidgets('de focusring is een omtrek en geen vlak over het blok', (
      tester,
    ) async {
      // De eerste poging tekende de halo met een `BoxShadow` zonder vervaging.
      // Dat is geen omtrek maar een gevulde vorm, en in de voorgrond zonder
      // achtergrondkleur overschilderde hij het hele blok: label, uitleg en pijl
      // weg, precies op het blok waar de presentator stond. De proeven eromheen
      // toetsten alleen gedrag en zagen er niets van (#1162, beeldkeuring).
      await tester.pumpWidget(
        _host([
          Slide.create(SlideType.menu).copyWith(
            title: 'Hoofdmenu',
            bullets: ['[Naar demo](#demo) — Kijk mee'],
          ),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Demo', anchor: 'demo', bullets: ['y']),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // De ring hangt in een IgnorePointer-overlay om het blok heen.
      final ringen = find.descendant(
        of: find.byKey(menuFocusRingKey),
        matching: find.byType(DecoratedBox),
      );
      expect(
        ringen,
        findsWidgets,
        reason: 'er hoort een ring om het blok met de focus te staan',
      );

      for (final box in tester.widgetList<DecoratedBox>(ringen)) {
        final decoration = box.decoration as BoxDecoration;
        expect(
          decoration.border,
          isNotNull,
          reason: 'de ring hoort een omtrek te zijn',
        );
        // Dit is waar het de vorige keer op misging: een vulling, een verloop of
        // een BoxShadow tekent een dicht vlak in plaats van een omtrek, en dekt
        // het blok af.
        expect(
          decoration.color,
          isNull,
          reason: 'een vulling dekt het blok af',
        );
        expect(decoration.gradient, isNull, reason: 'idem, als verloop');
        expect(
          decoration.boxShadow,
          anyOf(isNull, isEmpty),
          reason:
              'een BoxShadow zonder vervaging is een gevulde vorm, geen gloed',
        );
      }

      // En de ring ligt buiten het blok, niet erin: hij omsluit het label ruim,
      // in plaats van er een hap uit te nemen. Dat was de tweede fout — de ring
      // at bij zestien blokken de helft van een schijf op en sneed het label af.
      final labelVlak = tester.getRect(find.text('Naar demo'));
      final ringVlak = tester.getRect(ringen.first);
      expect(
        ringVlak.contains(labelVlak.topLeft) &&
            ringVlak.contains(labelVlak.bottomRight),
        isTrue,
        reason: 'de ring ($ringVlak) omsluit het label ($labelVlak) niet',
      );
      expect(find.text('Kijk mee'), findsOneWidget);
    });

    testWidgets('de focus verschuift niets op de dia', (tester) async {
      // De ring mag geen ruimte van het blok afnemen: doet hij dat wel, dan
      // springt de tekst zodra je erheen tabt — en bij een vol menu wordt hij
      // afgesneden.
      Future<Rect> labelVlak({required bool metFocus}) async {
        await tester.pumpWidget(
          _host([
            Slide.create(SlideType.menu).copyWith(
              title: 'Hoofdmenu',
              menuLayout: MenuLayout.circle,
              bullets: [
                for (var i = 0; i < 16; i++) '[Blok $i](#doel$i) — uitleg',
              ],
            ),
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Doel', anchor: 'doel0', bullets: ['y']),
          ]),
        );
        await tester.pumpAndSettle();
        if (metFocus) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        return tester.getRect(find.text('Blok 0'));
      }

      final zonder = await labelVlak(metFocus: false);
      final met = await labelVlak(metFocus: true);
      expect(met, zonder, reason: 'het label verschoof door de focus');
    });

    testWidgets('de categoriepillen zijn ook met het toetsenbord te wisselen', (
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

      // De balk staat vóór de blokken, dus de eerste twee stops zijn de pillen.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Naar het team'), findsOneWidget);
      expect(find.text('Naar prijzen'), findsNothing);
    });
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
