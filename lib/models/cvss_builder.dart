import '../services/cvss/cvss4.dart';

/// Building blocks for the finding wizard's **per-metric CVSS 4.0 builder**
/// (PENTEST_MIAUW §4.1/§7). The [Cvss4] engine parses and scores a vector but
/// offers no fluent builder, so this assembles a canonical vector string from
/// the user's per-metric choices and a scope object's CIA rating, then hands it
/// to [Cvss4.tryParseVector] for the live score/severity.
///
/// Metric and value names are the **English FIRST-published labels** — standard
/// reference content (like CWE names), not localised UI text (§12).

/// One CVSS 4.0 Base metric and its allowed values, in the order FIRST lists
/// them. [options] are `(token, label)` pairs; the first is the builder default.
class Cvss4BaseMetric {
  const Cvss4BaseMetric(this.code, this.label, this.options);

  final String code;
  final String label;
  final List<({String token, String label})> options;

  String get defaultToken => options.first.token;
}

/// The 11 mandatory Base metrics in canonical serialisation order
/// (AV → AC → AT → PR → UI → VC → VI → VA → SC → SI → SA).
const List<Cvss4BaseMetric> kCvss4BaseMetrics = [
  Cvss4BaseMetric('AV', 'Attack Vector', [
    (token: 'N', label: 'Network'),
    (token: 'A', label: 'Adjacent'),
    (token: 'L', label: 'Local'),
    (token: 'P', label: 'Physical'),
  ]),
  Cvss4BaseMetric('AC', 'Attack Complexity', [
    (token: 'L', label: 'Low'),
    (token: 'H', label: 'High'),
  ]),
  Cvss4BaseMetric('AT', 'Attack Requirements', [
    (token: 'N', label: 'None'),
    (token: 'P', label: 'Present'),
  ]),
  Cvss4BaseMetric('PR', 'Privileges Required', [
    (token: 'N', label: 'None'),
    (token: 'L', label: 'Low'),
    (token: 'H', label: 'High'),
  ]),
  Cvss4BaseMetric('UI', 'User Interaction', [
    (token: 'N', label: 'None'),
    (token: 'P', label: 'Passive'),
    (token: 'A', label: 'Active'),
  ]),
  Cvss4BaseMetric('VC', 'Confidentiality (Vulnerable System)', [
    (token: 'H', label: 'High'),
    (token: 'L', label: 'Low'),
    (token: 'N', label: 'None'),
  ]),
  Cvss4BaseMetric('VI', 'Integrity (Vulnerable System)', [
    (token: 'H', label: 'High'),
    (token: 'L', label: 'Low'),
    (token: 'N', label: 'None'),
  ]),
  Cvss4BaseMetric('VA', 'Availability (Vulnerable System)', [
    (token: 'H', label: 'High'),
    (token: 'L', label: 'Low'),
    (token: 'N', label: 'None'),
  ]),
  Cvss4BaseMetric('SC', 'Confidentiality (Subsequent System)', [
    (token: 'N', label: 'None'),
    (token: 'L', label: 'Low'),
    (token: 'H', label: 'High'),
  ]),
  Cvss4BaseMetric('SI', 'Integrity (Subsequent System)', [
    (token: 'N', label: 'None'),
    (token: 'L', label: 'Low'),
    (token: 'H', label: 'High'),
  ]),
  Cvss4BaseMetric('SA', 'Availability (Subsequent System)', [
    (token: 'N', label: 'None'),
    (token: 'L', label: 'Low'),
    (token: 'H', label: 'High'),
  ]),
];

/// The importance of one CIA dimension for a scope object, mapped 1:1 onto a
/// CVSS 4.0 Environmental Security Requirement token (`X`/`L`/`M`/`H`).
enum CiaLevel {
  notDefined('X', 'Not defined'),
  low('L', 'Low'),
  medium('M', 'Medium'),
  high('H', 'High');

  const CiaLevel(this.token, this.label);

  final String token;
  final String label;

