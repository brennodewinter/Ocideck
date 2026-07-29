part of 'stats.dart';

// Measurement systems analysis: Gage R&R by the ANOVA method.
//
// The ANOVA method and not the average-and-range method, which is the one most
// spreadsheets implement. Average-and-range cannot separate the
// operator-by-part interaction from anything else, so a gauge that only some
// operators read badly on a few parts looks fine. It also has no significance
// test to offer. The arithmetic here is longer; the answer is the one that can
// be defended.

/// One line of the Gage R&R ANOVA table.
class VarianceComponent {
  const VarianceComponent({
    required this.name,
    required this.sumOfSquares,
    required this.degreesOfFreedom,
  });

  final String name;
  final double sumOfSquares;
  final double degreesOfFreedom;

  double get meanSquare => sumOfSquares / degreesOfFreedom;
}

/// A crossed Gage R&R study: every operator measures every part, more than
/// once.
class GageRr {
  const GageRr._({
    required this.partCount,
    required this.operatorCount,
    required this.replicateCount,
    required this.table,
    required this.interactionPValue,
    required this.interactionPooled,
    required this.repeatabilityVariance,
    required this.operatorVariance,
    required this.interactionVariance,
    required this.partVariance,
    required this.tolerance,
  });

  /// Analyses [measurements], indexed `[part][operator][replicate]`.
  ///
  /// [interactionPoolingThreshold] follows the usual practice: when the
  /// operator-by-part interaction is not significant at this level it is
  /// pooled into repeatability, because estimating a term that is not there
  /// costs degrees of freedom and can drive a variance component negative.
  /// The result records whether the pooling happened, so a reader is never
  /// left guessing which model produced the number.
  static GageRr crossed(
    List<List<List<double>>> measurements, {
    double? tolerance,
    double interactionPoolingThreshold = 0.25,
  }) {
    const String what = 'Gage R&R';
    _requireAtLeast(what, 'parts', measurements.length, 2);
    final int parts = measurements.length;
    final int operators = measurements.first.length;
    _requireAtLeast(what, 'operators', operators, 2);
    final int replicates = measurements.first.first.length;
    _requireAtLeast(
      what,
      'measurements of each part by each operator',
      replicates,
      2,
    );

    for (final List<List<double>> part in measurements) {
      if (part.length != operators) {
        throw StatsRefusal(
          what,
          'not every part was measured by all $operators operator(s); a '
          'crossed study has to be balanced',
        );
      }
      for (final List<double> cell in part) {
        if (cell.length != replicates) {
          throw StatsRefusal(
            what,
            'not every operator/part pair has $replicates measurement(s); a '
            'crossed study has to be balanced',
          );
        }
      }
    }

    final _GageSums sums = _GageSums.of(
      measurements,
      parts,
      operators,
      replicates,
    );
    final List<VarianceComponent> table = <VarianceComponent>[
      VarianceComponent(
        name: 'Part',
        sumOfSquares: sums.partSs,
        degreesOfFreedom: (parts - 1).toDouble(),
      ),
      VarianceComponent(
        name: 'Operator',
        sumOfSquares: sums.operatorSs,
        degreesOfFreedom: (operators - 1).toDouble(),
      ),
      VarianceComponent(
        name: 'Part × Operator',
        sumOfSquares: sums.interactionSs,
        degreesOfFreedom: ((parts - 1) * (operators - 1)).toDouble(),
      ),
      VarianceComponent(
        name: 'Repeatability',
        sumOfSquares: sums.errorSs,
        degreesOfFreedom: (parts * operators * (replicates - 1)).toDouble(),
      ),
    ];

    final VarianceComponent interaction = table[2];
    final VarianceComponent error = table[3];
    final double interactionP = error.meanSquare <= 0
        ? 1
        : FDistribution(
            interaction.degreesOfFreedom,
            error.degreesOfFreedom,
          ).survival(interaction.meanSquare / error.meanSquare);
    final bool pool = interactionP > interactionPoolingThreshold;

    final double repeatability;
    final double interactionVariance;
    final double residualMeanSquare;
    if (pool) {
      residualMeanSquare =
          (interaction.sumOfSquares + error.sumOfSquares) /
          (interaction.degreesOfFreedom + error.degreesOfFreedom);
      repeatability = residualMeanSquare;
      interactionVariance = 0;
    } else {
      residualMeanSquare = interaction.meanSquare;
      repeatability = error.meanSquare;
      interactionVariance = math.max(
        0,
        (interaction.meanSquare - error.meanSquare) / replicates,
      );
    }

    return GageRr._(
      partCount: parts,
      operatorCount: operators,
      replicateCount: replicates,
      table: List<VarianceComponent>.unmodifiable(table),
      interactionPValue: interactionP,
      interactionPooled: pool,
      repeatabilityVariance: repeatability,
      operatorVariance: math.max(
        0,
        (table[1].meanSquare - residualMeanSquare) / (parts * replicates),
      ),
      interactionVariance: interactionVariance,
      partVariance: math.max(
        0,
        (table[0].meanSquare - residualMeanSquare) / (operators * replicates),
      ),
      tolerance: tolerance,
    );
  }

