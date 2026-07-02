import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';

void main() {
  test('chart palette starts with the EU flag colors', () {
    expect(chartColorPalette.take(2), ['#003399', '#FFCC00']);
  });

  group('parseCsv', () {
    test('reads header series names and labelled rows', () {
      final (x, series) = parseCsv('\n, 2025, 2026\nQ1, 10, 12\nQ2, 14, 9\n');
      expect(x, ['Q1', 'Q2']);
      expect(series.map((s) => s.name), ['2025', '2026']);
      expect(series[0].data, [10, 14]);
      expect(series[1].data, [12, 9]);
    });

    test('non-numeric cells become 0', () {
      final (x, series) = parseCsv(',A\nQ1,oops');
      expect(x, ['Q1']);
      expect(series.single.data, [0]);
    });
  });

  group('ChartSpec', () {
    test('round-trips inline data through the block JSON', () {
      const spec = ChartSpec(
        type: ChartType.line,
        title: 'Omzet',
        x: ['Q1', 'Q2'],
        rowColors: ['#003399', '#FFCC00'],
        series: [
          ChartSeries(name: '2025', data: [10, 14], color: '#EF4444'),
        ],
      );
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.type, ChartType.line);
      expect(back.title, 'Omzet');
      expect(back.x, ['Q1', 'Q2']);
      expect(back.rowColors, ['#003399', '#FFCC00']);
      expect(back.series.single.name, '2025');
      expect(back.series.single.data, [10, 14]);
      expect(back.series.single.color, '#EF4444');
      expect(back.hasInlineData, isTrue);
    });

    test('animation defaults stay out of the block (on, inherit theme)', () {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['Q1'],
        series: [
          ChartSeries(name: 'A', data: [1]),
        ],
      );
      expect(spec.animateOnEnter, isTrue);
      expect(spec.animationDurationMs, isNull);
      final block = spec.toBlock();
      expect(block, isNot(contains('animateOnEnter')));
      expect(block, isNot(contains('animationDurationMs')));
    });

    test('animation off + duration override round-trip through the block', () {
      const spec = ChartSpec(
        type: ChartType.bar,
        x: ['Q1'],
        series: [
          ChartSeries(name: 'A', data: [1]),
        ],
        animateOnEnter: false,
        animationDurationMs: 5000,
      );
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.animateOnEnter, isFalse);
      expect(back.animationDurationMs, 5000);
    });

    test('inheritAnimationDuration resets the override to null', () {
      const spec = ChartSpec(animationDurationMs: 5000);
      expect(spec.copyWith().animationDurationMs, 5000);
      expect(
        spec.copyWith(inheritAnimationDuration: true).animationDurationMs,
        isNull,
      );
    });

    test('storage form drops inline data when a source is linked', () {
      const spec = ChartSpec(
        type: ChartType.bar,
        title: 'Omzet',
        source: 'data/omzet.csv',
        x: ['Q1', 'Q2'],
        rowColors: ['#003399', '#FFCC00'],
        series: [
          ChartSeries(name: '2025', data: [10, 14], color: '#10B981'),
        ],
      );
      final stored = ChartSpec.parse(spec.toBlock(forStorage: true));
      expect(stored.source, 'data/omzet.csv');
      expect(stored.hasInlineData, isFalse);
      expect(stored.rowColors, ['#003399', '#FFCC00']);
      expect(stored.series.single.color, '#10B981');

      // The in-app/full form keeps the data.
      final full = ChartSpec.parse(spec.toBlock());
      expect(full.hasInlineData, isTrue);
    });

    test('withCsv fills x/series and keeps the source', () {
      const spec = ChartSpec(
        type: ChartType.bar,
        source: 'data/o.csv',
        rowColors: ['#003399', '#FFCC00'],
        series: [ChartSeries(name: 'oud', data: [], color: '#10B981')],
      );
      final filled = spec.withCsv(',A,B\nJan,1,2\nFeb,3,4');
      expect(filled.source, 'data/o.csv');
      expect(filled.x, ['Jan', 'Feb']);
      expect(filled.series.map((s) => s.name), ['A', 'B']);
      expect(filled.series[1].data, [2, 4]);
      expect(filled.series[0].color, '#10B981');
      expect(filled.series[1].color, isNull);
      expect(filled.rowColors, ['#003399', '#FFCC00']);
    });

    test('invalid colors are ignored while valid colors are normalized', () {
      final valid = ChartSeries.fromJson({
        'name': 'A',
        'data': [1],
        'color': 'ef4444',
      });
      final invalid = ChartSeries.fromJson({
        'name': 'B',
        'data': [2],
        'color': 'red',
      });
      expect(valid.color, '#EF4444');
      expect(invalid.color, isNull);
    });

    test('parse is tolerant of malformed JSON', () {
      final spec = ChartSpec.parse('{ not json');
      expect(spec.type, ChartType.bar);
      expect(spec.hasInlineData, isFalse);
    });

    test('round-trips optional min/max bound lines for bar/line', () {
      const spec = ChartSpec(
        type: ChartType.line,
        x: ['Q1'],
        series: [
          ChartSeries(name: 'A', data: [10]),
        ],
        minBound: 5,
        maxBound: 20,
      );
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.minBound, 5);
      expect(back.maxBound, 20);
    });

    test('bounds are dropped from a pie chart', () {
      const spec = ChartSpec(
        type: ChartType.pie,
        x: ['Q1'],
        series: [
          ChartSeries(name: 'A', data: [10]),
        ],
        minBound: 5,
        maxBound: 20,
      );
      expect(spec.supportsBounds, isFalse);
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.minBound, isNull);
      expect(back.maxBound, isNull);
    });

    test('round-trips a spider/radar chart type', () {
      const spec = ChartSpec(
        type: ChartType.radar,
        x: ['Snelheid', 'Kracht', 'Uithouding'],
        series: [
          ChartSeries(name: 'A', data: [3, 4, 5]),
        ],
      );
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.type, ChartType.radar);
      expect(back.x, ['Snelheid', 'Kracht', 'Uithouding']);
      expect(back.series.single.data, [3, 4, 5]);
    });

    test('radar keeps bounds as a scale but never draws bound lines', () {
      const spec = ChartSpec(
        type: ChartType.radar,
        x: ['A', 'B', 'C'],
        series: [
          ChartSeries(name: 'A', data: [1, 2, 3]),
        ],
        minBound: 1,
        maxBound: 5,
      );
      expect(spec.supportsBounds, isTrue);
      expect(spec.supportsBoundLines, isFalse);
      final back = ChartSpec.parse(spec.toBlock());
      expect(back.minBound, 1);
      expect(back.maxBound, 5);
    });

    test('bar/line draw bound lines but pie does not', () {
      const bar = ChartSpec(type: ChartType.bar);
      const line = ChartSpec(type: ChartType.line);
      const pie = ChartSpec(type: ChartType.pie);
      expect(bar.supportsBoundLines, isTrue);
      expect(line.supportsBoundLines, isTrue);
      expect(pie.supportsBoundLines, isFalse);
      expect(pie.supportsBounds, isFalse);
    });
  });
}
