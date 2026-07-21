import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/git/deck_search.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/widgets/dialogs/git_search_dialog.dart';

import 'git_forge_fake.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// Een forge waarvan het lezen van één deck faalt: een onleesbaar deck.
class _BrokenDeckForge extends FakeForge {
  _BrokenDeckForge(super.repo, this.brokenDeckDir);

  final String brokenDeckDir;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    if (path.startsWith('$brokenDeckDir/')) {
      throw const GitForgeException(GitForgeError.server, 'stuk');
    }
    return super.readBlob(ref, path);
  }
}

/// Een forge die de repo helemaal niet wil laten zien.
class _UnreachableForge extends FakeForge {
  _UnreachableForge(super.repo);

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) => throw const GitForgeException(GitForgeError.auth, 'geen toegang');
}

/// Een versneller die zegt dat zijn antwoord onvolledig kán zijn.
class _BestEffortShortlister implements DeckShortlister {
  _BestEffortShortlister(this.dirs);

  final Set<String> dirs;

  @override
  Future<DeckShortlist?> shortlist(
    String needle, {
    required bool caseSensitive,
    required String branch,
  }) async => DeckShortlist(dirs, coverage: DeckSearchCoverage.bestEffort);
}

/// Repo-breed zoeken (§9.3). Het scherm is een knop en géén zoeken-tijdens-
/// typen, en dat is de eerste bewering: er wordt pas gelezen als de gebruiker
/// dat vraagt.
///
/// Verder gaat het hier vooral om eerlijkheid over onvolledigheid. Elke getoonde
/// treffer klopt, maar "meer is er niet" mag dit scherm nooit suggereren — niet
/// bij een afgekapte lijst, niet bij een onleesbaar deck, en niet bij een
/// geïndexeerde serverzoekopdracht die achter kan lopen. Dat stil weglaten is
/// precies de fout die een tester een bevinding laat missen.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const jaarplan = '''
---
title: Jaarplan
author: Aisha
---

# Doelstellingen

We verhogen de dekking naar 80 procent.

---

# Risico's

Een onleesbaar deck is een risico voor de dekking.
''';

  const kwartaal = '''
# Kwartaalcijfers

