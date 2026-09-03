import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/procesverbetering_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Past the consent gate so the app shell renders. We only seed the consent
    // key, never wiping the whole prefs domain other tests may rely on.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  testWidgets('Welcome screen shows startup logo', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('OciDeck'), findsOneWidget);
  });

  testWidgets('Welcome screen exposes settings', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    // De voettekstlink staat als outlined knop met icoon; het label is nog
    // steeds de vindplaats.
    expect(find.text('Instellingen'), findsOneWidget);
  });

  testWidgets('het openscherm zegt wat dit is en waar de handleiding staat', (
    tester,
  ) async {
    // Het scherm was logo plus knoppen: wie hier voor het eerst kwam, kreeg
    // vier handelingen en geen antwoord op de enige vraag die hij had. De
    // handleiding zat drie klikken diep in de instellingen.
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('gewone Markdown-bestanden blijven'),
      findsOneWidget,
    );
    expect(find.text('Gebruikershandleiding'), findsOneWidget);
  });

  testWidgets('het openscherm telt geen sjablonen meer voor je', (
    tester,
  ) async {
    // Het openscherm meldde hoeveel sjablonen er klaarstonden. Dat getal helpt
    // niemand aan een presentatie: het staat op de plek waar één handeling
    // hoort en vraagt om lezen en rekenen voordat je mag klikken. Wélke
    // sjablonen er zijn, laat de kiezer zelf zien — en die staat één klik weg.
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('sjablonen om mee te beginnen'), findsNothing);
    // De twee maakknoppen staan er nog wél, elk met het icoon van hun soort.
    expect(find.text('Nieuwe presentatie'), findsOneWidget);
    expect(find.text('Nieuw document'), findsOneWidget);
    expect(find.byIcon(Icons.slideshow_outlined), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets(
    'de twee maakknoppen dragen een ondertitel die zegt wat je krijgt',
    (tester) async {
      // De knoppen heten 'Nieuwe presentatie' en 'Nieuw document' — twee namen
      // die voor een nieuweling hetzelfde klinken. Een ondertitel in gewone taal
      // maakt het verschil zichtbaar vóór de klik (#1961).
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
      expect(find.textContaining("Dia's, presenteren"), findsOneWidget);
      expect(find.textContaining('Doorlopende tekst'), findsOneWidget);
    },
  );

  testWidgets(
    'procesverbetering voegt geen losse aanmaakknop aan het openscherm toe',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [procesverbeteringRevealProvider.overrideWithValue(true)],
          child: const OciDeckApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nieuw verbeteringsproject'), findsNothing);
      expect(find.text('Nieuwe presentatie'), findsOneWidget);
    },
  );

  testWidgets(
    'het openscherm toont het versienummer, en een tik erop opent Over OciDeck',
    (tester) async {
      // Vóór deze tag stond het versienummer nergens op het openscherm — een
      // melder moest drie klikken diep in Instellingen om op te zoeken welke
      // versie SECURITY.md vraagt te vermelden. De tag woont nu in de
      // voettekstband onderaan, die in de nauwe (smal-scherm) layout onder de
      // kolommen schuift — vandaar eerst zichtbaar scrollen vóór de tik.
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();

      final versionFinder = find.text('v$kOciDeckVersion');
      expect(versionFinder, findsOneWidget);
      await tester.ensureVisible(versionFinder);
      await tester.pumpAndSettle();

      await tester.tap(versionFinder);
      await tester.pumpAndSettle();

      expect(find.text('Over OciDeck'), findsOneWidget);
    },
  );

  testWidgets('recent list marks remote-fetched files with a cloud badge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'recentFiles': ['/decks/remote.md', '/decks/lokaal.md'],
      'recentFileOrigins':
          '{"/decks/remote.md":"https://cloud.example · pres/remote.md"}',
    });
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    // Alleen de remote opgehaalde vermelding draagt de wolk-badge (de
    // Nextcloud-knop links gebruikt hetzelfde icoon, maar zonder tooltip);
    // de tooltip toont de bron zodat de gebruiker ziet wáár die vandaan komt.
    final badge = find.descendant(
      of: find.byType(Tooltip),
      matching: find.byIcon(Icons.cloud_outlined),
    );
    expect(badge, findsOneWidget);
    // Sinds de metadata-tegel heeft de badge twee Tooltip-ancestors (de
    // herkomst-tooltip en de tegel-tooltip); de dichtstbijzijnde draagt de
    // bron.
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: badge, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, 'https://cloud.example · pres/remote.md');
  });

  testWidgets('the only open presentation can be closed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(
      Deck(
        title: 'Test',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Test')],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(container.read(tabsProvider).current!.isOpen, isFalse);
  });

  testWidgets('closing one of two tabs does not double-dispose deck notifier', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'First',
            slides: [Slide.create(SlideType.title).copyWith(title: 'First')],
          ),
        );
    await tester.pump();

    container.read(tabsProvider.notifier).newEmptyTab();
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 2);

    final firstNotifier = container.read(tabsProvider).tabs[0].deckNotifier;
    container.read(tabsProvider.notifier).closeTab(1);
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).tabs.length, 1);
    expect(firstNotifier.mounted, isTrue);
    expect(container.read(tabsProvider).current!.label, 'First');
  });

  testWidgets('a play-only deck shows the locked play screen, not the editor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Vergrendeld',
            playOnly: true,
            slides: [Slide.create(SlideType.title).copyWith(title: 'Test')],
          ),
        );
    await tester.pumpAndSettle();

    // The locked screen shows a Play button and the deck title, but none of the
    // editing chrome (the slide-list rail is only built by the main layout).
    expect(find.text('Afspelen'), findsOneWidget);
    expect(
      find.text('Deze presentatie is vergrendeld op alleen afspelen.'),
      findsOneWidget,
    );
    expect(find.byType(SlideListPanel), findsNothing);

    // Closing from the play-only screen restores the normal (welcome) working.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sluiten'));
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).current!.isOpen, isFalse);
  });
}
