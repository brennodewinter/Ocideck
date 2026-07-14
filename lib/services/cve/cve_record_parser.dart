import '../../models/local_cve_record.dart';

/// Leest één CVE-record uit het CVE List V5-formaat (`dataVersion: 5.x`) en
/// houdt alleen over wat de bevinding-editor toont.
///
/// Twee dingen die je pas ziet als je echte records bekijkt:
///
///  * De CVSS-score staat lang niet altijd bij de CNA. Voor veel oudere CVE's
///    is hij later door een ADP (bijv. CISA-ADP) toegevoegd en staat hij in
///    `containers.adp[].metrics`. Alleen `containers.cna.metrics` lezen levert
///    dus voor een groot deel van de corpus géén score op.
///  * `metrics` is een lijst van objecten met wisselende sleutels
///    (`cvssV4_0`, `cvssV3_1`, `cvssV3_0`, `other`, …). We nemen de nieuwste
///    CVSS die we vinden en negeren de rest.
class CveRecordParser {
  const CveRecordParser._();

  /// Op nieuwste-eerst: een record dat zowel v4.0 als v3.1 draagt levert v4.0.
  static const _cvssKeys = ['cvssV4_0', 'cvssV3_1', 'cvssV3_0', 'cvssV2_0'];

  /// Descriptions kunnen lang zijn (soms kilobytes). De picker toont een paar
  /// regels, dus knippen we af — over 300.000 records scheelt dat gigabytes.
  static const maxDescription = 400;

  /// Null wanneer dit geen bruikbaar, gepubliceerd CVE-record is (een
  /// gereserveerde of teruggetrokken id heeft geen inhoud om te tonen).
  static LocalCveRecord? parse(Map<String, dynamic> json) {
    final meta = json['cveMetadata'];
    if (meta is! Map) return null;
    final id = (meta['cveId'] as String?)?.trim() ?? '';
    if (id.isEmpty) return null;

    // REJECTED/RESERVED dragen geen beschrijving; ze in de index zetten levert
    // alleen ruis in de zoekresultaten op.
    final state = (meta['state'] as String?)?.toUpperCase() ?? '';
    if (state != 'PUBLISHED') return null;

    final containers = json['containers'];
    final cna = containers is Map ? containers['cna'] : null;

    final title = cna is Map ? ((cna['title'] as String?) ?? '') : '';
    final description = cna is Map ? _description(cna['descriptions']) : '';

    final (score, vector) = _cvss(containers);

    return LocalCveRecord(
      id: id,
      title: title.trim(),
      description: description,
      published: _isoDate(meta['datePublished']),
      score: score,
      vector: vector,
    );
  }

  /// De Engelstalige beschrijving, of anders de eerste die er is — een record
  /// met alleen een Spaanse beschrijving is nog altijd beter dan een lege.
  static String _description(Object? descriptions) {
    if (descriptions is! List) return '';
    String? fallback;
    for (final d in descriptions) {
      if (d is! Map) continue;
      final value = (d['value'] as String?)?.trim();
      if (value == null || value.isEmpty) continue;
      final lang = (d['lang'] as String?)?.toLowerCase() ?? '';
      if (lang.startsWith('en')) return _clip(value);
      fallback ??= value;
    }
    return fallback == null ? '' : _clip(fallback);
  }

  static String _clip(String value) {
    final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= maxDescription
        ? flat
        : '${flat.substring(0, maxDescription).trimRight()}…';
  }

  /// Zoekt de beste CVSS in zowel de CNA- als de ADP-containers.
  static (double?, String) _cvss(Object? containers) {
    if (containers is! Map) return (null, '');

    final metricLists = <Object?>[
      if (containers['cna'] is Map) (containers['cna'] as Map)['metrics'],
      if (containers['adp'] is List)
        for (final adp in containers['adp'] as List)
          if (adp is Map) adp['metrics'],
    ];

    for (final key in _cvssKeys) {
      for (final metrics in metricLists) {
        if (metrics is! List) continue;
        for (final metric in metrics) {
          if (metric is! Map) continue;
          final cvss = metric[key];
          if (cvss is! Map) continue;
          final score = (cvss['baseScore'] as num?)?.toDouble();
          final vector = (cvss['vectorString'] as String?) ?? '';
          if (score != null || vector.isNotEmpty) return (score, vector);
        }
      }
    }
    return (null, '');
  }

  /// `2021-12-10T00:00:00.000Z` → `2021-12-10`. Onparsebaar → leeg.
  static String _isoDate(Object? value) {
    if (value is! String || value.isEmpty) return '';
    final t = value.indexOf('T');
    final date = t > 0 ? value.substring(0, t) : value;
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ? date : '';
  }
}
