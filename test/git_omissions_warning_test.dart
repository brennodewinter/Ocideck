// De "niet alles gaat mee naar git"-waarschuwing bestond zolang de git-opslag
// werk achterliet, en kromp per gelande laag: media (#515/#540), grafiekdata,
// notities (#541 deel 1) en ten slotte de tekenlaag (#541 deel 2). Daarmee was
// er geen ware regel meer over, en een dialoog zonder ware regels leert de
// gebruiker alleen wegklikken — dus is hij opgeheven. De zegelweigering die
// daarna nog als tussenstop bestond is ingetrokken (#541, 23-07-2026): git is
// een bestandssysteem, geen enforcer, en het zegel reist als sidecar mee.
//
// **Deze test bewaakt de afwezigheid.** Elke laag gaat rechtstreeks door naar
// het opslaandialoog; komt er ooit weer een tussenscherm, dan staat hier iets
// dat de gebruiker niet meer kan plaatsen, of is de schrijfkant van een
// sidecar stukgegaan zonder dat iemand het hoort.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
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
      id: 's1',
    ),
  ];

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

  testWidgets('een deck met tekeningen gaat rechtstreeks door', (tester) async {
    // De kern van #541 deel 2. Tot die wijziging was de tekenlaag de laatste
    // laag die achterbleef, en dít deck kreeg de blokkerende waarschuwing.
    // Nu reist `deck.ink.json` mee en is er niets te vragen.
    final a = plain('Test');
    await pumpWithDeck(
      tester,
      Deck(title: 'Test', slides: [a], annotations: {a.id: streek()}),
    );
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsOneWidget);
  });

  testWidgets('een deck met alléén notities gaat rechtstreeks door', (
    tester,
  ) async {
    // De gebruikerskant van #541 deel 1; sinds deel 2 is dit geen bijzonder
    // geval meer, maar de toets blijft: notities zijn de laag die het vaakst
    // gevuld is.
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

  testWidgets('een deck zonder extra lagen krijgt geen tussenvraag', (
    tester,
  ) async {
    await pumpWithDeck(tester, Deck(title: 'Test', slides: [plain('Test')]));
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsOneWidget);
  });

  testWidgets('een verzegeld deck gaat rechtstreeks door', (tester) async {
    // De weigering is ingetrokken (#541, 23-07-2026): git is een
    // bestandssysteem, geen enforcer. Het zegel reist als `deck.seal.json`
    // mee, dus er valt niets te weigeren en niets te waarschuwen — de
    // naamvraag komt gewoon.
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
      findsNothing,
    );
    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsOneWidget);
  });
}
