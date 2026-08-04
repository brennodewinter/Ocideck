/// Bewijs voor de terugdraai-logica van session-data-edits (#1235).
///
/// De kernbewering: `revertSlidesById` zet meerdere dia's in één ongedaan-stap
/// terug — één `undo()` herstelt álle teruggedraaide dia's, niet één per keer.
/// En de tracking-methode (oorspronkelijke dia vóór de eerste edit vangen met
/// `putIfAbsent`) bewaart de juiste pre-edit versie, zelfs na meerdere edits op
/// dezelfde dia.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Slide _tableSlide(String id, String title, List<List<String>> rows) {
  return Slide(
    id: id,
    type: SlideType.table,
    title: title,
    tableRows: rows,
    tableEditable: true,
  );
}

void main() {
  test('revertSlidesById draait meerdere dia’s in één undo-stap terug', () {
    final n = _notifier();
    final a = _tableSlide('a', 'Tabel A', const [
      ['Kop', 'Waarde'],
      ['x', '1'],
    ]);
    final b = _tableSlide('b', 'Tabel B', const [
      ['Kop', 'Waarde'],
      ['y', '2'],
    ]);
    n.newDeck('Deck', slides: [a, b]);
    expect(n.state.canUndo, isFalse);

    // Simuleer session-data-edits: vang de oorspronkelijke dia vóór de eerste
    // edit (zoals presentDeck dat doet met putIfAbsent), en schrijf door.
    final originals = <String, Slide>{};
    final deck = n.state.deck!;
    final ai = deck.slides.indexWhere((s) => s.id == 'a');
    final bi = deck.slides.indexWhere((s) => s.id == 'b');
    originals.putIfAbsent('a', () => n.state.deck!.slides[ai]);
    n.updateSlide(
      ai,
      a.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '99'],
        ],
      ),
    );
    originals.putIfAbsent('b', () => n.state.deck!.slides[bi]);
    n.updateSlide(
      bi,
      b.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['y', '77'],
        ],
      ),
    );

    // Beide dia's gewijzigd, één undo-stap per edit (geen coalescing tussen
    // verschillende id's) → canUndo waar, twee stappen op de stapel.
    expect(n.state.deck!.slides[ai].tableRows[1][1], '99');
    expect(n.state.deck!.slides[bi].tableRows[1][1], '77');

    // Terugdraaien in één stap.
    n.revertSlidesById(originals);
    expect(n.state.deck!.slides[ai].tableRows[1][1], '1');
    expect(n.state.deck!.slides[bi].tableRows[1][1], '2');

    // Eén undo() brengt beide session-edits terug — bewijst dat revert één
    // stap was, niet twee.
    n.undo();
    expect(n.state.deck!.slides[ai].tableRows[1][1], '99');
    expect(n.state.deck!.slides[bi].tableRows[1][1], '77');
  });

  test('putIfAbsent bewaart de oorspronkelijke dia, niet een latere edit', () {
    final n = _notifier();
    final a = _tableSlide('a', 'Tabel A', const [
      ['Kop', 'Waarde'],
      ['x', '1'],
    ]);
    n.newDeck('Deck', slides: [a]);
    final originals = <String, Slide>{};
    final deck = n.state.deck!;
    final ai = deck.slides.indexWhere((s) => s.id == 'a');

    // Eerste edit: vang origineel (waarde 1).
    originals.putIfAbsent('a', () => n.state.deck!.slides[ai]);
    n.updateSlide(
      ai,
      a.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '2'],
        ],
      ),
    );
    // Tweede edit: putIfAbsent overschrijft niet — origineel blijft 1.
    originals.putIfAbsent('a', () => n.state.deck!.slides[ai]);
    n.updateSlide(
      ai,
      a.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '3'],
        ],
      ),
    );

    expect(originals['a']!.tableRows[1][1], '1');
    n.revertSlidesById(originals);
    expect(n.state.deck!.slides[ai].tableRows[1][1], '1');
  });

  test('revertSlidesById laat dia’s buiten de map ongemoeid', () {
    final n = _notifier();
    final a = _tableSlide('a', 'A', const [
      ['K', 'V'],
      ['x', '1'],
    ]);
    final b = _tableSlide('b', 'B', const [
      ['K', 'V'],
      ['y', '2'],
    ]);
    n.newDeck('Deck', slides: [a, b]);
    final originals = <String, Slide>{};
    final deck = n.state.deck!;
    final ai = deck.slides.indexWhere((s) => s.id == 'a');
    originals.putIfAbsent('a', () => n.state.deck!.slides[ai]);
    n.updateSlide(
      ai,
      a.copyWith(
        tableRows: const [
          ['K', 'V'],
          ['x', '99'],
        ],
      ),
    );
    // 'b' wordt niet als session-edit bijgehouden → mag niet veranderen.
    n.revertSlidesById(originals);
    final bi = n.state.deck!.slides.indexWhere((s) => s.id == 'b');
    expect(n.state.deck!.slides[bi].tableRows[1][1], '2');
  });
}
