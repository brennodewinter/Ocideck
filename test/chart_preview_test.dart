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
}