De dekking staat op 79 procent.
''';

  FakeRepo repo() => FakeRepo(
    branches: {'main': 'c'},
    files: {
      'decks/jaarplan/deck.md': _b(jaarplan),
      'decks/kwartaalcijfers/deck.md': _b(kwartaal),
    },
  );

  /// Een deck met meer treffers dan de lijst toont, zodat de afkapping echt
  /// optreedt in plaats van dat we hem nabootsen.
  FakeRepo overflowingRepo() => FakeRepo(
    branches: {'main': 'c'},
    files: {
      'decks/veel/deck.md': _b(
        '# Veel\n\n${List.generate(DeckSearch.defaultMaxHits + 25, (i) => 'regel $i met dekking erin').join('\n\n')}',
      ),
    },
  );

  Future<String?> pump(
    WidgetTester tester,
    DeckSearch searcher, {
    bool viaShow = false,
  }) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: viaShow
              ? Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async =>
                        chosen = await GitSearchDialog.show(context, searcher),
                    child: const Text('open'),
                  ),
                )
              : GitSearchDialog(searcher: searcher),
        ),
      ),
    );
    if (viaShow) {
      await tester.tap(find.text('open'));
    }
    await tester.pumpAndSettle();
    return chosen;
  }

  Future<void> searchFor(WidgetTester tester, String term) async {
    await tester.enterText(find.byType(TextField), term);
    await tester.tap(find.widgetWithText(FilledButton, 'Zoeken'));
    await tester.pumpAndSettle();
  }

  testWidgets('er wordt niets gelezen tot de zoekknop ingedrukt wordt', (
    tester,
  ) async {
    final forge = _CountingForge(repo());
    await pump(tester, DeckSearch(forge: forge, branch: 'main'));

    // Alleen typen mag geen ronde over de repo kosten.
    await tester.enterText(find.byType(TextField), 'dekking');
    await tester.pumpAndSettle();
    expect(forge.blobReads, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Zoeken'));
    await tester.pumpAndSettle();
    expect(forge.blobReads, greaterThan(0));
  });

  testWidgets('een lege zoekterm doet niets', (tester) async {
    final forge = _CountingForge(repo());
    await pump(tester, DeckSearch(forge: forge, branch: 'main'));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Zoeken'));
    await tester.pumpAndSettle();

    expect(forge.blobReads, 0);
    // Geen "niets gevonden" ook: er is niet gezocht.
    expect(find.text('Niets gevonden.'), findsNothing);
  });

  testWidgets('treffers worden geteld en per deck en slide benoemd', (
    tester,
  ) async {
    await pump(tester, DeckSearch(forge: FakeForge(repo()), branch: 'main'));
    await searchFor(tester, 'dekking');

    expect(find.textContaining('vindplaatsen'), findsOneWidget);
    expect(
      find.textContaining('jaarplan · slide 1 — Doelstellingen'),
      findsOneWidget,
    );
    expect(find.textContaining('kwartaalcijfers · slide 1'), findsOneWidget);
    // Geen kanttekening: dit antwoord ís volledig.
    expect(
      find.textContaining('Er zijn meer treffers dan hier passen'),
      findsNothing,
    );
    expect(find.textContaining('Niet doorzocht'), findsNothing);
  });

  testWidgets('een treffer in de deck-eigenschappen heet ook zo', (
    tester,
  ) async {
    await pump(tester, DeckSearch(forge: FakeForge(repo()), branch: 'main'));
    await searchFor(tester, 'Aisha');

    // Front matter hoort niet bij een slide; "slide 0" zou liegen.
    expect(find.textContaining('deck-eigenschappen'), findsOneWidget);
    expect(find.textContaining('slide '), findsNothing);
  });

  testWidgets('hoofdlettergevoelig zoeken doet wat het aanvinkt', (
    tester,
  ) async {
    await pump(tester, DeckSearch(forge: FakeForge(repo()), branch: 'main'));
    await searchFor(tester, 'DEKKING');
    expect(find.textContaining('vindplaatsen'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await searchFor(tester, 'DEKKING');
    expect(find.text('Niets gevonden.'), findsOneWidget);
  });

  testWidgets('niets gevonden is een antwoord, geen lege lijst', (
    tester,
  ) async {
    await pump(tester, DeckSearch(forge: FakeForge(repo()), branch: 'main'));
    await searchFor(tester, 'zeppelin');

    expect(find.text('Niets gevonden.'), findsOneWidget);
  });

  testWidgets('een onleesbaar deck wordt gemeld, ook bij nul treffers', (
    tester,
  ) async {
    await pump(
      tester,
      DeckSearch(
        forge: _BrokenDeckForge(repo(), 'decks/jaarplan'),
        branch: 'main',
      ),
    );
    await searchFor(tester, 'zeppelin');

    // Anders leest de gebruiker "niets gevonden" als "het staat er niet".
    expect(find.text('Niets gevonden.'), findsOneWidget);
    expect(
      find.textContaining('Niet doorzocht, want onleesbaar:'),
      findsOneWidget,
    );
    expect(find.textContaining('jaarplan'), findsOneWidget);
  });

  testWidgets('een afgekapte lijst zegt dat er meer is', (tester) async {
    await pump(
      tester,
      DeckSearch(forge: FakeForge(overflowingRepo()), branch: 'main'),
    );
    await searchFor(tester, 'dekking');

    expect(
      find.textContaining('Er zijn meer treffers dan hier passen'),
      findsOneWidget,
    );
    expect(
      find.textContaining('${DeckSearch.defaultMaxHits} vindplaatsen'),
      findsOneWidget,
    );
  });

  testWidgets('een geïndexeerde serverzoekopdracht meldt haar vertraging', (
    tester,
  ) async {
    await pump(
      tester,
      DeckSearch(
        forge: FakeForge(repo()),
        branch: 'main',
        shortlister: _BestEffortShortlister(const {'decks/jaarplan'}),
      ),
    );
    await searchFor(tester, 'dekking');

    expect(
      find.textContaining(
        'door indexeringsvertraging kan een net gewijzigd '
        'deck ontbreken',
      ),
      findsOneWidget,
    );
  });

  testWidgets('een forge-fout wordt uitgelegd, niet verzwegen', (tester) async {
    await pump(
      tester,
      DeckSearch(forge: _UnreachableForge(repo()), branch: 'main'),
    );
    await searchFor(tester, 'dekking');

    // De echte reden (aanmelden mislukt), niet "er ging iets mis".
    expect(find.textContaining('Aanmelden bij de'), findsOneWidget);
    expect(find.text('Niets gevonden.'), findsNothing);
  });

  testWidgets('een treffer aanklikken geeft de deckmap terug', (tester) async {
    String? chosen;
    final searcher = DeckSearch(forge: FakeForge(repo()), branch: 'main');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  chosen = await GitSearchDialog.show(context, searcher),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await searchFor(tester, 'Kwartaalcijfers');

    await tester.tap(find.textContaining('kwartaalcijfers ·').first);
    await tester.pumpAndSettle();

    // De deckmap, niet de slide: het zoekresultaat wijst de weg, het deck is
    // waar je verder werkt.
    expect(chosen, 'decks/kwartaalcijfers');
  });

  testWidgets('sluiten geeft niets terug', (tester) async {
    final searcher = DeckSearch(forge: FakeForge(repo()), branch: 'main');
    final chosen = await pump(tester, searcher, viaShow: true);
    expect(chosen, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Sluiten'));
    await tester.pumpAndSettle();
    expect(find.byType(GitSearchDialog), findsNothing);
  });
}

/// Telt wat er werkelijk over de REST-laag gelezen wordt.
class _CountingForge extends FakeForge {
  _CountingForge(super.repo);

  int blobReads = 0;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    blobReads++;
    return super.readBlob(ref, path);
  }
}
