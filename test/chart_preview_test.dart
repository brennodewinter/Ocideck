import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(ChartSpec spec, {bool presentationMode = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(
              SlideType.chart,
            ).copyWith(customMarkdown: spec.toBlock()),
            presentationMode: presentationMode,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('chart title stays above the plot area', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet per kwartaal',
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: '2026', data: [10, 14]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final titleBottom = tester.getBottomLeft(find.text(spec.title)).dy;
    final plotTop = tester.getTopLeft(find.byType(BarChart)).dy;
    expect(titleBottom, lessThan(plotTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pie renders one chart per series with labels as slices', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      title: 'Verdeling',
      x: ['Team A', 'Team B'],
      series: [
        ChartSeries(name: 'Gereed', data: [70, 40], color: '#10B981'),
        ChartSeries(name: 'Open', data: [30, 60], color: '#EF4444'),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(find.byType(PieChart), findsNWidgets(2));
    expect(find.text('Team A'), findsOneWidget);
    expect(find.text('Team B'), findsOneWidget);
    expect(find.text('Gereed'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    final pieRect = tester.getRect(find.byType(PieChart).first);
    final titleRect = tester.getRect(find.text('Gereed'));
    expect(titleRect.left, greaterThan(pieRect.center.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pie is solid to the centre; donut keeps its hole (#1395)', (
    tester,
  ) async {
    const x = ['Lucht', 'Schaduw', 'Zon'];
    const series = [
      ChartSeries(name: 'Aandeel', data: [75, 10, 15]),
    ];

    // A pie draws a full circle: the slices meet at the centre (no hole), so a
    // drawing built from wedges — a pyramid against the sky — closes to a point.
    await tester.pumpWidget(
      _host(const ChartSpec(type: ChartType.pie, x: x, series: series)),
    );
    await tester.pump();
    expect(
      tester
          .widget<PieChart>(find.byType(PieChart).first)
          .data
          .centerSpaceRadius,
      0,
    );

    // A donut keeps its hole (it prints the total there).
    await tester.pumpWidget(
      _host(const ChartSpec(type: ChartType.donut, x: x, series: series)),
    );
    await tester.pump();
    expect(
      tester
          .widget<PieChart>(find.byType(PieChart).first)
          .data
          .centerSpaceRadius,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar chart uses most of the available vertical plot area', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Compacte titel',
      x: ['A', 'B', 'C'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20, 15]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(tester.getSize(find.byType(BarChart)).height, greaterThan(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart surface fills the remaining slide height', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Titel',
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final slide = tester.getRect(find.byType(SlidePreviewWidget));
    final surface = tester.getRect(find.byKey(const ValueKey('chart-surface')));
    expect(surface.height, greaterThan(slide.height * 0.72));
    expect(slide.bottom - surface.bottom, lessThan(slide.height * 0.04));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar and line hover tooltips show labels and values', (
    tester,
  ) async {
    const barSpec = ChartSpec(
      type: ChartType.bar,
      x: ['Januari'],
      series: [
        ChartSeries(name: 'Omzet', data: [42]),
      ],
    );
    await tester.pumpWidget(_host(barSpec));
    final bar = tester.widget<BarChart>(find.byType(BarChart));
    final barItem = bar.data.barTouchData.touchTooltipData.getTooltipItem(
      bar.data.barGroups.single,
      0,
      bar.data.barGroups.single.barRods.single,
      0,
    );
    expect(barItem?.text, 'Januari\nOmzet: 42');

    const lineSpec = ChartSpec(
      type: ChartType.line,
      x: ['Februari'],
      series: [
        ChartSeries(name: 'Bezoekers', data: [17.5]),
      ],
    );
    await tester.pumpWidget(_host(lineSpec));
    final line = tester.widget<LineChart>(find.byType(LineChart));
    final spot = LineBarSpot(
      line.data.lineBarsData.single,
      0,
      line.data.lineBarsData.single.spots.single,
    );
    final lineItems = line.data.lineTouchData.touchTooltipData.getTooltipItems([
      spot,
    ]);
    expect(lineItems.single?.text, 'Februari\nBezoekers: 17.5');
  });

  testWidgets('line tooltip uses true distance and shows every nearby dot', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.line,
      x: ['Q1'],
      series: [
        ChartSeries(name: 'Alpha', data: [10], color: '#2563EB'),
        ChartSeries(name: 'Beta', data: [10], color: '#EF4444'),
        ChartSeries(name: 'Gamma', data: [10], color: '#10B981'),
      ],
    );
    await tester.pumpWidget(_host(spec));
    final line = tester.widget<LineChart>(find.byType(LineChart));
    final touch = line.data.lineTouchData;

    // Proximity is Euclidean (x AND y), not the x-only default.
    expect(touch.distanceCalculator(Offset.zero, const Offset(3, 4)), 5);
    expect(touch.touchSpotThreshold, greaterThan(0));

    final spots = [
      for (var i = 0; i < 3; i++)
        LineBarSpot(
          line.data.lineBarsData[i],
          i,
          line.data.lineBarsData[i].spots.single,
        ),
    ];
    final items = touch.touchTooltipData.getTooltipItems(spots);
    // All overlapping dots are shown (none filtered out).
    expect(items.length, 3);
    expect(items.whereType<LineTooltipItem>().length, 3);
    expect(items[0]?.text, 'Q1\nAlpha: 10');
    expect(items[2]?.text, 'Q1\nGamma: 10');

    // A crowded stack uses a smaller font than a single tooltip.
    final single = touch.touchTooltipData.getTooltipItems([spots.first]);
    expect(
      items[0]!.textStyle.fontSize!,
      lessThan(single.single!.textStyle.fontSize!),
    );
  });

  testWidgets('pie hover shows the underlying category value', (tester) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      x: ['Gereed', 'Open'],
      series: [
        ChartSeries(name: 'Status', data: [70, 30]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final pie = tester.widget<PieChart>(find.byType(PieChart));
    final section = pie.data.sections.first;
    pie.data.pieTouchData.touchCallback!(
      const FlPointerHoverEvent(PointerHoverEvent()),
      PieTouchResponse(
        touchLocation: Offset.zero,
        touchedSection: PieTouchedSection(section, 0, 0, section.radius),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pie-hover-tooltip')), findsOneWidget);
    expect(find.text('Gereed: 70'), findsOneWidget);
  });

  testWidgets('bar chart draws the configured min/max bound lines', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['Q1'],
      series: [
        ChartSeries(name: 'Omzet', data: [10]),
      ],
      minBound: 5,
      maxBound: 20,
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final bar = tester.widget<BarChart>(find.byType(BarChart));
    final ys = bar.data.extraLinesData.horizontalLines.map((l) => l.y).toList();
    expect(ys, containsAll(<double>[5, 20]));
    // The max bound widens the axis so the line stays inside the plot.
    expect(bar.data.maxY, greaterThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering a legend entry fades the other series', (tester) async {
    const spec = ChartSpec(
      type: ChartType.line,
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: 'Alpha', data: [10, 12], color: '#2563EB'),
        ChartSeries(name: 'Beta', data: [8, 9], color: '#EF4444'),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    var line = tester.widget<LineChart>(find.byType(LineChart));
    expect(line.data.lineBarsData[0].color!.a, 1.0);
    expect(line.data.lineBarsData[1].color!.a, 1.0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Alpha')));
    await tester.pumpAndSettle();

    line = tester.widget<LineChart>(find.byType(LineChart));
    expect(line.data.lineBarsData[0].color!.a, 1.0); // hovered stays solid
    expect(line.data.lineBarsData[1].color!.a, lessThan(1.0)); // other fades
    expect(tester.takeException(), isNull);
  });

  testWidgets('bar chart animates its rods in (fl_chart tween) on enter', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['Januari'],
      series: [
        ChartSeries(name: 'Omzet', data: [42]),
      ],
    );

    BarChart chart() => tester.widget<BarChart>(find.byType(BarChart));
    double rodToY() => chart().data.barGroups.single.barRods.single.toY;

    // Presentation mode: fl_chart is handed a non-zero tween duration so it
    // lerps the rod 0 -> value internally, then the duration freezes to zero so
    // later hover/tooltip rebuilds don't re-animate. The final value is 42.
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump(); // run the post-frame swap to the real values
    expect(chart().duration, greaterThan(Duration.zero));
    expect(rodToY(), 42);
    await tester.pumpAndSettle();
    expect(chart().duration, Duration.zero);
    expect(rodToY(), 42);
    expect(tester.takeException(), isNull);

    // Editor/thumbnail (no presentation): no tween, final value immediately.
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    expect(chart().duration, Duration.zero);
    expect(rodToY(), 42);
  });

  testWidgets('chart re-animates on slide change even with identical markdown', (
    tester,
  ) async {
    // The presenter reuses the same preview State across slides (no key), so the
    // entrance must re-arm on a slide change, not only on a markdown edit.
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['Jan'],
      series: [
        ChartSeries(name: 'Omzet', data: [42]),
      ],
    );
    Duration dur() => tester.widget<BarChart>(find.byType(BarChart)).duration;

    // First slide: let the entrance play and freeze.
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pumpAndSettle();
    expect(dur(), Duration.zero);

    // A different slide (fresh uuid) with the SAME chart markdown re-arms it.
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump();
    expect(dur(), greaterThan(Duration.zero));
  });

  testWidgets('a chart with animation off is static even in presentation', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['Januari'],
      series: [
        ChartSeries(name: 'Omzet', data: [42]),
      ],
      animateOnEnter: false,
    );
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump();
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    // No tween at all, and the final value on the first frame.
    expect(chart.duration, Duration.zero);
    expect(chart.data.barGroups.single.barRods.single.toY, 42);
  });

  testWidgets('radar chart renders a polygon per series with axis labels', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: ['Snelheid', 'Kracht', 'Uithouding'],
      series: [
        ChartSeries(name: 'Alpha', data: [3, 4, 5], color: '#2563EB'),
        ChartSeries(name: 'Beta', data: [5, 2, 3], color: '#EF4444'),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    // Two visible series plus one invisible scale anchor.
    expect(radar.data.dataSets.length, 3);
    expect(radar.data.dataSets.first.dataEntries.map((e) => e.value), [
      3,
      4,
      5,
    ]);
    expect(radar.data.dataSets.last.fillColor, Colors.transparent);
    // The spoke labels are supplied through getTitle (canvas-painted).
    expect(radar.data.getTitle!(0, 0).text, 'Snelheid');
    expect(radar.data.getTitle!(2, 0).text, 'Uithouding');
    // The series legend is shown as real text widgets.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long radar labels stay outside the diagram and each other', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: [
        'Strategische wendbaarheid',
        'Operationele betrouwbaarheid',
        'Klantgerichte innovatie',
        'Duurzame inzetbaarheid',
        'Digitale volwassenheid',
        'Financiële weerbaarheid',
      ],
      series: [
        ChartSeries(name: 'Score', data: [3, 4, 5, 2, 4, 3]),
      ],
    );

    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump();

    // fl_chart draws the spider at 0.8 × half the (square) widget side; the
    // labels hug the polygon, so they may overlap the widget's corners but
    // must stay off the polygon itself (its apothem) and off each other.
    final radarRect = tester.getRect(find.byType(RadarChart));
    final center = radarRect.center;
    final radius = radarRect.width / 2 * 0.8;
    final apothem = radius * math.cos(math.pi / spec.x.length);
    double distanceToRect(Offset c, Rect r) {
      final nearest = Offset(
        c.dx.clamp(r.left, r.right),
        c.dy.clamp(r.top, r.bottom),
      );
      return (c - nearest).distance;
    }

    final labelRects = [
      for (var i = 0; i < spec.x.length; i++)
        tester.getRect(find.byKey(ValueKey('radar-axis-label-$i'))),
    ];
    for (final rect in labelRects) {
      expect(distanceToRect(center, rect), greaterThan(apothem * 0.98));
    }
    for (var i = 0; i < labelRects.length; i++) {
      for (var j = i + 1; j < labelRects.length; j++) {
        expect(labelRects[i].overlaps(labelRects[j]), isFalse);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('radar honours an explicit min/max scale with even ticks', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: ['A', 'B', 'C', 'D'],
      series: [
        ChartSeries(name: 'Score', data: [2, 4, 3, 5]),
      ],
      minBound: 0,
      maxBound: 10,
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    expect(radar.data.isMinValueAtCenter, isTrue);
    // The hidden anchor pins the scale to [0, 10].
    final anchor = radar.data.dataSets.last.dataEntries.map((e) => e.value);
    expect(anchor.reduce((a, b) => a < b ? a : b), 0);
    expect(anchor.reduce((a, b) => a > b ? a : b), 10);
    // The scale is shown in the side legend (0..10), not painted in the chart.
    expect(radar.data.ticksTextStyle?.color, Colors.transparent);
    expect(find.text('0'), findsWidgets);
    expect(find.text('10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('radar shows a tooltip for the hovered point', (tester) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: ['Snelheid', 'Kracht', 'Uithouding'],
      series: [
        ChartSeries(name: 'Alpha', data: [3, 4, 5]),
        ChartSeries(name: 'Beta', data: [5, 2, 3]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    final touch = radar.data.radarTouchData;
    expect(touch.enabled, isTrue);

    // Simulate hovering the second axis of the Beta series.
    final dataSet = radar.data.dataSets[1];
    final entry = dataSet.dataEntries[1];
    touch.touchCallback!(
      const FlPointerHoverEvent(PointerHoverEvent()),
      RadarTouchResponse(
        touchLocation: const Offset(20, 20),
        touchedSpot: RadarTouchedSpot(
          dataSet,
          1,
          entry,
          1,
          const FlSpot(1, 2),
          const Offset(20, 20),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Kracht\nBeta: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('radar ignores touches on the invisible scale anchor', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: ['A', 'B', 'C'],
      series: [
        ChartSeries(name: 'Alpha', data: [3, 4, 5]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final radar = tester.widget<RadarChart>(find.byType(RadarChart));
    final anchorIndex = radar.data.dataSets.length - 1; // the anchor dataset
    final anchor = radar.data.dataSets[anchorIndex];
    radar.data.radarTouchData.touchCallback!(
      const FlPointerHoverEvent(PointerHoverEvent()),
      RadarTouchResponse(
        touchLocation: Offset.zero,
        touchedSpot: RadarTouchedSpot(
          anchor,
          anchorIndex,
          anchor.dataEntries.first,
          0,
          const FlSpot(0, 0),
          Offset.zero,
        ),
      ),
    );
    await tester.pump();

    // No tooltip for the anchor: only the legend value "5" exists.
    expect(find.textContaining(': '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('radar chart asks for at least three labels', (tester) async {
    const spec = ChartSpec(
      type: ChartType.radar,
      x: ['Een', 'Twee'],
      series: [
        ChartSeries(name: 'Alpha', data: [3, 4]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(find.byType(RadarChart), findsNothing);
    expect(
      find.text('Een spider-diagram heeft minstens drie labels nodig'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('presentation mode enlarges chart labels', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['Categorie'],
      series: [
        ChartSeries(name: 'Waarde', data: [10]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    final normal = tester.widget<Text>(find.text('Categorie').first);
    final normalSize = normal.style!.fontSize!;
    expect(normalSize, lessThanOrEqualTo(12));

    await tester.pumpWidget(_host(spec, presentationMode: true));
    final presented = tester.widget<Text>(find.text('Categorie').first);
    expect(presented.style!.fontSize!, greaterThan(normalSize));
  });

  testWidgets('dense axis labels are thinned and stay inside the slide', (
    tester,
  ) async {
    const labels = [
      'Januari bijzonder lang',
      'Februari bijzonder lang',
      'Maart bijzonder lang',
      'April bijzonder lang',
      'Mei bijzonder lang',
      'Juni bijzonder lang',
      'Juli bijzonder lang',
      'Augustus bijzonder lang',
      'September bijzonder lang',
      'Oktober bijzonder lang',
      'November bijzonder lang',
      'December bijzonder lang',
    ];
    const spec = ChartSpec(
      type: ChartType.line,
      x: labels,
      series: [
        ChartSeries(
          name: 'Waarde',
          data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        ),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final visibleLabels = [
      for (final label in labels)
        if (find.text(label).evaluate().isNotEmpty) label,
    ];
    expect(visibleLabels.length, lessThanOrEqualTo(8));
    final slideRect = tester.getRect(find.byType(SlidePreviewWidget));
    for (final label in visibleLabels) {
      final rect = tester.getRect(find.text(label).first);
      expect(slideRect.contains(rect.topLeft), isTrue);
      expect(slideRect.contains(rect.bottomRight), isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('charts expose their data as a text alternative', (tester) async {
    final handle = tester.ensureSemantics();
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: '2026', data: [10, 14]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    // WCAG 1.1.1: the chart carries a label with type, title and values.
    expect(
      find.bySemanticsLabel('Grafiek (Staaf): Omzet. 2026: Q1 10, Q2 14'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('bar chart x-axis labels never run through each other', (
    tester,
  ) async {
    // Six groups: enough that the label slots are narrower than the clamp,
    // which used to overlap because the spacing was computed with n-1
    // intervals while bar groups each occupy a full nth of the axis.
    const labels = [
      'Strategische koers',
      'Operationele basis',
      'Innovatievermogen',
      'Mensen en cultuur',
      'Financiële ruimte',
      'Digitale veiligheid',
    ];
    const spec = ChartSpec(
      type: ChartType.bar,
      x: labels,
      series: [
        ChartSeries(name: 'Score', data: [3, 4, 5, 2, 4, 3]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final rects = [
      for (final label in labels)
        if (find.text(label).evaluate().isNotEmpty)
          tester.getRect(find.text(label).first),
    ];
    expect(rects.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pie shows at most two series and keeps labels inside the slide',
    (tester) async {
      const spec = ChartSpec(
        type: ChartType.pie,
        title: 'Veel gegevens',
        x: [
          'Een uitzonderlijk lang eerste label',
          'Een uitzonderlijk lang tweede label',
          'Een uitzonderlijk lang derde label',
          'Een uitzonderlijk lang vierde label',
          'Een uitzonderlijk lang vijfde label',
          'Een uitzonderlijk lang zesde label',
        ],
        series: [
          ChartSeries(name: 'Een', data: [1, 2, 3, 4, 5, 6]),
          ChartSeries(name: 'Twee', data: [2, 3, 4, 5, 6, 7]),
          ChartSeries(name: 'Drie', data: [3, 4, 5, 6, 7, 8]),
          ChartSeries(name: 'Vier', data: [4, 5, 6, 7, 8, 9]),
          ChartSeries(name: 'Vijf', data: [5, 6, 7, 8, 9, 10]),
          ChartSeries(name: 'Zes', data: [6, 7, 8, 9, 10, 11]),
        ],
      );

      await tester.pumpWidget(_host(spec));
      await tester.pump();

      expect(find.byType(PieChart), findsNWidgets(2));
      expect(find.text('Drie'), findsNothing);
      final legendTop = tester.getTopLeft(find.text(spec.x.first)).dy;
      for (final chart in tester.widgetList<PieChart>(find.byType(PieChart))) {
        final box = tester.renderObject<RenderBox>(find.byWidget(chart));
        final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
        expect(bottom, lessThanOrEqualTo(legendTop));
      }
      final slideRect = tester.getRect(find.byType(SlidePreviewWidget));
      for (final label in spec.x) {
        final rect = tester.getRect(find.text(label));
        expect(slideRect.contains(rect.topLeft), isTrue);
        expect(slideRect.contains(rect.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stacked bar stacks series vertically in one rod per group', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.stackedBar,
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: 'A', data: [3, 5]),
        ChartSeries(name: 'B', data: [2, 1]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final bar = tester.widget<BarChart>(find.byType(BarChart));
    // Stacking = one rod per group with a stack item per series — NOT several
    // side-by-side rods (which would be grouping).
    for (final group in bar.data.barGroups) {
      expect(group.barRods, hasLength(1));
      expect(group.barRods.single.rodStackItems, hasLength(2));
    }

    // Q1 stacks 3 then 2 → contiguous segments [0,3] and [3,5], total 5.
    final q1 = bar.data.barGroups.first.barRods.single;
    expect(q1.toY, 5);
    expect(q1.rodStackItems[0].fromY, 0);
    expect(q1.rodStackItems[0].toY, 3);
    expect(q1.rodStackItems[1].fromY, 3);
    expect(q1.rodStackItems[1].toY, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('area chart draws a filled line', (tester) async {
    const spec = ChartSpec(
      type: ChartType.area,
      title: 'Trend',
      x: ['Q1', 'Q2', 'Q3'],
      series: [
        ChartSeries(name: '2026', data: [10, 14, 12]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final line = tester.widget<LineChart>(find.byType(LineChart));
    expect(line.data.lineBarsData.single.belowBarData.show, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('donut shows the series total in the centre hole', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.donut,
      title: 'Verdeling',
      x: ['A', 'B', 'C'],
      series: [
        ChartSeries(name: 'Aandeel', data: [20, 30, 50]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(find.byType(PieChart), findsOneWidget);
    // 20 + 30 + 50 = 100, printed in the hole.
    expect(find.text('100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal bar renders category and value labels', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.horizontalBar,
      title: 'Ranglijst',
      x: ['Alpha', 'Beta'],
      series: [
        ChartSeries(name: 'Score', data: [8, 12]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal stacked bar renders category and segment labels', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.horizontalStackedBar,
      title: 'Verdeling',
      x: ['Alpha', 'Beta'],
      series: [
        ChartSeries(name: 'A', data: [6, 8]),
        ChartSeries(name: 'B', data: [4, 3]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();
    // The custom (hand-drawn) chart settles its entrance tween before the
    // segment value labels appear.
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // Each series is one segment across both bars; a wide segment prints its
    // value.
    expect(find.text('6'), findsWidgets);
    expect(find.text('8'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'combo overlays a line over the bars, degrades below two series',
    (tester) async {
      const combo = ChartSpec(
        type: ChartType.combo,
        title: 'Omzet en groei',
        x: ['Q1', 'Q2', 'Q3'],
        series: [
          ChartSeries(name: 'Omzet', data: [10, 14, 12]),
          ChartSeries(name: 'Groei %', data: [3, 8, 5]),
        ],
      );

      await tester.pumpWidget(_host(combo));
      await tester.pump();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(tester.takeException(), isNull);

      // One series → falls back to a plain bar chart (no line layer).
      const single = ChartSpec(
        type: ChartType.combo,
        x: ['Q1', 'Q2'],
        series: [
          ChartSeries(name: 'Omzet', data: [10, 14]),
        ],
      );
      await tester.pumpWidget(_host(single));
      await tester.pump();
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('waterfall floats each step from the running total', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.waterfall,
      title: 'Brug',
      x: ['Start', 'Erbij', 'Eraf'],
      series: [
        ChartSeries(name: 'Stap', data: [100, 20, -30]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final bar = tester.widget<BarChart>(find.byType(BarChart));
    // Cumulative: 0→100, 100→120, 120→90. Each rod floats between the two.
    final rods = [for (final g in bar.data.barGroups) g.barRods.single];
    expect(rods[0].fromY, 0);
    expect(rods[0].toY, 100);
    expect(rods[1].fromY, 100);
    expect(rods[1].toY, 120);
    expect(rods[2].fromY, 90);
    expect(rods[2].toY, 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heatmap renders every cell value and its column labels', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.heatmap,
      title: 'Risico',
      x: ['Laag', 'Hoog'],
      series: [
        ChartSeries(name: 'Kans A', data: [1, 4]),
        ChartSeries(name: 'Kans B', data: [2, 9]),
      ],
    );

    await tester.pumpWidget(_host(spec));
    await tester.pump();

    expect(find.text('Kans A'), findsOneWidget);
    expect(find.text('Kans B'), findsOneWidget);
    expect(find.text('Laag'), findsOneWidget);
    expect(find.text('Hoog'), findsOneWidget);
    // '4' is a cell value that isn't also a scale bound (min 1, max 9).
    expect(find.text('4'), findsOneWidget);
    // '9' is both the top cell and the scale maximum.
    expect(find.text('9'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new chart types animate in presentation mode without error', (
    tester,
  ) async {
    for (final type in [
      ChartType.area,
      ChartType.donut,
      ChartType.horizontalBar,
      ChartType.combo,
      ChartType.waterfall,
      ChartType.heatmap,
      ChartType.horizontalStackedBar,
    ]) {
      final spec = ChartSpec(
        type: type,
        title: 'Test',
        x: const ['A', 'B', 'C'],
        series: const [
          ChartSeries(name: 'Een', data: [3, 6, 4]),
          ChartSeries(name: 'Twee', data: [5, 2, 8]),
        ],
      );
      await tester.pumpWidget(_host(spec, presentationMode: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$type threw');
    }
  });

  // ── Hover tooltips for the previously silent chart types (issue #1281) ─────
  // fl_chart types: call the tooltip callback directly on the widget data.

  testWidgets('scatter hover tooltip shows the label and value', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.scatter,
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: 'Meting', data: [3, 7]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final chart = tester.widget<ScatterChart>(find.byType(ScatterChart));
    expect(chart.data.scatterTouchData.enabled, isTrue);
    final spot = chart.data.scatterSpots[1];
    final item = chart.data.scatterTouchData.touchTooltipData.getTooltipItems(
      spot,
    );
    expect(item?.text, 'Q2\nMeting: 7');
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacked bar hover tooltip lists every segment value', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.stackedBar,
      x: ['Q1'],
      series: [
        ChartSeries(name: 'A', data: [3]),
        ChartSeries(name: 'B', data: [2]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final bar = tester.widget<BarChart>(find.byType(BarChart));
    expect(bar.data.barTouchData.enabled, isTrue);
    final group = bar.data.barGroups.single;
    final item = bar.data.barTouchData.touchTooltipData.getTooltipItem(
      group,
      0,
      group.barRods.single,
      0,
    );
    expect(item?.text, 'Q1\nA: 3\nB: 2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('waterfall hover tooltip shows each step delta with its sign', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.waterfall,
      x: ['Start', 'Erbij', 'Eraf'],
      series: [
        ChartSeries(name: 'Stap', data: [100, 20, -30]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final bar = tester.widget<BarChart>(find.byType(BarChart));
    expect(bar.data.barTouchData.enabled, isTrue);
    final groups = bar.data.barGroups;
    final tt = bar.data.barTouchData.touchTooltipData;
    // The rod's from/to are min/max, so a fall would lose its sign; the tooltip
    // reads the signed delta instead.
    expect(
      tt.getTooltipItem(groups[1], 1, groups[1].barRods.single, 0)?.text,
      'Erbij\n20',
    );
    expect(
      tt.getTooltipItem(groups[2], 2, groups[2].barRods.single, 0)?.text,
      'Eraf\n-30',
    );
    expect(tester.takeException(), isNull);
  });

  // Custom-overlay types: simulate a mouse hover and read the floating tooltip.

  testWidgets('combo hover overlay shows the column values', (tester) async {
    const spec = ChartSpec(
      type: ChartType.combo,
      x: ['Q1', 'Q2', 'Q3'],
      series: [
        ChartSeries(name: 'Omzet', data: [10, 14, 12]),
        ChartSeries(name: 'Groei', data: [3, 8, 5]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(LineChart)));
    await tester.pump();

    expect(find.byKey(const ValueKey('cell-hover-tooltip')), findsOneWidget);
    final tip = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('cell-hover-tooltip')),
        matching: find.byType(Text),
      ),
    );
    // The centre column maps to Q2: both the bar and the line value are shown.
    expect(tip.data, contains('Omzet'));
    expect(tip.data, contains('Groei'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal bar hover overlay shows the label and value', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.horizontalBar,
      x: ['Alpha', 'Beta'],
      series: [
        ChartSeries(name: 'Score', data: [8, 12]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('hbar-cell-1-0'))),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('cell-hover-tooltip')), findsOneWidget);
    expect(find.text('Beta\nScore: 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal stacked bar hover overlay shows the segment value', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.horizontalStackedBar,
      x: ['Alpha', 'Beta'],
      series: [
        ChartSeries(name: 'A', data: [6, 8]),
        ChartSeries(name: 'B', data: [4, 3]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('hstack-seg-0-0'))),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('cell-hover-tooltip')), findsOneWidget);
    expect(find.text('Alpha\nA: 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bullet hover overlay shows the label and value', (tester) async {
    const spec = ChartSpec(
      type: ChartType.bullet,
      x: ['SLA'],
      series: [
        ChartSeries(name: 'Werkelijk', data: [80]),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('bullet-cell-0'))),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('cell-hover-tooltip')), findsOneWidget);
    expect(find.text('SLA\n80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
