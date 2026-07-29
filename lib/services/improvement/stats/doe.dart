part of 'stats.dart';

// Two-level factorial designs: the arithmetic of planning an experiment and of
// reading one back afterwards. Full factorials and 2^(k−p) fractions only —
// response-surface, optimal and mixture designs are out of scope by decision
// (docs/design/PROCESS_IMPROVEMENT.md §18).
//
// Three things this file refuses to do quietly.
//
//   * Invent a generator. A fraction is only as good as the design generators
//     that produced it, and choosing them badly confounds a main effect with a
//     two-factor interaction without saying so. Generators are either given by
//     the caller or taken from the published table below; a combination that
//     is in neither is refused.
//   * Hide the aliasing. Every effect a fractional design reports carries the
//     list of terms it cannot be told apart from. "D = ABC" is not a footnote,
//     it is the meaning of the number.
//   * Put a p-value on an unreplicated design. Without replication there is no
//     estimate of the error, so there is nothing to test against. What is
//     offered instead is Lenth's pseudo standard error, which says out loud
//     that it is inferring the noise from the small effects themselves.

/// The letters a design names its factors by, in order.
///
/// `I` is skipped, exactly as the published design tables skip it: `I` is the
/// identity column of the defining relation (`I = ABCD`), and a factor named I
/// would make its own alias structure unreadable.
const String designFactorLetters = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';

/// Where a full factorial stops being an experiment and becomes a wish.
///
/// Twelve factors is already 4096 runs. The cap is not arithmetic — the loop
/// would happily go on — it is the point past which producing the design would
/// be the least useful thing to tell the person asking for it.
const int maximumFullFactorialFactors = 12;

/// Published design generators for the 2^(k−p) fractions in common use, by
/// factor count and then by [FactorialDesign.fraction].
///
/// Reference data, transcribed rather than derived, on the same footing as the
/// control-chart factors in `constants.dart`: these are the minimum-aberration
/// choices from the standard tables (NIST/SEMATECH e-Handbook §5.3.3.4.7 —
/// US government work, freely usable). What is *not* stored is the resolution
/// each one achieves; that is computed from the defining relation, so the
/// table cannot end up disagreeing with itself.
const Map<int, Map<int, List<String>>> _publishedDesignGenerators =
    <int, Map<int, List<String>>>{
      3: <int, List<String>>{
        1: <String>['C = AB'],
      },
      4: <int, List<String>>{
        1: <String>['D = ABC'],
      },
      5: <int, List<String>>{
        1: <String>['E = ABCD'],
        2: <String>['D = AB', 'E = AC'],
      },
      6: <int, List<String>>{
        1: <String>['F = ABCDE'],
        2: <String>['E = ABC', 'F = BCD'],
        3: <String>['D = AB', 'E = AC', 'F = BC'],
      },
      7: <int, List<String>>{
        1: <String>['G = ABCDEF'],
        2: <String>['F = ABCD', 'G = ABDE'],
        3: <String>['E = ABC', 'F = BCD', 'G = ACD'],
        4: <String>['D = AB', 'E = AC', 'F = BC', 'G = ABC'],
      },
      8: <int, List<String>>{
        1: <String>['H = ABCDEFG'],
        2: <String>['G = ABCD', 'H = ABEF'],
        3: <String>['F = ABC', 'G = ABD', 'H = BCDE'],
        4: <String>['E = BCD', 'F = ACD', 'G = ABC', 'H = ABD'],
      },
      9: <int, List<String>>{
        1: <String>['J = ABCDEFGH'],
        2: <String>['H = ACDFG', 'J = BCEFG'],
        3: <String>['G = ABCD', 'H = ACEF', 'J = CDEF'],
        4: <String>['F = BCDE', 'G = ACDE', 'H = ABDE', 'J = ABCE'],
        5: <String>['E = ABC', 'F = BCD', 'G = ACD', 'H = ABD', 'J = ABCD'],
      },
    };

/// One factor and the two settings it will be run at.
class DesignFactor {
  const DesignFactor(this.name, {this.low = -1, this.high = 1});

  /// What the factor is called in the report, e.g. `'Voorverwarmen'`.
  final String name;