  /// The level for an on-disk Environmental token (`H`/`M`/`L`); anything else
  /// (including `X` or an empty cell) reads as [notDefined].
  static CiaLevel fromToken(String value) {
    final v = value.trim().toUpperCase();
    for (final level in values) {
      if (level != notDefined && level.token == v) return level;
    }
    return notDefined;
  }
}

/// A scope object's client-supplied CIA rating (Vertrouwelijkheid / Integriteit /
/// Beschikbaarheid, MIAUW 4.3.3). Each dimension pre-fills the matching CVSS 4.0
/// Environmental Security Requirement (CR/IR/AR), so a finding's score is
/// **CIA-weighted** by default (PENTEST_MIAUW §10.5).
class CiaRating {
  const CiaRating({
    this.confidentiality = CiaLevel.notDefined,
    this.integrity = CiaLevel.notDefined,
    this.availability = CiaLevel.notDefined,
  });

  final CiaLevel confidentiality;
  final CiaLevel integrity;
  final CiaLevel availability;

  /// Whether at least one dimension is set (so it changes the score).
  bool get isDefined =>
      confidentiality != CiaLevel.notDefined ||
      integrity != CiaLevel.notDefined ||
      availability != CiaLevel.notDefined;

  /// The Environmental requirement metrics this rating contributes: `CR` from
  /// confidentiality, `IR` from integrity, `AR` from availability.
  Map<String, String> toEnvironmental() => {
    'CR': confidentiality.token,
    'IR': integrity.token,
    'AR': availability.token,
  };

  CiaRating copyWith({
    CiaLevel? confidentiality,
    CiaLevel? integrity,
    CiaLevel? availability,
  }) => CiaRating(
    confidentiality: confidentiality ?? this.confidentiality,
    integrity: integrity ?? this.integrity,
    availability: availability ?? this.availability,
  );
}

/// Assemble a canonical CVSS 4.0 vector string from the chosen Base metric
/// tokens ([base], code → token; missing codes use the metric default) and an
/// optional [cia] rating whose set dimensions append `CR`/`IR`/`AR`. The result
/// is ordered Base → Environmental, exactly what [Cvss4.tryParseVector] expects.
String assembleCvss4Vector(Map<String, String> base, {CiaRating? cia}) {
  final parts = <String>['CVSS:4.0'];
  for (final metric in kCvss4BaseMetrics) {
    parts.add('${metric.code}:${base[metric.code] ?? metric.defaultToken}');
  }
  if (cia != null) {
    cia.toEnvironmental().forEach((code, token) {
      if (token != 'X') parts.add('$code:$token');
    });
  }
  return parts.join('/');
}

/// The canonical **Base-only** vector for [vector]: each of the eleven Base
/// metrics taken from [vector] when present, else its builder default; any
/// Threat/Environmental/Supplemental metrics are dropped. Seeds the per-metric
/// builder and strips a legacy vector's baked-in `CR`/`IR`/`AR` back to its
/// base — the CIA weighting now lives on the scope object, not the finding.
String baseCvss4Vector(String vector) {
  final parsed = Cvss4.tryParseVector(vector);
  return assembleCvss4Vector({
    for (final m in kCvss4BaseMetrics)
      m.code: parsed?[m.code] ?? m.defaultToken,
  });
}

/// The **context (environmental) score** for a finding whose base vector is
/// [baseVector], weighted by a scope object's [cia] rating. Returns `null` when
/// the rating adds nothing ([CiaRating.isDefined] is false) or [baseVector] does
/// not parse, so a caller renders the base score in those cases. The rating
/// overwrites `CR`/`IR`/`AR`, so a scope object's rating wins over any
/// requirement already baked into the vector (idempotent for a base-only one).
Cvss4? contextCvss(String baseVector, CiaRating cia) {
  if (!cia.isDefined) return null;
  final base = Cvss4.tryParseVector(baseVector);
  if (base == null) return null;
  return base.withEnvironmental(
    cr: cia.confidentiality.token,
    ir: cia.integrity.token,
    ar: cia.availability.token,
  );
}
