import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_deck_diff.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

Slide s(String id, {String title = ''}) =>
    Slide(id: id, type: SlideType.bullets, title: title);

Deck applyAll(Deck deck, List<DeckOp> ops) => ops.fold(deck, applyOp);

/// Toetst dat het toepassen van de diff `after` reproduceert op de oppervlakte
/// die de diff kent — d.w.z. alle velden in [SlideField.values] en
/// [DeckMetaField.values].
///
/// **Beperking:** deze helper is per definitie blind voor alles buiten die
/// oppervlakten. Een veld dat op [Slide] staat maar niet in [SlideField], wordt
/// door de diff in béíde richtingen over het hoofd gezien: de hervergelijking
/// komt leeg terug terwijl de waarde nooit is overgekomen. Dat was precies de
/// fout van #1803. De poort `check_collab_field_parity.dart` bewaakt die
/// richting apart.
///
/// Naast de hervergelijking vergelijkt deze helper ook veld-voor-veld over
/// [SlideField.values] tussen het resultaat en `after`, zodat een verschil
/// binnen de gesynchroniseerde oppervlakte nooit stil door de diff-glitch heen
/// glipt.
void expectReproduces(Deck before, Deck after) {
  final ops = deckDiffToOps(before, after, authorId: 'a');
  final result = applyAll(before, ops);

  // Been 1: de hervergelijking moet leeg zijn.
  expect(
    deckDiffToOps(result, after, authorId: 'a'),
    isEmpty,
    reason: 'applying the diff must land on `after` exactly',
  );
  expect(result.slides.map((x) => x.id), after.slides.map((x) => x.id));

  // Been 2: veld-voor-veld over SlideField.values. De hervergelijking hierboven
  // gebruikt dezelfde diff, dus een bug in slideFieldValue of _valuesEqual zou
  // in beide richtingen onzichtbaar zijn. Deze directe vergelijking vangt dat.
  final resultById = {for (final s in result.slides) s.id: s};
  for (final slide in after.slides) {
    final got = resultById[slide.id];
    if (got == null) continue;
    for (final field in SlideField.values) {
      expect(
        slideFieldValue(got, field),
        slideFieldValue(slide, field),
        reason: 'field $field on slide ${slide.id} differs after applying ops',
      );
    }
  }
}

