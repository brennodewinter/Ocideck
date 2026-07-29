import '../../models/openkat/openkat_models.dart';
import 'openkat_json_adapter.dart';

/// De twee exportvormen van OpenKAT, en wat ze delen.
///
/// Elke export heeft dezelfde envelop:
///
/// ```json
/// {"organization_code": "…", "organization_name": "…",
///  "organization_tags": [], "data": { … }}
/// ```
///
/// Het verschil zit in `data`:
///
/// * **Organisatierapport** ([OpenKatAggregateReportAdapter]) — één vlakke
///   samenvatting over de hele organisatie: `systems`, `findings`,
///   `basic_security`, `open_ports`, `summary`, `total_*`.
/// * **Rapporten per asset** ([OpenKatAssetReportsAdapter]) — `data` is
///   gesleuteld op rapporttype (`dns-report`, `mail-report`, …) en daarbinnen
///   op OOI-verwijzing, met per OOI een blokje
///   `{data, template, report_name, input_oois, report_types, plugins,
///   created_at}`.
///
/// De binnenkant is voor beide dezelfde: een `finding_types`-lijst met
/// KATFindingType-objecten, een `services`-map van OOI naar hostnamen, en
/// tellers als `number_of_compliant` naast `number_of_ips`. Die gedeelde
/// binnenkant staat in dit bestand één keer, in [OpenKatShapes].

/// De envelop die beide vormen delen.
abstract class OpenKatEnvelopeAdapter extends OpenKatJsonAdapter {
  const OpenKatEnvelopeAdapter();

  @override
  Set<OpenKatSourceFeature> get sourceFeatures => const {
    OpenKatSourceFeature.stableAssetIdentity,
  };

  /// De inhoud van `data`, of een lege map wanneer die ontbreekt.
  Map<String, dynamic> payload(Map<String, dynamic> json) =>
      OpenKatJsonAdapter.asMap(json['data']);

  /// Of dit een OpenKAT-envelop is. De adapters daaronder kijken vervolgens
  /// naar de vórm van `data`; deze controle alleen is niet genoeg om te kiezen.
  static bool isEnvelope(Map<String, dynamic> json) =>
      json['data'] is Map && json['organization_code'] is String;

  @override
  String? organizationCode(Map<String, dynamic> json) {
    final code = json['organization_code'];
    return code is String && code.isNotEmpty ? code : null;
  }

  @override
  String? organizationName(Map<String, dynamic> json) {
    final name = json['organization_name'];
    if (name is String && name.isNotEmpty) return name;
    return organizationCode(json);
  }
}

/// `data` is één vlakke samenvatting over de hele organisatie.
class OpenKatAggregateReportAdapter extends OpenKatEnvelopeAdapter {
  const OpenKatAggregateReportAdapter();

  @override
  Set<OpenKatSourceFeature> get sourceFeatures => const {
    OpenKatSourceFeature.stableAssetIdentity,
    OpenKatSourceFeature.stableFindingIdentity,
    OpenKatSourceFeature.reliableOpenedAt,
  };

  @override
  String get name => 'openkat-organisatierapport';

  @override
  bool recognizes(Map<String, dynamic> json) {
    if (!OpenKatEnvelopeAdapter.isEnvelope(json)) return false;
    final data = payload(json);
    // `findings` en `systems` op dít niveau maken het een organisatierapport;
    // bij de assetvorm zitten die een laag dieper, per OOI.
    return data['findings'] is Map ||
        data['systems'] is Map ||
        data['total_systems'] is int;
  }

  /// Het organisatierapport draagt zelf geen datum: de exportknop stempelt de
  /// bestandsnaam en niet de inhoud. De scanner valt daarom terug op
  /// [OpenKatJsonAdapter.dateFromFilename] — dat is geen tekortkoming van deze
  /// adapter maar van het bronformaat, en het staat hier zodat de volgende
  /// lezer niet nog eens gaat zoeken.
  @override
  DateTime? reportDate(Map<String, dynamic> json) => null;

