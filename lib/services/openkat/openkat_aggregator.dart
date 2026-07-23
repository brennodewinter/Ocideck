import '../../models/openkat/openkat_models.dart';

/// Aggregates OpenKAT snapshots into management metrics and ranked lists.
class OpenKatAggregator {
  const OpenKatAggregator();

  PortfolioAggregate aggregatePortfolio(
    List<OpenKatOrganization> organizations,
  ) {
    final current = organizations
        .map((o) => o.current)
        .whereType<OpenKatSnapshot>()
        .toList();
    final previous = organizations
        .map((o) => o.previous)
        .whereType<OpenKatSnapshot>()
        .toList();

    return PortfolioAggregate(
      current: _aggregateSnapshots(current, prefix: 'current'),
      previous: previous.isEmpty
          ? null
          : _aggregateSnapshots(previous, prefix: 'previous'),
      organizations: organizations,
    );
  }

  SnapshotAggregate aggregateSnapshot(OpenKatSnapshot snapshot) {
    return _aggregateSnapshots([snapshot], prefix: '');
  }

  SnapshotAggregate _aggregateSnapshots(
    List<OpenKatSnapshot> snapshots, {
    required String prefix,
  }) {
    final findings = snapshots.expand((s) => s.findings).toList();
    final systems = snapshots.expand((s) => s.systems).toSet().toList();

    final severityCounts = <String, int>{
      'critical': 0,
      'high': 0,
      'medium': 0,
      'low': 0,
    };
    for (final f in findings) {
      severityCounts[f.severity] = (severityCounts[f.severity] ?? 0) + 1;
    }

    final findingTypes = findings.map((f) => f.findingTypeId).toSet();
    final affectedSystems = findings
        .map((f) => f.systemId)
        .whereType<String>()
        .toSet();
    final criticalHighSystems = findings
        .where((f) => f.severity == 'critical' || f.severity == 'high')
        .map((f) => f.systemId)
        .whereType<String>()
        .toSet();

    final controls = <String, OpenKatControlScore>{};
    for (final snapshot in snapshots) {
      for (final entry in snapshot.controls.entries) {
        final existing = controls[entry.key];
        if (existing == null) {
          controls[entry.key] = entry.value;
        } else {
          final c = (entry.value.compliant ?? 0) + (existing.compliant ?? 0);
          final t = (entry.value.total ?? 0) + (existing.total ?? 0);
          controls[entry.key] = OpenKatControlScore(
            name: entry.value.name,
            compliant: c,
            total: t == 0 ? null : t,
          );
        }
      }
    }

    final hostnames = systems.where((s) => s.hostname != null).length;
    final ipv4 = systems.where((s) => _isIpv4(s.ip)).length;
    final ipv6 = systems.where((s) => _isIpv6(s.ip)).length;

    return SnapshotAggregate(
      totalSystems: systems.length,
      hostnames: hostnames,
      ipv4: ipv4,
      ipv6: ipv6,
      webObjects: systems.where((s) => s.hostname != null).length,
      severityCounts: severityCounts,
      uniqueFindingTypes: findingTypes.length,
      affectedSystems: affectedSystems.length,
      criticalHighSystems: criticalHighSystems.length,
      controls: controls,
      findings: findings,
    );
  }

