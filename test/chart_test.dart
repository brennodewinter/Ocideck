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

    test('a quoted field may contain a comma', () {
      final (x, series) = parseCsv(',Omzet\n"Amsterdam, NL",10\n"Parijs, FR",12');
      expect(x, ['Amsterdam, NL', 'Parijs, FR']);
      expect(series.single.data, [10, 12]);
    });

    test('a quoted numeric field parses as one value', () {
      // Excel exports decimals wrapped in quotes; before the quote-aware split
      // this became two cells and shifted the whole row.
      final (x, series) = parseCsv(',A,B\nQ1,"1.234",7');
      expect(x, ['Q1']);
      expect(series.map((s) => s.name), ['A', 'B']);
      expect(series[0].data, [1.234]);
      expect(series[1].data, [7]);
    });

    test('a doubled "" inside a quoted field is one literal quote', () {
      final (x, series) = parseCsv(',A\n"say ""hi""",1\n"""quoted""",2');
      expect(x, ['say "hi"', '"quoted"']);
      expect(series.single.data, [1, 2]);
    });

    test('quoted fields work in the header row too', () {
      final (x, series) = parseCsv(',"Omzet, netto"\nQ1,10');
      expect(series.single.name, 'Omzet, netto');
      expect(x, ['Q1']);
    });

    test('space before an opening quote still reads as one field', () {
      final (x, _) = parseCsv(',A\n "Amsterdam, NL" ,10');
      expect(x, ['Amsterdam, NL']);
    });

    test('a quoted field keeps its inner whitespace verbatim', () {
      final (x, _) = parseCsv(',A\n" spatie ",1');
      expect(x, [' spatie ']);
    });

    test('an unterminated quote runs to the end of the line', () {
      final (x, series) = parseCsv(',A\n"Amsterdam, NL,10');
      expect(x, ['Amsterdam, NL,10']);
      expect(series.single.data, [0]);
    });

    test('regression: unquoted CSV parses exactly as before', () {
      // Byte-for-byte the pre-fix behaviour: trimming, blank-line skipping,
      // empty leading header cell, short rows padded with 0.
      final (x, series) = parseCsv(
        '\n, 2025, 2026\nQ1, 10, 12\n\nQ2, 14, 9\nQ3, 3\n',
      );
      expect(x, ['Q1', 'Q2', 'Q3']);
      expect(series.map((s) => s.name), ['2025', '2026']);
      expect(series[0].data, [10, 14, 3]);
      expect(series[1].data, [12, 9, 0]);
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
