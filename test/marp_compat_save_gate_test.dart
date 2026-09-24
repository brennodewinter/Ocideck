import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

/// De opslaan-poort uit `saveDeckWithDestination`: alleen een rode status
/// (Marp kan het deck niet weergeven) vraagt om bevestiging. Aandachtspunten
/// slaan zonder vraag op, en een uitgeschakelde controle slaat de hele stap
/// over.
///
/// De rode test-deck gebruikt een titel die de front-matter-codec ongequote
/// uitstoot (`'x`) — het enige pad waarop een Deck-object vandaag een echt
/// ongeldige YAML-waarde produceert.
void main() {
  late Directory tmp;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_marp_save');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  DeckNotifier notifier(Deck deck) {
    final n = DeckNotifier(
      MarkdownService(),
      FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
        homeDirectory: () => tmp.path,
      ),
    );
    // Een bestaand bestandspad: dan schrijft opslaan direct terug zonder
    // bestemmingsdialoog of systeemvenster.
    n.loadDeck(deck, filePath: '${tmp.path}/deck.md');
    return n;
  }

  /// Rode status: de titel breekt de front-matter-YAML bij generateDeck.
  Deck redDeck() => const Deck(title: "'x");

  /// Aandachtspunt: de grafiek degradeert tot codeblok in Marp.
  Deck degradedDeck() =>
      Deck(title: 'Test', slides: [Slide.create(SlideType.chart)]);

  Deck cleanDeck() => const Deck(title: 'Test', theme: 'default');

  var saved = false;

  /// Knop die de echte opslaantrechter aanroept. De `watch` op settings trapt
  /// `_load` al bij de eerste build af, zodat de instelling geladen is vóór
  /// de opslag — net als in de app, waar hij allang gelezen is.
  Widget host(DeckNotifier n) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(settingsProvider);
            return ElevatedButton(
              onPressed: () async {
                saved = await saveDeckWithDestination(context, ref, n);
              },
              child: const Text('save'),
            );
          },
        ),
      ),
    ),
  );

  /// De opslagketen schrijft echt naar schijf — dat loopt alleen door in
  /// `runAsync`. Wacht tot [until] waar is (dialoog zichtbaar óf [saved]
  /// gezet), met een royale grens.
  Future<bool> waitFor(
    WidgetTester tester,
    bool Function() until, {
    Future<void> Function()? start,
  }) async {
    await tester.runAsync(() async {
      if (start != null) {
        await start();
      }
    });
    await pumpUntil(
      tester,
      until,
      timeout: const Duration(seconds: 15),
      reason: 'de Marp-opslagroute rondde niet af',
    );
    await tester.pumpAndSettle();
    return true;
  }

  bool dialogUp() => find.text('Marp · Probleem').evaluate().isNotEmpty;

  testWidgets('rode status kan in Markdown worden bekeken', (tester) async {
    saved = true;
    await tester.pumpWidget(host(notifier(redDeck())));
    await tester.pumpAndSettle();

    // De controle is synchroon en de herstelactie doet geen I/O.
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(dialogUp(), isTrue);
    expect(find.text('Opslaan'), findsOneWidget);
    expect(find.text('Markdown · Openen'), findsOneWidget);

    await tester.tap(find.text('Markdown · Openen'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(editorProvider).mode, EditorMode.markdown);
    expect(container.read(editorProvider).markdownScope, MarkdownScope.deck);
    // Niets weggeschreven: het doelbestand bestaat niet eens.
    expect(File('${tmp.path}/deck.md').existsSync(), isFalse);
  });

  testWidgets('"Opslaan" schrijft het bestand alsnog', (tester) async {
    saved = false;
    await tester.pumpWidget(host(notifier(redDeck())));
    await tester.pumpAndSettle();

    expect(
      await waitFor(
        tester,
        dialogUp,
        start: () => tester.tap(find.text('save')),
      ),
      isTrue,
    );
    expect(
      await waitFor(
        tester,
        () => saved,
        start: () => tester.tap(find.text('Opslaan')),
      ),
      isTrue,
      reason: 'de opslag na "Opslaan" liep niet door',
    );
    expect(File('${tmp.path}/deck.md').readAsStringSync(), contains("'x"));
  });

  testWidgets('aandachtspunten slaan zonder dialoog op', (tester) async {
    saved = false;
    await tester.pumpWidget(host(notifier(degradedDeck())));
    await tester.pumpAndSettle();

    expect(
      await waitFor(
        tester,
        () => saved,
        start: () => tester.tap(find.text('save')),
      ),
      isTrue,
      reason: 'de opslag met aandachtspunten liep niet door',
    );
    expect(dialogUp(), isFalse);
    expect(File('${tmp.path}/deck.md').existsSync(), isTrue);
  });

  testWidgets('schoon deck slaat zonder dialoog op', (tester) async {
    saved = false;
    await tester.pumpWidget(host(notifier(cleanDeck())));
    await tester.pumpAndSettle();

    expect(
      await waitFor(
        tester,
        () => saved,
        start: () => tester.tap(find.text('save')),
      ),
      isTrue,
    );
    expect(dialogUp(), isFalse);
  });

  testWidgets('controle uit → rood deck slaat toch zonder vraag op', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'marpCompatChecksEnabled': false});
    saved = false;
    await tester.pumpWidget(host(notifier(redDeck())));
    // De instelling laadt asynchroon (echte prefs-IO) — wacht er echt op.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await pumpUntil(
      tester,
      () => !container.read(settingsProvider).marpCompatChecksEnabled,
      reason: 'de Marp-instelling bleef ingeschakeld',
    );
    await tester.pumpAndSettle();

    expect(
      await waitFor(
        tester,
        () => saved,
        start: () => tester.tap(find.text('save')),
      ),
      isTrue,
      reason: 'de opslag met uitgeschakelde controle liep niet door',
    );
    expect(dialogUp(), isFalse);
  });
}
