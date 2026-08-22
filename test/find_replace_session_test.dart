import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_search.dart';
import 'package:ocideck/widgets/editors/find_replace_session.dart';
import 'package:ocideck/widgets/editors/markdown_source_controller.dart';

/// De zoek-/vervangstand die de documenteditor en de presentatie-broneditor
/// delen. Beide schermen zijn widgets met een eigen `setState`; de sessie zelf
/// is dat bewust niet, en dus toetsbaar zonder er een boom omheen te bouwen.
///
/// Wat hier wordt vastgelegd is precies wat er bij het samenvoegen van de twee
/// kopieën kon wegvallen: dat de teller meeloopt, dat de cursor op de juiste
/// treffer landt, en dat vervangen doorloopt in plaats van terug te springen.
void main() {
  late MarkdownSourceController controller;
  late List<TextMatchRange> revealed;
  late int rebuilds;

  FindReplaceSession sessionFor(String text) {
    controller = MarkdownSourceController(text: text);
    revealed = [];
    rebuilds = 0;
    return FindReplaceSession(
      controller: controller,
      onChanged: () => rebuilds++,
      onReveal: revealed.add,
    );
  }

  test('een vraag in de open balk telt en wijst de eerste treffer aan', () {
    final find = sessionFor('een kat, twee kat, drie kat');
    find.open(showReplace: false);
    find.setQuery('kat');

    expect(find.visible, isTrue);
    expect(find.matchCount, 3);
    expect(find.matchIndex, 0);
    expect(revealed.single.start, 4);
  });

  test('een dichte balk sleept de weergave nergens heen', () {
    final find = sessionFor('kat kat');
    find.setQuery('kat');

    expect(revealed, isEmpty, reason: 'niets te tonen, dus niet springen');
  });

  test('volgende en vorige lopen rond', () {
    final find = sessionFor('kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');

    find.next();
    expect(find.matchIndex, 1);
    find.next();
    expect(find.matchIndex, 0, reason: 'loopt rond aan het eind');
    find.previous();
    expect(find.matchIndex, 1, reason: 'loopt rond aan het begin');
  });

  test('hoofdlettergevoelig zoeken telt anders', () {
    final find = sessionFor('Kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    expect(find.matchCount, 2);

    find.setCaseSensitive(true);
    expect(find.matchCount, 1);
    expect(find.matchIndex, 0);
  });

  test('sluiten haalt de markering weg maar houdt de vraag', () {
    final find = sessionFor('kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    find.close();

    expect(find.visible, isFalse);
    expect(find.matchCount, 0);
    expect(find.query, 'kat', reason: 'de vraag overleeft het sluiten');

    find.open(showReplace: true);
    expect(find.matchCount, 2);
    expect(find.showReplace, isTrue);
  });

  test('vervang de huidige treffer en loop door naar de volgende', () {
    final find = sessionFor('kat kat kat');
    find.open(showReplace: true);
    find
      ..setQuery('kat')
      ..setReplacement('hond');

    find.replaceCurrent();

    expect(controller.text, 'hond kat kat');
    expect(find.matchCount, 2, reason: 'er staan er nog twee');
    expect(
      find.matchIndex,
      0,
      reason: 'de cursor blijft vooraan in de resterende rij, niet op de oude',
    );
  });

  test('alles vervangen laat niets gemarkeerd achter', () {
    final find = sessionFor('kat kat kat');
    find.open(showReplace: true);
    find
      ..setQuery('kat')
      ..setReplacement('hond');

    find.replaceAll();

    expect(controller.text, 'hond hond hond');
    expect(find.matchCount, 0);
    expect(find.matchIndex, -1);
  });

  test('alles vervangen zonder vraag raakt de tekst niet', () {
    final find = sessionFor('kat');
    find.open(showReplace: true);
    find.setReplacement('hond');

    find.replaceAll();

    expect(controller.text, 'kat');
  });

  test('typen werkt de teller bij zonder de cursor te verslepen', () {
    final find = sessionFor('kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    find.next();
    expect(find.matchIndex, 1);
    final revealsBefore = revealed.length;

    controller.text = 'kat kat kat';
    find.refreshWhileTyping();

    expect(find.matchCount, 3);
    expect(find.matchIndex, 1, reason: 'blijft staan waar je was');
    expect(
      revealed.length,
      revealsBefore,
      reason: 'typen mag de weergave niet naar een treffer trekken',
    );
  });

  test('een gesloten balk telt niet mee tijdens het typen', () {
    final find = sessionFor('kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    find.close();

    controller.text = 'kat kat kat';
    find.refreshWhileTyping();

    expect(find.matchCount, 0, reason: 'niet zichtbaar, dus niets te tellen');
  });

  test('een treffer die verdwijnt laat de cursor niet buiten de rij staan', () {
    final find = sessionFor('kat kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    find.next();
    find.next();
    expect(find.matchIndex, 2);

    controller.text = 'kat';
    find.refreshWhileTyping();

    expect(find.matchCount, 1);
    expect(find.matchIndex, 0);
  });

  test('inhoud van buitenaf wist de treffers maar laat de balk staan', () {
    final find = sessionFor('kat kat');
    find.open(showReplace: false);
    find.setQuery('kat');
    final revealsBefore = revealed.length;

    controller.text = 'heel andere tekst met kat erin';
    find.clearMatches();

    expect(find.visible, isTrue, reason: 'de balk blijft open');
    expect(find.matchCount, 0);
    expect(find.matchIndex, -1);
    expect(revealed.length, revealsBefore, reason: 'en springt nergens heen');
  });

  test('elke standwijziging vraagt om een herbouw', () {
    final find = sessionFor('kat');
    final atOpen = rebuilds;
    find.open(showReplace: false);
    expect(rebuilds, greaterThan(atOpen));

    final beforeClose = rebuilds;
    find.close();
    expect(rebuilds, greaterThan(beforeClose));
  });
}
