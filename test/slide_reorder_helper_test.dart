import 'package:flutter_test/flutter_test.dart';

import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/slide_reorder.dart';

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

  group('applySlideInsertion', () {
    List<String> apply(
      DeckNotifier deck,
      EditorNotifier editor,
      int dragged,
      int slot,
    ) {
      applySlideInsertion(
        dragged,
        slot,
        editor: editor.currentState,
        notifier: deck,
        editorNotifier: editor,
        slideCount: deck.state.deck!.slides.length,
      );
      return deck.state.deck!.slides.map((s) => s.id).toList();
    }

    test('slot 0 places the slide before the first one', () {
      final deck = _deckWith(3); // 4 slides
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..select(0);

      final after = apply(deck, editor, 2, 0);

      expect(after, [ids[2], ids[0], ids[1], ids[3]]);
      expect(editor.currentState.selectedIndex, 1);
    });

    test('a middle slot places the slide between its neighbours', () {
      final deck = _deckWith(3);
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..select(0);

      // Slot 3 = "vóór dia 3": de gesleepte dia 0 belandt tussen 2 en 3.
      final after = apply(deck, editor, 0, 3);

      expect(after, [ids[1], ids[2], ids[0], ids[3]]);
    });

    test('slot N places the slide after the last one', () {
      final deck = _deckWith(3);
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..select(0);

      final after = apply(deck, editor, 0, 4);

      expect(after, [ids[1], ids[2], ids[3], ids[0]]);
      expect(editor.currentState.selectedIndex, 3);
    });

    test('a selected block moves to a slot while keeping its order', () {
      final deck = _deckWith(4); // 5 slides
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..selectAll(5);
      editor
        ..select(1)
        ..toggleSelect(2);

      // Sleep dia 1 (deel van het blok {1,2}) naar slot 0: vóór alles.
      final after = apply(deck, editor, 1, 0);

      expect(after, [ids[1], ids[2], ids[0], ids[3], ids[4]]);
      expect(editor.currentState.selection, {0, 1});
      // De actieve dia (de laatst aangevinkte, index 2) rijdt mee naar het
      // tweede bloklid.
      expect(editor.currentState.selectedIndex, 1);
    });

    test('a slot inside or next to the dragged block changes nothing', () {
      final deck = _deckWith(4);
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..selectAll(5);
      editor
        ..select(1)
        ..toggleSelect(2);

      for (final slot in [1, 2, 3]) {
        expect(
          apply(deck, editor, 1, slot),
          ids,
          reason: 'slot $slot in/langs het eigen blok is een no-op',
        );
      }
    });

    test('a single slide dropped on its own slots changes nothing', () {
      final deck = _deckWith(3);
      final ids = deck.state.deck!.slides.map((s) => s.id).toList();
      final editor = EditorNotifier()..select(0);

      for (final slot in [1, 2]) {
        expect(apply(deck, editor, 1, slot), ids);
      }
    });
  });

  group('isNoOpInsertSlot', () {
    test('marks the slots in and around a contiguous block', () {
      expect(isNoOpInsertSlot({1, 2}, 1, 5), isTrue);
      expect(isNoOpInsertSlot({1, 2}, 2, 5), isTrue);
      expect(isNoOpInsertSlot({1, 2}, 3, 5), isTrue);
      expect(isNoOpInsertSlot({1, 2}, 0, 5), isFalse);
      expect(isNoOpInsertSlot({1, 2}, 4, 5), isFalse);
    });

    test('marks only member slots of a non-contiguous selection', () {
      expect(isNoOpInsertSlot({0, 2}, 0, 5), isTrue);
      expect(isNoOpInsertSlot({0, 2}, 1, 5), isFalse);
      expect(isNoOpInsertSlot({0, 2}, 2, 5), isTrue);
      expect(isNoOpInsertSlot({0, 2}, 3, 5), isFalse);
    });
  });
}
