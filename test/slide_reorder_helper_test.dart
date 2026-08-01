import 'package:flutter_test/flutter_test.dart';

import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';

DeckNotifier _deckWith(int extraSlides) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final n = DeckNotifier(md, file)..newDeck('D');
  for (var i = 0; i < extraSlides; i++) {
    n.addSlide(SlideType.bullets);
  }
  return n;
}

void main() {
  group('applySlideReorder', () {
    test('a single move reorders and the selection follows the slide', () {
      final deck = _deckWith(3); // 4 slides total
      final editor = EditorNotifier()..select(0);
      final movedId = deck.state.deck!.slides.first.id;

      applySlideReorder(
        0,
        2,
        editor: editor.currentState,
        notifier: deck,
        editorNotifier: editor,
        slideCount: deck.state.deck!.slides.length,
      );

      expect(deck.state.deck!.slides[2].id, movedId);
      // The active slide rode along to its new index.
      expect(editor.currentState.selectedIndex, 2);
    });

    test('a move above the active slide shifts the selection up by one', () {
      final deck = _deckWith(3);
      final editor = EditorNotifier()..select(2);

      // Drag slide 0 to the end: the active slide at 2 loses a predecessor.
      applySlideReorder(
        0,
        3,
        editor: editor.currentState,
        notifier: deck,
        editorNotifier: editor,
        slideCount: deck.state.deck!.slides.length,
      );

      expect(editor.currentState.selectedIndex, 1);
    });

    test(
      'a multi-selection moves as one block and the selection tracks it',
      () {
        final deck = _deckWith(4); // 5 slides
        final ids = deck.state.deck!.slides.map((s) => s.id).toList();
        final editor = EditorNotifier()..selectAll(5);
        // Keep only the first two selected as the dragged block.
        editor
          ..select(0)
          ..toggleSelect(1);

        applySlideReorder(
          0,
          3,
          editor: editor.currentState,
          notifier: deck,
          editorNotifier: editor,
          slideCount: deck.state.deck!.slides.length,
        );

        final after = deck.state.deck!.slides.map((s) => s.id).toList();
        // The two-slide block [0,1] moved together, keeping its internal order.
        final newStart = after.indexOf(ids[0]);
        expect(after[newStart + 1], ids[1]);
        expect(editor.currentState.hasMultiSelection, isTrue);
        expect(editor.currentState.selection.length, 2);
      },
    );
  });
}
