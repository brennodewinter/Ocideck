import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/services/improvement/chart_derivation.dart';
import 'package:ocideck/services/improvement/improvement_analysis_helpers.dart';

void main() {
  group('probability plot derivation', () {
    ChartSpec sample(List<double> data) => ChartSpec(
      type: ChartType.probabilityPlot,
      x: [for (var i = 0; i < data.length; i++) '${i + 1}'],
      series: [ChartSeries(name: 'Y', data: data)],
    );

    test('needs at least four points', () {
      expect(deriveProbabilityPlot(sample([1, 2, 3])), isNull);
      expect(
        deriveProbabilityPlot(sample([3, 1, 4, 2, 5, 6, 7, 8])),
        isNotNull,
      );
    });

    test('sorts values and pairs with theoretical quantiles', () {
      final view = deriveProbabilityPlot(sample([5, 1, 3, 2, 4, 6, 7, 8]));
      expect(view, isNotNull);
      expect(view!.sortedValues, orderedEquals([1, 2, 3, 4, 5, 6, 7, 8]));
      expect(view.theoreticalQuantiles.length, 8);
      expect(view.normalityPValue, isNotNull);
    });
  });

  group('parseNumberColumn', () {
    test('reads lines and separators', () {
      expect(parseNumberColumn('1\n2,3;4\t5'), [1, 2, 3, 4, 5]);
    });
  });

  group('Gage R&R helpers', () {
    const table = '''
Part\tOperator\tValue
P1\tA\t1
P1\tA\t2
P1\tB\t3
P1\tB\t4
P2\tA\t5
P2\tA\t6
P2\tB\t7
P2\tB\t8
''';

    test('parseGageRrTable nests balanced data', () {
      final nested = parseGageRrTable(table);
      expect(nested, isNotNull);
      expect(nested!.length, 2);
      expect(nested.first.length, 2);
      expect(nested.first.first, [1, 2]);
    });

    test('runGageRrAnalysis returns %study variation and ndc', () {
      final nested = parseGageRrTable(table)!;
      final outcome = runGageRrAnalysis(nested, tolerance: 20);
      expect(outcome.refusal, isNull);
      expect(outcome.result!.percentStudyVariation, greaterThan(0));
      expect(outcome.result!.distinctCategories, greaterThan(0));
    });

    test('gageRrFromChartGrid groups duplicate part rows as replicates', () {
      final nested = gageRrFromChartGrid(
        partLabels: const ['P1', 'P1', 'P2', 'P2'],
        operatorNames: const ['A', 'B'],
        cellValues: const [
          ['1', '3'],
          ['2', '4'],
          ['5', '7'],
          ['6', '8'],
        ],
      );
      expect(nested, isNotNull);
      expect(runGageRrAnalysis(nested!).result, isNotNull);
    });
  });

  group('inference helpers', () {
    test('one-sample t refuses n < 2', () {
      final outcome = runInferenceAnalysis(
        kind: InferenceTestKind.oneSampleT,
        dataRaw: '5',
      );
      expect(outcome.result, isNull);
      expect(outcome.refusal, contains('StatsRefusal'));
    });

    test('two-sample t needs two blocks', () {
      final outcome = runInferenceAnalysis(
        kind: InferenceTestKind.twoSampleT,
        dataRaw: '1\n2\n3',
      );
      expect(outcome.result, isNull);
    });

    test('one-way ANOVA runs on grouped blocks', () {
      final outcome = runInferenceAnalysis(
        kind: InferenceTestKind.oneWayAnova,
        dataRaw: '1\n2\n3\n\n4\n5\n6',
      );
      expect(outcome.result, isNotNull);
      expect(outcome.result!.pValue, inInclusiveRange(0, 1));
    });
  });

  group('regression helpers', () {
    test('simple line returns slope and R²', () {
      final outcome = runRegressionAnalysis(
        xRaw: '1\n2\n3\n4',
        yRaw: '2\n4\n6\n8',
      );
      expect(outcome.refusal, isNull);
      expect(outcome.result!.slope, closeTo(2, 1e-9));
      expect(outcome.result!.rSquared, closeTo(1, 1e-9));
    });

    test('refuses mismatched columns', () {
      final outcome = runRegressionAnalysis(xRaw: '1\n2', yRaw: '1');
      expect(outcome.result, isNull);
    });
  });
}
