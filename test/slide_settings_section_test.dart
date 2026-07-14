import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
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

    await tester.binding.setSurfaceSize(const Size(900, 2400));
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
}
