import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/git/deck_merge.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/local_conflict.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/document_conflict_dialog.dart';
import 'package:ocideck/widgets/dialogs/local_deck_conflict_dialog.dart';

/// #2323: vergelijken en veilig samenvoegen van lokale bestandsconflicten.
/// De zuivere helft: de driewegs-orkestratie rond [mergeDeckVersions], het
/// toepassen van de botsingskeuzes, de blok/woord-vergelijking voor
/// documenten, en de basis- plus vingerafdruk-bewaking in [DeckNotifier].
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Slide bullets(String title, List<String> items) =>
      Slide.create(SlideType.bullets).copyWith(title: title, bullets: items);

  Deck deckOf(List<Slide> slides) => Deck(title: 'Deck', slides: slides);

  final one = bullets('Eén', const ['a']);
  final two = bullets('Twee', const ['b']);
  final three = bullets('Drie', const ['c']);

  group('analyzeLocalDeckConflict', () {
    test('niet-overlappende wijzigingen: schone merge, beide kanten erin', () {
      final ours = deckOf([
        bullets('Eén', const ['a van mij']),
        two,
      ]);
      final theirs = deckOf([
        one,
        bullets('Twee', const ['b van schijf']),
      ]);
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: ours,
        theirs: theirs,
      );

      expect(c.hasBase, isTrue);
      expect(c.merge!.isClean, isTrue);
      expect(c.merge!.merged.slides[0].bullets, const ['a van mij']);
      expect(c.merge!.merged.slides[1].bullets, const ['b van schijf']);
    });

    test('allebei dezelfde slide bewerkt: een botsing, geen stille keuze', () {
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([
          bullets('Eén', const ['a van mij']),
          two,
        ]),
        theirs: deckOf([
          bullets('Eén', const ['a van schijf']),
          two,
        ]),
      );

      expect(c.merge!.isClean, isFalse);
      expect(c.merge!.conflicts, hasLength(1));
      expect(c.merge!.conflicts.first.isDeleteAgainstEdit, isFalse);
      // De voorlopige merge houdt onze kant — nooit stilletjes die van de
      // ander.
      expect(c.merge!.merged.slides[0].bullets, const ['a van mij']);
    });

    test(
      'wij verwijderden, schijf bewerkte: verwijder-tegen-wijzig-botsing',
      () {
        final c = analyzeLocalDeckConflict(
          base: deckOf([one, two]),
          ours: deckOf([two]),
          theirs: deckOf([
            bullets('Eén', const ['a van schijf']),
            two,
          ]),
        );

        expect(c.merge!.conflicts, hasLength(1));
        final conflict = c.merge!.conflicts.first;
        expect(conflict.isDeleteAgainstEdit, isTrue);
        expect(conflict.ours, isNull);
        expect(conflict.theirs, isNotNull);
      },
    );

    test('zonder basis: geen merge, wel een verschil-overzicht', () {
      final ours = deckOf([one, two]);
      final theirs = deckOf([one, three]);
      final c = analyzeLocalDeckConflict(
        base: null,
        ours: ours,
        theirs: theirs,
      );

      expect(c.hasBase, isFalse);
      expect(c.merge, isNull);
      // Zonder basis toont de diff wat de schijfversie anders heeft dan de
      // onze — direct bruikbaar als overzicht.
      expect(c.theirsDiff.hasChanges, isTrue);
    });

    test('alleen schijf veranderde: schone merge geeft de schijfversie', () {
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([one, two]),
        theirs: deckOf([
          one,
          bullets('Twee', const ['b nieuw']),
          three,
        ]),
      );

      expect(c.merge!.isClean, isTrue);
      expect(c.merge!.merged.slides.map((s) => s.title), [
        'Eén',
        'Twee',
        'Drie',
      ]);
    });
  });

  group('applyDeckConflictChoices', () {
    test('keuze voor schijfkant zet die slide in de merge', () {
      final ourOne = bullets('Eén', const ['a van mij']);
      final theirOne = bullets('Eén', const ['a van schijf']);
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([ourOne, two]),
        theirs: deckOf([theirOne, two]),
      );
      final merged = applyDeckConflictChoices(c.merge!, [theirOne]);
      expect(merged.slides[0].bullets, const ['a van schijf']);
    });

    test('verwijderd-houden keuze haalt de slide uit de merge', () {
      // Wij gooiden 'Eén' weg, schijf bewerkte hem: de voorlopige merge houdt
      // de schijfversie; kiest de gebruiker onze kant, dan verdwijnt hij.
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([two]),
        theirs: deckOf([
          bullets('Eén', const ['a van schijf']),
          two,
        ]),
      );
      final conflict = c.merge!.conflicts.single;
      expect(conflict.ours, isNull);
      final merged = applyDeckConflictChoices(c.merge!, [conflict.ours]);
      expect(merged.slides.map((s) => s.title), ['Twee']);
    });
  });

  group('diffDocBlocks', () {
    test('identieke bronnen: één gelijk paar', () {
      final pairs = diffDocBlocks('Kop\n\nAlinea.', 'Kop\n\nAlinea.');
      expect(pairs, hasLength(1));
      expect(pairs.single.equal, isTrue);
    });

    test('een gewijzigde alinea wordt als paar naast elkaar gezet', () {
      final pairs = diffDocBlocks(
        'Kop\n\nOude tekst.\n\nSlot.',
        'Kop\n\nNieuwe tekst.\n\nSlot.',
      );
      expect(pairs, hasLength(3));
      expect(pairs[1].equal, isFalse);
      expect(pairs[1].ours, contains('Oude'));
      expect(pairs[1].theirs, contains('Nieuwe'));
    });

    test('een extra blok bij de ander kant heeft een lege eigen kant', () {
      final pairs = diffDocBlocks('Kop\n\nA.', 'Kop\n\nA.\n\nB.');
      expect(pairs, hasLength(3));
      expect(pairs[0].equal, isTrue);
      expect(pairs[1].equal, isTrue);
      expect(pairs[2].ours, isNull);
      expect(pairs[2].theirs, contains('B.'));
    });

    test(
      'frontmatter blijft één blok en regeleinden geven geen vals verschil',
      () {
        const a = '---\ntheme: rvs\n---\n\nTekst hier.';
        const b = '---\r\ntheme: rvs\r\n---\r\n\r\nTekst hier.';
        final pairs = diffDocBlocks(a, b);
        // De blokken verschillen (LF vs CRLF), maar zijn als één frontmatter-
        // blok uitgelijnd — niet opgehakt in losse regels.
        expect(pairs, hasLength(2));
        expect(pairs[0].ours, contains('theme: rvs'));
        expect(pairs[0].theirs, contains('theme: rvs'));
        expect(pairs[1].equal, isTrue);
      },
    );
  });

  group('diffDocWords', () {
    test('markeert alleen de gewijzigde woorden, en alleen van kant a', () {
      final parts = diffDocWords(
        'De kat zit op de mat.',
        'De hond zit op de mat.',
      );
      final text = parts.map((p) => p.text).join();
      expect(text, 'De kat zit op de mat.');
      final changed = parts.where((p) => p.changed).map((p) => p.text).join();
      expect(changed.trim(), 'kat');
      // Woorden die alleen de andere kant kent komen niet mee.
      expect(text, isNot(contains('hond')));
    });
  });

  group('DeckNotifier — basis en merge-toepassing', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ocideck_local_conflict_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    String writeDeck(String name, String title) {
      final path = '${tempDir.path}/$name';
      File(path).writeAsStringSync('---\nmarp: true\n---\n# $title\n');
      return path;
    }

    FileService files() => FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
      homeDirectory: () => tempDir.path,
    );

    DeckNotifier notifier() => DeckNotifier(MarkdownService(), files());

    test(
      'schone lading vanaf een pad zet de basis; een nieuw deck niet',
      () async {
        final path = writeDeck('a.md', 'A');
        final f = files();
        final n = notifier();
        final deck = await f.openDeck(path);
        n.loadDeck(deck!, filePath: path);
        expect(n.baseDeck, isNotNull);
        expect(n.baseDeck!.title, 'A');

        n.newDeck('Vers');
        expect(n.baseDeck, isNull);
      },
    );

    test(
      'vuile lading vanaf een pad zet géén basis (hersteld, niet bewezen)',
      () async {
        final path = writeDeck('b.md', 'B');
        final f = files();
        final n = notifier();
        final deck = await f.openDeck(path);
        n.loadDeck(deck!, filePath: path, isDirty: true);
        expect(n.baseDeck, isNull);
      },
    );

    test('applyMergedDeck: één ongedaan-stap, blijft vuil, werkt niet bij '
        'verlopen vingerafdruk', () async {
      final path = writeDeck('c.md', 'C');
      final f = files();
      final n = notifier();
      final deck = await f.openDeck(path);
      n.loadDeck(deck!, filePath: path);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final mtime = await f.fileMtime(path);

      // Een vingerafdruk die niet klopt: niets gebeurt.
      final stale = DateTime.fromMillisecondsSinceEpoch(0);
      expect(await n.applyMergedDeck(deck, expectedMtime: stale), isFalse);
      expect(n.state.deck!.title, 'C');
      expect(n.state.isDirty, isFalse);

      // De echte vingerafdruk: één mutatie, vuil, ongedaan te maken.
      final merged = deck.copyWith(title: 'Samengevoegd');
      expect(await n.applyMergedDeck(merged, expectedMtime: mtime), isTrue);
      expect(n.state.deck!.title, 'Samengevoegd');
      expect(n.state.isDirty, isTrue);
      expect(n.state.canUndo, isTrue);
      n.undo();
      expect(n.state.deck!.title, 'C');

      // De schijfversie zit in de merge, dus géén vals-conflict meer.
      expect(await n.fileChangedExternally(), isFalse);
    });
  });

  group('DocumentConflictDialog', () {
    Widget host(String ours, String theirs) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => DocumentConflictDialog.show(
              context,
              ours: ours,
              theirs: theirs,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    testWidgets('toont beide versies en de keuzes', (tester) async {
      await tester.pumpWidget(
        host('Eerste zin.\n\nEigen stuk.', 'Eerste zin.\n\nSchijfstuk.'),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mijn versie'), findsWidgets);
      expect(find.text('Versie op schijf'), findsWidgets);
      expect(find.text('Versie op schijf laden'), findsOneWidget);
      expect(find.text('Mijn versie bewaren'), findsOneWidget);
      expect(find.text('Mijn versie als kopie bewaren'), findsOneWidget);
      expect(find.text('Terug'), findsOneWidget);
      // De verschillende alinea's staan naast elkaar.
      expect(find.textContaining('Eigen stuk'), findsOneWidget);
      expect(find.textContaining('Schijfstuk'), findsOneWidget);
    });

    testWidgets('knopkeuzes komen als actie terug', (tester) async {
      DocumentConflictAction? action;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  action = await DocumentConflictDialog.show(
                    context,
                    ours: 'A',
                    theirs: 'B',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versie op schijf laden'));
      await tester.pumpAndSettle();
      expect(action, DocumentConflictAction.loadDisk);
    });
  });

  group('LocalDeckCompareDialog', () {
    Widget host(LocalDeckConflict c, void Function(Deck?) onDone) =>
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final result = await showDialog<Deck>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => LocalDeckCompareDialog(conflict: c),
                  );
                  onDone(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('botsing eist een expliciete keuze voordat samenvoegen kan', (
      tester,
    ) async {
      final ourOne = bullets('Eén', const ['a van mij']);
      final theirOne = bullets('Eén', const ['a van schijf']);
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([ourOne, two]),
        theirs: deckOf([theirOne, two]),
      );
      expect(c.merge!.isClean, isFalse);

      Deck? result;
      var opened = false;
      await tester.pumpWidget(host(c, (d) => result = d));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      opened = true;
      expect(opened, isTrue);

      // Zonder keuze is de primaire knop uitgeschakeld.
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Samenvoegen en toepassen'),
      );
      expect(apply.onPressed, isNull);

      // Kies de schijfkant en pas toe: de merge levert hun slide.
      await tester.tap(find.text('Versie op schijf').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Samenvoegen en toepassen'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.slides[0].bullets, const ['a van schijf']);
    });

    testWidgets('schone merge: meteen toepasbaar, Terug geeft null', (
      tester,
    ) async {
      final c = analyzeLocalDeckConflict(
        base: deckOf([one, two]),
        ours: deckOf([one, two]),
        theirs: deckOf([
          one,
          bullets('Twee', const ['b nieuw']),
        ]),
      );
      expect(c.merge!.isClean, isTrue);

      Deck? result = deckOf([one]);
      await tester.pumpWidget(host(c, (d) => result = d));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Samenvoegen en toepassen'),
      );
      expect(apply.onPressed, isNotNull);

      await tester.tap(find.text('Terug'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
