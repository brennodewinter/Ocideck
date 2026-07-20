import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';

const _spec = ChartSpec(
  type: ChartType.bullet,
  title: 'Verhelptijd tegen norm',
  x: ['Kritiek (14d)', 'Hoog (30d)', 'Middel (90d)'],
  series: [
    ChartSeries(name: 'Gehaald', data: [38, 61, 84]),
  ],
  targets: [90, 90, 80],
  bands: [60, 80],
);

void main() {
  group('bulletAxisMax', () {
    test('loopt net voorbij het grootste dat moet passen', () {
      // De streefwaarde is hier groter dan elke meting; zou de as alleen naar
      // de metingen kijken, dan viel het streepje buiten beeld.
      expect(_spec.bulletAxisMax, closeTo(90 * 1.05, 0.001));
    });

    test('een vastgezette bovengrens wint', () {
      expect(_spec.copyWith(maxBound: 100).bulletAxisMax, 100);
    });

    test('een band telt mee, ook zonder metingen erboven', () {
      const spec = ChartSpec(
        type: ChartType.bullet,
        x: ['A'],
        series: [
          ChartSeries(name: 'x', data: [10]),
        ],
        bands: [200],
      );
      expect(spec.bulletAxisMax, closeTo(210, 0.001));
    });

    test('louter nullen levert een bruikbare as, geen deling door nul', () {
      const spec = ChartSpec(
        type: ChartType.bullet,
        x: ['A'],
        series: [
          ChartSeries(name: 'x', data: [0]),
        ],
      );
      expect(spec.bulletAxisMax, 1);
    });
  });

  group('targetAt', () {
    test('geeft de streefwaarde van die rij', () {
      expect(_spec.targetAt(0), 90);
      expect(_spec.targetAt(2), 80);
    });

    test('een rij zonder norm heeft er geen', () {
      // Niet elke rij hoeft een afgesproken norm te hebben; een kortere lijst
      // is een geldige toestand, geen fout.
      const partial = ChartSpec(
        type: ChartType.bullet,
        x: ['A', 'B'],
        series: [
          ChartSeries(name: 'x', data: [1, 2]),
        ],
        targets: [5],
      );
      expect(partial.targetAt(0), 5);
      expect(partial.targetAt(1), isNull);
      expect(partial.targetAt(9), isNull);
    });
  });

  group('round-trip', () {
    test('streefwaarden en banden overleven het blok', () {
      final again = ChartSpec.parse(_spec.toBlock());
      expect(again.type, ChartType.bullet);
      expect(again.targets, [90, 90, 80]);
      expect(again.bands, [60, 80]);
      expect(again.toBlock(), _spec.toBlock());
    });

    test('een ander charttype schrijft ze niet weg', () {
      // Anders blijft een streefwaarde in een taartdiagram hangen tot iemand
      // het bestand met de hand opruimt.
      final asPie = _spec.copyWith(type: ChartType.pie);
      expect(asPie.toBlock(), isNot(contains('targets')));
      expect(asPie.toBlock(), isNot(contains('bands')));
    });

    test('zonder normen blijft het blok schoon', () {
      const plain = ChartSpec(
        type: ChartType.bullet,
        x: ['A'],
        series: [
          ChartSeries(name: 'x', data: [1]),
        ],
      );
      expect(plain.toBlock(), isNot(contains('targets')));
      expect(plain.toBlock(), isNot(contains('bands')));
    });

    test('onleesbare waarden worden overgeslagen, niet geraden', () {
      final spec = ChartSpec.parse(
        '{"type":"bullet","x":["A"],"targets":[5,"nvt",7],"bands":["x"]}',
      );
      expect(spec.targets, [5, 7]);
      expect(spec.bands, isEmpty);
    });
  });

  test('bullet is geen taartachtige en houdt zijn grenzen', () {
    expect(_spec.isPieLike, isFalse);
    // maxBound moet blijven werken: dat is hoe je de as op 100% vastzet.
    expect(_spec.copyWith(maxBound: 100).toBlock(), contains('maxBound'));
  });

  group('parseChartNumberList', () {
    test('leest een lijst met komma\'s', () {
      expect(parseChartNumberList('90, 90, 80'), [90, 90, 80]);
      expect(parseChartNumberList('60;80'), [60, 80]);
    });

    test('halverwege typen wist de rest niet', () {
      // De editor emit bij elke toetsaanslag. Zou een half getal de hele lijst
      // bederven, dan verdween de vorige rij terwijl je nog aan het tikken was.
      expect(parseChartNumberList('90, '), [90]);
      expect(parseChartNumberList('90, -'), [90]);
    });

    test('leeg blijft leeg', () {
      expect(parseChartNumberList(''), isEmpty);
      expect(parseChartNumberList('  '), isEmpty);
    });
  });
}
