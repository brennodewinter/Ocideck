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

    test('data round-trips through the JSON data file', () {
      const spec = ChartSpec(
        type: ChartType.line,
        title: 'Omzet',
        source: 'data/omzet.json',
        x: ['Jan', 'Feb'],
        series: [
          ChartSeries(name: 'Omzet', data: [120, 138]),
          ChartSeries(name: 'Marge', data: [14, 17]),
        ],
      );
      // Emptied of its data, then refilled from what it wrote itself.
      final refilled = spec
          .copyWith(x: const [], series: const [])
          .withJson(spec.dataToJson());
      expect(refilled.x, ['Jan', 'Feb']);
      expect(refilled.series.map((s) => s.name), ['Omzet', 'Marge']);
      expect(refilled.series[0].data, [120, 138]);
      expect(refilled.series[1].data, [14, 17]);
    });

    test('the data file carries values only, never styling', () {
      const spec = ChartSpec(
        rowColors: ['#003399'],
        series: [
          ChartSeries(name: 'A', data: [1], color: '#FFCC00'),
        ],
        x: ['Jan'],
        title: 'Titel',
        minBound: 0,
      );
      final json = spec.dataToJson();
      // Colours, title and bounds belong to the block; only x/series travel.
      expect(json, isNot(contains('#003399')), reason: 'row colour');
      expect(json, isNot(contains('#FFCC00')), reason: 'series colour');
      expect(json, isNot(contains('color')));
      expect(json, isNot(contains('Titel')));
      expect(json, isNot(contains('minBound')));
      expect(json, contains('"x"'));
      expect(json, contains('"name": "A"'));
    });

    test('recolouring does not change the data file', () {
      const spec = ChartSpec(
        x: ['Jan'],
        series: [
          ChartSeries(name: 'A', data: [1]),
        ],
      );
      // The save path compares two of these to decide whether to rewrite the
      // file; styling must not register as a data edit.
      final recoloured = spec.copyWith(
        rowColors: ['#003399'],
        series: [
          const ChartSeries(name: 'A', data: [1], color: '#FFCC00'),
        ],
      );
      expect(recoloured.dataToJson(), spec.dataToJson());
    });

    test('withJson keeps the colours the block already had', () {
      const spec = ChartSpec(
        source: 'data/o.json',
        x: ['Jan', 'Feb'],
        rowColors: ['#003399', '#FFCC00'],
        series: [ChartSeries(name: 'oud', data: [], color: '#10B981')],
      );
      // Sorting the rows in a spreadsheet swaps Jan and Feb. Each row keeps the
      // colour of its *label*, so the palette travels with the row rather than
      // staying behind at its old position.
      final filled = spec.withJson(
        '{"x":["Feb","Jan"],"series":[{"name":"A","data":[2,1]}]}',
      );
      expect(filled.source, 'data/o.json');
      expect(filled.x, ['Feb', 'Jan']);
      expect(filled.rowColors, ['#FFCC00', '#003399']);
      expect(filled.series.single.color, '#10B981');
    });

    test('a label the block never had falls back to its position colour', () {
      const spec = ChartSpec(
        x: ['Jan'],
        rowColors: ['#003399'],
        series: [ChartSeries(name: 'oud', data: [])],
      );
      // Mrt is new, so there is no label to follow — position decides, which
      // keeps a freshly added row from arriving colourless.
      final filled = spec.withJson('{"x":["Mrt"],"series":[]}');
      expect(filled.rowColors, ['#003399']);
    });

    test('a corrupt data file leaves the chart as it was', () {
      const spec = ChartSpec(
        source: 'data/o.json',
        x: ['Jan'],
        series: [
          ChartSeries(name: 'A', data: [1]),
        ],
      );
      // Blanking the chart would hide the problem behind an empty plot.
      for (final bad in ['{', 'null', '[]', '{"series":[]}', '']) {
        final out = spec.withJson(bad);
        expect(out.x, ['Jan'], reason: 'input: $bad');
        expect(out.series.single.data, [1], reason: 'input: $bad');
      }
    });

    test('withData picks the reader from the extension', () {
      const spec = ChartSpec(x: [], series: []);
      expect(
        spec.withData('{"x":["Jan"],"series":[]}', path: 'data/o.json').x,
        ['Jan'],
      );
      expect(spec.withData(',A\nJan,1', path: 'data/o.csv').x, ['Jan']);
      // No extension: CSV, the form that existed before JSON did.
      expect(spec.withData(',A\nJan,1', path: 'data/o').x, ['Jan']);
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

  group('heatmap colour ramp', () {
    test('is theme-independent and picks a ramp by background lightness', () {
      final light = heatmapRamp(darkBackground: false);
      final dark = heatmapRamp(darkBackground: true);
      expect(light, isNot(equals(dark)));
      // On a light slide the low end is pale (near-white) and the high end is a
      // deep red; on a dark slide it inverts so low recedes into the dark.
      expect(isDarkHex(light.first), isFalse);
      expect(isDarkHex(light.last), isTrue);
      expect(isDarkHex(dark.first), isTrue);
      expect(isDarkHex(dark.last), isFalse);
    });

    test('interpolates between stops and pins the endpoints', () {
      final ramp = heatmapRamp(darkBackground: false);
      expect(heatmapColorAt(ramp, 0), ramp.first);
      expect(heatmapColorAt(ramp, 1), ramp.last);
      // A value between stops is a blend, so it matches no exact stop.
      final between = heatmapColorAt(ramp, 0.6);
      expect(ramp.contains(between), isFalse);
      // Out-of-range and NaN clamp to the ends rather than throwing.
      expect(heatmapColorAt(ramp, -1), ramp.first);
      expect(heatmapColorAt(ramp, 2), ramp.last);
      expect(heatmapColorAt(ramp, double.nan), ramp.first);
    });

    test('isDarkHex reads plain colours, tolerant of format', () {
      expect(isDarkHex('#FFFFFF'), isFalse);
      expect(isDarkHex('#000000'), isTrue);
      expect(isDarkHex('fff'), isFalse); // no '#', shorthand
    });
  });
}
