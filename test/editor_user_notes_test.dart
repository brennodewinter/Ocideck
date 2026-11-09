import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:ocideck/models/slide.dart';

const _l10n = AppLocalizations(Locale('nl'));

Future<void> _switchToMarkdownMode(WidgetTester tester, Finder scope) async {
  await tester.tap(
    find.descendant(of: scope, matching: find.text(_l10n.t('markdownMode'))),
  );
  await tester.pumpAndSettle();
}

/// De werkruimte zoals de shell hem opbouwt: sliderail naast het editorpaneel.
/// Toetsen die in de notities vallen mogen de rail nooit bereiken.
Future<void> _pumpWorkspace(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Row(
            children: [
              SizedBox(width: 320, child: SlideListPanel(railWidth: 320)),
              Expanded(child: EditorPanel()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('Delete removes selected speaker note text, not the slide', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    deckNotifier.addSlide(SlideType.bullets);
    final slide = container.read(deckProvider).deck!.slides.first;
    deckNotifier.updateSlide(0, slide.copyWith(notes: 'Bewaar verwijder dit'));

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpWorkspace(tester, container);

    final notes = find.byKey(ValueKey('speaker-notes-${slide.id}-p0'));
    final field = find.descendant(
      of: notes,
      matching: find.byType(QuillEditor),
    );
    await tester.tap(field);
    await tester.pump();
    tester
        .widget<QuillEditor>(field)
        .controller
        .updateSelection(
          const TextSelection(baseOffset: 7, extentOffset: 20),
          ChangeSource.local,
        );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    final deck = container.read(deckProvider).deck!;
    expect(deck.slides, hasLength(2));
    expect(deck.slides.first.notes, 'Bewaar');
  });

  testWidgets('Backspace removes selected speaker note text, not the slide', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    deckNotifier.addSlide(SlideType.bullets);
    final slide = container.read(deckProvider).deck!.slides.first;
    deckNotifier.updateSlide(0, slide.copyWith(notes: 'Bewaar verwijder dit'));

    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpWorkspace(tester, container);

    final notes = find.byKey(ValueKey('speaker-notes-${slide.id}-p0'));
    final field = find.descendant(
      of: notes,
      matching: find.byType(QuillEditor),
    );
    await tester.tap(field);
    await tester.pump();
    tester
        .widget<QuillEditor>(field)
        .controller
        .updateSelection(
          const TextSelection(baseOffset: 7, extentOffset: 20),
          ChangeSource.local,
        );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final deck = container.read(deckProvider).deck!;
    expect(deck.slides, hasLength(2));
    expect(deck.slides.first.notes, 'Bewaar');
  });

  testWidgets(
    'Delete and Backspace in markdown-mode notes edit text, not the slide',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      deckNotifier.addSlide(SlideType.bullets);
      final slide = container.read(deckProvider).deck!.slides.first;
      deckNotifier.updateSlide(
        0,
        slide.copyWith(notes: 'Bewaar verwijder dit'),
      );

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpWorkspace(tester, container);

      final notes = find.byKey(ValueKey('speaker-notes-${slide.id}-p0'));
      await _switchToMarkdownMode(tester, notes);
      final field = find.descendant(
        of: notes,
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);

      for (final key in [
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.backspace,
      ]) {
        await tester.enterText(field, 'Bewaar verwijder dit');
        await tester.pump();
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection(
          baseOffset: 7,
          extentOffset: 20,
        );
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();

        final deck = container.read(deckProvider).deck!;
        expect(deck.slides, hasLength(2));
        expect(deck.slides.first.notes, 'Bewaar');
      }
    },
  );

  testWidgets(
    'Delete after a remount that took the notes focus keeps the slide',
    (tester) async {
      // #2839: demonteert het gefocuste notitieveld (hier via de
      // revisie-remount van een undo), dan pakt de autofocus van de
      // sliderail de primaire focus. Een Delete daarna hoorde de dia te
      // wissen; hij mag alleen wissen als de gebruiker de rail zelf
      // aanraakte.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      deckNotifier.addSlide(SlideType.bullets);
      final slide = container.read(deckProvider).deck!.slides.first;
      deckNotifier.updateSlide(
        0,
        slide.copyWith(notes: 'Bewaar verwijder dit'),
      );

      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpWorkspace(tester, container);

      final notes = find.byKey(ValueKey('speaker-notes-${slide.id}-p0'));
      final field = find.descendant(
        of: notes,
        matching: find.byType(QuillEditor),
      );
      await tester.tap(field);
      await tester.pump();
      tester
          .widget<QuillEditor>(field)
          .controller
          .updateSelection(
            const TextSelection(baseOffset: 7, extentOffset: 20),
            ChangeSource.local,
          );
      await tester.pump();

      // De undo remount de hele editor-subtree (editor-rev-*): het
      // gefocuste veld demonteert en de rail-autofocus pakt de focus.
      deckNotifier.undo();
      await tester.pump();

      var focusInRail = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
        if (e.widget is SlideListPanel) focusInRail = true;
        return true;
      });
      expect(
        focusInRail,
        isTrue,
        reason: 'preconditie van de bug: focus viel stil in de rail',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(container.read(deckProvider).deck!.slides, hasLength(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(container.read(deckProvider).deck!.slides, hasLength(2));
    },
  );

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
            ...GlobalMaterialLocalizations.delegates,
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
            ...GlobalMaterialLocalizations.delegates,
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
            ...GlobalMaterialLocalizations.delegates,
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
            ...GlobalMaterialLocalizations.delegates,
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