  final int partCount;
  final int operatorCount;
  final int replicateCount;

  /// The ANOVA table, in the order Part, Operator, Part × Operator,
  /// Repeatability.
  final List<VarianceComponent> table;

  /// p-value of the operator-by-part interaction, from the full model.
  final double interactionPValue;

  /// Whether the interaction was pooled into repeatability.
  final bool interactionPooled;

  /// σ² of the gauge itself, measuring the same thing twice.
  final double repeatabilityVariance;

  /// σ² between operators.
  final double operatorVariance;

  /// σ² of the operator-by-part interaction; zero when pooled.
  final double interactionVariance;

  /// σ² between the parts — the variation the study is trying to see.
  final double partVariance;

  /// The specification width, if the study was given one.
  final double? tolerance;

  /// σ² of everything that is not the part: operator plus interaction.
  double get reproducibilityVariance => operatorVariance + interactionVariance;

  /// σ² of the measurement system as a whole.
  double get gageVariance => repeatabilityVariance + reproducibilityVariance;

  /// σ² of part and measurement system together.
  double get totalVariance => gageVariance + partVariance;

  double get repeatabilitySd => math.sqrt(repeatabilityVariance);
  double get reproducibilitySd => math.sqrt(reproducibilityVariance);
  double get gageSd => math.sqrt(gageVariance);
  double get partSd => math.sqrt(partVariance);
  double get totalSd => math.sqrt(totalVariance);

  /// The share of the *variance* the measurement system accounts for.
  double get percentContribution => 100 * gageVariance / totalVariance;

  /// The share of the *study variation* — standard deviations, not variances —
  /// the measurement system accounts for.
  ///
  /// This is the figure the AIAG rule of thumb is stated against (under 10%
  /// acceptable, 10–30% conditionally, over 30% unacceptable) and it is always
  /// the larger of the two percentages, because a ratio of standard deviations
  /// beneath one exceeds the ratio of their squares. Quoting
  /// [percentContribution] against the same thresholds is the standard way to
  /// make a bad gauge look adequate.
  double get percentStudyVariation => 100 * gageSd / totalSd;

  /// The gauge against the specification width, when one was given.
  double? get percentTolerance {
    final double? t = tolerance;
    return t == null || t <= 0 ? null : 100 * 6 * gageSd / t;
  }

  /// The number of distinct categories the gauge can tell apart across the
  /// range of the parts. Below two the gauge can only sort into "high" and
  /// "low"; five or more is the usual requirement.
  int get distinctCategories =>
      gageSd <= 0 ? 0 : (1.41 * partSd / gageSd).floor();
}

/// The four sums of squares of the crossed two-way layout.
class _GageSums {
  const _GageSums({
    required this.partSs,
    required this.operatorSs,
    required this.interactionSs,
    required this.errorSs,
  });

  factory _GageSums.of(
    List<List<List<double>>> data,
    int parts,
    int operators,
    int replicates,
  ) {
    final List<double> partMeans = List<double>.filled(parts, 0);
    final List<double> operatorMeans = List<double>.filled(operators, 0);
    final List<List<double>> cellMeans = <List<double>>[
      for (int i = 0; i < parts; i++) List<double>.filled(operators, 0),
    ];
    double grandSum = 0;
    double errorSs = 0;

    for (int i = 0; i < parts; i++) {
      for (int j = 0; j < operators; j++) {
        double cellSum = 0;
        for (final double x in data[i][j]) {
          cellSum += x;
        }
        final double cellMean = cellSum / replicates;
        cellMeans[i][j] = cellMean;
        for (final double x in data[i][j]) {
          errorSs += (x - cellMean) * (x - cellMean);
        }
        partMeans[i] += cellSum;
        operatorMeans[j] += cellSum;
        grandSum += cellSum;
      }
    }
    for (int i = 0; i < parts; i++) {
      partMeans[i] /= operators * replicates;
    }
    for (int j = 0; j < operators; j++) {
      operatorMeans[j] /= parts * replicates;
    }
    final double grandMean = grandSum / (parts * operators * replicates);

    double partSs = 0;
    for (final double m in partMeans) {
      partSs += (m - grandMean) * (m - grandMean);
    }
    partSs *= operators * replicates;

    double operatorSs = 0;
    for (final double m in operatorMeans) {
      operatorSs += (m - grandMean) * (m - grandMean);
    }
    operatorSs *= parts * replicates;

    double interactionSs = 0;
    for (int i = 0; i < parts; i++) {
      for (int j = 0; j < operators; j++) {
        final double effect =
            cellMeans[i][j] - partMeans[i] - operatorMeans[j] + grandMean;
        interactionSs += effect * effect;
      }
    }
    interactionSs *= replicates;

    return _GageSums(
      partSs: partSs,
      operatorSs: operatorSs,
      interactionSs: interactionSs,
      errorSs: errorSs,
    );
  }

  final double partSs;
  final double operatorSs;
  final double interactionSs;
  final double errorSs;
}
