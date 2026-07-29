import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/services/improvement/chart_derivation.dart';
import 'package:ocideck/services/improvement/stats/stats.dart';
import 'package:ocideck/services/scene/scene.dart';

void main() {
  group('chart derivation', () {
    ChartSpec sample(ChartType type, List<double> data) => ChartSpec(
      type: type,
      x: [for (var i = 0; i < data.length; i++) '${i + 1}'],
      series: [ChartSeries(name: 'Y', data: data)],
    );

    test('I-MR derives limits and never needs stored UCL', () {
      final view = deriveIndividualsChart(
        sample(ChartType.controlChart, [
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
        ]),
      );
      expect(view, isNotNull);
      expect(view!.ucl, greaterThan(view.center));
      expect(view.lcl, lessThan(view.center));
    });

    test('Pareto sorts descending and marks vital few', () {
      final view = derivePareto(
        ChartSpec(
          type: ChartType.pareto,
          x: const ['A', 'B', 'C', 'D'],
          series: const [
            ChartSeries(name: 'n', data: [5, 40, 10, 20]),
          ],
        ),
      );
      expect(view, isNotNull);
      expect(view!.labels.first, 'B');
      expect(view.vitalFewCount, greaterThan(0));
      expect(view.cumulativePct.last, closeTo(100, 0.01));
    });

    test('histogram bins and optional Cpk', () {
      final data = [for (var i = 0; i < 30; i++) 10.0 + (i % 5) * 0.2];
      final view = deriveHistogram(
        ChartSpec(
          type: ChartType.histogram,
          x: [for (var i = 0; i < data.length; i++) '$i'],
          series: [ChartSeries(name: 'Y', data: data)],
          usl: 12,
          lsl: 9,
        ),
      );
      expect(view, isNotNull);
      expect(view!.counts.reduce((a, b) => a + b), data.length);
    });

    test('yRef Y-01 ignores local spec limits for Cpk', () {
      final data = [for (var i = 0; i < 30; i++) 10.0 + (i % 5) * 0.2];
      const y01 = ImprovementY01Metric(usl: 11.5, lsl: 9.5);
      final yRefView = deriveHistogram(
        ChartSpec(
          type: ChartType.histogram,
          yRef: 'Y-01',
          usl: 99,
          lsl: 1,
          x: [for (var i = 0; i < data.length; i++) '$i'],
          series: [ChartSeries(name: 'Y', data: data)],
        ),
        y01: y01,
      );
      final localView = deriveHistogram(
        ChartSpec(
          type: ChartType.histogram,
          usl: 99,
          lsl: 1,
          x: [for (var i = 0; i < data.length; i++) '$i'],
          series: [ChartSeries(name: 'Y', data: data)],
        ),
      );
      expect(yRefView!.cpk, isNot(localView!.cpk));
    });

    test('control limits are absent from ChartSpec.toBlock', () {
      final block = sample(ChartType.controlChart, [1, 2, 3, 4, 5]).toBlock();
      expect(block.contains('ucl'), isFalse);
      expect(block.contains('lcl'), isFalse);
      expect(block.contains('controlChart'), isTrue);
    });

    test('box plot needs at least four points', () {
      expect(deriveBoxPlot(sample(ChartType.boxPlot, [1, 2, 3])), isNull);
      expect(
        deriveBoxPlot(sample(ChartType.boxPlot, [1, 2, 3, 4, 5, 6, 7])),
        isNotNull,
      );
    });

    test('probability plot stores no derived quantiles in ChartSpec', () {
      final block = sample(ChartType.probabilityPlot, [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]).toBlock();
      expect(block.contains('quantile'), isFalse);
      expect(block.contains('probabilityPlot'), isTrue);
    });

    ChartSpec twoThreeFactorial({required ChartType type}) {
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

    test('DOE grid parses a 2^3 design and derives main effects', () {
      final spec = twoThreeFactorial(type: ChartType.mainEffects);
      expect(parseDoeChartGrid(spec), isNotNull);
      final view = deriveMainEffects(spec);
      expect(view, isNotNull);
      expect(view!.lines, hasLength(3));
      expect(view.lines[0].high - view.lines[0].low, closeTo(4, 0.01));
      expect(view.lines[1].high - view.lines[1].low, closeTo(6, 0.01));
      expect(view.lines[2].high - view.lines[2].low, closeTo(2, 0.01));
    });

    test('interaction plot lists two-factor panels', () {
      final view = deriveInteraction(
        twoThreeFactorial(type: ChartType.interaction),
      );
      expect(view, isNotNull);
      expect(view!.panels, hasLength(3));
      expect(view.panels.first.lines, hasLength(2));
    });

    test('generateDoeDesignGrid fills coded factors and empty Y', () {
      final grid = generateDoeDesignGrid(factorCount: 3, fractional: false);
      expect(grid, isNotNull);
      expect(grid!.xLabels, hasLength(8));
      expect(grid.seriesNames, ['A', 'B', 'C', 'Y']);
      expect(grid.cellValues.every((row) => row.last.isEmpty), isTrue);
    });

    test('main effects are absent from ChartSpec.toBlock', () {
      final block = twoThreeFactorial(type: ChartType.mainEffects).toBlock();
      expect(block.contains('effect'), isFalse);
      expect(block.contains('mainEffects'), isTrue);
    });
  });

  group('scene', () {
    test('demo scene serialises to SVG with nodes', () {
      final svg = sceneToSvg(Scene.demo());
      expect(svg, contains('<svg'));
      expect(svg, contains('<rect'));
      expect(svg, contains('<text'));
      expect(svg, contains('demo'));
    });

    test('ApproximateTextMeasurer scales with font size', () {
      const m = ApproximateTextMeasurer();
      expect(
        m.widthOf('abc', fontSize: 20),
        greaterThan(m.widthOf('ab', fontSize: 20)),
      );
      expect(m.lineHeight(fontSize: 16), greaterThan(16));
    });
  });
}
