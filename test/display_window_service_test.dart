import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/display_window_service.dart';

void main() {
  const service = DisplayWindowService();

  group('DisplayWindowService.applyToBullets', () {
    test('returns all items when spec is null', () {
      final bullets = ['a', 'b', 'c'];
      final result = service.applyToBullets(bullets, null);
      expect(result.items, bullets);
      expect(result.wasLimited, false);
    });

    test('takes the first N items for mode first', () {
      final result = service.applyToBullets([
        'a',
        'b',
        'c',
        'd',
      ], const DisplayWindowSpec(limit: 2, mode: DisplayWindowMode.first));
      expect(result.items, ['a', 'b']);
      expect(result.wasLimited, true);
      expect(result.countCaption, 'Eerste 2 van 4 punten');
    });

    test('takes the last N items for mode last', () {
      final result = service.applyToBullets([
        'a',
        'b',
        'c',
        'd',
      ], const DisplayWindowSpec(limit: 2, mode: DisplayWindowMode.last));
      expect(result.items, ['c', 'd']);
      expect(result.wasLimited, true);
    });

    test('top/bottom fall back to first for bullets', () {
      final top = service.applyToBullets([
        'a',
        'b',
        'c',
        'd',
      ], const DisplayWindowSpec(limit: 2, mode: DisplayWindowMode.top));
      expect(top.items, ['a', 'b']);
    });

    test('hide remainder does not add a trailing bullet', () {
      final result = service.applyToBullets(
        ['a', 'b', 'c'],
        const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.first,
          remainder: DisplayWindowRemainder.hide,
        ),
      );
      expect(result.items.length, 2);
    });

    test('does not duplicate caption when showCount is false', () {
      final result = service.applyToBullets([
        'a',
        'b',
        'c',
      ], const DisplayWindowSpec(limit: 2, showCount: false));
      expect(result.countCaption, null);
    });
  });

  group('DisplayWindowService.applyToTable', () {
    test('keeps the header row and takes top data rows', () {
      final rows = [
        ['Name', 'Score'],
        ['a', '10'],
        ['b', '5'],
        ['c', '20'],
        ['d', '15'],
      ];
      final result = service.applyToTable(
        rows,
        const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.top,
          key: '1',
        ),
      );
      expect(result.items.first, ['Name', 'Score']);
      // Highest scores first: c=20, d=15
      expect(result.items[1], ['c', '20']);
      expect(result.items[2], ['d', '15']);
    });

    test('aggregates hidden rows as "Overig" when requested', () {
      final rows = [
        ['Name', 'Score'],
        ['a', '10'],
        ['b', '5'],
        ['c', '20'],
        ['d', '15'],
      ];
      final result = service.applyToTable(
        rows,
        const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.top,
          key: '1',
          remainder: DisplayWindowRemainder.other,
        ),
      );
      expect(result.items.last.first, 'Overig');
      expect(result.items.last[1], '15'); // 10 + 5
    });

    test('sorts bottom ascending by numeric key column', () {
      final rows = [
        ['Name', 'Score'],
        ['a', '10'],
        ['b', '5'],
        ['c', '20'],
      ];
      final result = service.applyToTable(
        rows,
        const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.bottom,
          key: '1',
        ),
      );
      expect(result.items[1], ['b', '5']);
      expect(result.items[2], ['a', '10']);
    });
  });

  group('determinisme bij gelijke waarden', () {
    // Acceptatiecriterium #672: dezelfde top-N bij elk heropenen. Bij gelijke
    // waarden beslist de bronpositie — Darts sort is niet stabiel, dus zonder
    // expliciete tie-break kon de selectie per run verschillen.
    test('tabel: gelijke waarden houden hun bronvolgorde', () {
      final rows = [
        ['kop', 'waarde'],
        for (var i = 0; i < 12; i++) ['rij $i', '5'],
      ];
      final result = service.applyToTable(
        rows,
        const DisplayWindowSpec(
          limit: 4,
          mode: DisplayWindowMode.top,
          key: '1',
          showCount: false,
        ),
        unit: 'regels',
      );
      expect(result.items.skip(1).map((r) => r.first), [
        'rij 0',
        'rij 1',
        'rij 2',
        'rij 3',
      ]);
    });

    test('grafiek: gelijke waarden houden hun bronvolgorde', () {
      final chart = ChartSpec(
        type: ChartType.bar,
        title: '',
        x: [for (var i = 0; i < 12; i++) 'cat $i'],
        series: [ChartSeries(name: 'a', data: List.filled(12, 5.0))],
      );
      final result = service.applyToChart(
        chart,
        const DisplayWindowSpec(
          limit: 4,
          mode: DisplayWindowMode.top,
          showCount: false,
        ),
      );
      expect(result.items.x, ['cat 0', 'cat 1', 'cat 2', 'cat 3']);
    });
  });

  group('DisplayWindowService.applyToChart', () {
    final chart = ChartSpec(
      type: ChartType.bar,
      x: ['a', 'b', 'c', 'd'],
      series: [
        ChartSeries(name: 's1', data: [1.0, 2.0, 3.0, 4.0]),
      ],
    );

    test('takes top N categories by the first series', () {
      final result = service.applyToChart(
        chart,
        const DisplayWindowSpec(limit: 2, mode: DisplayWindowMode.top),
      );
      expect(result.items.x, ['d', 'c']);
      expect(result.items.series.first.data, [4.0, 3.0]);
    });

    test('takes last N for time-series charts instead of sorting on value', () {
      final lineChart = chart.copyWith(type: ChartType.line);
      final result = service.applyToChart(
        lineChart,
        const DisplayWindowSpec(limit: 2, mode: DisplayWindowMode.top),
      );
      expect(result.items.x, ['c', 'd']);
    });

    test('aggregates hidden values as "Overig" for bar charts', () {
      final result = service.applyToChart(
        chart,
        const DisplayWindowSpec(
          limit: 2,
          mode: DisplayWindowMode.top,
          remainder: DisplayWindowRemainder.other,
        ),
      );
      expect(result.items.x, ['d', 'c', 'Overig']);
      expect(result.items.series.first.data, [4.0, 3.0, 3.0]);
    });
  });

  group('viewLimitCaptionRowIndex', () {
    Slide tableWith(List<List<String>> rows, DisplayWindowSpec? spec) =>
        Slide.create(
          SlideType.table,
        ).copyWith(tableRows: rows, viewLimit: spec);

    final rows = <List<String>>[
      const ['#', 'Naam'],
      const ['1', 'Aap'],
      const ['Eerste 1 van 9 regels', ''],
    ];

    test('finds the caption row a view limit appended', () {
      expect(
        viewLimitCaptionRowIndex(
          tableWith(rows, const DisplayWindowSpec(limit: 1)),
          rows,
        ),
        2,
      );
    });

    test('finds nothing without an active limit or with the count off', () {
      expect(viewLimitCaptionRowIndex(tableWith(rows, null), rows), isNull);
      expect(
        viewLimitCaptionRowIndex(
          tableWith(rows, const DisplayWindowSpec(limit: 1, showCount: false)),
          rows,
        ),
        isNull,
      );
    });

    // Een gewone datarij mag nooit als bijschrift uit de tabel worden getild.
    test('a filled last row is data, not a caption', () {
      final filled = <List<String>>[
        const ['#', 'Naam'],
        const ['1', 'Aap'],
        const ['2', 'Noot'],
      ];
      expect(
        viewLimitCaptionRowIndex(
          tableWith(filled, const DisplayWindowSpec(limit: 2)),
          filled,
        ),
        isNull,
      );
    });
  });
}