void main() {
  group('deckDiffToOps', () {
    test('an unchanged deck produces no ops', () {
      final deck = Deck(
        title: 'd',
        slides: [s('a', title: 'x')],
      );
      expect(deckDiffToOps(deck, deck, authorId: 'a'), isEmpty);
    });

    test('a single field change is one SetSlideField', () {
      final before = Deck(
        title: 'd',
        slides: [s('a', title: 'old')],
      );
      final after = Deck(
        title: 'd',
        slides: [s('a', title: 'new')],
      );
      final ops = deckDiffToOps(before, after, authorId: 'a');
      expect(ops, hasLength(1));
      final op = ops.single as SetSlideField;
      expect(op.field, SlideField.title);
      expect(op.value, 'new');
      expect(op.version, 0, reason: 'unassigned until the session stamps it');
      expectReproduces(before, after);
    });

    test('a list field change is carried whole', () {
      final before = Deck(
        title: 'd',
        slides: [
          s('a').copyWith(bullets: const ['one']),
        ],
      );
      final after = Deck(
        title: 'd',
        slides: [
          s('a').copyWith(bullets: const ['one', 'two']),
        ],
      );
      final ops = deckDiffToOps(before, after, authorId: 'a');
      expect((ops.single as SetSlideField).value, ['one', 'two']);
      expectReproduces(before, after);
    });

    test('an equal list produces no op', () {
      final before = Deck(
        title: 'd',
        slides: [
          s('a').copyWith(bullets: const ['one', 'two']),
        ],
      );
      final after = Deck(
        title: 'd',
        slides: [
          s('a').copyWith(bullets: const ['one', 'two']),
        ],
      );
      expect(deckDiffToOps(before, after, authorId: 'a'), isEmpty);
    });

    test('a deck-metadata change is a SetDeckMeta', () {
      final before = Deck(title: 'old');
      final after = Deck(title: 'new');
      final ops = deckDiffToOps(before, after, authorId: 'a');
      final op = ops.single as SetDeckMeta;
      expect(op.field, DeckMetaField.title);
      expect(op.value, 'new');
      expectReproduces(before, after);
    });

    test('adding a slide is an InsertSlide carrying the whole slide', () {
      final before = Deck(title: 'd', slides: [s('a')]);
      final after = Deck(
        title: 'd',
        slides: [
          s('a'),
          s('b', title: 'brand new'),
        ],
      );
      final ops = deckDiffToOps(before, after, authorId: 'a');
      final insert = ops.whereType<InsertSlide>().single;
      expect(insert.slide.id, 'b');
      expect(insert.slide.title, 'brand new');
      expect(insert.index, 1);
      expectReproduces(before, after);
    });

    test('removing a slide is a RemoveSlide', () {
      final before = Deck(title: 'd', slides: [s('a'), s('b')]);
      final after = Deck(title: 'd', slides: [s('a')]);
      final ops = deckDiffToOps(before, after, authorId: 'a');
      expect((ops.single as RemoveSlide).slideId, 'b');
      expectReproduces(before, after);
    });

    test('a pure reorder is ReorderSlide ops', () {
      final before = Deck(title: 'd', slides: [s('a'), s('b'), s('c')]);
      final after = Deck(title: 'd', slides: [s('c'), s('a'), s('b')]);
      final ops = deckDiffToOps(before, after, authorId: 'a');
      expect(ops.every((o) => o is ReorderSlide), isTrue);
      expectReproduces(before, after);
    });

    test('a combined edit reproduces after exactly', () {
      // Remove b, add d, reorder, and edit a's title — all at once.
      final before = Deck(
        title: 'deck',
        slides: [
          s('a', title: 'a0'),
          s('b'),
          s('c'),
        ],
      );
      final after = Deck(
        title: 'deck v2',
        slides: [
          s('c'),
          s('d', title: 'new'),
          s('a', title: 'a1'),
        ],
      );
      expectReproduces(before, after);
    });

    test('replacing every slide reproduces after exactly', () {
      final before = Deck(title: 'd', slides: [s('a'), s('b')]);
      final after = Deck(title: 'd', slides: [s('x'), s('y'), s('z')]);
      expectReproduces(before, after);
    });

    // #1803 — een gewijzigde paneelzoom bereikte de andere cliënt niet: het veld
    // stond niet in [SlideField], en de diff loopt uitsluitend over die enum.
    //
    // Waarom deze toets de wáárde na toepassing leest in plaats van op
    // [expectReproduces] te leunen: die helper is blind voor velden buiten de
    // diff-oppervlakte (zie haar doc-comment). Pas nadat imageZoom in
    // [SlideField] was opgenomen, dekt expectReproduces dit veld — vandaar dat
    // de aanroep hieronder nu wél groen is. De directe waarde-check blijft als
    // canarie: mocht iemand imageZoom ooit uit SlideField halen, dan faalt deze
    // toets eerder dan expectReproduces.
    test('a changed panel zoom reaches the other client (#1803)', () {
      final before = Deck(title: 'd', slides: [s('a').copyWith(imageZoom: 0)]);
      final after = Deck(title: 'd', slides: [s('a').copyWith(imageZoom: 140)]);

      final ops = deckDiffToOps(before, after, authorId: 'a');
      expect(
        ops,
        hasLength(1),
        reason: 'de zoomwijziging moet één op opleveren',
      );
      expect((ops.single as SetSlideField).field, SlideField.imageZoom);

      expect(
        applyAll(before, ops).slides.single.imageZoom,
        140,
        reason: 'de ontvanger moet dezelfde bijsnijding zien',
      );
      expectReproduces(before, after);
    });
  });
}
