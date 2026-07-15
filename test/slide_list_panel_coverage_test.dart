import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/slide_clipboard_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-coverage tests for the slide thumbnail rail: search, the skip banner,
/// the bulk-action bar, the per-thumbnail context menu and the add/paste
/// buttons. The existing slide_list_panel_test.dart covers scrolling/selection
/// bookkeeping; this suite drives the panel's controls.

/// A no-op paste that yields nothing, so the "paste image" button reliably
/// takes the "empty clipboard" branch instead of hitting the real Pasteboard
/// plugin (which is not registered under `flutter test`).
class _NoImageService extends ImageService {
  @override
  Future<String?> pasteImage({String? projectPath}) async => null;
}

Deck _titledDeck(List<String> titles) => Deck(
  title: 'Test',
  slides: [
    for (final t in titles)
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: t, bullets: const ['een', 'twee']),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  double height = 720,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: height,
            child: const SlideListPanel(railWidth: 320),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({});
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

Finder _thumb(int index) =>
    find.byWidgetPredicate((w) => w is SlideThumbnail && w.index == index);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('search filters the rail and can be cleared', (tester) async {
    final container = _container();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['Alpha', 'Beta', 'Gamma']));
    await _pump(tester, container);

    // Typing a matching term narrows the count shown in the header.
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);

    // A term that matches nothing shows the empty state.
    await tester.enterText(find.byType(TextField), 'zzz-nope');
    await tester.pump();
    expect(find.textContaining('Geen slides met'), findsOneWidget);

    // The clear button resets the query and the empty state disappears.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.textContaining('Geen slides met'), findsNothing);
    expect(find.byType(SlideThumbnail), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the quick skip toggle raises the skip banner and clears it', (
    tester,
  ) async {
    final container = _container();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['A', 'B', 'C']));
    await _pump(tester, container);

    // The first thumbnail's quick "skip" toggle marks it skipped.
    await tester.tap(
      find.descendant(
        of: _thumb(0),
        matching: find.byIcon(Icons.visibility_outlined),
      ),
    );
    await tester.pump();
    expect(find.text('1 slide overgeslagen'), findsOneWidget);

    // "Alles tonen" clears every skip and dismisses the banner.
    await tester.tap(find.text('Alles tonen'));
    await tester.pump();
    expect(find.text('1 slide overgeslagen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bulk-action bar toggles skip and can be dismissed', (
    tester,
  ) async {
    final container = _container();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['A', 'B', 'C']));
    await _pump(tester, container);

    // Select a two-slide range so the bulk bar appears.
    final editor = container.read(editorProvider.notifier);
    editor.select(0);
    editor.selectRange(1);
    await tester.pump();
    expect(find.text('2 geselecteerd'), findsOneWidget);

    // The "skip" tooltip is shared with each thumbnail's quick toggle, so scope
    // the tap to the bulk bar's own row (the one carrying the count label).
    final bulkRow = find
        .ancestor(of: find.text('2 geselecteerd'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(
        of: bulkRow,
        matching: find.byTooltip('Overslaan bij presenteren/exporteren'),
      ),
    );
    await tester.pump();
    expect(find.textContaining('overgeslagen'), findsWidgets);

    // "Weer tonen" is unique to the bulk bar (thumbnails say "Weer tonen bij…").
    await tester.tap(find.byTooltip('Weer tonen'));
    await tester.pump();

    // Deselecting collapses to a single selection, hiding the bar.
    await tester.tap(find.byTooltip('Selectie opheffen'));
    await tester.pump();
    expect(find.text('2 geselecteerd'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bulk copy with no other deck open reports it', (tester) async {
    // Reads tabsProvider, which spins up a 25s autosave timer — dispose the
    // container at the end so the timer is cancelled before the pending-timer
    // check runs.
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['A', 'B', 'C']));
    await _pump(tester, container);

    final editor = container.read(editorProvider.notifier);
    editor.select(0);
    editor.selectRange(1);
    await tester.pump();

    await tester.tap(find.byTooltip('Kopiëren naar ander deck'));
    await tester.pump();
    expect(
      find.text('Geen ander deck open. Open eerst een ander tabblad.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('the bulk-action bar deletes the selected slides', (
    tester,
  ) async {
    final container = _container();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['A', 'B', 'C']));
    await _pump(tester, container);

    final editor = container.read(editorProvider.notifier);
    editor.select(0);
    editor.selectRange(1); // selects slides 0 and 1
    await tester.pump();

    expect(container.read(deckProvider).deck!.slides.length, 3);
    await tester.tap(find.byTooltip('Verwijderen'));
    await tester.pump();

    // Two removed, one kept (the panel always keeps at least one).
    expect(container.read(deckProvider).deck!.slides.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the context menu duplicates and deletes a slide', (
    tester,
  ) async {
    final container = _container();
    container.read(deckProvider.notifier).loadDeck(_titledDeck(['A', 'B']));
    await _pump(tester, container);

    // Search mode renders a plain (non-reorderable) ListView that reuses the
    // exact same per-thumbnail callbacks. The reorderable rail otherwise trips a
    // framework semantics-geometry assertion when its keyed items rebuild while
    // a menu route is opening. Every bullets slide matches "een" (its type
    // label is "Alleen Bullets"), so the filter keeps the whole list visible.
    await tester.enterText(find.byType(TextField), 'een');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Bounded pumps (not pumpAndSettle): the preview can host a blinking caret.
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> openMenu(int index) async {
      final button = find.descendant(
        of: _thumb(index),
        matching: find.byIcon(Icons.more_vert),
      );
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle();
    }

    // Duplicate grows the deck by one.
    await openMenu(0);
    await tester.tap(find.text('Dupliceren'));
    await settle();
    expect(container.read(deckProvider).deck!.slides.length, 3);

    // Split (bullets with two items) grows it again.
    await openMenu(0);
    await tester.tap(find.text('In tweeën splitsen'));
    await settle();
    expect(container.read(deckProvider).deck!.slides.length, 4);

    // Delete shrinks it back.
    await openMenu(0);
    await tester.tap(find.text('Verwijderen'));
    await settle();
    expect(container.read(deckProvider).deck!.slides.length, 3);

    // Drain the panel's scroll-to-top post-frame callbacks while still mounted;
    // the widget reads `ref` in them without a mounted guard, so a stray one
    // firing after teardown would surface as an unexpected exception.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('copying a slide reveals the paste button and pastes it', (
    tester,
  ) async {
    final container = _container();
    container.read(deckProvider.notifier).loadDeck(_titledDeck(['A', 'B']));
    await _pump(tester, container);

    // "Kopiëren" in the context menu stores the slide on the clipboard.
    await tester.tap(
      find.descendant(of: _thumb(0), matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Kopiëren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(container.read(slideClipboardProvider), isNotNull);

    // The paste button now exists; tapping it inserts a copy.
    final pasteButton = find.text('Slide plakken');
    expect(pasteButton, findsOneWidget);
    await tester.ensureVisible(pasteButton);
    await tester.tap(pasteButton);
    await tester.pump();
    expect(container.read(deckProvider).deck!.slides.length, 3);

    // Drain the scroll-to-top post-frame callbacks while still mounted.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the paste-image button reports an empty clipboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [imageServiceProvider.overrideWithValue(_NoImageService())],
    );
    addTearDown(container.dispose);
    container.read(deckProvider.notifier).loadDeck(_titledDeck(['A']));
    await _pump(tester, container);

    final button = find.text('Afbeelding plakken');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(
      find.text('Geen afbeelding op het klembord gevonden.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add-slide button opens the picker and inserts a type', (
    tester,
  ) async {
    final container = _container();
    container.read(deckProvider.notifier).loadDeck(_titledDeck(['A']));
    await _pump(tester, container);

    // Search mode swaps the reorderable rail for a plain ListView, so opening
    // the dialog route on top does not trip the reorderable semantics bug.
    await tester.enterText(find.byType(TextField), 'een');
    await tester.pump();

    final addButton = find.text('Slide toevoegen');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AddSlideDialog), findsOneWidget);

    // Pick the first curated type; the dialog returns it and the panel inserts.
    await tester.tap(find.text('Titelpagina').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AddSlideDialog), findsNothing);
    expect(container.read(deckProvider).deck!.slides.length, 2);

    // Drain the scroll-to-top post-frame callbacks while still mounted.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard shortcuts move the selection and delete', (
    tester,
  ) async {
    final container = _container();
    container
        .read(deckProvider.notifier)
        .loadDeck(_titledDeck(['A', 'B', 'C', 'D']));
    await _pump(tester, container);

    // The panel autofocuses; arrow keys walk the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(editorProvider).selectedIndex, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(editorProvider).selectedIndex, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(editorProvider).selectedIndex, 0);

    // Delete with a single selection drops that one slide (4 → 3).
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(deckProvider).deck!.slides.length, 3);

    // Ctrl+A selects every remaining slide.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(container.read(editorProvider).selection.length, 3);
    expect(tester.takeException(), isNull);
  });
}