  /// The setting the coded level −1 stands for.
  final double low;

  /// The setting the coded level +1 stands for.
  final double high;

  /// The actual setting a coded level asks for.
  double settingFor(int codedLevel) => codedLevel > 0 ? high : low;
}

/// A product of factors, with the sign it carries.
///
/// Used for both halves of the same idea: a word of the defining relation
/// (`I = −ABCD`) and an alias of an effect (`AB = −CD`). An empty [factors] is
/// the identity column.
class SignedTerm {
  const SignedTerm(this.factors, this.sign);

  /// Factor indices, ascending.
  final List<int> factors;

  /// +1 or −1.
  final int sign;

  /// How many factors the term multiplies together.
  int get order => factors.length;

  /// e.g. `'ABCD'`, or `'−ABCD'` when the sign is negative.
  String get label => '${sign < 0 ? '−' : ''}${factorialTermLabel(factors)}';

  @override
  String toString() => label;
}

/// The letters of a term, e.g. `[0, 2]` → `'AC'`. The empty term is `'I'`.
String factorialTermLabel(List<int> term) {
  if (term.isEmpty) return 'I';
  return <String>[for (final int j in term) _letterFor(j)].join();
}

/// The inverse of [factorialTermLabel]: `'AC'` → `[0, 2]`.
List<int> factorialTerm(String letters) {
  final List<int> term = <int>[];
  for (final String letter in letters.trim().toUpperCase().split('')) {
    final int index = designFactorLetters.indexOf(letter);
    if (index < 0 || term.contains(index)) {
      throw StatsRefusal(
        'a design term',
        '"$letters" is not a product of distinct factor letters '
            '($designFactorLetters)',
      );
    }
    term.add(index);
  }
  term.sort();
  return term;
}

String _letterFor(int index) {
  if (index < 0 || index >= designFactorLetters.length) {
    throw StatsRefusal(
      'a factor letter',
      'a design can name at most ${designFactorLetters.length} factors, so '
          'there is no letter for factor ${index + 1}',
    );
  }
  return designFactorLetters[index];
}

/// A two-level factorial design: which runs to perform, and what each run
/// will and will not be able to tell you afterwards.
class FactorialDesign {
  const FactorialDesign._({
    required this.factors,
    required this.points,
    required this.replicates,
    required this.fraction,
    required this.generators,
    required this.definingRelation,
  });

  /// The full factorial in [factors]: every combination of the two levels.
  factory FactorialDesign.full(
    List<DesignFactor> factors, {
    int replicates = 1,
  }) {
    const String what = 'a full factorial design';
    _checkFactors(what, factors, replicates);
    if (factors.length > maximumFullFactorialFactors) {
      throw StatsRefusal(
        what,
        'a full factorial in ${factors.length} factors asks for '
        '${1 << factors.length} runs; run a fraction instead',
      );
    }
    return FactorialDesign._(
      factors: List<DesignFactor>.unmodifiable(factors),
      points: _standardOrder(factors.length),
      replicates: replicates,
      fraction: 0,
      generators: const <String>[],
      definingRelation: const <SignedTerm>[],
    );
  }

  /// A 2^(k−[fraction]) fraction of the full factorial in [factors].
  ///
  /// The first `k − fraction` factors form the base design; each remaining
  /// factor is placed on an interaction of the base factors by a generator
  /// such as `'D = ABC'` (a leading `-` is allowed: `'E = -ABCD'`). Omit
  /// [generators] to take the published choice for this size, and be refused
  /// if the table has none — guessing a generator is how a main effect ends up
  /// confounded with a two-factor interaction in silence.
  factory FactorialDesign.fractional(
    List<DesignFactor> factors, {
    required int fraction,
    List<String>? generators,
    int replicates = 1,
  }) {
    const String what = 'a fractional factorial design';
    _checkFactors(what, factors, replicates);
    final int k = factors.length;
    if (fraction < 1 || fraction > k - 2) {
      throw StatsRefusal(
        what,
        'a 2^($k−$fraction) design leaves ${k - fraction} base factor(s); the '
        'fraction has to leave at least two',
      );
    }
    final List<String> spec =
        generators ?? _publishedGeneratorsFor(k, fraction, what);
    if (spec.length != fraction) {
      throw StatsRefusal(
        what,
        'a 2^($k−$fraction) design needs exactly $fraction generator(s), got '
        '${spec.length}',
      );
    }
    final int base = k - fraction;
    final List<_Generator> parsed = <_Generator>[
      for (int i = 0; i < spec.length; i++)
        _Generator.parse(spec[i], base + i, base, what),
    ];
    return FactorialDesign._(
      factors: List<DesignFactor>.unmodifiable(factors),
      points: _fractionalPoints(base, parsed),
      replicates: replicates,
      fraction: fraction,
      generators: List<String>.unmodifiable(<String>[
        for (final _Generator g in parsed) g.text,
      ]),
      definingRelation: _definingRelation(parsed),
    );
  }

