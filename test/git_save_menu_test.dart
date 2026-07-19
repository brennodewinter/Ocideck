import 'package:flutter/material.dart';
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

// De UI-lijm van "Opslaan naar git…": met een ingestelde repo staat het item in
// het overloopmenu, en een tik komt uit bij saveToGit — zichtbaar doordat het
// opslaandialoog om een deknaam vraagt. Zo is de koppeling bewezen zonder een
// echte forge op te zetten.
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

  testWidgets('het overloopmenu toont "Opslaan naar git…"', (tester) async {
    await pumpWithDeck(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opslaan naar git…'), findsOneWidget);
    expect(find.text('Nu synchroniseren'), findsOneWidget);
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
    await tester.tap(find.text('Opslaan naar git…'));
    await tester.pumpAndSettle();

    // Het opslaandialoog vraagt om een deknaam: bewijs dat het menu-item bij
    // _saveToGit uitkomt en niet onderweg blijft hangen.
    expect(find.text('Deknaam'), findsOneWidget);
  });
}
