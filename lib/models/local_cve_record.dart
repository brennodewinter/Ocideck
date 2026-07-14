import 'dart:convert';

import 'cve_hit.dart';

/// Eén CVE zoals hij in de lokale index staat: het minimum om hem te kunnen
/// vinden en tonen, niet de hele CVE-record.
///
/// De bron (CVE List V5) is enkele gigabytes; wat de bevinding-editor er
/// werkelijk uit gebruikt is een handvol velden. Alles wat we niet tonen wordt
/// bij het indexeren weggegooid — dat scheelt een orde van grootte op schijf en
/// maakt zoeken een bestandsscan in plaats van een databasevraagstuk.
class LocalCveRecord {
  final String id;
  final String title;
  final String description;

  /// Publicatiedatum als ISO-datum (`2021-12-10`), of leeg.
  final String published;

  /// CVSS-basisscore, of null als de bron er geen gaf.
  final double? score;

  /// De CVSS-vectorstring, of leeg. Kan v3.1 of v4.0 zijn — de bron mengt ze.
  final String vector;

  const LocalCveRecord({
    required this.id,
    this.title = '',
    this.description = '',
    this.published = '',
    this.score,
    this.vector = '',
  });

  /// Dezelfde vorm als een online treffer, zodat de CVE-picker niet hoeft te
  /// weten waar zijn resultaten vandaan komen — en de gebruiker geen tweede,
  /// net iets andere lijst voorgeschoteld krijgt.
  ///
  /// De titel gaat vóór de beschrijving: die is er niet altijd, en waar hij er
  /// is zegt hij in vijf woorden wat de beschrijving in vijftig zegt.
  CveHit toHit() => CveHit(
    id: id,
    description: title.isEmpty
        ? description
        : (description.isEmpty ? title : '$title — $description'),
    cvssScore: score,
    cvssSeverity: _severity,
    published: published,
  );

  /// De CVSS-band bij [score], in dezelfde woorden als de online bronnen ze
  /// geven (NVD schrijft ze in hoofdletters).
  String get _severity {
    final s = score;
    if (s == null) return '';
    if (s <= 0.0) return 'NONE';
    if (s < 4.0) return 'LOW';
    if (s < 7.0) return 'MEDIUM';
    if (s < 9.0) return 'HIGH';
    return 'CRITICAL';
  }

  /// Korte sleutels: dit staat 300.000 keer op schijf, dus elke byte telt.
  Map<String, dynamic> toJson() => {
    'i': id,
    if (title.isNotEmpty) 't': title,
    if (description.isNotEmpty) 'd': description,
    if (published.isNotEmpty) 'p': published,
    if (score != null) 's': score,
    if (vector.isNotEmpty) 'v': vector,
  };

  static LocalCveRecord fromJson(Map<String, dynamic> json) => LocalCveRecord(
    id: (json['i'] as String?) ?? '',
    title: (json['t'] as String?) ?? '',
    description: (json['d'] as String?) ?? '',
    published: (json['p'] as String?) ?? '',
    score: (json['s'] as num?)?.toDouble(),
    vector: (json['v'] as String?) ?? '',
  );

  /// Eén regel van het indexbestand (JSONL). Nooit een letterlijke newline in de
  /// waarde: `jsonEncode` escapet hem, dus een regel blijft een regel.
  String toIndexLine() => jsonEncode(toJson());

  /// Null wanneer de regel geen bruikbare record is (leeg of stuk). Een kapotte
  /// regel mag de hele index niet onbruikbaar maken.
  static LocalCveRecord? tryParseIndexLine(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;
      final record = fromJson(json);
      return record.id.isEmpty ? null : record;
    } on FormatException {
      return null;
    }
  }
}
