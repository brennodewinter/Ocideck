// Native Dart port of the FIRST CVSS v4.0 reference calculator
// (github.com/FIRSTdotorg/cvss-v4-calculator). Pure Dart, no Flutter imports,
// isolate-safe. The metric model, the MacroVector→score lookup table and the
// interpolation algorithm mirror the reference so this engine reproduces
// FIRST's scores exactly. Rationale (PENTEST_MIAUW.md §7): offline, unit- and
// mutation-testable, no bundled JS runtime.
//
// Attribution: the MacroVector lookup table and max-severity data are
// "Copyright FIRST, Red Hat, and contributors" (SPDX-License-Identifier:
// BSD-2-Clause). See cvss4_lookup.dart.
//
// Split for the file-size ratchet:
//   - cvss4_lookup.dart  — the MacroVector lookup table + max-severity data.
//   - cvss4_scoring.dart — MacroVector derivation + interpolation algorithm.
library;

part 'cvss4_lookup.dart';
part 'cvss4_scoring.dart';

/// Aantal MacroVector-rijen in de FIRST-scoretabel. Alleen om de gebruiker te
/// laten zien hóéveel referentiegegevens er lokaal zijn (Instellingen →
/// Uitbreidingen). Het scoren leest altijd de privé-tabel.
int get cvss4LookupSize => _cvssLookup.length;

/// Qualitative severity band for a CVSS v4.0 score, per the FIRST rating scale:
/// None 0.0 / Low 0.1–3.9 / Medium 4.0–6.9 / High 7.0–8.9 / Critical 9.0–10.0.
enum Cvss4Severity {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High'),
  critical('Critical');

  const Cvss4Severity(this.label);

  /// English rating label as published by FIRST.
  final String label;

  /// Maps a [score] (0.0–10.0) to its band.
  static Cvss4Severity fromScore(double score) {
    if (score <= 0.0) return Cvss4Severity.none;
    if (score < 4.0) return Cvss4Severity.low;
    if (score < 7.0) return Cvss4Severity.medium;
    if (score < 9.0) return Cvss4Severity.high;
    return Cvss4Severity.critical;
  }
}

/// One CVSS v4.0 metric in canonical order: its short key, the values it
/// accepts and whether it is mandatory (only the eleven Base metrics are).
class _MetricDef {
  const _MetricDef(this.key, this.values, {this.mandatory = false});

  final String key;
  final List<String> values;
  final bool mandatory;
}

/// The full metric set in the order FIRST serialises them:
/// Base → Threat → Environmental → Supplemental. This ordering is what
/// [Cvss4.parseVector] enforces and what [Cvss4.vector] emits. The value lists
/// include `'X'` (Not Defined) for every optional metric.
const List<_MetricDef> _metricOrder = [
  // Base (11, all mandatory).
  _MetricDef('AV', ['N', 'A', 'L', 'P'], mandatory: true),
  _MetricDef('AC', ['L', 'H'], mandatory: true),
  _MetricDef('AT', ['N', 'P'], mandatory: true),
  _MetricDef('PR', ['N', 'L', 'H'], mandatory: true),
  _MetricDef('UI', ['N', 'P', 'A'], mandatory: true),
  _MetricDef('VC', ['H', 'L', 'N'], mandatory: true),
  _MetricDef('VI', ['H', 'L', 'N'], mandatory: true),
  _MetricDef('VA', ['H', 'L', 'N'], mandatory: true),
  _MetricDef('SC', ['H', 'L', 'N'], mandatory: true),
  _MetricDef('SI', ['H', 'L', 'N'], mandatory: true),
  _MetricDef('SA', ['H', 'L', 'N'], mandatory: true),
  // Threat (1).
  _MetricDef('E', ['X', 'A', 'P', 'U']),
  // Environmental (14): security requirements + modified Base metrics.
  _MetricDef('CR', ['X', 'H', 'M', 'L']),
  _MetricDef('IR', ['X', 'H', 'M', 'L']),
  _MetricDef('AR', ['X', 'H', 'M', 'L']),
  _MetricDef('MAV', ['X', 'N', 'A', 'L', 'P']),
  _MetricDef('MAC', ['X', 'L', 'H']),
  _MetricDef('MAT', ['X', 'N', 'P']),
  _MetricDef('MPR', ['X', 'N', 'L', 'H']),
  _MetricDef('MUI', ['X', 'N', 'P', 'A']),
  _MetricDef('MVC', ['X', 'H', 'L', 'N']),
  _MetricDef('MVI', ['X', 'H', 'L', 'N']),
  _MetricDef('MVA', ['X', 'H', 'L', 'N']),
  _MetricDef('MSC', ['X', 'H', 'L', 'N']),
  _MetricDef('MSI', ['X', 'S', 'H', 'L', 'N']),
  _MetricDef('MSA', ['X', 'S', 'H', 'L', 'N']),
  // Supplemental (6).
  _MetricDef('S', ['X', 'N', 'P']),
  _MetricDef('AU', ['X', 'N', 'Y']),
  _MetricDef('R', ['X', 'A', 'U', 'I']),
  _MetricDef('V', ['X', 'D', 'C']),
  _MetricDef('RE', ['X', 'L', 'M', 'H']),
  _MetricDef('U', ['X', 'Clear', 'Green', 'Amber', 'Red']),
];

