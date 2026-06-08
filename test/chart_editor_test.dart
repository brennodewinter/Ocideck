import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/chart_editor.dart';

Widget _host(Slide slide, ValueChanged<Slide> onUpdate) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 650,
        child: ChartEditor(slide: slide, onUpdate: onUpdate),
      ),
    ),
  );
}

void main() {
  testWidgets('chart grid fills the available editor width', (tester) async {
    const spec = ChartSpec(
      x: ['A', 'B'],
      series: [
        ChartSeries(name: 'Waarde', data: [10, 20]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    final gridWidth = tester
        .getSize(find.byKey(const ValueKey('chart-grid')))
        .width;
    expect(gridWidth, greaterThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving a row keeps its values and color together', (
    tester,
  ) async {
    const spec = ChartSpec(
      x: ['B', 'A'],
      rowColors: ['#EF4444', '#10B981'],
      series: [
        ChartSeries(name: 'Waarde', data: [20, 10]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.tap(find.byKey(const ValueKey('chart-row-up-1')));
    await tester.pump();

    final result = ChartSpec.parse(updated.customMarkdown);
    expect(result.x, ['A', 'B']);
    expect(result.rowColors, ['#10B981', '#EF4444']);
    expect(result.series.single.data, [10, 20]);
  });

  testWidgets('sorting a value column moves complete rows', (tester) async {
    const spec = ChartSpec(
      x: ['A', 'B', 'C'],
      rowColors: ['#003399', '#FFCC00', '#EF4444'],
      series: [
        ChartSeries(name: 'Waarde', data: [30, 10, 20]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.tap(find.byKey(const ValueKey('chart-sort-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oplopend sorteren'));
    await tester.pump();

    final result = ChartSpec.parse(updated.customMarkdown);
    expect(result.x, ['B', 'C', 'A']);
    expect(result.rowColors, ['#FFCC00', '#EF4444', '#003399']);
    expect(result.series.single.data, [10, 20, 30]);
  });

  testWidgets('pie dims the third series without disabling its input', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      x: ['A'],
      series: [
        ChartSeries(name: 'Een', data: [1]),
        ChartSeries(name: 'Twee', data: [2]),
        ChartSeries(name: 'Drie', data: [3]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    final column = tester.widget<Container>(
      find.byKey(const ValueKey('chart-series-column-2')),
    );
    expect(column.color, const Color(0xFFE2E8F0));
    final input = tester.widget<TextFormField>(
      find.byKey(const ValueKey('v-0-0-2')),
    );
    expect(input.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bound fields are offered for bar/line and emit min/max', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      x: ['A'],
      series: [
        ChartSeries(name: 'Waarde', data: [10]),
      ],
    );
    var updated = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(updated, (slide) => updated = slide));
    await tester.pump();

    expect(find.byKey(const ValueKey('chart-min-bound')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-max-bound')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('chart-max-bound')),
      '20',
    );
    await tester.pump();

    expect(ChartSpec.parse(updated.customMarkdown).maxBound, 20);
  });

  testWidgets('bound fields are hidden for a pie chart', (tester) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      x: ['A'],
      series: [
        ChartSeries(name: 'Een', data: [1]),
      ],
    );
    final slide = Slide.create(
      SlideType.chart,
    ).copyWith(customMarkdown: spec.toBlock());

    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pump();

    expect(find.byKey(const ValueKey('chart-min-bound')), findsNothing);
    expect(find.byKey(const ValueKey('chart-max-bound')), findsNothing);
  });
}
