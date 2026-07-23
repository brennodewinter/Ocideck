import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

const _l10n = AppLocalizations(Locale('nl'));

// De slide-instellingen.
//
// Twee dingen worden hier vastgehouden, en het tweede is het belangrijkst.
//
// 1. Eén vorm. Elke instelling is een regel met de bediening rechts, gegroepeerd
//    naar de vraag die je stelt. Zolang elke instelling zijn eigen rij optuigde,
//    dreef de vorm bij elke nieuwe feature verder uiteen — en zo is dit blok ook
//    lelijk geworden.
//
// 2. De ingeklapte kop vertelt wat er afwijkt. Dat is geen versiering: de
//    dispositie "weglaten" bepáált wat de ontvanger krijgt. Kun je dat niet zien
//    zonder open te klappen, dan klap je niet open, en dan mis je het.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Slide Function(Slide)? slide,
    ThemeProfile Function(ThemeProfile)? profile,
    Size surface = const Size(900, 2400),
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');

    final deck = container.read(deckProvider).deck!;
    if (profile != null) {
      notifier.updateThemeProfile(profile(deck.themeProfile));
    }
    if (slide != null) {
      notifier.updateSlide(0, slide(deck.slides.single));
    }

    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> expand(WidgetTester tester) async {
    final toggle = find.text(_l10n.d('Slide-instellingen'));
    expect(toggle, findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  group('het blok', () {
    testWidgets('start ingeklapt en klapt open', (tester) async {
      await pump(tester);

      expect(find.text(_l10n.d('Automatisch doorgaan')), findsNothing);
      expect(find.text(_l10n.d('TLP van deze slide')), findsNothing);

      await expand(tester);

      expect(find.text(_l10n.d('Automatisch doorgaan')), findsOneWidget);
      expect(find.text(_l10n.d('TLP van deze slide')), findsOneWidget);
      expect(find.text(_l10n.d('Persoonsgegevens')), findsOneWidget);
    });

    testWidgets('groepeert naar de vraag die je stelt', (tester) async {
      // Niet één platte lijst van zeven dingen, maar drie vragen: wat staat er
      // op de slide, wat gebeurt er tijdens het presenteren, en wat mag de
      // ontvanger ermee.
      await pump(tester);
      await expand(tester);

      expect(
        find.text(_l10n.d('Tijdens presenteren').toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(_l10n.d('Classificatie en privacy').toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('toont geen dode schakelaar voor een logo dat er niet is', (
      tester,
    ) async {
      // Een uitgegrijsde schakelaar voor iets dat het stijlprofiel niet heeft, is
      // erger dan een ontbrekende: hij belooft een keuze die er niet is.
      await pump(tester, profile: (p) => p.copyWith(clearLogo: true));
      await expand(tester);

      expect(find.text(_l10n.d('Logo tonen')), findsNothing);
    });

    testWidgets('en wél als het profiel een logo heeft', (tester) async {
      await pump(tester, profile: (p) => p.copyWith(logoPath: 'logo.png'));
      await expand(tester);

      expect(find.text(_l10n.d('Logo tonen')), findsOneWidget);
    });
  });

  group(
    'nabijheid: de groepen zijn kaarten, geen regels over de volle breedte',
    () {
      // De aanleiding: bij een breed paneel stond het label op x≈290 en de
      // schakelaar op x≈1330. Duizend pixels tussen twee dingen die bij elkaar
      // horen — je oog moet heen en weer, en bij zes regels raak je kwijt welke
      // schakelaar bij welk label hoort.
      Offset labelAt(WidgetTester tester, String group) =>
          tester.getTopLeft(find.text(_l10n.d(group).toUpperCase()));

      testWidgets('breed: de drie kaarten staan náást elkaar', (tester) async {
        await pump(
          tester,
          profile: (p) => p.copyWith(logoPath: 'logo.png'),
          surface: const Size(1600, 1600),
        );
        await expand(tester);

        final a = labelAt(tester, 'Op deze slide');
        final b = labelAt(tester, 'Tijdens presenteren');
        final c = labelAt(tester, 'Classificatie en privacy');

        expect(a.dy, b.dy, reason: 'zelfde rij');
        expect(b.dy, c.dy, reason: 'zelfde rij');
        expect(a.dx, lessThan(b.dx));
        expect(b.dx, lessThan(c.dx));
      });

      testWidgets('smal: ze stapelen terug', (tester) async {
        // Kolommen die niet passen, zijn erger dan geen kolommen: dan wordt het
        // label afgekapt en de bediening geplet. Onder de ~360px per kaart valt
        // de indeling terug op één kolom.
        await pump(
          tester,
          profile: (p) => p.copyWith(logoPath: 'logo.png'),
          surface: const Size(680, 2400),
        );
        await expand(tester);

        final a = labelAt(tester, 'Op deze slide');
        final b = labelAt(tester, 'Tijdens presenteren');
        final c = labelAt(tester, 'Classificatie en privacy');

        expect(a.dx, b.dx, reason: 'zelfde kolom');
        expect(a.dy, lessThan(b.dy));
        expect(b.dy, lessThan(c.dy));
      });

      testWidgets('en de bediening blijft dicht bij haar label', (
        tester,
      ) async {
        // De harde eis achter dit hele herontwerp. Binnen een kaart mag de afstand
        // van label naar schakelaar niet weer richting de volle paneelbreedte
        // groeien — dan is er niets opgelost.
        await pump(
          tester,
          profile: (p) => p.copyWith(logoPath: 'logo.png'),
          surface: const Size(1600, 1600),
        );
        await expand(tester);

        final label = tester.getTopRight(find.text(_l10n.d('Logo tonen')));
        final control = tester.getTopLeft(find.byType(Switch).first);

        expect(control.dx - label.dx, lessThan(340));
      });
    },
  );

  group('de duur verschijnt pas als de timing aan staat', () {
    testWidgets('uit: geen stepper', (tester) async {
      // Voorheen stonden een min, een waarde en een plus er altijd, met een
      // streepje als de instelling uit stond. Drie knoppen die niets deden.
      await pump(tester);
      await expand(tester);

      expect(find.byTooltip(_l10n.d('Duur verlengen')), findsNothing);
    });

    testWidgets('aan: de stepper met de waarde', (tester) async {
      await pump(tester, slide: (s) => s.copyWith(advanceDuration: 3.0));
      await expand(tester);

      expect(find.byTooltip(_l10n.d('Duur verlengen')), findsOneWidget);
      expect(find.text('3.0 s'), findsOneWidget);
    });
  });

  group('de ingeklapte kop vat samen wat er afwijkt', () {
    testWidgets('een gezette TLP', (tester) async {
      await pump(tester, slide: (s) => s.copyWith(tlp: TlpLevel.amber));
      expect(find.text('TLP:AMBER'), findsOneWidget);
    });

    testWidgets('een geredigeerde slide — dit is de badge die ertoe doet', (
      tester,
    ) async {
      // "Weglaten" bepaalt wat de ontvanger krijgt. Voorheen zag je dat alleen
      // door het blok open te klappen, en dus zag je het niet.
      await pump(
        tester,
        slide: (s) => s.copyWith(privacy: PrivacyDisposition.redact),
      );
      expect(find.text(_l10n.d('Weggelaten')), findsOneWidget);
    });

    testWidgets('en de automatische doorloop', (tester) async {
      await pump(tester, slide: (s) => s.copyWith(advanceDuration: 2.5));
      expect(find.text('2.5 s'), findsOneWidget);
    });

    testWidgets('een schone slide draagt geen badges', (tester) async {
      await pump(tester);
      expect(find.text('TLP:AMBER'), findsNothing);
      expect(find.text(_l10n.d('Weggelaten')), findsNothing);
    });
  });

  group('weergave beperken (#672)', () {
    Slide bulletsSlide(Slide _) => Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Lijst', bullets: const ['a', 'b', 'c', 'd']);

    Slide tableSlide(Slide _) => Slide.create(SlideType.table).copyWith(
      title: 'Tabel',
      tableRows: const [
        ['Naam', 'Waarde'],
        ['x', 'tekst'],
        ['y', 'nog meer tekst'],
      ],
    );

    Future<void> zetLimietAan(WidgetTester tester) async {
      await expand(tester);
      final schakel = find.text(_l10n.d('Beperk het aantal getoonde items'));
      await tester.ensureVisible(schakel);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.ancestor(of: schakel, matching: find.byType(Row)),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('aanzetten zet een limiet op de slide, met de tellerregel', (
      tester,
    ) async {
      final container = await pump(tester, slide: bulletsSlide);
      await zetLimietAan(tester);

      final slide = container.read(deckProvider).deck!.slides.single;
      expect(slide.viewLimit, isNotNull);
      expect(slide.viewLimit!.isActive, isTrue);
      // De tellerregel: hoeveel er in de data zit en hoeveel de dia toont —
      // zodat de limiet nooit als verlies leest.
      expect(find.textContaining(_l10n.d('In de data')), findsOneWidget);
    });

    testWidgets('een niet-numerieke sorteerkolom krijgt een waarschuwing', (
      tester,
    ) async {
      final container = await pump(tester, slide: tableSlide);
      await zetLimietAan(tester);

      // Hoogste op kolom 1, en die kolom is tekst.
      final notifier = container.read(deckProvider.notifier);
      final slide = container.read(deckProvider).deck!.slides.single;
      notifier.updateSlide(
        0,
        slide.copyWith(
          viewLimit: const DisplayWindowSpec(
            limit: 1,
            mode: DisplayWindowMode.top,
            key: '1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          _l10n.d(
            'De sorteerkolom bevat geen getallen; hoogste/laagste en samenvoegen werken dan niet zinvol.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('een titeldia heeft de sectie niet', (tester) async {
      await pump(tester);
      await expand(tester);
      expect(
        find.text(_l10n.d('Beperk het aantal getoonde items')),
        findsNothing,
        reason: 'een dia zonder databron heeft niets te beperken',
      );
    });
  });
}
