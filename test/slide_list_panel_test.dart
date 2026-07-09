import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

void main() {
  // Regression: the thumbnail rail used to leave numberStart at 1, so a split
  // numbered slide's second half restarted at 1 in the builder even though the
  // main preview and the presentation continued the count. The rail must
  // compute the same start as those, so the overview matches what is shown.
  testWidgets('rail thumbnails continue a numbered list across a split', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final first = Slide.create(SlideType.bullets).copyWith(
      title: 'Eerste',
      listStyle: ListStyle.numbered,
      bullets: const ['een', 'twee', 'drie'],
    );
    final second = Slide.create(SlideType.bullets).copyWith(
      title: 'Vervolg',
      listStyle: ListStyle.numbered,
      continueNumbering: true,
      bullets: const ['vier', 'vijf'],
    );
    container
        .read(deckProvider.notifier)
        .loadDeck(Deck(title: 'T', slides: [first, second]));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(width: 320, child: SlideListPanel(railWidth: 320)),
          ),
        ),
      ),
    );
    await tester.pump();

    SlideThumbnail thumbAt(int i) => tester.widget<SlideThumbnail>(
      find.byWidgetPredicate((w) => w is SlideThumbnail && w.index == i),
    );
    // First slide starts at 1; the continued second half starts past its three
    // items, at 4.
    expect(thumbAt(0).numberStart, 1);
    expect(thumbAt(1).numberStart, 4);
  });

  testWidgets('resizing the rail brings the edited slide back into view', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    for (var i = 0; i < 19; i++) {
      deckNotifier.addSlide(SlideType.bullets);
    }
    container.read(editorProvider.notifier).select(12);

    final width = ValueNotifier<double>(320);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, w, _) => SizedBox(
                  width: w,
                  height: 600,
                  child: SlideListPanel(railWidth: w),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The selected slide (12) sits far below the fold and nothing scrolls it
    // into view on its own.
    bool slide12Visible() => find
        .byWidgetPredicate((w) => w is SlideThumbnail && w.index == 12)
        .evaluate()
        .isNotEmpty;
    expect(slide12Visible(), isFalse);

    // Drag the rail wider: thumbnails change height, and once the resize
    // settles the list scrolls the slide being edited back to the top.
    width.value = 240;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // debounce fires
    await tester.pump(); // coarse jump near the unbuilt slide
    await tester.pump(); // precise reveal starts
    await tester.pump(const Duration(milliseconds: 200)); // animateTo settles

    expect(slide12Visible(), isTrue);
    final rect = tester.getRect(
      find.byWidgetPredicate((w) => w is SlideThumbnail && w.index == 12),
    );
    // At the top of the list area (below the panel header).
    expect(rect.top, lessThan(120));
  });

  testWidgets('thumbnails expose one concise semantic label per slide', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    deckNotifier.addSlide(SlideType.bullets);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(width: 320, child: SlideListPanel(railWidth: 320)),
          ),
        ),
      ),
    );
    await tester.pump();

    // Screen readers get "Slide n/m: title-or-type" per card, instead of the
    // full content of every mini preview.
    expect(find.bySemanticsLabel(RegExp(r'^Slide 1/2: ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Slide 2/2: ')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('thumbnail shows badge when slide has user notes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    final slide = container.read(deckProvider).deck!.slides.single;
    deckNotifier.setUserNoteForSlide(slide.id, 'Cursusnotitie');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(width: 320, child: SlideListPanel(railWidth: 320)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (w) => w is SlideThumbnail && w.hasUserNotes && w.index == 0,
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
  });

  testWidgets('deleting a slide keeps the newly focused slide in view', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    final editorNotifier = container.read(editorProvider.notifier);
    deckNotifier.newDeck('Test');
    for (var i = 0; i < 19; i++) {
      deckNotifier.addSlide(SlideType.bullets);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: SlideListPanel(railWidth: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Finder thumb(int i) =>
        find.byWidgetPredicate((w) => w is SlideThumbnail && w.index == i);

    // Select a slide far below the fold and let it scroll to the top.
    editorNotifier.select(15);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(thumb(15), findsOneWidget);
    expect(thumb(0), findsNothing);

    // Delete slide 15 exactly as the panel's context menu does: drop the slide,
    // then move focus to the slide above it.
    deckNotifier.removeSlide(15);
    editorNotifier.select(14);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));

    // Regression: the list must follow the focus to slide 14, not snap back to
    // the top with slide 0 showing.
    expect(
      thumb(14),
      findsOneWidget,
      reason: 'focused slide should be visible',
    );
    final rect = tester.getRect(thumb(14));
    expect(rect.top, lessThan(200), reason: 'focused slide should be near top');
  });

  testWidgets('deleting a slide below the selection keeps it in view', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final deckNotifier = container.read(deckProvider.notifier);
    final editorNotifier = container.read(editorProvider.notifier);
    deckNotifier.newDeck('Test');
    for (var i = 0; i < 19; i++) {
      deckNotifier.addSlide(SlideType.bullets);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: SlideListPanel(railWidth: 320),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Finder thumb(int i) =>
        find.byWidgetPredicate((w) => w is SlideThumbnail && w.index == i);

    editorNotifier.select(14);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(thumb(14), findsOneWidget);
    expect(thumb(0), findsNothing);

    // Delete slide 15 (below the selection) via the context menu: the focus
    // target is the already-selected slide 14, so `select` is a no-op and only
    // the deck length changes.
    deckNotifier.removeSlide(15);
    editorNotifier.select(14);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      thumb(14),
      findsOneWidget,
      reason: 'focused slide should stay in view',
    );
    final rect = tester.getRect(thumb(14));
    expect(rect.top, lessThan(200), reason: 'focused slide should be near top');
  });
}
