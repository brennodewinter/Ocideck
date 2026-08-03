import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';

import 'support/question_answer_limit_fixture.dart';

/// Coverage for `lib/services/marp_html/marp_html_service_charts.dart`.
///
/// Every chart kind reaches the SVG renderer through the public static entry
/// point [MarpHtmlService.renderChartBlocks], which parses a ```chart fenced
/// block into a [ChartSpec] and emits a self-contained inline `<svg>`. We build
/// specs, round-trip them through [ChartSpec.toBlock] (the exact JSON the app
/// stores) and assert on the produced markup — exercising every `ChartType`
/// branch plus the shared helpers (axes, bound lines, legends, colour picking).

/// Wrap a spec's block in a ```chart fence and render it to HTML.
String _render(ChartSpec spec, {ThemeProfile? theme}) =>
    MarpHtmlService.renderChartBlocks(
      '```chart\n${spec.toBlock()}\n```',
      theme: theme,
    );

/// Render a raw JSON chart block (for cases [ChartSpec.toBlock] can't express,
/// e.g. a source-only block whose inline data has been stripped).
String _renderRaw(String json, {ThemeProfile? theme}) =>
    MarpHtmlService.renderChartBlocks('```chart\n$json\n```', theme: theme);

/// A slide-scoped theme with distinctive colours so their presence is provable.
const _theme = ThemeProfile(
  slideBackgroundColor: '#0A0B0C',
  textColor: '#EEF1F4',
  accentColor: '#AB12CD',
);