/// A parsed, validated CVSS v4.0 vector. Immutable; scoring is pure and cached.
class Cvss4 {
  Cvss4._(this._metrics);

  /// Every metric key → its selected value. Optional metrics that were absent
  /// hold `'X'` (Not Defined); the eleven Base metrics always hold a real value.
  final Map<String, String> _metrics;

  /// Parses [vector] (e.g. `CVSS:4.0/AV:N/AC:L/…`), validating the prefix,
  /// metric ordering, allowed values and the presence of all Base metrics.
  /// Throws a [FormatException] when the vector is invalid.
  factory Cvss4.parseVector(String vector) {
    final parsed = tryParseVector(vector);
    if (parsed == null) {
      throw FormatException('Invalid CVSS v4.0 vector', vector);
    }
    return parsed;
  }

  /// Like [Cvss4.parseVector] but returns `null` instead of throwing.
  static Cvss4? tryParseVector(String vector) {
    final parts = vector.split('/');
    if (parts.isEmpty || parts.first != 'CVSS:4.0') return null;

    final selected = {for (final def in _metricOrder) def.key: 'X'};
    var orderIndex = 0;
    for (final token in parts.skip(1)) {
      final sep = token.indexOf(':');
      if (sep <= 0 || sep == token.length - 1) return null;
      final key = token.substring(0, sep);
      final value = token.substring(sep + 1);

      // Walk the canonical order until we reach this metric, rejecting a Base
      // metric that appears out of order and an unknown/duplicate metric.
      while (true) {
        if (orderIndex >= _metricOrder.length) return null; // too many metrics
        final expected = _metricOrder[orderIndex];
        orderIndex++;
        if (key != expected.key) {
          if (expected.mandatory) return null; // missing mandatory Base metric
          continue; // skip an omitted optional metric and retry
        }
        if (!expected.values.contains(value)) return null; // value not allowed
        selected[key] = value;
        break;
      }
    }

    // A valid vector carries every Base metric.
    for (final def in _metricOrder) {
      if (def.mandatory && selected[def.key] == 'X') return null;
    }
    return Cvss4._(selected);
  }

  /// The value selected for [metric] (its short key, e.g. `'AV'`), or `null`
  /// when [metric] is not a CVSS v4.0 metric. Optional metrics left unset read
  /// as `'X'`.
  String? operator [](String metric) => _metrics[metric];

  /// The canonical vector string: the `CVSS:4.0` prefix followed by every
  /// metric in canonical order, omitting optional metrics left at their
  /// Not-Defined (`X`) default.
  String get vector {
    final buffer = StringBuffer('CVSS:4.0');
    for (final def in _metricOrder) {
      final value = _metrics[def.key]!;
      if (value != 'X') {
        buffer.write('/${def.key}:$value');
      }
    }
    return buffer.toString();
  }

  /// Returns a copy of this vector with the Environmental Security Requirements
  /// `CR`/`IR`/`AR` overwritten (`'X'` clears a requirement), every other metric
  /// preserved. Used to derive a finding's **context (environmental) score**
  /// from its scope object's CIA rating without baking the rating into the
  /// stored vector — so changing the scope object re-scores every finding that
  /// references it. An unrecognised token clamps to `'X'` (Not Defined).
  Cvss4 withEnvironmental({String cr = 'X', String ir = 'X', String ar = 'X'}) {
    final next = Map<String, String>.from(_metrics);
    next['CR'] = _clampValue('CR', cr);
    next['IR'] = _clampValue('IR', ir);
    next['AR'] = _clampValue('AR', ar);
    return Cvss4._(next);
  }

  /// [value] if it is an allowed value for metric [key], else `'X'`.
  static String _clampValue(String key, String value) {
    for (final def in _metricOrder) {
      if (def.key == key) return def.values.contains(value) ? value : 'X';
    }
    return 'X';
  }

  /// The CVSS v4.0 score (0.0–10.0), rounded to one decimal place, computed
  /// via the faithful MacroVector + interpolation algorithm. Cached.
  late final double score = _cvss4Score(_metrics);

  /// The qualitative severity band derived from [score].
  Cvss4Severity get severity => Cvss4Severity.fromScore(score);

  @override
  String toString() => vector;
}
