import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

/// Pumps [SlidePreviewWidget] on a large, fixed surface so the 16:9 content has
/// room and never overflows. Uses bounded [pump]s — a media preview spins up
/// tickers/controllers, so [pumpAndSettle] would hang.
Future<void> _pumpPreview(
  WidgetTester tester,
  Slide slide, {
  double width = 960,
  double height = 540,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SlideListPanel', () {
    testWidgets('renders one thumbnail per slide in a multi-slide deck', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      for (var i = 0; i < 4; i++) {
        deckNotifier.addSlide(SlideType.image);
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SizedBox(
                width: 320,
                height: 1200,
                child: SlideListPanel(railWidth: 320),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1 starter slide + 4 added = 5 cards on a tall rail that fits them all.
      expect(find.byType(SlideThumbnail), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reflects a selection change made through the editor provider', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      for (var i = 0; i < 4; i++) {
        deckNotifier.addSlide(SlideType.bullets);
      }
      container.read(editorProvider.notifier).select(0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SizedBox(
                width: 320,
                height: 1200,
                child: SlideListPanel(railWidth: 320),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // De selectie zit sinds de perf-optimalisatie ín de thumbnail (elke
      // kaart bewaakt zijn eigen editorProvider-select), dus we lezen de
      // daadwerkelijk gerenderde staat af via Semantics.selected i.p.v. een
      // widget-veld.
      bool isPrimary(int index) {
        final thumb = find.byWidgetPredicate(
          (w) => w is SlideThumbnail && w.index == index,
        );
        final semantics = tester.widget<Semantics>(
          find.descendant(of: thumb, matching: find.byType(Semantics)).first,
        );
        return semantics.properties.selected ?? false;
      }

      expect(isPrimary(0), isTrue);
      expect(isPrimary(2), isFalse);

      // Een selectie via de provider verplaatst de markering: de betrokken
      // thumbnails reageren op de editor-state (het paneel rebuildt niet meer).
      container.read(editorProvider.notifier).select(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // scroll-to-top

      expect(isPrimary(2), isTrue);
      expect(isPrimary(0), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('media previews', () {
    testWidgets('image slide preview builds with a missing image path', (
      tester,
    ) async {
      // A path that resolves to nothing falls back to the placeholder rather
      // than throwing — assert it builds cleanly.
      final slide = Slide.create(
        SlideType.image,
      ).copyWith(imagePath: 'does/not/exist.png', title: 'Een afbeelding');
      await _pumpPreview(tester, slide);

      expect(find.byType(SlidePreviewWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('video slide preview builds with a missing video path', (
      tester,
    ) async {
      // No media is enabled, so the controller never initialises and the movie
      // placeholder shows; it must build without throwing.
      final slide = Slide.create(
        SlideType.video,
      ).copyWith(videoPath: 'does/not/exist.mp4', title: 'Een video');
      await _pumpPreview(tester, slide);

      expect(find.byType(SlidePreviewWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('question preview', () {
    testWidgets('multiple-choice question slide preview renders its answers', (
      tester,
    ) async {
      const spec = QuestionSpec(
        prompt: 'Welke kleur heeft de lucht op een heldere dag?',
        answers: [
          QuestionAnswer(text: 'Blauw', correct: true),
          QuestionAnswer(text: 'Groen'),
          QuestionAnswer(text: 'Rood'),
          QuestionAnswer(text: 'Geel'),
        ],
        optionCount: 4,
      );
      final slide = Slide.create(
        SlideType.question,
      ).copyWith(customMarkdown: spec.toBlock());
      await _pumpPreview(tester, slide);

      expect(find.byType(SlidePreviewWidget), findsOneWidget);
      // Authoring view shows every answer with the correct one marked.
      expect(find.textContaining('Blauw'), findsOneWidget);
      expect(find.textContaining('Groen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('true/false question slide preview renders its statement', (
      tester,
    ) async {
      const spec = QuestionSpec(
        kind: QuestionKind.trueFalse,
        prompt: 'De hoofdstad van Nederland is Amsterdam.',
        statementIsTrue: true,
      );
      final slide = Slide.create(
        SlideType.question,
      ).copyWith(customMarkdown: spec.toBlock());
      await _pumpPreview(tester, slide);

      expect(find.byType(SlidePreviewWidget), findsOneWidget);
      expect(find.textContaining('Juist'), findsOneWidget);
      expect(find.textContaining('Onjuist'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
