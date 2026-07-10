// Part of the cvss4 library — see cvss4.dart. Split out for the file-size
// ratchet: this holds the ALGORITHM — MacroVector derivation and the
// interpolation scorer, a faithful port of FIRST's cvss_score.js. Every
// function is pure over a full metric map (all keys present; optional metrics
// read as `'X'`), so the engine is isolate-safe.
part of 'cvss4.dart';

// Per-metric ordering weights measuring the "severity distance" between the
// scored vector and a highest-severity vector of its MacroVector. Lifted
// verbatim from the reference's `*_levels` tables. (E has no distance weight —
// EQ5 contributes a proportion of 0 — so no `_eLevels` table is needed.)
const Map<String, double> _avLevels = {'N': 0.0, 'A': 0.1, 'L': 0.2, 'P': 0.3};
const Map<String, double> _prLevels = {'N': 0.0, 'L': 0.1, 'H': 0.2};
const Map<String, double> _uiLevels = {'N': 0.0, 'P': 0.1, 'A': 0.2};
const Map<String, double> _acLevels = {'L': 0.0, 'H': 0.1};
const Map<String, double> _atLevels = {'N': 0.0, 'P': 0.1};
const Map<String, double> _vcLevels = {'H': 0.0, 'L': 0.1, 'N': 0.2};
const Map<String, double> _viLevels = {'H': 0.0, 'L': 0.1, 'N': 0.2};
const Map<String, double> _vaLevels = {'H': 0.0, 'L': 0.1, 'N': 0.2};
const Map<String, double> _scLevels = {'H': 0.1, 'L': 0.2, 'N': 0.3};
const Map<String, double> _siLevels = {'S': 0.0, 'H': 0.1, 'L': 0.2, 'N': 0.3};
const Map<String, double> _saLevels = {'S': 0.0, 'H': 0.1, 'L': 0.2, 'N': 0.3};
const Map<String, double> _crLevels = {'H': 0.0, 'M': 0.1, 'L': 0.2};
const Map<String, double> _irLevels = {'H': 0.0, 'M': 0.1, 'L': 0.2};
const Map<String, double> _arLevels = {'H': 0.0, 'M': 0.1, 'L': 0.2};

/// The *effective* value of [metric], applying the reference `m()` rules:
/// `E:X`→`A`, `CR/IR/AR:X`→`H`, and any set Modified environmental metric
/// (`M…`) overrides its Base counterpart.
String _m(Map<String, String> selected, String metric) {
  final value = selected[metric];
  if (metric == 'E' && value == 'X') return 'A';
  if ((metric == 'CR' || metric == 'IR' || metric == 'AR') && value == 'X') {
    return 'H';
  }
  final modified = selected['M$metric'];
  if (modified != null && modified != 'X') return modified;
  return value ?? 'X';
}

/// Derives the six-digit MacroVector (`EQ1…EQ6`) from the effective metric
/// values, per the reference `macroVector()`.
String _macroVector(Map<String, String> s) {
  final av = _m(s, 'AV');
  final pr = _m(s, 'PR');
  final ui = _m(s, 'UI');
  final vc = _m(s, 'VC');
  final vi = _m(s, 'VI');
  final va = _m(s, 'VA');
  final sc = _m(s, 'SC');
  final si = _m(s, 'SI');
  final sa = _m(s, 'SA');
  final cr = _m(s, 'CR');
  final ir = _m(s, 'IR');
  final ar = _m(s, 'AR');

  // EQ1: privilege/interaction/vector reachability.
  final String eq1;
  if (av == 'N' && pr == 'N' && ui == 'N') {
    eq1 = '0';
  } else if ((av == 'N' || pr == 'N' || ui == 'N') && av != 'P') {
    eq1 = '1';
  } else {
    eq1 = '2';
  }

  // EQ2: attack complexity + requirements.
  final eq2 = (_m(s, 'AC') == 'L' && _m(s, 'AT') == 'N') ? '0' : '1';

  // EQ3: vulnerable-system confidentiality/integrity/availability.
  final String eq3;
  if (vc == 'H' && vi == 'H') {
    eq3 = '0';
  } else if (vc == 'H' || vi == 'H' || va == 'H') {
    eq3 = '1';
  } else {
    eq3 = '2';
  }

  // EQ4: subsequent-system impact (Safety wins).
  final String eq4;
  if (_m(s, 'MSI') == 'S' || _m(s, 'MSA') == 'S') {
    eq4 = '0';
  } else if (sc == 'H' || si == 'H' || sa == 'H') {
    eq4 = '1';
  } else {
    eq4 = '2';
  }

  // EQ5: exploit maturity.
  final e = _m(s, 'E');
  final eq5 = e == 'A'
      ? '0'
      : e == 'P'
      ? '1'
      : '2';

  // EQ6: security-requirement-weighted impact.
  final eq6High =
      (cr == 'H' && vc == 'H') ||
      (ir == 'H' && vi == 'H') ||
      (ar == 'H' && va == 'H');
  final eq6 = eq6High ? '0' : '1';

  return '$eq1$eq2$eq3$eq4$eq5$eq6';
}

