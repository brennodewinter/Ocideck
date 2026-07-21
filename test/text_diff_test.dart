import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_diff.dart';

/// De vergelijking achter de correctie op een getypt antwoord. Wat hier misgaat
/// wijst de kijker straks de verkeerde letters aan — vervelender dan geen
/// aanwijzing, want een foute les blijft ook hangen.
String _render(List<TextDiffSegment> segments) =>
    segments.map((s) => '${s.kind.name}(${s.text})').join('');

void main() {
  test('gelijke teksten leveren één ongedeeld stuk op', () {
    expect(diffText('kluis', 'kluis'), [
      const TextDiffSegment('kluis', TextDiffKind.same),
    ]);
  });

  test('twee lege teksten leveren niets op', () {
    expect(diffText('', ''), isEmpty);
  });

  test('een leeg antwoord is één gemist stuk', () {
    expect(diffText('', 'kluis'), [
      const TextDiffSegment('kluis', TextDiffKind.onlyRight),
    ]);
  });

  test('een verwisselde letter wijst precies die plek aan', () {
    // "klius" tegen "kluis": de i staat één plek te vroeg. De vergelijking
    // wijst hem daar aan als overtollig en achter de u als ontbrekend — de
    // rest blijft ongemoeid, want dáár is niets mis mee.
    expect(
      _render(diffText('klius', 'kluis')),
      'same(kl)onlyLeft(i)same(u)onlyRight(i)same(s)',
    );
  });

  test('een te veel getypt woord wordt als overtollig aangewezen', () {
    final diff = diffText('in de grote kluis', 'in de kluis');
    expect(
      diff.where((s) => s.kind == TextDiffKind.onlyLeft).map((s) => s.text),
      contains('grote '),
    );
    expect(diff.any((s) => s.kind == TextDiffKind.onlyRight), isFalse);
  });

  test('een gemist woord wordt als ontbrekend aangewezen', () {
    final diff = diffText('in de kluis', 'in de grote kluis');
    expect(
      diff.where((s) => s.kind == TextDiffKind.onlyRight).map((s) => s.text),
      contains('grote '),
    );
  });

  test('hoofdletters tellen niet mee, maar blijven wel staan', () {
    // Hoofdletters worden bij het goedrekenen genegeerd; ze hier als fout
    // aanwijzen zou de kijker op het verkeerde been zetten.
    final diff = diffText('In De Kluis', 'in de kluis');
    expect(diff.every((s) => s.kind == TextDiffKind.same), isTrue);
    // De oorspronkelijke schrijfwijze komt terug, niet de kleingemaakte.
    expect(diff.map((s) => s.text).join(), 'In De Kluis');
  });

  test('twee kanten laten elk hun eigen stukken zien', () {
    final diff = diffText('klius', 'kluis');
    expect(
      leftSide(diff).every((s) => s.kind != TextDiffKind.onlyRight),
      isTrue,
    );
    expect(leftSide(diff).map((s) => s.text).join(), 'klius');
    expect(
      rightSide(diff).every((s) => s.kind != TextDiffKind.onlyLeft),
      isTrue,
    );
    expect(rightSide(diff).map((s) => s.text).join(), 'kluis');
  });

  test('een absurd lang antwoord wordt niet teken voor teken vergeleken', () {
    // De vergelijking kost lengte × lengte; bij zoiets is "dit stond er, dit
    // hoorde er te staan" even behulpzaam en oneindig veel goedkoper.
    final long = 'a' * (textDiffMaxLength + 1);
    final diff = diffText(long, 'kluis');
    expect(diff.map((s) => s.kind).toList(), [
      TextDiffKind.onlyLeft,
      TextDiffKind.onlyRight,
    ]);
  });

  test('accenten en emoji blijven heel', () {
    // Runes, geen code-eenheden: een emoji mag niet doormidden gehakt worden.
    final diff = diffText('café 🔐', 'café 🔑');
    expect(diff.map((s) => s.text).join(), contains('café '));
    expect(
      diff.where((s) => s.kind == TextDiffKind.onlyLeft).map((s) => s.text),
      contains('🔐'),
    );
  });
}