  /// Compare [current] and [previous] and return a readable conclusion plus
  /// up to three supporting facts. Does not invent scores; uses the counts
  /// OpenKAT produced.
  TrendConclusion compare(
    SnapshotAggregate current,
    SnapshotAggregate? previous,
  ) {
    if (previous == null) {
      return const TrendConclusion(
        label: 'Eerste meting',
        lines: ['Eerste meting; nog geen trend beschikbaar'],
      );
    }

    final lines = <String>[];
    final worse = <bool>[];
    final better = <bool>[];

    final criticalDelta =
        current.severityCounts['critical']! -
        previous.severityCounts['critical']!;
    _addDeltaLine(lines, 'kritieke findings', criticalDelta, worse, better);

    final highDelta =
        current.severityCounts['high']! - previous.severityCounts['high']!;
    _addDeltaLine(lines, 'hoge findings', highDelta, worse, better);

    final mediumDelta =
        current.severityCounts['medium']! - previous.severityCounts['medium']!;
    _addDeltaLine(lines, 'medium findings', mediumDelta, worse, better);

    final affectedDelta = current.affectedSystems - previous.affectedSystems;
    _addDeltaLine(lines, 'getroffen systemen', affectedDelta, worse, better);

    final controlChanges = <String>[];
    for (final key in {...current.controls.keys, ...previous.controls.keys}) {
      final c = current.controls[key]?.ratio;
      final p = previous.controls[key]?.ratio;
      if (c != null && p != null && (c - p).abs() > 0.01) {
        final direction = c > p ? 'verbeterd' : 'verslechterd';
        controlChanges.add(
          '$key-dekking $direction van ${_pct(p)} naar ${_pct(c)}',
        );
      }
    }
    if (controlChanges.isNotEmpty && lines.length < 3) {
      lines.add(controlChanges.first);
    }

    String label;
    if (worse.isEmpty && better.isNotEmpty) {
      label = 'Beter';
    } else if (better.isEmpty && worse.isNotEmpty) {
      label = 'Slechter';
    } else {
      label = 'Gemengd';
    }

    return TrendConclusion(label: label, lines: lines.take(3).toList());
  }