/// Extracts a metric's value out of a composed max-severity vector string such
/// as `AV:N/PR:N/UI:N/…`, mirroring the reference `extractValueMetric()`.
String _extractValueMetric(String metric, String vector) {
  final rest = vector.substring(vector.indexOf(metric) + metric.length + 1);
  final slash = rest.indexOf('/');
  return slash > 0 ? rest.substring(0, slash) : rest;
}

/// Raw per-metric severity distances between the scored vector [s] and the
/// highest-severity [maxVector], keyed by metric. A negative entry means
/// [maxVector] is not actually ≥ the scored vector on that metric.
Map<String, double> _distancesFor(Map<String, String> s, String maxVector) {
  double d(String metric, Map<String, double> levels) =>
      levels[_m(s, metric)]! - levels[_extractValueMetric(metric, maxVector)]!;
  return {
    'AV': d('AV', _avLevels),
    'PR': d('PR', _prLevels),
    'UI': d('UI', _uiLevels),
    'AC': d('AC', _acLevels),
    'AT': d('AT', _atLevels),
    'VC': d('VC', _vcLevels),
    'VI': d('VI', _viLevels),
    'VA': d('VA', _vaLevels),
    'SC': d('SC', _scLevels),
    'SI': d('SI', _siLevels),
    'SA': d('SA', _saLevels),
    'CR': d('CR', _crLevels),
    'IR': d('IR', _irLevels),
    'AR': d('AR', _arLevels),
  };
}

/// Current per-EQ severity distances: builds every candidate highest-severity
/// vector for [macro], picks the first that dominates the scored vector [s] on
/// every metric, and returns that vector's distances grouped by EQ. EQ5's
/// current distance is always 0 in the reference, so it is not returned.
({double eq1, double eq2, double eq3eq6, double eq4}) _currentSeverityDistances(
  Map<String, String> s,
  String macro,
) {
  final eq1Maxes = _maxEq1[macro[0]]!;
  final eq2Maxes = _maxEq2[macro[1]]!;
  final eq3eq6Maxes = _maxEq3Eq6[macro[2]]![macro[5]]!;
  final eq4Maxes = _maxEq4[macro[3]]!;
  final eq5Maxes = _maxEq5[macro[4]]!;

  final maxVectors = <String>[];
  for (final a in eq1Maxes) {
    for (final b in eq2Maxes) {
      for (final c in eq3eq6Maxes) {
        for (final d in eq4Maxes) {
          for (final e in eq5Maxes) {
            maxVectors.add('$a$b$c$d$e');
          }
        }
      }
    }
  }

  // The first max vector that dominates the scored vector; if none does, the
  // reference keeps the last one evaluated.
  late Map<String, double> dist;
  for (final maxVector in maxVectors) {
    dist = _distancesFor(s, maxVector);
    if (dist.values.every((v) => v >= 0)) break;
  }

  return (
    eq1: dist['AV']! + dist['PR']! + dist['UI']!,
    eq2: dist['AC']! + dist['AT']!,
    eq3eq6:
        dist['VC']! +
        dist['VI']! +
        dist['VA']! +
        dist['CR']! +
        dist['IR']! +
        dist['AR']!,
    eq4: dist['SC']! + dist['SI']! + dist['SA']!,
  );
}

