// De git-opslag laat werk achter, en dat moet de gebruiker vóór de commit horen.
//
// `deck.md`, de assetpool (afbeeldingen én media), de grafiekdata en sinds #541
// de gebruikersnotities gaan mee; de tekenlaag (`.ink.json`) en het zegel
// (`.seal.json`) niet — `services/git/` schrijft die sidecars nergens. Op schijf
// reizen ze wél mee, dus wie van een bestand naar git verhuist raakt ze kwijt
// zonder dat er iets misgaat waar de app op kan wijzen. De waarschuwing hoort
// vóór de commit — daarna is de keuze al gemaakt.
//
// **Deze test bewaakt vooral het krimpen.** Bij elke laag die alsnog gaat
// reizen, moet de melding exact die regel verliezen en de andere houden. Een
// waarschuwing die meer opsomt dan er misgaat, leert de lezer hem in zijn
// geheel weg te klikken — en dan is ook de regel over het zegel weg. Daarom
// staat hieronder niet alleen wat er nog gemeld wordt, maar per verhuisde laag
// een toets dat er niets meer over gemeld wordt: media sinds #515, notities
// sinds #541.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // Zie git_save_menu_test: zonder deze stub blijft readGitToken hangen.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'gitRepo':
          '{"baseUrl":"https://git.example.org","owner":"acme",'
          '"repo":"decks","provider":"gitea","defaultBranch":"main",'
          '"trustedInternal":true}',
    });
  });

  Slide plain(String title) =>
      Slide.create(SlideType.title).copyWith(title: title);

  List<InkStroke> streek() => const [
    InkStroke(
      tool: InkTool.pen,
      color: 0xFFEF4444,
      width: 0.004,
      points: [Offset(0.1, 0.2)],
    ),
  ];

  group('gitDeckOmissions', () {
    test('telt de tekenlaag, en negeert wat wél meereist', () {
      final a = plain('Een');
      final b = Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(videoPath: 'films/demo.mp4');
      final c = Slide.create(
        SlideType.freeMarkdown,
      ).copyWith(audioPath: 'geluid/uitleg.m4a');
      final deck = Deck(
        title: 'R',
        slides: [a, b, c],
        annotations: {a.id: streek()},
        userNotes: {a.id: 'Niet vergeten te noemen'},
      );

      final missing = gitDeckOmissions(deck);
      // Video en audio tellen niet mee sinds #515, de notities niet sinds #541:
      // die reizen alle drie mee. Wat overblijft is de tekenlaag. Een
      // waarschuwing die onwaar is, leert de gebruiker de hele melding weg te
      // klikken.
      expect(missing.annotatedSlides, 1);
      expect(missing.isNotEmpty, isTrue);
    });

    test('een deck met alléén notities meldt niets meer', () {
      // De kern van #541. Vóór die wijziging was dit een waarschuwing; nu reist
      // de notitie mee en is er niets te melden. Wordt dit weer rood, dan is de
      // schrijfkant stukgegaan zonder dat een gebruiker het te horen krijgt.
      final a = plain('Een');
      final deck = Deck(
        title: 'R',
        slides: [a],
        userNotes: {a.id: 'Niet vergeten te noemen'},
      );

      expect(gitDeckOmissions(deck).isEmpty, isTrue);
    });

    test('een lege tekenlaag telt niet mee', () {
      final a = plain('Een');
      final deck = Deck(title: 'R', slides: [a], annotations: {a.id: const []});
      // Een waarschuwing die ook afgaat als er niets aan de hand is, leert de
      // gebruiker hem weg te klikken.
      expect(gitDeckOmissions(deck).isEmpty, isTrue);
    });

    test('een deck zonder extra lagen meldt niets', () {
      expect(
        gitDeckOmissions(Deck(title: 'R', slides: [plain('Een')])).isEmpty,
        isTrue,
      );
    });
  });

  Future<void> pumpWithDeck(WidgetTester tester, Deck deck) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(tabsProvider).current!.deckNotifier.loadDeck(deck);
    await tester.pumpAndSettle();
  }

  Future<void> tapSaveTo(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opslaan naar…'));
    await tester.pumpAndSettle();
  }

  Deck deckWithInk() {
    final a = plain('Test');
    return Deck(title: 'Test', slides: [a], annotations: {a.id: streek()});
  }

  testWidgets('opslaan naar git waarschuwt eerst over wat achterblijft', (
    tester,
  ) async {
    await pumpWithDeck(tester, deckWithInk());
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsOneWidget);
    // In de dialoog zelf, niet ergens anders in de shell: het woord komt ook
    // op de diastrook voor.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Tekeningen op slides'),
      ),
      findsOneWidget,
    );
    // Blokkerend: het opslaandialoog komt pas ná deze keuze.
    expect(find.text('Deknaam'), findsNothing);
  });

  testWidgets('een deck met alléén notities gaat rechtstreeks door', (
    tester,
  ) async {
    // De gebruikerskant van #541: waar dit vroeger een blokkerende vraag gaf,
    // reizen de notities nu mee en is er niets te vragen. Zou de melding
    // terugkomen, dan staat hier een tussenscherm dat de gebruiker niet meer
    // kan plaatsen — en dat is precies hoe een waarschuwing zijn gezag verliest.
    final a = plain('Test');
    await pumpWithDeck(
      tester,
      Deck(
        title: 'Test',
        slides: [a],
        userNotes: {a.id: 'Deze zin hoort erbij'},
      ),
    );
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsOneWidget);
  });

  testWidgets('annuleren stopt het opslaan', (tester) async {
    await pumpWithDeck(tester, deckWithInk());
    await tapSaveTo(tester);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsNothing);
  });

  testWidgets('doorgaan brengt de gebruiker bij het opslaandialoog', (
    tester,
  ) async {
    await pumpWithDeck(tester, deckWithInk());
    await tapSaveTo(tester);
    await tester.tap(find.text('Toch opslaan'));
    await tester.pumpAndSettle();

    expect(find.text('Deknaam'), findsOneWidget);
  });

  testWidgets('een deck zonder extra lagen krijgt geen tussenvraag', (
    tester,
  ) async {
    await pumpWithDeck(tester, Deck(title: 'Test', slides: [plain('Test')]));
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsOneWidget);
  });

  testWidgets('een verzegeld deck wordt geweigerd, niet gewaarschuwd', (
    tester,
  ) async {
    // Tot #541 deel 3 stond het zegel in de waarschuwing: het deck ging mee en
    // het zegel viel stil weg. Sinds D12 gaat een verzegeld deck helemaal niet
    // naar een werkbranch — die kan herschreven en geforceerd geduwd worden, en
    // een zegel dat dat overleeft zegt niets meer.
    //
    // De waarschuwing verliest dus exact die ene regel, en er komt géén
    // "Toch opslaan": een weigering die je kunt wegklikken is er geen.
    await pumpWithDeck(
      tester,
      Deck(
        title: 'Test',
        slides: [plain('Test')],
        finalized: true,
        sealAlgo: 'sha-512',
        sealHash: 'a' * 128,
        sealAt: '2026-07-10T12:00:00.000Z',
      ),
    );
    await tapSaveTo(tester);

    expect(
      find.text('Een verzegeld deck gaat niet naar een werkbranch'),
      findsOneWidget,
    );
    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Toch opslaan'), findsNothing);
    // En het opslaan begint niet: de naamvraag komt er niet.
    expect(find.text('Deknaam'), findsNothing);
  });

  testWidgets('een verzegeld deck mét tekeningen noemt alleen de weigering', (
    tester,
  ) async {
    // Twee dialogen achter elkaar zou de weigering laten lezen als de tweede
    // helft van een waarschuwing waar je doorheen kunt klikken.
    final slide = plain('Test');
    await pumpWithDeck(
      tester,
      Deck(
        title: 'Test',
        slides: [slide],
        finalized: true,
        sealAlgo: 'sha-512',
        sealHash: 'a' * 128,
        sealAt: '2026-07-10T12:00:00.000Z',
        annotations: {slide.id: streek()},
      ),
    );
    await tapSaveTo(tester);

    expect(
      find.text('Een verzegeld deck gaat niet naar een werkbranch'),
      findsOneWidget,
    );
    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
  });
}
