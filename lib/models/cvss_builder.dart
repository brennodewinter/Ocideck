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
/// them. [options] are `(token, label, dutchLabel)` records; the first is the
/// builder default. [label] is the English FIRST-published name (stable
/// reference); [dutchLabel] is the Dutch source shown in the UI (localise with
/// `l10n.d(...)`), so the builder reads in the interface language.
class Cvss4BaseMetric {
  const Cvss4BaseMetric(this.code, this.label, this.dutchLabel, this.options);

  final String code;
  final String label;
  final String dutchLabel;
  final List<({String token, String label, String dutchLabel})> options;

  String get defaultToken => options.first.token;
}

/// The 11 mandatory Base metrics in canonical serialisation order
/// (AV → AC → AT → PR → UI → VC → VI → VA → SC → SI → SA).
const List<Cvss4BaseMetric> kCvss4BaseMetrics =
    [
      Cvss4BaseMetric('AV', 'Attack Vector', 'Aanvalsvector', [
        (token: 'N', label: 'Network', dutchLabel: 'Netwerk'),
        (token: 'A', label: 'Adjacent', dutchLabel: 'Aangrenzend'),
        (token: 'L', label: 'Local', dutchLabel: 'Lokaal'),
        (token: 'P', label: 'Physical', dutchLabel: 'Fysiek'),
      ]),
      Cvss4BaseMetric('AC', 'Attack Complexity', 'Aanvalscomplexiteit', [
        (token: 'L', label: 'Low', dutchLabel: 'Laag'),
        (token: 'H', label: 'High', dutchLabel: 'Hoog'),
      ]),
      Cvss4BaseMetric('AT', 'Attack Requirements', 'Aanvalsvereisten', [
        (token: 'N', label: 'None', dutchLabel: 'Geen'),
        (token: 'P', label: 'Present', dutchLabel: 'Aanwezig'),
      ]),
      Cvss4BaseMetric('PR', 'Privileges Required', 'Vereiste rechten', [
        (token: 'N', label: 'None', dutchLabel: 'Geen'),
        (token: 'L', label: 'Low', dutchLabel: 'Laag'),
        (token: 'H', label: 'High', dutchLabel: 'Hoog'),
      ]),
      Cvss4BaseMetric('UI', 'User Interaction', 'Gebruikersinteractie', [
        (token: 'N', label: 'None', dutchLabel: 'Geen'),
        (token: 'P', label: 'Passive', dutchLabel: 'Passief'),
        (token: 'A', label: 'Active', dutchLabel: 'Actief'),
      ]),
      Cvss4BaseMetric(
        'VC',
        'Confidentiality (Vulnerable System)',
        'Vertrouwelijkheid (kwetsbaar systeem)',
        [
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
        ],
      ),
      Cvss4BaseMetric(
        'VI',
        'Integrity (Vulnerable System)',
        'Integriteit (kwetsbaar systeem)',
        [
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
        ],
      ),
      Cvss4BaseMetric(
        'VA',
        'Availability (Vulnerable System)',
        'Beschikbaarheid (kwetsbaar systeem)',
        [
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
        ],
      ),
      Cvss4BaseMetric(
        'SC',
        'Confidentiality (Subsequent System)',
        'Vertrouwelijkheid (vervolgsysteem)',
        [
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
        ],
      ),
      Cvss4BaseMetric(
        'SI',
        'Integrity (Subsequent System)',
        'Integriteit (vervolgsysteem)',
        [
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
        ],
      ),
      Cvss4BaseMetric(
        'SA',
        'Availability (Subsequent System)',
        'Beschikbaarheid (vervolgsysteem)',
        [
          (token: 'N', label: 'None', dutchLabel: 'Geen'),
          (token: 'L', label: 'Low', dutchLabel: 'Laag'),
          (token: 'H', label: 'High', dutchLabel: 'Hoog'),
        ],
      ),
    ];

/// The importance of one CIA dimension for a scope object, mapped 1:1 onto a
/// CVSS 4.0 Environmental Security Requirement token (`X`/`L`/`M`/`H`).
enum CiaLevel {
  notDefined('X', 'Not defined', 'Niet gedefinieerd'),
  low('L', 'Low', 'Laag'),
  medium('M', 'Medium', 'Middel'),
  high('H', 'High', 'Hoog');

  const CiaLevel(this.token, this.label, this.dutchLabel);

  final String token;
  final String label;

  /// Dutch source label for the UI; localise with `l10n.d(level.dutchLabel)`.
  final String dutchLabel;

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