  final List<DesignFactor> factors;

  /// The distinct treatment combinations, in standard (Yates) order, coded −1
  /// and +1. The first factor alternates fastest.
  final List<List<int>> points;

  /// How often the whole design is run. Two or more is what buys an estimate
  /// of the error that does not have to be inferred from the effects.
  final int replicates;

  /// The `p` of 2^(k−p); zero for a full factorial.
  final int fraction;

  /// The generators as given, e.g. `['D = ABC']`.
  final List<String> generators;

  /// Every non-identity word of the defining relation, shortest first. Empty
  /// for a full factorial, which confounds nothing.
  final List<SignedTerm> definingRelation;

  int get factorCount => factors.length;

  /// How many base factors the fraction was built on.
  int get baseFactorCount => factorCount - fraction;

  /// Distinct treatment combinations, before replication.
  int get pointCount => points.length;

  /// Total runs to perform: [pointCount] × [replicates].
  int get runCount => pointCount * replicates;

  /// The resolution of the design — the length of the shortest word in the
  /// defining relation. Null for a full factorial, where nothing is aliased.
  ///
  /// Read as: a resolution IV design confounds two-factor interactions with
  /// each other but keeps main effects clear of them; resolution III does not
  /// even manage that.
  int? get resolution => definingRelation.isEmpty
      ? null
      : definingRelation
            .map((SignedTerm w) => w.order)
            .reduce((int a, int b) => a < b ? a : b);

  /// The coded levels of run [runIndex], replicates included.
  List<int> codedRun(int runIndex) => points[_pointOf(runIndex)];

  /// The actual factor settings of run [runIndex].
  List<double> settingsFor(int runIndex) {
    final List<int> coded = codedRun(runIndex);
    return <double>[
      for (int j = 0; j < factorCount; j++) factors[j].settingFor(coded[j]),
    ];
  }

  /// Which treatment combination run [runIndex] repeats.
  int _pointOf(int runIndex) {
    if (runIndex < 0 || runIndex >= runCount) {
      throw StatsRefusal(
        'a design run',
        'this design has $runCount run(s); there is no run ${runIndex + 1}',
      );
    }
    return runIndex % pointCount;
  }

  /// The ±1 column an effect is estimated from, one entry per run.
  List<int> contrastColumn(List<int> term) {
    _checkTerm(term);
    return <int>[for (int i = 0; i < runCount; i++) _signAt(_pointOf(i), term)];
  }

  int _signAt(int point, List<int> term) {
    int sign = 1;
    for (final int j in term) {
      sign *= points[point][j];
    }
    return sign;
  }

  /// The terms this design can actually estimate, one per distinct column,
  /// each named by the shortest member of its alias class.
  ///
  /// A 2^(k−p) design has 2^(k−p) − 1 columns and no more, however many
  /// interactions the factors could form between them. That shortfall is the
  /// price of the fraction, and it is returned as a list rather than implied.
  List<List<int>> get estimableTerms {
    final List<List<int>> terms = <List<int>>[];
    for (int mask = 1; mask < (1 << baseFactorCount); mask++) {
      terms.add(
        clearestAliasOf(<int>[
          for (int j = 0; j < baseFactorCount; j++)
            if ((mask >> j) & 1 == 1) j,
        ]),
      );
    }
    terms.sort(_byOrderThenLetters);
    return terms;
  }