  /// Alle issues gesorteerd; [limit] null betekent álles — de dia begrenst
  /// zelf via zijn weergavelimiet (#672), zodat de data niet-destructief
  /// bewaard blijft (bewaker-bevinding #767).
  List<OpenKatIssue> topIssues(
    List<OpenKatOrganization> organizations, {
    int? limit,
  }) {
    final byType = <String, OpenKatIssue>{};
    for (final org in organizations) {
      final current = org.current;
      if (current == null) continue;
      final previous = org.previous;
      for (final finding in current.findings) {
        final issue = byType.putIfAbsent(
          finding.findingTypeId,
          () => OpenKatIssue(
            findingTypeId: finding.findingTypeId,
            findingTypeName: finding.findingTypeName ?? finding.findingTypeId,
          ),
        );
        byType[finding.findingTypeId] = issue._addFinding(
          finding,
          organizationCode: org.code,
          previous: previous,
        );
      }
    }
    final sorted = byType.values.toList()..sort(_issueComparator);
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  List<OpenKatFinding> longestOpenFindings(
    List<OpenKatOrganization> organizations, {
    int? limit,
  }) {
    final open = <OpenKatFinding>[];
    for (final org in organizations) {
      final current = org.current;
      if (current == null) continue;
      open.addAll(
        current.findings.where((f) => f.openedAt != null).toList()
          ..sort((a, b) {
            final ac = a.openedAt!;
            final bc = b.openedAt!;
            return ac.compareTo(bc);
          }),
      );
    }
    open.sort((a, b) {
      final ad = a.openedAt!;
      final bd = b.openedAt!;
      var cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
      cmp = _severityRank(a.severity).compareTo(_severityRank(b.severity));
      if (cmp != 0) return cmp;
      cmp = (a.systemId ?? '').compareTo(b.systemId ?? '');
      if (cmp != 0) return cmp;
      return a.findingTypeId.compareTo(b.findingTypeId);
    });
    return open.take(limit ?? 1 << 30).toList();
  }

  List<OpenKatSystemStats> systemsWithMostFindings(
    OpenKatSnapshot snapshot, {
    int? limit,
  }) {
    final bySystem = <String, OpenKatSystemStats>{};
    for (final finding in snapshot.findings) {
      final id = finding.systemId ?? 'onbekend';
      final stats = bySystem.putIfAbsent(
        id,
        () => OpenKatSystemStats(systemId: id),
      );
      bySystem[id] = stats._addFinding(finding);
    }
    final sorted = bySystem.values.toList()..sort(_systemStatsComparator);
    return sorted.take(limit ?? 1 << 30).toList();
  }

  List<OpenKatSystemChange> mostImprovedSystems(
    OpenKatOrganization organization, {
    int? limit,
  }) {
    final current = organization.current;
    final previous = organization.previous;
    if (current == null || previous == null) return const [];

    final currentStats = <String, OpenKatSystemStats>{};
    for (final f in current.findings) {
      final id = f.systemId ?? 'onbekend';
      currentStats[id] = (currentStats[id] ?? OpenKatSystemStats(systemId: id))
          ._addFinding(f);
    }
    final previousStats = <String, OpenKatSystemStats>{};
    for (final f in previous.findings) {
      final id = f.systemId ?? 'onbekend';
      previousStats[id] =
          (previousStats[id] ?? OpenKatSystemStats(systemId: id))._addFinding(
            f,
          );
    }

    final changes = <OpenKatSystemChange>[];
    for (final id in currentStats.keys) {
      final prev = previousStats[id];
      if (prev == null) continue;
      final cur = currentStats[id]!;
      final improved =
          (cur.critical < prev.critical) ||
          (cur.high < prev.high) ||
          (cur.medium < prev.medium) ||
          (cur.total < prev.total);
      final regressed =
          (cur.critical > prev.critical) ||
          (cur.high > prev.high) ||
          (cur.medium > prev.medium);
      if (!improved) continue;
      changes.add(
        OpenKatSystemChange(
          systemId: id,
          oldStats: prev,
          newStats: cur,
          classification: regressed ? 'gemengd' : 'verbeterd',
        ),
      );
    }
    changes.sort(_systemChangeComparator);
    return changes.take(limit ?? 1 << 30).toList();
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  void _addDeltaLine(
    List<String> lines,
    String label,
    int delta,
    List<bool> worse,
    List<bool> better,
  ) {
    if (delta == 0) return;
    if (delta > 0) {
      worse.add(true);
      lines.add('$delta meer $label');
    } else {
      better.add(true);
      lines.add('${-delta} minder $label');
    }
  }

  String _pct(double value) => '${(value * 100).round()}%';

  bool _isIpv4(String? value) =>
      value != null &&
      RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(value);

  bool _isIpv6(String? value) =>
      value != null && value.contains(':') && !value.contains('.');

  int _severityRank(String severity) {
    switch (severity) {
      case 'critical':
        return 0;
      case 'high':
        return 1;
      case 'medium':
        return 2;
      case 'low':
        return 3;
      default:
        return 4;
    }
  }

  int _issueComparator(OpenKatIssue a, OpenKatIssue b) {
    var cmp = _severityRank(
      a.highestSeverity,
    ).compareTo(_severityRank(b.highestSeverity));
    if (cmp != 0) return cmp;
    cmp = b.affectedSystems.compareTo(a.affectedSystems);
    if (cmp != 0) return cmp;
    cmp = b.affectedOrganizations.compareTo(a.affectedOrganizations);
    if (cmp != 0) return cmp;
    if (a.oldestOpening != null && b.oldestOpening != null) {
      cmp = a.oldestOpening!.compareTo(b.oldestOpening!);
      if (cmp != 0) return cmp;
    }
    return a.findingTypeId.compareTo(b.findingTypeId);
  }

  int _systemStatsComparator(OpenKatSystemStats a, OpenKatSystemStats b) {
    var cmp = b.critical.compareTo(a.critical);
    if (cmp != 0) return cmp;
    cmp = b.high.compareTo(a.high);
    if (cmp != 0) return cmp;
    cmp = b.medium.compareTo(a.medium);
    if (cmp != 0) return cmp;
    cmp = b.total.compareTo(a.total);
    if (cmp != 0) return cmp;
    return a.systemId.compareTo(b.systemId);
  }

  int _systemChangeComparator(OpenKatSystemChange a, OpenKatSystemChange b) {
    var cmp = (b.oldStats.critical - b.newStats.critical).compareTo(
      a.oldStats.critical - a.newStats.critical,
    );
    if (cmp != 0) return cmp;
    cmp = (b.oldStats.high - b.newStats.high).compareTo(
      a.oldStats.high - a.newStats.high,
    );
    if (cmp != 0) return cmp;
    cmp = (b.oldStats.medium - b.newStats.medium).compareTo(
      a.oldStats.medium - a.newStats.medium,
    );
    if (cmp != 0) return cmp;
    return (b.oldStats.total - b.newStats.total).compareTo(
      a.oldStats.total - a.newStats.total,
    );
  }
}

class SnapshotAggregate {
  final int totalSystems;
  final int hostnames;
  final int ipv4;
  final int ipv6;
  final int webObjects;
  final Map<String, int> severityCounts;
  final int uniqueFindingTypes;
  final int affectedSystems;
  final int criticalHighSystems;
  final Map<String, OpenKatControlScore> controls;
  final List<OpenKatFinding> findings;

  const SnapshotAggregate({
    required this.totalSystems,
    required this.hostnames,
    required this.ipv4,
    required this.ipv6,
    required this.webObjects,
    required this.severityCounts,
    required this.uniqueFindingTypes,
    required this.affectedSystems,
    required this.criticalHighSystems,
    required this.controls,
    required this.findings,
  });

  int get totalFindings => findings.length;
}

class PortfolioAggregate {
  final SnapshotAggregate current;
  final SnapshotAggregate? previous;
  final List<OpenKatOrganization> organizations;

  const PortfolioAggregate({
    required this.current,
    this.previous,
    required this.organizations,
  });
}

class TrendConclusion {
  final String label;
  final List<String> lines;

  const TrendConclusion({required this.label, required this.lines});
}

class OpenKatIssue {
  final String findingTypeId;
  final String? findingTypeName;
  final Set<String> _affectedSystems = <String>{};
  final Set<String> _affectedOrganizations = <String>{};
  final List<DateTime> _openings = <DateTime>[];
  String highestSeverity = 'low';
  int occurrenceCount = 0;
  int deltaSincePrevious = 0;
  String? recommendation;
  String? impact;

  OpenKatIssue({required this.findingTypeId, this.findingTypeName});

  int get affectedSystems => _affectedSystems.length;
  int get affectedOrganizations => _affectedOrganizations.length;
  DateTime? get oldestOpening => _openings.isEmpty
      ? null
      : _openings.reduce((a, b) => a.isBefore(b) ? a : b);

  OpenKatIssue _addFinding(
    OpenKatFinding finding, {
    required String organizationCode,
    OpenKatSnapshot? previous,
  }) {
    occurrenceCount++;
    _affectedSystems.add(finding.systemId ?? 'onbekend');
    _affectedOrganizations.add(organizationCode);
    if (finding.openedAt != null) _openings.add(finding.openedAt!);
    if (_severityRank(finding.severity) < _severityRank(highestSeverity)) {
      highestSeverity = finding.severity;
    }
    recommendation ??= finding.recommendation;
    impact ??= finding.impact;
    if (previous != null) {
      final wasPresent = previous.findings.any((f) => f.id == finding.id);
      if (!wasPresent) deltaSincePrevious++;
    }
    return this;
  }

  static int _severityRank(String severity) {
    switch (severity) {
      case 'critical':
        return 0;
      case 'high':
        return 1;
      case 'medium':
        return 2;
      case 'low':
        return 3;
      default:
        return 4;
    }
  }
}

class OpenKatSystemStats {
  final String systemId;
  int critical = 0;
  int high = 0;
  int medium = 0;
  int low = 0;
  int total = 0;
  final Set<String> findingTypes = <String>{};
  DateTime? oldestOpening;

  OpenKatSystemStats({required this.systemId});

  OpenKatSystemStats _addFinding(OpenKatFinding finding) {
    switch (finding.severity) {
      case 'critical':
        critical++;
      case 'high':
        high++;
      case 'medium':
        medium++;
      case 'low':
        low++;
    }
    total++;
    findingTypes.add(finding.findingTypeId);
    if (finding.openedAt != null) {
      oldestOpening =
          oldestOpening == null || finding.openedAt!.isBefore(oldestOpening!)
          ? finding.openedAt
          : oldestOpening;
    }
    return this;
  }
}

class OpenKatSystemChange {
  final String systemId;
  final OpenKatSystemStats oldStats;
  final OpenKatSystemStats newStats;
  final String classification;

  const OpenKatSystemChange({
    required this.systemId,
    required this.oldStats,
    required this.newStats,
    required this.classification,
  });
}