void main() {
  group('every chart type renders a self-contained inline SVG', () {
    ChartSpec specFor(ChartType type) => ChartSpec(
      type: type,
      title: 'Titel',
      x: const ['Alpha', 'Beta', 'Gamma'],
      series: const [
        ChartSeries(name: 'Reeks één', data: [3, 6, 4], color: '#2563EB'),
        ChartSeries(name: 'Reeks twee', data: [5, 2, 8], color: '#EF4444'),
      ],
    );

    for (final type in ChartType.values) {
      test('${type.name} produces an <svg> and consumes the fence', () {
        final html = _render(specFor(type));
        expect(html, contains('<div class="chart">'));
        expect(html, contains('<svg'));
        expect(html, contains('</svg>'));
        // The ```chart fence was replaced, not left in the output.
        expect(html, isNot(contains('```chart')));
      });

      test('${type.name} also renders with a theme applied', () {
        final html = _render(specFor(type), theme: _theme);
        expect(html, contains('<svg'));
        expect(html, contains('</svg>'));
      });
    }
  });

  group('shape markers per chart type', () {
    test('bar draws rects, axes gridlines and a series legend', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'Alpha', data: [10, 14]),
            ChartSeries(name: 'Beta', data: [6, 9]),
          ],
        ),
      );
      expect(html, contains('<rect'));
      // Axis gridlines use the fixed slate stroke colour.
      expect(html, contains('stroke="#e2e8f0"'));
      // The series legend prints both series names.
      expect(html, contains('Alpha'));
      expect(html, contains('Beta'));
      // First series with no colour + no theme falls back to the palette head.
      expect(html, contains('#003399'));
    });

    test('stacked bar sums series for its y scale and draws rects', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.stackedBar,
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'A', data: [3, 5]),
            ChartSeries(name: 'B', data: [2, 1]),
          ],
        ),
      );
      expect(html, contains('<rect'));
      expect(html, contains('<svg'));
    });

    test('line draws a polyline with point circles, no area fill', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.line,
          x: ['Q1', 'Q2', 'Q3'],
          series: [
            ChartSeries(name: 'Bezoekers', data: [10, 14, 12]),
          ],
        ),
      );
      expect(html, contains('<polyline'));
      expect(html, contains('<circle'));
      // A plain line has no filled polygon under it.
      expect(html, isNot(contains('<polygon')));
    });

    test('area draws a filled polygon under the line', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.area,
          x: ['Q1', 'Q2', 'Q3'],
          series: [
            ChartSeries(name: '2026', data: [10, 14, 12]),
          ],
        ),
      );
      expect(html, contains('<polygon'));
      expect(html, contains('<polyline'));
      // A single-series area uses the denser fill opacity.
      expect(html, contains('fill-opacity="0.28"'));
    });

    test('multi-series area uses the lighter fill opacity', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.area,
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'A', data: [10, 14]),
            ChartSeries(name: 'B', data: [4, 9]),
          ],
        ),
      );
      expect(html, contains('fill-opacity="0.16"'));
    });

    test('scatter draws a circle per data point', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.scatter,
          x: ['A', 'B', 'C'],
          series: [
            ChartSeries(name: 'Punten', data: [3, 7, 5]),
          ],
        ),
      );
      expect(html, contains('<circle'));
    });

    test(
      'pie draws slice paths and a per-label legend (not a series legend)',
      () {
        final html = _render(
          const ChartSpec(
            type: ChartType.pie,
            x: ['Team A', 'Team B'],
            series: [
              ChartSeries(name: 'Gereed', data: [70, 40]),
            ],
          ),
        );
        expect(html, contains('<path'));
        // Pie legend lists the x labels.
        expect(html, contains('Team A'));
        expect(html, contains('Team B'));
      },
    );

    test('donut prints the series total in its centre hole', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.donut,
          x: ['A', 'B', 'C'],
          series: [
            ChartSeries(name: 'Aandeel', data: [20, 30, 50]),
          ],
        ),
      );
      // 20 + 30 + 50 = 100, printed as the centre total.
      expect(html, contains('>100</text>'));
      expect(html, contains('<path'));
    });

    test('donut hole uses the theme slide background colour', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.donut,
          x: ['A', 'B'],
          series: [
            ChartSeries(name: 'Aandeel', data: [40, 60]),
          ],
        ),
        theme: _theme,
      );
      expect(html, contains('fill="#0A0B0C"'));
    });

    test('radar draws a polygon per series plus axis labels', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.radar,
          x: ['Snelheid', 'Kracht', 'Uithouding'],
          series: [
            ChartSeries(name: 'A', data: [3, 4, 5], color: '#2563EB'),
            ChartSeries(name: 'B', data: [5, 2, 3], color: '#EF4444'),
          ],
        ),
      );
      expect(html, contains('<polygon'));
      expect(html, contains('Snelheid'));
      expect(html, contains('Kracht'));
      expect(html, contains('Uithouding'));
      expect(html, contains('fill="#2563EB"'));
      expect(html, contains('fill="#EF4444"'));
    });

    test('radar with fewer than three labels draws no radar polygon', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.radar,
          x: ['Een', 'Twee'],
          series: [
            ChartSeries(name: 'Alpha', data: [3, 4]),
          ],
        ),
      );
      // Early return skips the spider; only the legend remains.
      expect(html, contains('<svg'));
      expect(html, isNot(contains('<polygon')));
      expect(html, contains('Alpha'));
    });

    test('horizontal bar prints category and value labels', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.horizontalBar,
          x: ['Alpha', 'Beta'],
          series: [
            ChartSeries(name: 'Score', data: [8, 12]),
          ],
        ),
      );
      expect(html, contains('Alpha'));
      expect(html, contains('Beta'));
      expect(html, contains('>12</text>'));
    });

    test('horizontal bar omits the value label for a zero-length bar', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.horizontalBar,
          x: ['Alpha', 'Beta'],
          series: [
            ChartSeries(name: 'Score', data: [8, 0]),
          ],
        ),
      );
      // The non-zero bar keeps its label; the zero bar gets none.
      expect(html, contains('>8</text>'));
    });

    test('horizontal bar renders a decimal value label', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.horizontalBar,
          x: ['Alpha'],
          series: [
            ChartSeries(name: 'Score', data: [8.5]),
          ],
        ),
      );
      expect(html, contains('>8.5</text>'));
    });

    test(
      'horizontal stacked bar draws segments with category + value labels',
      () {
        final html = _render(
          const ChartSpec(
            type: ChartType.horizontalStackedBar,
            x: ['Alpha', 'Beta'],
            series: [
              ChartSeries(name: 'A', data: [6, 8]),
              ChartSeries(name: 'B', data: [4, 3]),
            ],
          ),
        );
        expect(html, contains('<rect'));
        // Category labels down the left, and a wide segment prints its value.
        expect(html, contains('Alpha'));
        expect(html, contains('Beta'));
        expect(html, contains('>6</text>'));
        // Both series appear in the legend.
        expect(html, contains('>A</text>'));
        expect(html, contains('>B</text>'));
      },
    );

    test('horizontal stacked bar scales its axis to the widest total', () {
      // Beta's stacked total is 8 + 4 = 12, larger than any single value, so the
      // axis end (max × 1.15 ≈ 13.8) reflects the SUM, not the biggest segment.
      final html = _render(
        const ChartSpec(
          type: ChartType.horizontalStackedBar,
          x: ['Alpha', 'Beta'],
          series: [
            ChartSeries(name: 'A', data: [5, 8]),
            ChartSeries(name: 'B', data: [3, 4]),
          ],
        ),
      );
      expect(html, contains('>13.8</text>'));
    });

    test('combo overlays a line over the bars (two+ series)', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.combo,
          x: ['Q1', 'Q2', 'Q3'],
          series: [
            ChartSeries(name: 'Omzet', data: [10, 14, 12]),
            ChartSeries(name: 'Groei', data: [3, 8, 5]),
          ],
        ),
      );
      expect(html, contains('<rect'));
      expect(html, contains('<polyline'));
    });

    test('combo with a single series degrades to a plain bar chart', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.combo,
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'Omzet', data: [10, 14]),
          ],
        ),
      );
      expect(html, contains('<rect'));
      // No second-axis line is drawn in the fallback.
      expect(html, isNot(contains('<polyline')));
    });

    test('combo tolerates a flat line series (equal values)', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.combo,
          x: ['Q1', 'Q2', 'Q3'],
          series: [
            ChartSeries(name: 'Omzet', data: [10, 14, 12]),
            ChartSeries(name: 'Groei', data: [5, 5, 5]),
          ],
        ),
      );
      expect(html, contains('<polyline'));
      expect(html, contains('<svg'));
    });

    test('waterfall colours up/down steps and shows both bound lines', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.waterfall,
          x: ['Start', 'Eraf', 'Erbij'],
          series: [
            ChartSeries(name: 'Stap', data: [100, -150, 20]),
          ],
          minBound: -80,
          maxBound: 150,
        ),
      );
      // Positive delta = success green, negative delta = danger red.
      expect(html, contains('fill="#15803D"'));
      expect(html, contains('fill="#EF4444"'));
      // Its own signed-scale bound lines (waterfall carries its own key).
      expect(html, contains('stroke-dasharray'));
      expect(html, contains('min -80'));
      expect(html, contains('max 150'));
    });

    test('heatmap renders cell values, column labels and a colour scale', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.heatmap,
          x: ['Laag', 'Hoog'],
          series: [
            ChartSeries(name: 'Kans A', data: [1, 4]),
            ChartSeries(name: 'Kans B', data: [2, 9]),
          ],
        ),
      );
      expect(html, contains('Kans A'));
      expect(html, contains('Kans B'));
      expect(html, contains('Laag'));
      expect(html, contains('Hoog'));
      expect(html, contains('>4</text>'));
      // A light slide uses the light heat ramp (pale-yellow low stop).
      expect(html, contains('#FFFFB2'));
    });

    test('heatmap on a dark slide switches to the dark heat ramp', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.heatmap,
          x: ['Laag', 'Hoog'],
          series: [
            ChartSeries(name: 'Kans A', data: [1, 4]),
          ],
        ),
        theme: ThemeProfile(slideBackgroundColor: '#101018'),
      );
      // The dark ramp's low stop, not the light ramp's.
      expect(html, contains('#4B1D06'));
      expect(html, isNot(contains('#FFFFB2')));
    });

    test('heatmap greys out absent (ragged) cells', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.heatmap,
          x: ['Laag', 'Midden', 'Hoog'],
          series: [
            ChartSeries(name: 'Kans A', data: [1, 4, 7]),
            // Shorter than x → the last cell is absent and greyed.
            ChartSeries(name: 'Kans B', data: [2]),
          ],
        ),
      );
      expect(html, contains('fill="#f1f5f9"'));
    });
  });

  group('bound lines on cartesian charts', () {
    test('bar draws dashed min/max threshold lines with labels', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'Omzet', data: [10, 14]),
          ],
          minBound: 5,
          maxBound: 20,
        ),
      );
      expect(html, contains('stroke-dasharray'));
      expect(html, contains('min 5'));
      expect(html, contains('max 20'));
    });

    test('scatter honours bound lines too', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.scatter,
          x: ['A', 'B'],
          series: [
            ChartSeries(name: 'Punten', data: [10, 14]),
          ],
          minBound: 6,
          maxBound: 18,
        ),
      );
      expect(html, contains('<circle'));
      expect(html, contains('stroke-dasharray'));
      expect(html, contains('min 6'));
      expect(html, contains('max 18'));
    });

    test('pie never draws bound lines even when bounds are present in JSON', () {
      // Bounds are dropped by toBlock for pie, so feed raw JSON to force them.
      final html = _renderRaw(
        '{"type":"pie","x":["A","B"],'
        '"series":[{"name":"Een","data":[1,2]}],'
        '"minBound":5,"maxBound":20}',
      );
      expect(html, isNot(contains('stroke-dasharray')));
      expect(html, isNot(contains('min 5')));
    });
  });

  group('colour selection', () {
    test('first series with no colour uses the theme accent when themed', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['A'],
          series: [
            ChartSeries(name: 'Waarde', data: [10]),
          ],
        ),
        theme: _theme,
      );
      // _color() returns the theme accent for series 0 without an explicit hue.
      expect(html, contains('#AB12CD'));
    });

    test('an explicit series colour overrides the theme accent', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['A'],
          series: [
            ChartSeries(name: 'Waarde', data: [10], color: '#112233'),
          ],
        ),
        theme: _theme,
      );
      expect(html, contains('#112233'));
      expect(html, isNot(contains('#AB12CD')));
    });

    test('pie slices honour explicit rowColors', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.pie,
          x: ['A', 'B'],
          rowColors: ['#123456', '#654321'],
          series: [
            ChartSeries(name: 'Verdeling', data: [40, 60]),
          ],
        ),
      );
      expect(html, contains('fill="#123456"'));
      expect(html, contains('fill="#654321"'));
    });
  });

  group('legend edge cases', () {
    test('an empty series name falls back to "Reeks N"', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['A'],
          series: [
            ChartSeries(name: '', data: [10]),
          ],
        ),
      );
      expect(html, contains('Reeks 1'));
    });

    test('a long series name is truncated with an ellipsis', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['A'],
          series: [
            ChartSeries(name: 'Verylongseriesname', data: [10]),
          ],
        ),
      );
      // 12+ chars are cut to 11 chars + an ellipsis.
      expect(html, contains('Verylongser'));
      expect(html, contains('…'));
    });

    test('the series legend shows at most six entries', () {
      final html = _render(
        ChartSpec(
          type: ChartType.bar,
          x: const ['A'],
          series: [
            for (var i = 0; i < 8; i++)
              ChartSeries(name: 'S$i', data: const [3]),
          ],
        ),
      );
      // Only the first six series names appear in the legend.
      expect(html, contains('S0'));
      expect(html, contains('S5'));
      expect(html, isNot(contains('S6')));
      expect(html, isNot(contains('S7')));
    });

    test('pie legend wraps labels over multiple rows and clamps at three', () {
      final html = _render(
        ChartSpec(
          type: ChartType.pie,
          x: [for (var i = 0; i < 20; i++) 'L$i'],
          series: const [
            ChartSeries(name: 'Verdeling', data: [1]),
          ],
        ),
      );
      // Rows clamp to three (18 slots); the first is shown, the 19th is dropped.
      expect(html, contains('>L0</text>'));
      expect(html, contains('>L17</text>'));
      expect(html, isNot(contains('>L18</text>')));
      expect(html, isNot(contains('>L19</text>')));
    });
  });

  group('titles and empty data', () {
    test('a long title is truncated to fit the header band', () {
      final title = 'X' * 80;
      final html = _render(
        ChartSpec(
          type: ChartType.bar,
          title: title,
          x: const ['A'],
          series: const [
            ChartSeries(name: 'V', data: [1]),
          ],
        ),
      );
      expect(html, contains('…</text>'));
      // The full 80-char title is not emitted verbatim.
      expect(html, isNot(contains(title)));
    });

    test('a titled chart shifts the plot area down (title branch)', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          title: 'Omzet',
          x: ['A'],
          series: [
            ChartSeries(name: 'V', data: [1]),
          ],
        ),
      );
      expect(html, contains('font-weight="bold"'));
      expect(html, contains('Omzet'));
    });

    test('all-zero data still renders without dividing by zero', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          x: ['A', 'B'],
          series: [
            ChartSeries(name: 'Nul', data: [0, 0]),
          ],
        ),
      );
      expect(html, contains('<svg'));
      expect(html, contains('<rect'));
    });

    test('dense/long x labels are thinned and truncated on the axis', () {
      final html = _render(
        ChartSpec(
          type: ChartType.bar,
          x: [for (var i = 0; i < 10; i++) 'Verylonglabel$i'],
          series: [
            ChartSeries(name: 'V', data: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          ],
        ),
      );
      // Axis labels over 10 chars are cut to 9 chars + an ellipsis.
      expect(html, contains('Verylongl'));
      expect(html, contains('<svg'));
    });
  });

  group('CSV source vs inline data', () {
    test('a source-only block (stripped inline data) renders an empty SVG', () {
      final html = _renderRaw('{"type":"bar","source":"data/omzet.csv"}');
      // hasInlineData is false → the placeholder empty SVG, no bars.
      expect(
        html,
        contains(
          '<svg viewBox="0 0 800 450" xmlns="http://www.w3.org/2000/svg">'
          '</svg>',
        ),
      );
      expect(html, isNot(contains('<rect')));
    });

    test('an empty series list yields the empty-SVG placeholder', () {
      final html = _renderRaw('{"type":"bar","x":["A","B"],"series":[]}');
      expect(html, contains('</svg>'));
      expect(html, isNot(contains('<rect')));
    });

    test('a chart that keeps both a source and inline data renders fully', () {
      // withCsv-style: a source is set but the data is present, so it draws.
      final html = _render(
        const ChartSpec(
          type: ChartType.bar,
          source: 'data/omzet.csv',
          x: ['Q1', 'Q2'],
          series: [
            ChartSeries(name: 'Omzet', data: [10, 14]),
          ],
        ),
      );
      expect(html, contains('<rect'));
    });

    test('parseCsv-hydrated spec renders like an inline chart', () {
      // Exercise the CSV → spec path, then the export renderer over it.
      final spec = const ChartSpec(
        type: ChartType.line,
        source: 'data/omzet.csv',
      ).withCsv('Maand,Omzet\nJan,10\nFeb,14\nMrt,9');
      final html = _render(spec);
      expect(html, contains('<polyline'));
      expect(html, contains('Jan'));
      expect(html, contains('Omzet'));
    });
  });

  group('radar scale nice-rounding branches', () {
    // Different data ranges push _radarScale through its nice-step buckets and
    // the explicit-bounds path; all must render a spider without throwing.
    final ranges = <List<double>>[
      [3, 4, 5], // small range → step 1
      [3, 8, 22], // mid range → step 5
      [3, 8, 60], // → step 20
      [50, 360, 120], // large range → step 100
    ];
    for (var i = 0; i < ranges.length; i++) {
      test('auto scale for range set #$i', () {
        final html = _render(
          ChartSpec(
            type: ChartType.radar,
            x: const ['A', 'B', 'C'],
            series: [ChartSeries(name: 'Score', data: ranges[i])],
          ),
        );
        expect(html, contains('<polygon'));
      });
    }

    test('explicit min/max bounds fix the radar scale', () {
      final html = _render(
        const ChartSpec(
          type: ChartType.radar,
          x: ['A', 'B', 'C', 'D'],
          series: [
            ChartSeries(name: 'Score', data: [2, 4, 3, 5]),
          ],
          minBound: 0,
          maxBound: 10,
        ),
      );
      expect(html, contains('<polygon'));
      // The scale legend prints the outer tick value.
      expect(html, contains('>10</text>'));
    });
  });

  group('negatieve waarden', () {
    // De app-preview heeft een `_minY` en geeft die aan fl_chart mee; de
    // SVG-export had alleen een `_maxY` die bij 0 begint. Een verliesreeks kwam
    // daardoor uit op `height="-1610"` — ongeldige SVG, dus de browser liet de
    // staaf weg — onder een y-as van 0 tot 1. Erger dan een lege grafiek, want
    // het ziet er aannemelijk uit.
    String render(String json) =>
        MarpHtmlService.renderChartBlocks('```chart\n$json\n```');

    List<String> axisLabels(String svg) => RegExp(
      r'fill="#64748b">([^<]+)<',
    ).allMatches(svg).map((m) => m.group(1)!).toList();

    test('een negatieve staafreeks levert geldige, zichtbare staven', () {
      final svg = render(
        '{"type":"bar","x":["Q1","Q2","Q3"],'
        '"series":[{"name":"Winst","data":[-5,-3,-8]}]}',
      );
      expect(
        RegExp(r'height="-[\d.]+"').hasMatch(svg),
        isFalse,
        reason: 'een negatieve hoogte is ongeldige SVG',
      );
      expect(RegExp(r'<rect ').allMatches(svg).length, greaterThanOrEqualTo(3));
      // En de as loopt mee naar beneden in plaats van 0..1 te verzinnen.
      expect(axisLabels(svg).first, startsWith('-'));
    });

    test('een lijn met gemengde waarden blijft binnen het tekenvlak', () {
      final svg = render(
        '{"type":"line","x":["a","b","c"],'
        '"series":[{"name":"S","data":[10,-10,5]}]}',
      );
      final pts = RegExp(r'points="([^"]+)"').firstMatch(svg)!.group(1)!;
      for (final pair in pts.split(' ')) {
        final y = double.parse(pair.split(',')[1]);
        expect(y, lessThanOrEqualTo(382.0), reason: 'onder de plotbodem');
        expect(y, greaterThanOrEqualTo(0.0));
      }
    });

    test('een reeks zonder negatieve waarden verandert niet', () {
      final svg = render(
        '{"type":"bar","x":["a","b"],"series":[{"name":"S","data":[4,8]}]}',
      );
      expect(axisLabels(svg).first, '0');
    });
  });

  group('vraagdia', () {
    test('de export toont de vraag maar niet het goede antwoord', () {
      // Zonder renderer viel het blok terug op de codeweergave van marked, en
      // stond de hele specificatie leesbaar op de dia — inclusief
      // `"correct": true`, in invoervolgorde. Wie een quizdeck als HTML
      // rondstuurde, deelde de antwoordsleutel mee.
      final out = MarpHtmlService.renderQuestionBlocks(
        '```question\n'
        '{"kind":"multipleChoice","prompt":"Wat is de juiste keuze?",'
        '"answers":[{"text":"Het juiste antwoord","correct":true},'
        '{"text":"Een fout antwoord","correct":false}]}\n'
        '```',
      );
      expect(out, contains('Wat is de juiste keuze?'));
      expect(out, contains('Het juiste antwoord'));
      expect(out, contains('Een fout antwoord'));
      expect(out, isNot(contains('correct')));
      expect(out, isNot(contains('```')));
    });

    test('een waar/niet-waar-vraag toont beide opties, niet de uitkomst', () {
      final out = MarpHtmlService.renderQuestionBlocks(
        '```question\n'
        '{"kind":"trueFalse","prompt":"Is dit waar?","statementIsTrue":true}\n'
        '```',
      );
      expect(out, contains('Is dit waar?'));
      expect(out, contains('Waar'));
      expect(out, contains('Niet waar'));
      expect(out, isNot(contains('statementIsTrue')));
    });

    test('tekst in een optie wordt als HTML ontsnapt', () {
      final out = MarpHtmlService.renderQuestionBlocks(
        '```question\n'
        '{"kind":"multipleChoice","prompt":"<b>vet</b>",'
        '"answers":[{"text":"a & b","correct":true}]}\n'
        '```',
      );
      expect(out, contains('&lt;b&gt;vet&lt;/b&gt;'));
      expect(out, contains('a &amp; b'));
    });

    test('exactly eight answers are included in static export', () {
      final out = MarpHtmlService.renderQuestionBlocks(
        '```question\n${questionBlockWithAnswers(8)}\n```',
      );

      expect(RegExp(r'<li>').allMatches(out), hasLength(8));
      expect(out, contains('Antwoord 7'));
    });

    test(
      'an oversized question exports a notice instead of answer widgets',
      () {
        final out = MarpHtmlService.renderQuestionBlocks(
          '```question\n${questionBlockWithAnswers(9)}\n```',
        );

        expect(out, contains('Ongeldige vraag'));
        expect(out, contains('Maximaal aantal items: 8'));
        expect(out, contains('Antwoorden: 9'));
        expect(out, isNot(contains('<li>')));
        expect(out, isNot(contains('Antwoord 8')));
      },
    );

    test('a twenty-answer multiple-choice bank remains exportable', () {
      final out = MarpHtmlService.renderQuestionBlocks(
        '```question\n${multipleChoiceBeerQuestionBlock(20)}\n```',
      );

      expect(out, isNot(contains('Ongeldige vraag')));
      expect(out, contains('Wat is geen bier?'));
      expect('<li>'.allMatches(out), hasLength(20));
    });
  });
}
