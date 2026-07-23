import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

/// De twee keuzes uit #607: presenteren begint standaard bij dia 1, en de
/// repetitiesamenvatting verschijnt niet meer vanzelf.
void main() {
  test('een nieuw deck toont de repetitiesamenvatting niet uit zichzelf', () {
    // De samenvatting is een repetitiehulp, geen rapportkaart die de
    // presentator ongevraagd voorgeschoteld krijgt op het moment dat hij net
    // klaar is voor een zaal. Wie hem wil, zet hem aan onder
    // Presentatie-eigenschappen; de instelling blijft bestaan.
    expect(const Deck(title: 'x').showRehearsalSummary, isFalse);
  });

  test('het per-deck-veld overschrijft de standaard nog steeds', () {
    // De keuze verhuist alleen de standaard, niet de mogelijkheid: een deck dat
    // de samenvatting bewust aan had, houdt hem.
    expect(
      const Deck(title: 'x', showRehearsalSummary: true).showRehearsalSummary,
      isTrue,
    );
  });

  testWidgets('het contextmenu van een dia biedt "presenteer vanaf hier"', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(deckProvider.notifier).newDeck('Test');

    var presentedFrom = -1;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 260,
              child: SlideThumbnail(
                slide: container.read(deckProvider).deck!.slides.single,
                index: 3,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
                onPresentFromHere: (i) => presentedFrom = i,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final item = find.text('Presenteer vanaf hier');
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(presentedFrom, 3, reason: 'de callback krijgt de juiste dia mee');
  });

  testWidgets('zonder de callback is het menu-item er niet', (tester) async {
    // De diastrook levert de callback alleen wanneer presenteren kan; een
    // losse thumbnail (bijvoorbeeld in een test of een preview) hoort het item
    // dan ook niet te tonen.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(deckProvider.notifier).newDeck('Test');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 260,
              child: SlideThumbnail(
                slide: container.read(deckProvider).deck!.slides.single,
                index: 0,
                onTap: () {},
                onDuplicate: () {},
                onDelete: () {},
                onToggleSkip: () {},
                onCopyImage: () {},
                onSplit: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Presenteer vanaf hier'), findsNothing);
  });
}
