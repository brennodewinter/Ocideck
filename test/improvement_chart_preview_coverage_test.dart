import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(ChartSpec spec) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(
              SlideType.chart,
            ).copyWith(customMarkdown: spec.toBlock()),
          ),
        ),
      ),
    ),
  );
}

ChartSpec _sample(
  ChartType type,
  List<double> data, {
  double? usl,
  double? lsl,
}) => ChartSpec(
  type: type,
  title: type.name,
  x: [for (var i = 0; i < data.length; i++) '${i + 1}'],
  series: [ChartSeries(name: 'Y', data: data)],
  usl: usl,
  lsl: lsl,
);

ChartSpec _doe(ChartType type) {
  final design = FactorialDesign.full(const [
    DesignFactor('A'),
    DesignFactor('B'),
    DesignFactor('C'),
  ]);
  final responses = <double>[
    for (final p in design.points)
      (10 + 2 * p[0] + 3 * p[1] + 1 * p[2]).toDouble(),
  ];
  return ChartSpec(
    type: type,
    title: type.name,
    x: [for (var i = 0; i < design.pointCount; i++) '${i + 1}'],
    series: [
      ChartSeries(
        name: 'A',
        data: [for (final p in design.points) p[0].toDouble()],
      ),
      ChartSeries(
        name: 'B',
        data: [for (final p in design.points) p[1].toDouble()],
      ),
      ChartSeries(
        name: 'C',
        data: [for (final p in design.points) p[2].toDouble()],
      ),
      ChartSeries(name: 'Y', data: responses),
    ],
  );
}

Future<void> _pumpSpec(WidgetTester tester, ChartSpec spec) async {
  await tester.pumpWidget(_host(spec));
  // Grow animation for CustomPaint painters.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('control chart paints with enough points', (tester) async {
    await _pumpSpec(
      tester,
      _sample(ChartType.controlChart, [
        10,
        11,
        9.5,
        10.2,
        10.1,
        9.8,
        10.4,
        10.0,
        9.9,
        10.3,
        12.5,
        10.1,
      ]),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('control chart placeholder when too few points', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.controlChart, [1]));
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });

  testWidgets('histogram with USL/LSL paints', (tester) async {
    final data = [for (var i = 0; i < 30; i++) 10.0 + (i % 5) * 0.2];
    await _pumpSpec(
      tester,
      _sample(ChartType.histogram, data, usl: 12, lsl: 9),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('histogram placeholder', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.histogram, [1]));
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });

  testWidgets('pareto paints', (tester) async {
    await _pumpSpec(
      tester,
      const ChartSpec(
        type: ChartType.pareto,
        title: 'Pareto',
        x: ['A', 'B', 'C', 'D'],
        series: [
          ChartSeries(name: 'n', data: [5, 40, 10, 20]),
        ],
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pareto placeholder', (tester) async {
    await _pumpSpec(
      tester,
      const ChartSpec(type: ChartType.pareto, title: 'empty'),
    );
    expect(find.textContaining('Geen grafiekgegevens'), findsOneWidget);
  });

  testWidgets('run chart paints', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.runChart, [1, 2, 3, 4, 5, 4, 3]));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('run chart placeholder', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.runChart, [1]));
    expect(find.textContaining('Geen grafiekgegevens'), findsOneWidget);
  });

  testWidgets('box plot paints', (tester) async {
    await _pumpSpec(
      tester,
      _sample(ChartType.boxPlot, [1, 2, 3, 4, 5, 6, 7, 8, 9]),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('box plot placeholder', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.boxPlot, [1, 2, 3]));
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });

  testWidgets('probability plot paints', (tester) async {
    await _pumpSpec(
      tester,
      _sample(ChartType.probabilityPlot, [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      ]),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('probability plot placeholder', (tester) async {
    await _pumpSpec(tester, _sample(ChartType.probabilityPlot, [1]));
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });

  testWidgets('main effects paints', (tester) async {
    await _pumpSpec(tester, _doe(ChartType.mainEffects));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main effects placeholder with too-thin DOE grid', (
    tester,
  ) async {
    // hasInlineData must be true or the outer chart preview shows the generic
    // empty placeholder and never reaches the improvement painter branch.
    await _pumpSpec(
      tester,
      const ChartSpec(
        type: ChartType.mainEffects,
        title: 'thin',
        x: ['1'],
        series: [
          ChartSeries(name: 'Y', data: [1]),
        ],
      ),
    );
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });

  testWidgets('interaction paints', (tester) async {
    await _pumpSpec(tester, _doe(ChartType.interaction));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interaction placeholder with too-thin DOE grid', (tester) async {
    await _pumpSpec(
      tester,
      const ChartSpec(
        type: ChartType.interaction,
        title: 'thin',
        x: ['1'],
        series: [
          ChartSeries(name: 'Y', data: [1]),
        ],
      ),
    );
    expect(find.textContaining('Te weinig gegevens'), findsOneWidget);
  });
}