  /// The terms [term] cannot be told apart from, with the sign each enters
  /// with. Empty for a full factorial.
  List<SignedTerm> aliasesOf(List<int> term) {
    _checkTerm(term);
    return <SignedTerm>[
      for (final SignedTerm word in definingRelation)
        SignedTerm(_symmetricDifference(term, word.factors), word.sign),
    ]..sort(
      (SignedTerm a, SignedTerm b) => _byOrderThenLetters(a.factors, b.factors),
    );
  }

  /// The shortest name for the column [term] sits on — `ABCD` in a design
  /// where `D = ABC` is really the `D` column, and reporting it as a
  /// four-factor interaction would be true but useless.
  List<int> clearestAliasOf(List<int> term) {
    List<int> best = List<int>.of(term);
    for (final SignedTerm alias in aliasesOf(term)) {
      if (_byOrderThenLetters(alias.factors, best) < 0) {
        best = alias.factors;
      }
    }
    return best;
  }

  /// An order to run the design in, drawn from [random].
  ///
  /// Offered because randomisation is not decoration: run the design in
  /// standard order and any drift over the session — a warming machine, an
  /// operator finding their rhythm — lands on whichever factor happens to
  /// change slowest, and becomes indistinguishable from that factor's effect.
  List<int> randomisedRunOrder(math.Random random) {
    final List<int> order = <int>[for (int i = 0; i < runCount; i++) i];
    for (int i = order.length - 1; i > 0; i--) {
      final int j = random.nextInt(i + 1);
      final int swap = order[i];
      order[i] = order[j];
      order[j] = swap;
    }
    return order;
  }

  void _checkTerm(List<int> term) {
    for (final int j in term) {
      if (j < 0 || j >= factorCount) {
        throw StatsRefusal(
          'a design term',
          'this design has $factorCount factor(s); ${_letterFor(j)} is not '
              'one of them',
        );
      }
    }
  }
}

/// One parsed generator, e.g. `D = -ABC`.
class _Generator {
  const _Generator(this.target, this.sign, this.sources, this.text);

  /// Index of the factor being placed.
  final int target;

  final int sign;

  /// Indices of the base factors whose product the target rides on.
  final List<int> sources;

  /// The generator as written, kept for the report.
  final String text;

  static _Generator parse(
    String text,
    int expectedTarget,
    int baseFactorCount,
    String what,
  ) {
    final List<String> halves = text.split('=');
    if (halves.length != 2) {
      throw StatsRefusal(
        what,
        'generator "$text" is not of the form "D = ABC"',
      );
    }
    final List<int> target = factorialTerm(halves.first);
    if (target.length != 1 || target.first != expectedTarget) {
      throw StatsRefusal(
        what,
        'generator "$text" should place factor '
        '${_letterFor(expectedTarget)}; the factors after the base design '
        'are placed in order',
      );
    }
    String right = halves.last.trim();
    int sign = 1;
    if (right.startsWith('-') || right.startsWith('+')) {
      sign = right.startsWith('-') ? -1 : 1;
      right = right.substring(1).trim();
    }
    final List<int> sources = factorialTerm(right);
    if (sources.length < 2) {
      throw StatsRefusal(
        what,
        'generator "$text" rides on fewer than two base factors, which would '
        'make ${_letterFor(expectedTarget)} a copy of another factor',
      );
    }
    for (final int j in sources) {
      if (j >= baseFactorCount) {
        throw StatsRefusal(
          what,
          'generator "$text" uses ${_letterFor(j)}, which is not part of the '
          'base design (A..${_letterFor(baseFactorCount - 1)})',
        );
      }
    }
    return _Generator(expectedTarget, sign, sources, text.trim());
  }

  /// The word this generator contributes to the defining relation: `D = ABC`
  /// multiplied through by D gives `I = ABCD`.
  SignedTerm get word => SignedTerm(<int>[...sources, target]..sort(), sign);
}

List<String> _publishedGeneratorsFor(int factors, int fraction, String what) {
  final List<String>? published =
      _publishedDesignGenerators[factors]?[fraction];
  if (published == null) {
    throw StatsRefusal(
      what,
      'no published generator set for 2^($factors−$fraction); give the '
      'generators explicitly, because choosing them is a methodological '
      'decision and not one to guess at',
    );
  }
  return published;
}

