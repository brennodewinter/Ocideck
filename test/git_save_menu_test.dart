import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// De UI-lijm van "Opslaan naar…": met precies één ingestelde verbinding — een
// git-repo — komt een tik daarop rechtstreeks bij saveToGit uit, zonder
// tussenvraag welke verbinding het moet zijn. Zichtbaar doordat het
// opslaandialoog om een deknaam vraagt; zo is de koppeling bewezen zonder een
// echte forge op te zetten.
//
// Dat er één gedeelde ingang is in plaats van één per opslagsoort is de kern:
// opslaan zonder meer volgt de herkomst, en dít item is het pad om iets bewust
// ergens anders neer te zetten.
//
// Dat de git-items zónder ingestelde repo helemaal wegblijven is een aparte
// afspraak; die staat in app_shell_actions_test.dart.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // De sleutelbos bestaat niet in een test; zonder deze stub blijft
    // readGitToken hangen en komt gitForgeProvider nooit rond, waardoor een tik
    // op het menu-item spoorloos verdwijnt in plaats van iets te tonen.
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

  Future<void> pumpWithDeck(WidgetTester tester) async {
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
            title: 'Test',
            slides: [Slide.create(SlideType.title).copyWith(title: 'Test')],
          ),
        );
    await tester.pumpAndSettle();
  }

  testWidgets('het overloopmenu toont "Opslaan naar…"', (tester) async {
    await pumpWithDeck(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opslaan naar…'), findsOneWidget);
    expect(find.text('Openen uit…'), findsOneWidget);
    // De git-eigen handelingen blijven in hun eigen blok staan; alleen openen
    // en opslaan zijn samengevoegd.
    expect(find.text('Nu synchroniseren'), findsOneWidget);
    // En de oude, per-protocol items zijn weg.
    expect(find.text('Opslaan naar git…'), findsNothing);
    expect(find.text('Openen uit git…'), findsNothing);
  });

  testWidgets('tikken op het item opent het opslaandialoog', (tester) async {
    await pumpWithDeck(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opslaan naar…'));
    await tester.pumpAndSettle();

    // Eén verbinding, dus geen tussenvraag: het opslaandialoog vraagt meteen om
    // een deknaam. Bewijs dat het menu-item bij _saveToGit uitkomt en niet
    // onderweg in een keuzedialoog blijft hangen.
    expect(find.text('Deknaam'), findsOneWidget);
  });
}