/// The lookup scores of the next-lower MacroVector along each EQ axis (`null`
/// when no lower MacroVector exists), per the reference. EQ3 and EQ6 move
/// together; when both are 0 there are two candidate descents and the higher
/// score is taken.
({double? eq1, double? eq2, double? eq3eq6, double? eq4, double? eq5})
_nextLowerMacroScores(String macro) {
  final e1 = int.parse(macro[0]);
  final e2 = int.parse(macro[1]);
  final e3 = int.parse(macro[2]);
  final e4 = int.parse(macro[3]);
  final e5 = int.parse(macro[4]);
  final e6 = int.parse(macro[5]);
  String mv(int a, int b, int c, int d, int e, int f) => '$a$b$c$d$e$f';

  double? eq3eq6;
  if (e3 == 1 && e6 == 1) {
    eq3eq6 = _cvssLookup[mv(e1, e2, e3 + 1, e4, e5, e6)];
  } else if (e3 == 0 && e6 == 1) {
    eq3eq6 = _cvssLookup[mv(e1, e2, e3 + 1, e4, e5, e6)];
  } else if (e3 == 1 && e6 == 0) {
    eq3eq6 = _cvssLookup[mv(e1, e2, e3, e4, e5, e6 + 1)];
  } else if (e3 == 0 && e6 == 0) {
    // Two possible descents: take the one with the higher score.
    final left = _cvssLookup[mv(e1, e2, e3, e4, e5, e6 + 1)];
    final right = _cvssLookup[mv(e1, e2, e3 + 1, e4, e5, e6)];
    eq3eq6 = (left != null && right != null && left > right) ? left : right;
  } else {
    eq3eq6 = _cvssLookup[mv(e1, e2, e3 + 1, e4, e5, e6 + 1)];
  }

  return (
    eq1: _cvssLookup[mv(e1 + 1, e2, e3, e4, e5, e6)],
    eq2: _cvssLookup[mv(e1, e2 + 1, e3, e4, e5, e6)],
    eq3eq6: eq3eq6,
    eq4: _cvssLookup[mv(e1, e2, e3, e4 + 1, e5, e6)],
    eq5: _cvssLookup[mv(e1, e2, e3, e4, e5 + 1, e6)],
  );
}

/// The maximal severity depth of each EQ for [macro], already scaled by the
/// 0.1 step so it can divide a raw severity distance into a proportion.
({double eq1, double eq2, double eq3eq6, double eq4}) _maxSeverityFor(
  String macro,
) {
  const step = 0.1;
  return (
    eq1: _maxSevEq1[macro[0]]! * step,
    eq2: _maxSevEq2[macro[1]]! * step,
    eq3eq6: _maxSevEq3Eq6[macro[2]]![macro[5]]! * step,
    eq4: _maxSevEq4[macro[3]]! * step,
  );
}

/// Computes the CVSS v4.0 score for a full metric map [s] (every key present;
/// optional metrics as `'X'`). Faithful port of FIRST's `cvss_score()`.
double _cvss4Score(Map<String, String> s) {
  // Shortcut: no impact on any (sub)system metric → 0.0.
  const impacts = ['VC', 'VI', 'VA', 'SC', 'SI', 'SA'];
  if (impacts.every((metric) => _m(s, metric) == 'N')) return 0.0;

  final macro = _macroVector(s);
  final value = _cvssLookup[macro]!;

  final lower = _nextLowerMacroScores(macro);
  final current = _currentSeverityDistances(s, macro);
  final maxSev = _maxSeverityFor(macro);

  // Maximal scoring difference per EQ (null when there is no lower MacroVector).
  final available = <double?>[
    lower.eq1 == null ? null : value - lower.eq1!,
    lower.eq2 == null ? null : value - lower.eq2!,
    lower.eq3eq6 == null ? null : value - lower.eq3eq6!,
    lower.eq4 == null ? null : value - lower.eq4!,
    lower.eq5 == null ? null : value - lower.eq5!,
  ];
  // Proportion of each EQ's depth the scored vector has descended. EQ5's
  // proportion is always 0 in the reference.
  final proportion = <double>[
    current.eq1 / maxSev.eq1,
    current.eq2 / maxSev.eq2,
    current.eq3eq6 / maxSev.eq3eq6,
    current.eq4 / maxSev.eq4,
    0.0,
  ];

  var existing = 0;
  var normalizedSum = 0.0;
  for (var i = 0; i < available.length; i++) {
    final dist = available[i];
    if (dist == null) continue;
    existing++;
    normalizedSum += dist * proportion[i];
  }

  final mean = existing == 0 ? 0.0 : normalizedSum / existing;
  var result = value - mean;
  if (result < 0) result = 0.0;
  if (result > 10) result = 10.0;
  return (result * 10).round() / 10;
}
