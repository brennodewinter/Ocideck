import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/panels/slide_quality_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

Widget _host(Deck deck) {
  AppLocalizations.setActiveLanguageCode('nl');
  return ProviderScope(
    overrides: [deckProvider.overrideWith((ref) => _deckNotifier(deck))],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: Scaffold(body: SlideQualityPanel()),
    ),
  );
}

void main() {
  Deck denseBulletDeck(int count) => Deck(
    title: 'Demo',
    slides: [
      Slide.create(SlideType.bulletsImage).copyWith(
        title: 'blah blah blah',
        imagePath: 'images/pasted.png',
        bullets: List.generate(
          count,
          (i) =>
              'Controleer op een SPECI: Kijk of er tussentijds een speciaal '
              'weerrapport is uitgegeven vanwege plotseling veranderde '
              'omstandigheden ${i + 1}.',
        ),
      ),
    ],
  );

  // Dertien bullets: ruim boven [kMoveToNotesMaxBulletCount] (#912), dus 'te
  // veel bullets' — splitsen is de enige remedie.
  Deck overfullDeck() => denseBulletDeck(13);

  // Zeven lange 'label: uitleg'-bullets: onder de bullet-drempel maar wél
  // woord-dicht, zodat er een dichtheidsmelding is én 'Uitleg naar notities'
  // mag verschijnen.
  Deck denseFewDeck() => denseBulletDeck(7);

  testWidgets('shows quality issues for an overfull split bullet slide', (
    tester,
  ) async {
    await tester.pumpWidget(_host(overfullDeck()));
    await tester.pump();

    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsNothing,
    );
    expect(find.textContaining('Slidekwaliteit'), findsOneWidget);
    expect(find.textContaining('fout(en)'), findsOneWidget);
    expect(find.textContaining('waarschuwing(en)'), findsOneWidget);
  });

  testWidgets('offers a Splits slide action that splits a dense bullet slide', (
    tester,
  ) async {
    await tester.pumpWidget(_host(overfullDeck()));
    await tester.pump();
    // Expand the panel so the issue tiles (and the split action) are shown.
    await tester.tap(find.textContaining('Slidekwaliteit'));
    await tester.pump();

    final splitButton = find.widgetWithText(TextButton, 'Splits slide');
    expect(splitButton, findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SlideQualityPanel)),
    );
    expect(container.read(deckProvider).deck!.slides.length, 1);

    await tester.ensureVisible(splitButton.first);
    await tester.tap(splitButton.first);
    await tester.pump();

    // These long bullets barely fit beside the image, so the overfull slide is
    // spread over several pages (not just two) — none left full.
    expect(container.read(deckProvider).deck!.slides.length, greaterThan(1));
  });

  testWidgets(
    'offers an Uitleg naar notities action that trims dense bullets',
    (tester) async {
      await tester.pumpWidget(_host(denseFewDeck()));
      await tester.pump();
      await tester.tap(find.textContaining('Slidekwaliteit'));
      await tester.pump();

      final trimButton = find.widgetWithText(
        TextButton,
        'Uitleg naar notities',
      );
      expect(trimButton, findsWidgets);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SlideQualityPanel)),
      );

      await tester.ensureVisible(trimButton.first);
      await tester.tap(trimButton.first);
      await tester.pump();

      // The label stays on the slide; the explanation moves to the notes, with
      // a dash in front of it (#913).
      final slide = container.read(deckProvider).deck!.slides.first;
      expect(slide.bullets.first, 'Controleer op een SPECI');
      expect(slide.notes.contains('- Controleer op een SPECI'), isTrue);
      expect(slide.notes.contains('Kijk of er tussentijds'), isTrue);
    },
  );

  testWidgets(
    'te veel bullets: alleen Splits slide, geen Uitleg naar notities (#912)',
    (tester) async {
      // Boven [kMoveToNotesMaxBulletCount] hoort splitsen de enige remedie te
      // zijn: naar de notities halen verandert het aantal bullets niet.
      await tester.pumpWidget(_host(overfullDeck()));
      await tester.pump();
      await tester.tap(find.textContaining('Slidekwaliteit'));
      await tester.pump();

      expect(
        find.widgetWithText(TextButton, 'Splits slide'),
        findsWidgets,
      );
      expect(
        find.widgetWithText(TextButton, 'Uitleg naar notities'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Fix alle problemen splitst een te volle dia in één klik (#915)',
    (tester) async {
      await tester.pumpWidget(_host(overfullDeck()));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SlideQualityPanel)),
      );
      expect(container.read(deckProvider).deck!.slides.length, 1);

      final fixAll = find.widgetWithText(TextButton, 'Fix alle problemen');
      expect(fixAll, findsOneWidget);
      await tester.tap(fixAll);
      await tester.pump();

      // De dia is gesplitst en er verschijnt een terugkoppeling.
      expect(container.read(deckProvider).deck!.slides.length, greaterThan(1));
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'geen Fix-alles-knop als er niets structureel op te lossen valt',
    (tester) async {
      // Een lege dia is een inhoudsmelding, geen structureel probleem.
      final deck = Deck(title: 'Leeg', slides: [Slide.create(SlideType.bullets)]);
      await tester.pumpWidget(_host(deck));
      await tester.pump();

      expect(find.textContaining('Slidekwaliteit'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Fix alle problemen'),
        findsNothing,
      );
    },
  );

  testWidgets('green bar lists the checks that were performed', (tester) async {
    final cleanDeck = Deck(
      title: 'Schoon',
      themeProfile: const ThemeProfile(
        textColor: '#000000',
        slideBackgroundColor: '#FFFFFF',
        titleTextColor: '#000000',
        titleBackgroundColor: '#FFFFFF',
        tableTextColor: '#000000',
        tableHeaderTextColor: '#000000',
        tableHeaderBackgroundColor: '#FFFFFF',
      ),
      slides: [Slide.create(SlideType.title).copyWith(title: 'Welkom')],
    );

    await tester.pumpWidget(_host(cleanDeck));
    await tester.pump();

    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsOneWidget,
    );
    // Ingeklapt: de verantwoording is nog verborgen tot je uitklapt.
    expect(find.textContaining('Uitgevoerde controles'), findsNothing);

    await tester.tap(find.textContaining('Slidekwaliteit'));
    await tester.pump();

    expect(find.textContaining('Uitgevoerde controles'), findsOneWidget);
    expect(
      find.text('Contrast en leesbaarheid van tekstkleuren'),
      findsOneWidget,
    );
    expect(find.textContaining('getoetst aan WCAG AA'), findsOneWidget);
    // De parameterregel toont de echte drempels uit de constanten, bv. de
    // bullet-waarschuwing (8) en de quote-grens (750 tekens).
    expect(find.textContaining('Waarschuwing boven 8 bullets'), findsOneWidget);
    expect(find.textContaining('Quote boven 750 tekens'), findsOneWidget);
  });

  testWidgets('app shell tab scope shows quality issues for overfull deck', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    AppLocalizations.setActiveLanguageCode('nl');

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container.read(tabsProvider).current!.deckNotifier.loadDeck(overfullDeck());
    await tester.pumpAndSettle();

    // Quality now lives behind the compact "Kwaliteit" chip in the editor
    // header; open it to reveal the counts and issues.
    expect(
      find.textContaining('Geen kwaliteitsproblemen gevonden'),
      findsNothing,
    );
    await tester.tap(find.text('Kwaliteit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fout(en)'), findsOneWidget);
    expect(find.textContaining('waarschuwing(en)'), findsOneWidget);
  });

  // Een korte slide gevolgd door een overvolle voortzetting: de korte slide
  // rendert microscopisch klein zonder dat er iets mis is met zijn eigen tekst.
  Deck draggedDeck() => Deck(
    title: 'Demo',
    slides: [
      Slide.create(SlideType.bullets).copyWith(
        title: 'Wat maakt Ocideck bijzonder?',
        bullets: const [
          'Van scan naar verhaal',
          'Evidence-first compliance',
          'Levende rapportage',
        ],
      ),
      Slide.create(SlideType.bullets).copyWith(
        title: 'Dit is een hele volle slide',
        continuesSplit: true,
        bullets: List.generate(
          40,
          (i) =>
              'Bullet $i met een flinke lap tekst erin, want dit is een alinea '
              'die per ongeluk als bullet op de slide is beland en daar veel '
              'te veel ruimte opeist om nog leesbaar te blijven voor een zaal.',
        ),
      ),
    ],
  );

  testWidgets('de knop haalt de volle pagina uit de reeks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final notifier = _deckNotifier(draggedDeck());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deckProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(body: SlideQualityPanel()),
        ),
      ),
    );
    await tester.pump();

    // Het paneel opent ingeklapt; klap het uit om de meldingen te zien.
    await tester.tap(find.textContaining('Slidekwaliteit'));
    await tester.pump();

    // De melding staat onder die van de volle slide zelf, dus scroll erheen.
    final button = find.widgetWithText(
      TextButton,
      'Haal volle pagina uit de reeks',
    );
    await tester.scrollUntilVisible(button, 200);

    // De melding legt uit dat de reeks het probleem is, niet deze slide.
    expect(
      find.textContaining('Niet de tekst op deze slide is het probleem'),
      findsOneWidget,
    );
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();

    // De vlag is weg, de tekst is niet aangeraakt, en de melding is verdwenen.
    expect(notifier.state.deck!.slides[1].continuesSplit, isFalse);
    expect(notifier.state.deck!.slides[1].bullets, hasLength(40));
    expect(
      find.textContaining('Niet de tekst op deze slide is het probleem'),
      findsNothing,
    );
  });

  testWidgets('de repareerknop staat naast de Kwaliteit-chip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    AppLocalizations.setActiveLanguageCode('nl');

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final notifier = container.read(tabsProvider).current!.deckNotifier;
    notifier.loadDeck(draggedDeck());
    await tester.pumpAndSettle();

    // Slide 1 (de korte) is geselecteerd: de knop hoort er te staan, zonder dat
    // het kwaliteitspaneel open hoeft.
    expect(find.text('Kwaliteit'), findsOneWidget);
    expect(find.text('Repareer slide'), findsOneWidget);

    await tester.tap(find.text('Repareer slide'));
    await tester.pumpAndSettle();

    // De vlag is weg, de tekst onaangeroerd, en de knop verdwijnt weer.
    expect(notifier.state.deck!.slides[1].continuesSplit, isFalse);
    expect(notifier.state.deck!.slides[1].bullets, hasLength(40));
    expect(find.text('Repareer slide'), findsNothing);
  });

  testWidgets('geen repareerknop op een deck zonder meegetrokken slide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    AppLocalizations.setActiveLanguageCode('nl');

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(tabsProvider).current!.deckNotifier.loadDeck(overfullDeck());
    await tester.pumpAndSettle();

    // Wel degelijk een overvolle slide, maar geen reeks — dus geen knop.
    expect(find.text('Kwaliteit'), findsOneWidget);
    expect(find.text('Repareer slide'), findsNothing);
  });
}