/// The 2^[factorCount] treatment combinations in standard (Yates) order.
List<List<int>> _standardOrder(int factorCount) => <List<int>>[
  for (int run = 0; run < (1 << factorCount); run++)
    <int>[for (int j = 0; j < factorCount; j++) ((run >> j) & 1) == 0 ? -1 : 1],
];

/// The base design with each generated factor's column appended.
List<List<int>> _fractionalPoints(
  int baseFactorCount,
  List<_Generator> generators,
) {
  final List<List<int>> points = _standardOrder(baseFactorCount);
  for (final _Generator g in generators) {
    for (final List<int> row in points) {
      int level = g.sign;
      for (final int j in g.sources) {
        level *= row[j];
      }
      row.add(level);
    }
  }
  return points;
}

/// Every product of the generator words — the full defining contrast subgroup,
/// which is what the aliasing actually follows from.
List<SignedTerm> _definingRelation(List<_Generator> generators) {
  final List<SignedTerm> words = <SignedTerm>[];
  for (int mask = 1; mask < (1 << generators.length); mask++) {
    List<int> factors = const <int>[];
    int sign = 1;
    for (int i = 0; i < generators.length; i++) {
      if ((mask >> i) & 1 == 0) continue;
      final SignedTerm word = generators[i].word;
      factors = _symmetricDifference(factors, word.factors);
      sign *= word.sign;
    }
    words.add(SignedTerm(factors, sign));
  }
  words.sort(
    (SignedTerm a, SignedTerm b) => _byOrderThenLetters(a.factors, b.factors),
  );
  return List<SignedTerm>.unmodifiable(words);
}

/// Terms multiply like sets: a factor squared is the identity column, so it
/// drops out. `AB · BCD = ACD`.
List<int> _symmetricDifference(List<int> a, List<int> b) => <int>[
  for (final int j in a)
    if (!b.contains(j)) j,
  for (final int j in b)
    if (!a.contains(j)) j,
]..sort();

/// Shortest first, then alphabetically — so `D` beats `ABC` and `AB` beats
/// `AC`.
int _byOrderThenLetters(List<int> a, List<int> b) {
  if (a.length != b.length) return a.length - b.length;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}

void _checkFactors(String what, List<DesignFactor> factors, int replicates) {
  _requireAtLeast(what, 'factors', factors.length, 2);
  if (factors.length > designFactorLetters.length) {
    throw StatsRefusal(
      what,
      'a design can name at most ${designFactorLetters.length} factors, got '
      '${factors.length}',
    );
  }
  _requireAtLeast(what, 'replicates', replicates, 1);
  for (final DesignFactor factor in factors) {
    if (factor.low == factor.high) {
      throw StatsRefusal(
        what,
        'factor "${factor.name}" has the same value for both of its levels, '
        'so the design would never change it',
      );
    }
  }
}

/// One estimated effect, with everything needed to decide whether to believe
/// it.
class FactorialEffect {
  const FactorialEffect({
    required this.term,
    required this.effect,
    required this.sumOfSquares,
    required this.aliases,
    required this.standardError,
    required this.degreesOfFreedom,
  });

  /// The factor indices this column stands for.
  final List<int> term;

  /// The change in the response from the low setting to the high setting: the
  /// mean of the runs at +1 minus the mean of the runs at −1. This is the
  /// "effect" a factorial report quotes, and it is twice the regression
  /// [coefficient] in coded units — a difference worth stating, because half
  /// the software in this field quotes the other one.
  final double effect;

  final double sumOfSquares;

  /// The terms this effect cannot be told apart from. Empty for a full
  /// factorial.
  final List<SignedTerm> aliases;

  /// Null when the design was run once: with no replication there is no
  /// independent estimate of the error.
  final double? standardError;

  /// Residual degrees of freedom behind [standardError], or null.
  final double? degreesOfFreedom;

  /// e.g. `'A'`, `'AB'`.
  String get name => factorialTermLabel(term);

  /// How many factors this effect involves. One is a main effect.
  int get order => term.length;

  /// The regression coefficient in coded units, [effect] / 2.
  double get coefficient => effect / 2;