  @override
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json) {
    final systems = OpenKatJsonAdapter.asMap(payload(json)['systems']);
    return OpenKatShapes.systemsFromServices(
      OpenKatJsonAdapter.asMap(systems['services']),
    );
  }

  @override
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json) {
    final findings = OpenKatJsonAdapter.asMap(payload(json)['findings']);
    return OpenKatShapes.findingsFromOccurrences(
      OpenKatJsonAdapter.asMapList(findings['finding_types']),
    );
  }

  @override
  Map<String, OpenKatControlScore> controlScores(Map<String, dynamic> json) {
    final security = OpenKatJsonAdapter.asMap(payload(json)['basic_security']);
    return OpenKatShapes.controlsFromBasicSecuritySummary(
      OpenKatJsonAdapter.asMap(security['summary']),
    );
  }
}

/// `data` is gesleuteld op rapporttype en daarbinnen op OOI.
class OpenKatAssetReportsAdapter extends OpenKatEnvelopeAdapter {
  const OpenKatAssetReportsAdapter();

  @override
  String get name => 'openkat-assetrapporten';

  @override
  bool recognizes(Map<String, dynamic> json) {
    if (!OpenKatEnvelopeAdapter.isEnvelope(json)) return false;
    final data = payload(json);
    if (data.isEmpty) return false;
    // Elke waarde is een map van OOI naar een rapportblok. Eén herkend blok is
    // genoeg; een export met alleen lege rapporttypes hoort ook binnen te
    // komen, want "nul bevindingen" is een geldige uitkomst.
    for (final entry in data.entries) {
      final byOoi = entry.value;
      if (byOoi is! Map) return false;
      for (final report in byOoi.values) {
        if (report is Map && report.containsKey('template')) return true;
      }
    }
    return false;
  }

  @override
  DateTime? reportDate(Map<String, dynamic> json) {
    // Elk rapportblok draagt hetzelfde stempel `created_at`. De vroegste
    // winnen laat de datum niet verspringen wanneer een export tijdens het
    // schrijven een seconde overgaat.
    DateTime? earliest;
    _forEachReport(json, (type, ooi, report) {
      final stamp = OpenKatJsonAdapter.parseTimestamp(report['created_at']);
      if (stamp == null) return;
      if (earliest == null || stamp.isBefore(earliest!)) earliest = stamp;
    });
    return earliest;
  }

  @override
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json) {
    final out = <Map<String, dynamic>>[];
    _forEachReport(json, (type, ooi, report) {
      if (type != 'systems-report') return;
      final data = OpenKatJsonAdapter.asMap(report['data']);
      out.addAll(
        OpenKatShapes.systemsFromServices(
          OpenKatJsonAdapter.asMap(data['services']),
        ),
      );
    });
    return out;
  }

  @override
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json) {
    final out = <Map<String, dynamic>>[];
    // Álle rapporttypes worden afgelopen, ook de types die we niet bij naam
    // kennen: OpenKAT vult `findings-report` alleen wanneer er expliciet om
    // een bevindingenrapport is gevraagd, terwijl de deelrapporten hun
    // bevindingen altijd meedragen. Een onbekend rapporttype levert zo niets
    // op in plaats van stil zijn bevindingen te laten vallen.
    _forEachReport(json, (type, ooi, report) {
      final data = OpenKatJsonAdapter.asMap(report['data']);
      // Twee vormen naast elkaar: de deelrapporten dragen een kale lijst
      // KATFindingType-objecten, het bevindingenrapport draagt paren van
      // type + waarnemingen.
      out.addAll(
        OpenKatShapes.findingsFromOccurrences(
          OpenKatJsonAdapter.asMapList(data['finding_types']),
          fallbackOoi: ooi,
        ),
      );
    });
    return out;
  }

  @override
  Map<String, OpenKatControlScore> controlScores(Map<String, dynamic> json) {
    final totals = <String, ({int compliant, int total})>{};
    _forEachReport(json, (type, ooi, report) {
      final counts = OpenKatShapes.controlFromCounts(
        type,
        OpenKatJsonAdapter.asMap(report['data']),
      );
      if (counts == null) return;
      final running = totals[counts.name];
      totals[counts.name] = (
        compliant: (running?.compliant ?? 0) + counts.compliant,
        total: (running?.total ?? 0) + counts.total,
      );
    });
    return {
      for (final entry in totals.entries)
        entry.key: OpenKatControlScore(
          name: entry.key,
          compliant: entry.value.compliant,
          total: entry.value.total,
        ),
    };
  }

  /// Loopt elk `(rapporttype, OOI, rapportblok)` af.
  void _forEachReport(
    Map<String, dynamic> json,
    void Function(String type, String ooi, Map<String, dynamic> report) visit,
  ) {
    for (final typeEntry in payload(json).entries) {
      final byOoi = typeEntry.value;
      if (byOoi is! Map) continue;
      for (final ooiEntry in byOoi.entries) {
        final report = ooiEntry.value;
        if (report is! Map) continue;
        visit(
          typeEntry.key,
          ooiEntry.key.toString(),
          OpenKatJsonAdapter.asMap(report),
        );
      }
    }
  }
}

