import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

const _l10n = AppLocalizations(Locale('nl'));

Future<void> _switchToMarkdownMode(WidgetTester tester, Finder scope) async {
  await tester.tap(
    find.descendant(of: scope, matching: find.text(_l10n.t('markdownMode'))),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('speaker notes and user notes are separate fields', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Spreker tekst');
    deckNotifier.updateSlide(0, slide);
    deckNotifier.setUserNoteForSlide(slide.id, 'Bestaande cursusnotitie');

    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(deckProvider).deck!.slides.single.notes,
      'Spreker tekst',
    );

    final userNotesEditor = find.byKey(ValueKey('user-notes-${slide.id}-p0'));
    expect(userNotesEditor, findsOneWidget);
    await _switchToMarkdownMode(tester, userNotesEditor);

    final userField = find.descendant(
      of: userNotesEditor,
      matching: find.byType(TextField),
    );
    expect(userField, findsOneWidget);
    expect(
      tester.widget<TextField>(userField).controller?.text,
      'Bestaande cursusnotitie',
    );

    await tester.enterText(userField, 'Nieuwe cursusnotitie');
    await tester.pump();

    final deck = container.read(deckProvider).deck!;
    expect(deck.userNotes[slide.id], 'Nieuwe cursusnotitie');
    expect(deck.slides.single.notes, 'Spreker tekst');

    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('clearing user note leaves speaker notes intact', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Blijft staan');
    deckNotifier.updateSlide(0, slide);
    deckNotifier.setUserNoteForSlide(slide.id, 'Weg hiermee');

    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final userNotesEditor = find.byKey(ValueKey('user-notes-${slide.id}-p0'));
    await _switchToMarkdownMode(tester, userNotesEditor);

    final userField = find.descendant(
      of: userNotesEditor,
      matching: find.byType(TextField),
    );
    await tester.enterText(userField, '');
    await tester.pump();

    final deck = container.read(deckProvider).deck!;
    expect(deck.userNotes.containsKey(slide.id), isFalse);
    expect(deck.slides.single.notes, 'Blijft staan');

    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('discard button clears speaker notes only', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Spreker tekst');
    deckNotifier.updateSlide(0, slide);
    deckNotifier.setUserNoteForSlide(slide.id, 'Cursusnotitie');

    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('discard-speaker-notes-${slide.id}')));
    await tester.pumpAndSettle();

    final deck = container.read(deckProvider).deck!;
    expect(deck.slides.single.notes, isEmpty);
    expect(deck.userNotes[slide.id], 'Cursusnotitie');
  });

  testWidgets('discard button clears user notes only', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(notes: 'Spreker tekst');
    deckNotifier.updateSlide(0, slide);
    deckNotifier.setUserNoteForSlide(slide.id, 'Cursusnotitie');

    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('discard-user-notes-${slide.id}')));
    await tester.pumpAndSettle();

    final deck = container.read(deckProvider).deck!;
    expect(deck.slides.single.notes, 'Spreker tekst');
    expect(deck.userNotes.containsKey(slide.id), isFalse);
  });
}