  /// t statistic, or null on an unreplicated design.
  double? get tStatistic {
    final double? se = standardError;
    return se == null || se == 0 ? null : effect / se;
  }

  /// Two-sided p-value, or null on an unreplicated design.
  double? get pValue {
    final double? t = tStatistic;
    final double? df = degreesOfFreedom;
    if (t == null || df == null || df <= 0) return null;
    return StudentTDistribution(df).twoSidedP(t);
  }

  @override
  String toString() => '$name: ${effect.toStringAsFixed(4)}';
}

/// The effects a factorial design's responses imply.
class FactorialAnalysis {
  const FactorialAnalysis._({
    required this.design,
    required this.grandMean,
    required this.effects,
    required this.totalSumOfSquares,
    required this.pureErrorSumOfSquares,
    required this.pureErrorDegreesOfFreedom,
  });

  /// Reads [responses] back against [design].
  ///
  /// One response per run, in the design's own run order: the [design].points
  /// in standard order, then the whole block again for each further replicate.
  /// If the experiment was run in a randomised order — and it should have been
  /// ([FactorialDesign.randomisedRunOrder]) — the responses have to be put
  /// back in design order first.
  static FactorialAnalysis of(FactorialDesign design, List<double> responses) {
    const String what = 'factorial effects';
    if (responses.length != design.runCount) {
      throw StatsRefusal(
        what,
        'the design has ${design.runCount} run(s) and ${responses.length} '
        'response(s) were given',
      );
    }
    final Descriptives summary = Descriptives.of(responses);
    final double? pureError = design.replicates > 1
        ? _pureErrorSumOfSquares(design, responses)
        : null;
    final double? pureErrorDf = design.replicates > 1
        ? (design.pointCount * (design.replicates - 1)).toDouble()
        : null;
    final double? meanSquare = pureError == null || pureErrorDf == null
        ? null
        : pureError / pureErrorDf;
    final double? standardError = meanSquare == null
        ? null
        : 2 * math.sqrt(meanSquare / design.runCount);

    return FactorialAnalysis._(
      design: design,
      grandMean: summary.mean,
      effects: List<FactorialEffect>.unmodifiable(<FactorialEffect>[
        for (final List<int> term in design.estimableTerms)
          _effectFor(design, responses, term, standardError, pureErrorDf),
      ]),
      totalSumOfSquares: summary.sumOfSquaredDeviations,
      pureErrorSumOfSquares: pureError,
      pureErrorDegreesOfFreedom: pureErrorDf,
    );
  }

  final FactorialDesign design;

  /// The mean response over every run — the intercept of the coded model.
  final double grandMean;

  /// Every estimable effect, main effects first, then by term.
  final List<FactorialEffect> effects;

  /// Σ(y − ȳ)² over all runs.
  final double totalSumOfSquares;

  /// The variation between replicates of the same treatment combination —
  /// pure error, the only error estimate in a factorial that does not depend
  /// on assuming some effects away. Null when the design was run once.
  final double? pureErrorSumOfSquares;

  final double? pureErrorDegreesOfFreedom;

  /// Pure error mean square, the σ̂² behind every standard error here.
  double? get pureErrorMeanSquare {
    final double? ss = pureErrorSumOfSquares;
    final double? df = pureErrorDegreesOfFreedom;
    return ss == null || df == null || df <= 0 ? null : ss / df;
  }

  /// Whether the design was replicated, and so whether the p-values exist.
  bool get isReplicated => design.replicates > 1;

  /// The single-factor effects.
  List<FactorialEffect> get mainEffects =>
      effects.where((FactorialEffect e) => e.order == 1).toList();

  /// The interactions, of every order.
  List<FactorialEffect> get interactions =>
      effects.where((FactorialEffect e) => e.order > 1).toList();

  /// The effects up to and including [order] — usually 2, because a
  /// three-factor interaction is rarely the story and often the noise.
  List<FactorialEffect> effectsUpTo(int order) =>
      effects.where((FactorialEffect e) => e.order <= order).toList();