/// De binnenkant die beide exportvormen delen.
///
/// Losse functies met platte in- en uitvoer, zodat ze zonder een hele export
/// te bouwen te toetsen zijn — en zodat de adapters erboven leesbaar blijven.
abstract final class OpenKatShapes {
  /// `{"IPAddressV4|internet|1.2.3.4": {"hostnames": [...], "services": [...]}}`
  /// naar systeemobjecten.
  static List<Map<String, dynamic>> systemsFromServices(
    Map<String, dynamic> services,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final entry in services.entries) {
      final ooi = entry.key;
      final value = OpenKatJsonAdapter.asMap(entry.value);
      final hostnames = value['hostnames'];
      out.add({
        'ooi': ooi,
        if (ipFromOoi(ooi) != null) 'ip': ipFromOoi(ooi),
        if (hostnames is List && hostnames.isNotEmpty)
          'hostname': _hostnameOf(hostnames.first),
      });
    }
    return out;
  }

  /// Bevindingen uit een `finding_types`-lijst.
  ///
  /// Twee vormen komen hier binnen, en het onderscheid is één sleutel:
  ///
  /// * `{"finding_type": {...}, "occurrences": [{"finding": {...}}]}` — het
  ///   organisatierapport, één regel per wáárneming;
  /// * `{"object_type": "KATFindingType", "id": …}` — een deelrapport, dat het
  ///   type kaal noemt bij de OOI waar het rapport over gaat.
  static List<Map<String, dynamic>> findingsFromOccurrences(
    List<Map<String, dynamic>> findingTypes, {
    String? fallbackOoi,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final entry in findingTypes) {
      final paired = entry['finding_type'];
      if (paired is Map) {
        final type = OpenKatJsonAdapter.asMap(paired);
        final occurrences = OpenKatJsonAdapter.asMapList(entry['occurrences']);
        if (occurrences.isEmpty) {
          out.add(_finding(type, ooi: fallbackOoi));
          continue;
        }
        for (final occurrence in occurrences) {
          final finding = OpenKatJsonAdapter.asMap(occurrence['finding']);
          out.add(
            _finding(
              type,
              ooi: finding['ooi']?.toString() ?? fallbackOoi,
              primaryKey: finding['primary_key']?.toString(),
              description: finding['description']?.toString(),
              firstSeen: occurrence['first_seen']?.toString(),
            ),
          );
        }
        continue;
      }
      // Kale KATFindingType: het deelrapport noemt het type, de OOI is die van
      // het rapport zelf.
      if (entry['id'] != null || entry['primary_key'] != null) {
        out.add(_finding(entry, ooi: fallbackOoi));
      }
    }
    return out;
  }

  /// De basisbeveiligingssamenvatting van het organisatierapport:
  /// `{"Web": {"rpki": {"number_of_compliant": 1, "total": 1}, …}}`.
  ///
  /// De termen (`Web`, `Mail`, `Other`, …) worden opgeteld: het deck spreekt
  /// over de organisatie, niet over één systeemsoort. De term blijft wél in de
  /// naam staan zodra er meer dan één is, anders verdwijnt een slechte
  /// mailscore stil in een goede webscore.
  static Map<String, OpenKatControlScore> controlsFromBasicSecuritySummary(
    Map<String, dynamic> summary,
  ) {
    final out = <String, OpenKatControlScore>{};
    final multipleTerms = summary.length > 1;
    for (final termEntry in summary.entries) {
      final controls = OpenKatJsonAdapter.asMap(termEntry.value);
      for (final controlEntry in controls.entries) {
        final counts = OpenKatJsonAdapter.asMap(controlEntry.value);
        final compliant = counts['number_of_compliant'];
        final total = counts['total'] ?? counts['number_of_ips'];
        if (compliant is! int || total is! int) continue;
        final label = multipleTerms
            ? '${controlEntry.key} (${termEntry.key})'
            : controlEntry.key;
        out[label] = OpenKatControlScore(
          name: label,
          compliant: compliant,
          total: total,
        );
      }
    }
    return out;
  }

  /// De tellers van één deelrapport, wanneer dat rapport er een draagt.
  ///
  /// `rpki-report` en `safe-connections-report` tellen conforme systemen; de
  /// overige deelrapporten dragen geen noemer en leveren dus niets — een score
  /// zonder noemer is geen score.
  static ({String name, int compliant, int total})? controlFromCounts(
    String reportType,
    Map<String, dynamic> data,
  ) {
    final total = data['number_of_ips'];
    if (total is! int || total == 0) return null;
    final compliant = switch (reportType) {
      'rpki-report' => data['number_of_compliant'],
      'safe-connections-report' => data['number_of_available'],
      _ => null,
    };
    if (compliant is! int) return null;
    return (name: reportType, compliant: compliant, total: total);
  }

  /// Het IP-adres uit een OOI-verwijzing, of null wanneer het er geen draagt.
  static String? ipFromOoi(String ooi) {
    final lower = ooi.toLowerCase();
    if (!lower.startsWith('ipaddressv4|') &&
        !lower.startsWith('ipaddressv6|')) {
      return null;
    }
    final parts = ooi.split('|');
    return parts.length >= 3 ? parts.sublist(2).join('|') : null;
  }

  static String? _hostnameOf(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      final name = OpenKatJsonAdapter.asMap(value)['name'];
      if (name is String) return name;
    }
    return null;
  }

  static Map<String, dynamic> _finding(
    Map<String, dynamic> type, {
    String? ooi,
    String? primaryKey,
    String? description,
    String? firstSeen,
  }) {
    final id =
        type['id']?.toString() ??
        type['primary_key']?.toString().split('|').last;
    return {
      'finding_type': {
        // `name` is in echte exports geregeld null (KAT-NO-SECURITY-TXT).
        // Terugvallen op de id houdt de dia leesbaar in plaats van "null".
        'id': id,
        'name': type['name'] ?? id,
      },
      'severity': type['risk_severity']?.toString() ?? 'unknown',
      'ooi': ?ooi,
      'primary_key': ?primaryKey,
      if (type['recommendation'] != null)
        'recommendation': type['recommendation'],
      if (type['impact'] != null) 'impact': type['impact'],
      'description': ?description,
      'first_seen': ?firstSeen,
    };
  }
}

/// De adapters, in de volgorde waarin de scanner ze probeert.
///
/// Het organisatierapport staat voorop: het is specifieker (`data.findings`)
/// dan de assetvorm, die alleen naar de vórm van `data` kijkt.
const List<OpenKatJsonAdapter> openKatAdapters = [
  OpenKatAggregateReportAdapter(),
  OpenKatAssetReportsAdapter(),
];
