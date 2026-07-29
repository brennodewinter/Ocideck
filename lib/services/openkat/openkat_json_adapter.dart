import '../../models/openkat/openkat_models.dart';

/// Abstracts over de exportvormen van OpenKAT.
///
/// Adapters halen dezelfde logische feiten op (organisatie, datum, systemen,
/// bevindingen, basisbeveiliging) zonder dat de aanroeper de bronindeling hoeft
/// te kennen. De concrete adapters staan in `openkat_export_adapters.dart`.
///
/// **Waarom dit contract er zo uitziet.** De eerste opzet van deze laag was
/// geschreven zonder een echte export bij de hand: hij zocht naar `systems` en
/// `findings` náást elkaar op het hoogste niveau. Zo ziet een OpenKAT-export er
/// niet uit. Elke echte export heeft één envelop —
/// `{organization_code, organization_name, organization_tags, data}` — en het
/// verschil zit uitsluitend in wat er in `data` staat. Dat is de reden dat
/// [recognizes] op de envelop kijkt en de adapters op de inhoud daarvan.
abstract class OpenKatJsonAdapter {
  const OpenKatJsonAdapter();

  /// De naam die als `schema` in het importmanifest terechtkomt.
  String get name;

  /// Mogelijkheden die deze exportvorm als broncontract aantoonbaar draagt.
  ///
  /// Concrete adapters melden CVE- of monitoringsteun pas wanneer daar een
  /// expliciet bronveld voor bestaat; een lege lijst betekent dus onbekend.
  Set<OpenKatSourceFeature> get sourceFeatures => const {};

  bool recognizes(Map<String, dynamic> json);
  String? organizationCode(Map<String, dynamic> json);
  String? organizationName(Map<String, dynamic> json);
  DateTime? reportDate(Map<String, dynamic> json);

  /// Systeemobjecten in de vorm die [OpenKatNormalizer] verwacht: per systeem
  /// een map met `ooi`, en waar bekend `hostname` en `ip`.
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json);

  /// Bevindingsobjecten: per bevinding een map met `finding_type` (het
  /// KATFindingType-object), `severity`, `ooi` en waar bekend `recommendation`
  /// en `impact`.
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json);

  /// De basisbeveiligingstellers, mét noemer.
  ///
  /// Dit gaf eerder een `Map<String, int>` terug — alleen het aantal conforme
  /// systemen. Daarmee was [OpenKatControlScore.ratio] per definitie null en
  /// kon de aggregator geen enkele trend berekenen, terwijl OpenKAT de noemer
  /// gewoon meelevert (`number_of_compliant` naast `number_of_ips`).
  Map<String, OpenKatControlScore> controlScores(Map<String, dynamic> json);

  /// Leest een datum uit een bestandsnaam.
  ///
  /// OpenKAT stempelt zijn exports als `<organisatie>_20260319200604.json`:
  /// veertien cijfers zonder scheidingstekens. De oude uitdrukking eiste
  /// scheidingstekens (`2026-03-19`) en liet dus juist de vorm liggen die de
  /// exportknop zelf produceert. Beide vormen worden nu herkend, met de
  /// langste eerst — anders leest `20260319200604` als `2026-03-19` plus ruis.
  static DateTime? dateFromFilename(String filename) {
    final stamped = RegExp(r'(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})');
    final stampedMatch = stamped.firstMatch(filename);
    if (stampedMatch != null) {
      final parsed = _dateFrom(stampedMatch, withTime: true);
      if (parsed != null) return parsed;
    }
    final dated = RegExp(r'(\d{4})[-_]?(\d{2})[-_]?(\d{2})');
    final datedMatch = dated.firstMatch(filename);
    if (datedMatch != null) {
      final parsed = _dateFrom(datedMatch, withTime: false);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Dezelfde stempel als [dateFromFilename], maar dan uit een JSON-waarde:
  /// OpenKAT schrijft `created_at` als `"20260319200604"` en niet als ISO-8601.
  static DateTime? parseTimestamp(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    return dateFromFilename(raw);
  }

  static DateTime? _dateFrom(RegExpMatch m, {required bool withTime}) {
    final year = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    final day = int.tryParse(m.group(3)!);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (!withTime) return DateTime.utc(year, month, day);
    final hour = int.tryParse(m.group(4)!) ?? 0;
    final minute = int.tryParse(m.group(5)!) ?? 0;
    final second = int.tryParse(m.group(6)!) ?? 0;
    if (hour > 23 || minute > 59 || second > 59) return null;
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  /// Leest een map, ongeacht of de decoder hem als `Map<String, dynamic>` of
  /// als een losser getypeerde `Map` afleverde.
  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }

  /// Leest een lijst van maps; alles wat geen map is valt weg.
  static List<Map<String, dynamic>> asMapList(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) asMap(item),
    ];
  }
}