  /// The effect on the column named [letters], e.g. `'AB'`.
  FactorialEffect effectNamed(String letters) {
    final List<int> wanted = design.clearestAliasOf(factorialTerm(letters));
    for (final FactorialEffect effect in effects) {
      if (_byOrderThenLetters(effect.term, wanted) == 0) return effect;
    }
    throw StatsRefusal(
      'the effect $letters',
      'this design does not estimate it',
    );
  }

  /// The effects ordered by absolute size, largest first — the list a Pareto
  /// of effects is drawn from.
  List<FactorialEffect> get bySize => List<FactorialEffect>.of(effects)
    ..sort(
      (FactorialEffect a, FactorialEffect b) =>
          b.effect.abs().compareTo(a.effect.abs()),
    );

  /// Lenth's pseudo standard error: an estimate of the noise taken from the
  /// effects themselves, on the assumption that most of them are noise.
  ///
  /// This is the honest answer to "the design was not replicated, now what".
  /// It is not a measured error and it is not interchangeable with one — if
  /// half the factors really do matter, the assumption behind it fails and it
  /// will overstate the noise. Lenth (1989).
  double get lenthPseudoStandardError {
    const String what = "Lenth's pseudo standard error";
    _requireAtLeast(what, 'effects', effects.length, 3);
    final List<double> sizes = <double>[
      for (final FactorialEffect e in effects) e.effect.abs(),
    ]..sort();
    final double s0 = 1.5 * _medianOf(sizes, 0, sizes.length);
    if (s0 <= 0) {
      throw const StatsRefusal(
        what,
        'every effect is exactly zero, so there is no spread to read a noise '
        'level off',
      );
    }
    final List<double> trimmed = <double>[
      for (final double size in sizes)
        if (size < 2.5 * s0) size,
    ];
    if (trimmed.isEmpty) {
      throw const StatsRefusal(
        what,
        'no effect is small enough to be taken for noise, so the method has '
        'nothing left to estimate from',
      );
    }
    return 1.5 * _medianOf(trimmed, 0, trimmed.length);
  }

  /// The size an individual effect has to reach before Lenth's method calls it
  /// real, at confidence [level].
  double lenthMarginOfError({double level = 0.95}) =>
      _lenthCritical((1 + level) / 2) * lenthPseudoStandardError;

  /// The stricter threshold that holds for *all* the effects at once.
  ///
  /// Reported next to [lenthMarginOfError] because a design estimates dozens
  /// of effects, and testing dozens of things at 5% each is how a factorial
  /// produces a discovery from pure noise.
  double lenthSimultaneousMarginOfError({double level = 0.95}) {
    final int m = effects.length;
    final double gamma = (1 + math.pow(level, 1 / m)) / 2;
    return _lenthCritical(gamma) * lenthPseudoStandardError;
  }

  /// Lenth's critical value: a t quantile on m/3 degrees of freedom, which is
  /// the approximation his paper establishes for the PSE.
  double _lenthCritical(double probability) =>
      StudentTDistribution(effects.length / 3).quantile(probability);
}

FactorialEffect _effectFor(
  FactorialDesign design,
  List<double> responses,
  List<int> term,
  double? standardError,
  double? degreesOfFreedom,
) {
  final List<int> column = design.contrastColumn(term);
  double contrast = 0;
  for (int i = 0; i < responses.length; i++) {
    contrast += column[i] * responses[i];
  }
  final int n = responses.length;
  return FactorialEffect(
    term: List<int>.unmodifiable(term),
    effect: 2 * contrast / n,
    sumOfSquares: contrast * contrast / n,
    aliases: design.aliasesOf(term),
    standardError: standardError,
    degreesOfFreedom: degreesOfFreedom,
  );
}

/// Σ over treatment combinations of Σ(y − ȳ_combination)².
double _pureErrorSumOfSquares(FactorialDesign design, List<double> responses) {
  double total = 0;
  for (int point = 0; point < design.pointCount; point++) {
    double sum = 0;
    for (int r = 0; r < design.replicates; r++) {
      sum += responses[point + r * design.pointCount];
    }
    final double cellMean = sum / design.replicates;
    for (int r = 0; r < design.replicates; r++) {
      final double delta = responses[point + r * design.pointCount] - cellMean;
      total += delta * delta;
    }
  }
  return total;
}
