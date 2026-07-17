import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// De UI-lijm van "Opslaan naar git…": het item staat in het overloopmenu en de
// handler is bereikbaar. Zonder ingestelde repo hoort een tik de configuratie-
// melding te tonen — zo weten we dat het menu-item écht bij saveToGit uitkomt,
// zonder een echte forge te hoeven opzetten.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
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
  });

  testWidgets(
    'zonder ingestelde repo meldt tikken dat je er eerst een instelt',
    (tester) async {
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

      expect(
        find.textContaining('Stel eerst een git-repository in'),
        findsOneWidget,
      );
    },
  );
}
