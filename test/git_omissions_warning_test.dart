// De git-opslag laat werk achter, en dat moet de gebruiker vóór de commit horen.
//
// `deck.md`, de afbeeldingenpool en de grafiekdata gaan mee; video, audio, de
// tekenlaag (`.ink.json`) en de gebruikersnotities (`.user-notes.json`) niet —
// `services/git/` schrijft die sidecars nergens. Op schijf reizen ze wél mee,
// dus wie van een bestand naar git verhuist raakt ze kwijt zonder dat er iets
// misgaat waar de app op kan wijzen. Ze alsnog meenemen is een grotere ingreep;
// de waarschuwing kan niet wachten, en hoort vóór de commit — daarna is de
// keuze al gemaakt.
import 'dart:ui' show Offset;

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

  group('gitDeckOmissions', () {
    test('telt video, audio, tekeningen en notities apart', () {
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
        annotations: {
          a.id: const [
            InkStroke(
              tool: InkTool.pen,
              color: 0xFFEF4444,
              width: 0.004,
              points: [Offset(0.1, 0.2)],
            ),
          ],
        },
        userNotes: {a.id: 'Niet vergeten te noemen'},
      );

      final missing = gitDeckOmissions(deck);
      expect(missing.videoSlides, 1);
      expect(missing.audioSlides, 1);
      expect(missing.annotatedSlides, 1);
      expect(missing.noteSlides, 1);
      expect(missing.isNotEmpty, isTrue);
    });

    test('een leeg notitieveld of een lege tekenlaag telt niet mee', () {
      final a = plain('Een');
      final deck = Deck(
        title: 'R',
        slides: [a],
        annotations: {a.id: const []},
        userNotes: {a.id: '   '},
      );
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

  Deck deckWithNotes() {
    final a = plain('Test');
    return Deck(
      title: 'Test',
      slides: [a],
      userNotes: {a.id: 'Deze zin hoort erbij'},
    );
  }

  testWidgets('opslaan naar git waarschuwt eerst over wat achterblijft', (
    tester,
  ) async {
    await pumpWithDeck(tester, deckWithNotes());
    await tapSaveTo(tester);

    expect(find.text('Niet alles gaat mee naar git'), findsOneWidget);
    // In de dialoog zelf, niet ergens anders in de shell: het woord komt ook
    // op de diastrook voor.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Gebruikersnotities'),
      ),
      findsOneWidget,
    );
    // Blokkerend: het opslaandialoog komt pas ná deze keuze.
    expect(find.text('Deknaam'), findsNothing);
  });

  testWidgets('annuleren stopt het opslaan', (tester) async {
    await pumpWithDeck(tester, deckWithNotes());
    await tapSaveTo(tester);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(find.text('Niet alles gaat mee naar git'), findsNothing);
    expect(find.text('Deknaam'), findsNothing);
  });

  testWidgets('doorgaan brengt de gebruiker bij het opslaandialoog', (
    tester,
  ) async {
    await pumpWithDeck(tester, deckWithNotes());
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
}
