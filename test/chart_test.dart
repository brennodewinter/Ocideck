import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/utils/csv.dart';
import 'package:ocideck/utils/number_convention.dart';

void main() {
  test('chart palette starts with the EU flag colors', () {
    expect(chartColorPalette.take(2), ['#003399', '#FFCC00']);
  });

  group('parseCsv', () {
    test('reads header series names and labelled rows', () {
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        '\n, 2025, 2026\nQ1, 10, 12\nQ2, 14, 9\n',
      );
      expect(x, ['Q1', 'Q2']);
      expect(series.map((s) => s.name), ['2025', '2026']);
      expect(series[0].data, [10, 14]);
      expect(series[1].data, [12, 9]);
    });

    test('non-numeric cells become 0 and are reported', () {
      final result = parseCsv(',A\nQ1,oops');
      expect(result.$1, ['Q1']);
      expect(result.$2.single.data, [0]);
      expect(result.unreadable, ['oops']);
    });

    test('an empty cell is a statement, not a mistake: 0 and unreported', () {
      // A short row means "no value here"; complaining about it would train
      // the user to ignore the warning that does matter.
      final result = parseCsv(',A,B\nQ1,10');
      expect(result.$2[1].data, [0]);
      expect(result.unreadable, isEmpty);
    });

    test('clean CSV reports nothing unreadable', () {
      final result = parseCsv(',A\nQ1,10\nQ2,12');
      expect(result.unreadable, isEmpty);
    });

    test('a quoted field may contain a comma', () {
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        ',Omzet\n"Amsterdam, NL",10\n"Parijs, FR",12',
      );
      expect(x, ['Amsterdam, NL', 'Parijs, FR']);
      expect(series.single.data, [10, 12]);
    });

    test('a quoted numeric field parses as one value', () {
      // Excel exports decimals wrapped in quotes; before the quote-aware split
      // this became two cells and shifted the whole row.
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        ',A,B\nQ1,"1.234",7',
      );
      expect(x, ['Q1']);
      expect(series.map((s) => s.name), ['A', 'B']);
      expect(series[0].data, [1.234]);
      expect(series[1].data, [7]);
    });

    test('a doubled "" inside a quoted field is one literal quote', () {
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        ',A\n"say ""hi""",1\n"""quoted""",2',
      );
      expect(x, ['say "hi"', '"quoted"']);
      expect(series.single.data, [1, 2]);
    });

    test('quoted fields work in the header row too', () {
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        ',"Omzet, netto"\nQ1,10',
      );
      expect(series.single.name, 'Omzet, netto');
      expect(x, ['Q1']);
    });

    test('space before an opening quote still reads as one field', () {
      final (x, _, unreadable: _, ambiguous: _) = parseCsv(
        ',A\n "Amsterdam, NL" ,10',
      );
      expect(x, ['Amsterdam, NL']);
    });

    test('a quoted field keeps its inner whitespace verbatim', () {
      final (x, _, unreadable: _, ambiguous: _) = parseCsv(',A\n" spatie ",1');
      expect(x, [' spatie ']);
    });

    test('an unterminated quote runs to the end of the line', () {
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        ',A\n"Amsterdam, NL,10',
      );
      expect(x, ['Amsterdam, NL,10']);
      expect(series.single.data, [0]);
    });

    test('regression: unquoted CSV parses exactly as before', () {
      // Byte-for-byte the pre-fix behaviour: trimming, blank-line skipping,
      // empty leading header cell, short rows padded with 0.
      final (x, series, unreadable: _, ambiguous: _) = parseCsv(
        '\n, 2025, 2026\nQ1, 10, 12\n\nQ2, 14, 9\nQ3, 3\n',
      );
      expect(x, ['Q1', 'Q2', 'Q3']);
      expect(series.map((s) => s.name), ['2025', '2026']);
      expect(series[0].data, [10, 14, 3]);
      expect(series[1].data, [12, 9, 0]);
    });
  });

  group('parseCsv delimiters', () {
    test('a Dutch Excel export (semicolons) is read, not mangled', () {
      // Was: labels ['Q1;10', 'Q2;14'] and no series at all.
      final result = parseCsv('Label;Omzet\nQ1;10\nQ2;14');
      expect(result.$1, ['Q1', 'Q2']);
      expect(result.$2.single.name, 'Omzet');
      expect(result.$2.single.data, [10, 14]);
      expect(result.unreadable, isEmpty);
    });

    test('with a semicolon separator a comma is a decimal mark', () {
      final result = parseCsv('Label;Omzet\nQ1;10,5\nQ2;14,25');
      expect(result.$2.single.data, [10.5, 14.25]);
      expect(result.unreadable, isEmpty);
    });

    test('tab-separated files are read too', () {
      final result = parseCsv('Label\tOmzet\nQ1\t10\nQ2\t12');
      expect(result.$1, ['Q1', 'Q2']);
      expect(result.$2.single.data, [10, 12]);
    });

    test('a comma file keeps the comma separator even with quoted commas', () {
      // The header has more commas inside quotes than out; detection must not
      // be fooled into picking a separator that is not there.
      final result = parseCsv(',"Omzet, netto"\nQ1,10');
      expect(result.$2.single.name, 'Omzet, netto');
      expect(result.$1, ['Q1']);
      expect(result.$2.single.data, [10]);
    });

    test('quoting still works under a semicolon separator', () {
      final result = parseCsv('Label;Omzet\n"Amsterdam; NL";10');
      expect(result.$1, ['Amsterdam; NL']);
      expect(result.$2.single.data, [10]);
    });

    test('an unaccompanied 1,234 is handed back as a question', () {
      // Could be 1234 or 1.234 and nothing in this file says which. It draws
      // as 0 and comes back in `ambiguous` — not as a wrong number, and not
      // lumped in with values that are simply unreadable.
      final result = parseCsv(',A\nQ1,"1,234"');
      expect(result.$2.single.data, [0]);
      expect(result.ambiguous, ['1,234']);
      expect(result.unreadable, isEmpty);
    });

    test('answering the question resolves it either way', () {
      const csv = ',A\nQ1,"1,234"';
      expect(parseCsv(csv, convention: DecimalConvention.dot).$2.single.data, [
        1234,
      ]);
      expect(
        parseCsv(csv, convention: DecimalConvention.comma).$2.single.data,
        [1.234],
      );
      expect(
        parseCsv(csv, convention: DecimalConvention.dot).ambiguous,
        isEmpty,
      );
    });

    test('a neighbour that settles the convention answers it for free', () {
      // No question needed: 10,5 can only be a decimal comma, so 1,234 in the
      // same file is 1.234 too.
      final decimal = parseCsv(',A,B\nQ1,"1,234","10,5"');
      expect(decimal.ambiguous, isEmpty);
      expect(decimal.$2[0].data, [1.234]);
      expect(decimal.$2[1].data, [10.5]);

      // And the other way: 10.5 fixes the dot as decimal, so 1,234 groups.
      final grouped = parseCsv(',A,B\nQ1,"1,234","10.5"');
      expect(grouped.ambiguous, isEmpty);
      expect(grouped.$2[0].data, [1234]);
      expect(grouped.$2[1].data, [10.5]);
    });

    test('a value carrying both marks needs no question at all', () {
      // 1.234,56 settles itself: the last mark is the decimal one.
      final result = parseCsv('Label;Omzet\nQ1;"1.234,56"');
      expect(result.$2.single.data, [1234.56]);
      expect(result.unreadable, isEmpty);
      expect(result.ambiguous, isEmpty);
    });

    test('a whole file of three-digit groups is what actually gets asked', () {
      final result = parseCsv(',Omzet\nQ1,"1,234"\nQ2,"2,500"\nQ3,"12,000"');
      expect(result.ambiguous, ['1,234', '2,500', '12,000']);
      expect(result.$2.single.data, [0, 0, 0]);
    });

    test('the app reading back its own CSV asks nothing', () {
      // chartDataAsCsv writes a dot decimal mark, so 1.234 must stay 1.234
      // without a prompt or every round-trip would interrogate the user.
      final result = parseCsv(',A\nQ1,1.234\nQ2,2.5');
      expect(result.ambiguous, isEmpty);
      expect(result.$2.single.data, [1.234, 2.5]);
    });

    test('currency and percent signs are refused and reported', () {
      final result = parseCsv(',A\nQ1,"€ 1000"\nQ2,"12%"');
      expect(result.$2.single.data, [0, 0]);
      expect(result.unreadable, ['€ 1000', '12%']);
    });
  });

  group('chartDataAsCsv weert formules', () {
    // Een data/*.csv reist mee met het deck en wordt bij de ontvanger in een
    // spreadsheet geopend. Labels komen uit de deck-tekst — onvertrouwde
    // invoer — dus mag geen enkele cel daar als formule aankomen.
    ChartSpec specWithLabel(String label) => ChartSpec(
      type: ChartType.bar,
      x: [label],
      series: const [
        ChartSeries(name: 'A', data: [1]),
      ],
    );

    for (final leader in ['=', '+', '-', '@', '\t', '\r']) {
      test('een label dat met ${leader.trim().isEmpty ? 'witruimte' : leader} '
          'begint krijgt de tekstvoorloop', () {
        final csv = chartDataAsCsv(specWithLabel('${leader}HYPERLINK("x")'));
        final label = parseCsvLine(csv.split('\n')[1]).first;
        expect(
          label.startsWith(leader),
          isFalse,
          reason: 'de cel begint nog met $leader en wordt dus een formule',
        );
        expect(label.startsWith("'"), isTrue);
      });
    }

    test('een reeksnaam die met = begint krijgt de tekstvoorloop', () {
      final csv = chartDataAsCsv(
        ChartSpec(
          type: ChartType.bar,
          x: const ['Q1'],
          series: const [
            ChartSeries(name: '=cmd|calc', data: [1]),
          ],
        ),
      );
      expect(parseCsvLine(csv.split('\n').first)[1], "'=cmd|calc");
    });

    test(
      'de voorloop overleeft de rondgang niet: het label komt heel terug',
      () {
        final csv = chartDataAsCsv(specWithLabel('=SUM(A1)'));
        expect(parseCsv(csv).$1, ['=SUM(A1)']);
      },
    );

    test('een label dat écht met een apostrof begint blijft ongemoeid', () {
      final csv = chartDataAsCsv(specWithLabel("'s Gravenhage"));
      expect(parseCsv(csv).$1, ["'s Gravenhage"]);
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

  group('readableChartInk', () {
    test('keeps the preferred colour when it clears the contrast bar', () {
      // Brand navy on white and light text on a dark slide both pass — the
      // theme colour is kept so the chart title stays on-brand.
      expect(readableChartInk('#003399', '#FFFFFF'), '#003399');
      expect(readableChartInk('#EEF1F4', '#0A0B0C'), '#EEF1F4');
    });

    test('flips to white on a dark ground when the preferred ink fails', () {
      // Theme-navy on a near-black card: unreadable, so it becomes white.
      expect(readableChartInk('#003399', '#111827'), '#FFFFFF');
      expect(readableChartInk('#1E293B', '#0F172A'), '#FFFFFF');
    });

    test(
      'flips to a dark ink on a light ground when the preferred ink fails',
      () {
        // A pale colour on white is invisible; fall back to a dark ink.
        expect(readableChartInk('#F5F5F5', '#FFFFFF'), '#1A1A1A');
      },
    );
  });

  group('taart-percentages (showSliceLabels, #1395)', () {
    const pie = ChartSpec(
      type: ChartType.pie,
      x: ['Lucht', 'Zon'],
      series: [
        ChartSeries(name: 'Aandeel', data: [75, 25]),
      ],
    );

    test('standaard aan; het blok blijft schoon', () {
      expect(pie.showSliceLabels, isTrue);
      expect(pie.toBlock(), isNot(contains('showSliceLabels')));
    });

    test('uitgezet overleeft het blok', () {
      final off = pie.copyWith(showSliceLabels: false);
      expect(off.toBlock(), contains('"showSliceLabels": false'));
      expect(ChartSpec.parse(off.toBlock()).showSliceLabels, isFalse);
    });

    test('alleen een taartachtige schrijft de vlag weg', () {
      // Anders blijft de keuze hangen na een typewissel naar bijv. een staaf.
      final bar = pie.copyWith(type: ChartType.bar, showSliceLabels: false);
      expect(bar.toBlock(), isNot(contains('showSliceLabels')));
    });

    test('een ontbrekende sleutel valt terug op aan', () {
      expect(ChartSpec.parse('{"type":"pie"}').showSliceLabels, isTrue);
    });
  });
}
