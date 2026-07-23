/// Abstracts over the two supported OpenKAT export schema families.
///
/// Adapters extract the same logical facts (organization, date, systems,
/// findings, controls) without the caller needing to know the source layout.
abstract class OpenKatJsonAdapter {
  const OpenKatJsonAdapter();

  String get name;
  bool recognizes(Map<String, dynamic> json);
  String? organizationCode(Map<String, dynamic> json);
  String? organizationName(Map<String, dynamic> json);
  DateTime? reportDate(Map<String, dynamic> json);

  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json);
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json);
  Map<String, int> controlScores(Map<String, dynamic> json);

  /// Stable value extractor used by the normalizer.
  static String? stringAt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String) return value;
      if (value is Map) {
        final nested = value[key];
        if (nested is String) return nested;
      }
    }
    return null;
  }

  static DateTime? dateFromFilename(String filename) {
    final re = RegExp(r'(\d{4})[-_](\d{2})[-_](\d{2})');
    final m = re.firstMatch(filename);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }
}

/// Aggregate organisation report: a single JSON object summarising the whole
/// organisation, with nested objects/arrays for systems and findings.
class OpenKatAggregateAdapter extends OpenKatJsonAdapter {
  const OpenKatAggregateAdapter();

  @override
  String get name => 'openkat-aggregate';

  @override
  bool recognizes(Map<String, dynamic> json) {
    return json.containsKey('organization') ||
        json.containsKey('organization_code') ||
        json.containsKey('report_date');
  }

  @override
  String? organizationCode(Map<String, dynamic> json) {
    final org = json['organization'];
    if (org is Map) return org['code']?.toString() ?? org['id']?.toString();
    return json['organization_code']?.toString() ??
        json['organization']?.toString();
  }

  @override
  String? organizationName(Map<String, dynamic> json) {
    final org = json['organization'];
    if (org is Map) return org['name']?.toString();
    return json['organization_name']?.toString() ??
        json['organization']?.toString();
  }

  @override
  DateTime? reportDate(Map<String, dynamic> json) {
    final raw = json['report_date'] ?? json['date'] ?? json['created_at'];
    return _parseDate(raw);
  }

  @override
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json) {
    final systems = json['systems'];
    if (systems is List) {
      return [for (final s in systems) _asMap(s)];
    }
    final hosts = json['hostnames'] ?? json['ips'];
    if (hosts is List) {
      return [for (final h in hosts) _asMap(h)];
    }
    return [];
  }

  @override
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json) {
    final findings = json['findings'];
    if (findings is List) {
      return [for (final f in findings) _asMap(f)];
    }
    return [];
  }

  @override
  Map<String, int> controlScores(Map<String, dynamic> json) {
    final controls = json['controls'] ?? json['technical_controls'];
    if (controls is! Map) return const {};
    final out = <String, int>{};
    for (final entry in controls.entries) {
      final value = entry.value;
      if (value is int) {
        out[entry.key.toString()] = value;
      } else if (value is Map) {
        final c = value['compliant'] ?? value['score'];
        if (c is int) out[entry.key.toString()] = c;
      }
    }
    return out;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    if (raw is Map && raw['date'] is String) {
      return DateTime.tryParse(raw['date'] as String);
    }
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }
}

/// Per-asset, per-report-type exports: a JSON object that may contain a report
/// per asset or a list of reports. We treat the top-level object as the report
/// and look for asset/finding arrays inside.
class OpenKatPerAssetAdapter extends OpenKatJsonAdapter {
  const OpenKatPerAssetAdapter();

  @override
  String get name => 'openkat-per-asset';

  @override
  bool recognizes(Map<String, dynamic> json) {
    return json.containsKey('reports') ||
        json.containsKey('report_types') ||
        json.containsKey('oois') ||
        json.containsKey('observed_at');
  }

  @override
  String? organizationCode(Map<String, dynamic> json) {
    final raw = json['organization_code'] ?? json['organization'];
    if (raw is String) return raw;
    if (raw is Map) return raw['code']?.toString();
    final reports = json['reports'];
    if (reports is List && reports.isNotEmpty) {
      final first = _asMap(reports.first);
      final org = first['organization'] ?? first['organization_code'];
      if (org is String) return org;
      if (org is Map) return org['code']?.toString();
    }
    return null;
  }

  @override
  String? organizationName(Map<String, dynamic> json) {
    final raw = json['organization_name'] ?? json['organization'];
    if (raw is String) return raw;
    if (raw is Map) return raw['name']?.toString();
    return null;
  }

  @override
  DateTime? reportDate(Map<String, dynamic> json) {
    final raw =
        json['observed_at'] ??
        json['created_at'] ??
        json['report_date'] ??
        json['valid_time'];
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is Map && raw['start'] is String) {
      return DateTime.tryParse(raw['start'] as String);
    }
    return null;
  }

  @override
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json) {
    final oois = json['oois'];
    if (oois is List) {
      return [for (final o in oois) _asMap(o)];
    }
    final reports = json['reports'];
    final out = <Map<String, dynamic>>[];
    if (reports is List) {
      for (final r in reports) {
        final report = _asMap(r);
        final inputOois = report['input_oois'] ?? report['oois'];
        if (inputOois is List) {
          out.addAll([for (final o in inputOois) _asMap(o)]);
        }
      }
    }
    return out;
  }

  @override
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json) {
    final findings = json['findings'];
    if (findings is List) {
      return [for (final f in findings) _asMap(f)];
    }
    final reports = json['reports'];
    final out = <Map<String, dynamic>>[];
    if (reports is List) {
      for (final r in reports) {
        final report = _asMap(r);
        final items = report['findings'] ?? report['items'];
        if (items is List) {
          out.addAll([for (final f in items) _asMap(f)]);
        }
      }
    }
    return out;
  }

  @override
  Map<String, int> controlScores(Map<String, dynamic> json) {
    final out = <String, int>{};
    final reports = json['reports'];
    if (reports is List) {
      for (final r in reports) {
        final report = _asMap(r);
        if (report['report_type']?.toString().contains('control') == true) {
          final results = report['results'] ?? report['data'];
          if (results is Map) {
            for (final entry in results.entries) {
              final value = entry.value;
              if (value is int) {
                out[entry.key.toString()] = value;
              } else if (value is Map) {
                final c = value['compliant'] ?? value['score'];
                if (c is int) out[entry.key.toString()] = c;
              }
            }
          }
        }
      }
    }
    return out;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }
}

const List<OpenKatJsonAdapter> openKatAdapters = [
  OpenKatAggregateAdapter(),
  OpenKatPerAssetAdapter(),
];
