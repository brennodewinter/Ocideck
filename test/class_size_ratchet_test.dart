import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de klassegrootte-ratchet
/// (`classSizesIn` in `tool/check_conventions.dart`).
///
/// De ratchet bestaat omdat de bestandsteller een `part`-splitsing niet ziet:
/// zeven bestanden van 400 regels zijn zeven groene bestanden en één klasse van
/// 2.800. Dat gedrag wordt hier met verzonnen bestanden getoetst, want de echte
/// boom kan die vorm niet op bestelling aannemen — en een teller die op de
/// werkelijke waarden wordt afgestemd bewijst alleen zichzelf.
///
/// De teller leest regels in plaats van een AST. Dat mag omdat
/// `make format-check` de opmaak vastlegt, maar het legt de bewijslast wél hier:
/// elk randgeval dat de opmaak toelaat hoort een geval in deze test te zijn.
void main() {
  Map<String, List<String>> tree(Map<String, String> files) => {
    for (final e in files.entries) e.key: e.value.split('\n'),
  };

  test('een extensie in een part telt bij de klasse die hij uitbreidt', () {
    final sizes = classSizesIn(
      tree({
        'lib/a.dart':
            "part 'parts/a_extra.dart';\n"
            'class Groot {\n'
            '  int een = 1;\n'
            '}',
        'lib/parts/a_extra.dart':
            "part of '../a.dart';\n"
            'extension GrootExtra on Groot {\n'
            '  int twee() => 2;\n'
            '  int drie() => 3;\n'
            '}',
      }),
    );

    // 3 regels in de library + 4 in de part = 7, onder één sleutel.
    expect(sizes.lines['lib/a.dart#Groot'], 7);
    expect(sizes.sites['lib/a.dart#Groot'], [
      'lib/a.dart:2',
      'lib/parts/a_extra.dart:2',
    ]);
    // De extensie zelf is geen aparte klasse.
    expect(sizes.lines.containsKey('lib/a.dart#GrootExtra'), isFalse);
  });

  test('gelijknamige private klassen in twee libraries blijven gescheiden', () {
    final sizes = classSizesIn(
      tree({
        'lib/een.dart': 'class _FooState {\n  int a = 1;\n}',
        'lib/twee.dart': 'class _FooState {\n  int b = 1;\n  int c = 2;\n}',
      }),
    );

    expect(sizes.lines['lib/een.dart#_FooState'], 3);
    expect(sizes.lines['lib/twee.dart#_FooState'], 4);
  });

  test('een kop over meer regels telt vanaf de eerste regel', () {
    final sizes = classSizesIn(
      tree({
        'lib/b.dart':
            'class Lang extends StatefulWidget\n'
            '    with EenMixin, NogEen {\n'
            '  int a = 1;\n'
            '}',
      }),
    );

    // Zonder die vervolgregel zou de klasse ongeteld blijven — een gat waar
    // precies de grootste klassen doorheen glippen.
    expect(sizes.lines['lib/b.dart#Lang'], 4);
  });

  test('een enum op één regel telt als één regel', () {
    final sizes = classSizesIn(
      tree({'lib/c.dart': 'enum Modus { visueel, markdown }'}),
    );

    expect(sizes.lines['lib/c.dart#Modus'], 1);
  });

  test('een mixin-toepassing zonder body telt niet mee', () {
    final sizes = classSizesIn(
      tree({
        'lib/d.dart':
            'class Toepassing = Basis with Erbij;\n'
            'class Echt {\n'
            '  int a = 1;\n'
            '}',
      }),
    );

    expect(sizes.lines.containsKey('lib/d.dart#Toepassing'), isFalse);
    expect(sizes.lines['lib/d.dart#Echt'], 3);
  });

  test("een '''-tekst met een accolade op kolom 0 sluit de klasse niet", () {
    final sizes = classSizesIn(
      tree({
        'lib/e.dart':
            'class MetSjabloon {\n'
            "  static const css = '''\n"
            'body {\n'
            '  color: red;\n'
            '}\n'
            "''';\n"
            '  int daarna = 1;\n'
            '}',
      }),
    );

    // Zou de `}` in de CSS als sluitregel gelden, dan meet de teller 5 in
    // plaats van 8 — een te grote klasse die zichzelf klein rekent.
    expect(sizes.lines['lib/e.dart#MetSjabloon'], 8);
  });

  test('de basislijn dekt precies de klassen die vandaag te groot zijn', () {
    // De ratchet mag alleen krimpen: elke sleutel in de basislijn hoort een
    // plafond boven het maximum te hebben, anders staat er een uitzondering
    // die geen uitzondering meer is.
    for (final entry in classSizeBaseline.entries) {
      expect(
        entry.value,
        greaterThan(maxClassLines),
        reason:
            '${entry.key} staat op ${entry.value} en past daarmee onder '
            'maxClassLines ($maxClassLines) — haal de regel uit '
            'classSizeBaseline in plaats van hem te laten staan.',
      );
    }
  });
}
