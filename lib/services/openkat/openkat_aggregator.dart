import '../../models/openkat/openkat_models.dart';

/// De ernstbanden die een managementrapportage uitsplit.
const List<String> openKatSeverityBands = ['critical', 'high', 'medium', 'low'];

/// Waar elk ander niveau in belandt — OpenKAT kent er meer dan deze vier
/// (`recommendation`, `unknown`, en soms een leeg veld).
///
/// Zonder deze band verdween het verschil: een uitdraai met 295 findings toonde
/// een uitsplitsing die er 218 verklaarde, en niets op de dia wees erop dat de
/// overige 77 bestonden. Een uitsplitsing die het totaal niet verklaart maakt de
/// hele rapportage ongeloofwaardig, dus telt alles mee — ook wat wij niet kennen.
const String openKatOtherSeverity = 'other';

/// De banden in weergavevolgorde, met de restcategorie achteraan.
const List<String> openKatSeverityOrder = [
  ...openKatSeverityBands,
  openKatOtherSeverity,
];

/// De band waar [severity] onder valt; alles buiten [openKatSeverityBands]
/// telt als [openKatOtherSeverity].
String openKatSeverityBand(String severity) =>
    openKatSeverityBands.contains(severity) ? severity : openKatOtherSeverity;

/// Findings geteld per band, met elke band aanwezig (ook op nul) zodat een
/// grafiekas en een tabelkolom niet per momentopname van vorm wisselen.
Map<String, int> openKatSeverityCounts(Iterable<OpenKatFinding> findings) {
  final counts = <String, int>{
    for (final band in openKatSeverityOrder) band: 0,
  };
  for (final finding in findings) {
    final band = openKatSeverityBand(finding.severity);
    counts[band] = counts[band]! + 1;
  }
  return counts;
}

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

    final severityCounts = openKatSeverityCounts(findings);

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
        direction: OpenKatTrendDirection.firstMeasurement,
        facts: [],
      );
    }

    final facts = <OpenKatTrendFact>[];
    final worse = <bool>[];
    final better = <bool>[];

    final criticalDelta =
        current.severityCounts['critical']! -
        previous.severityCounts['critical']!;
    _addDeltaFact(
      facts,
      OpenKatTrendMetric.criticalFindings,
      criticalDelta,
      worse,
      better,
    );

    final highDelta =
        current.severityCounts['high']! - previous.severityCounts['high']!;
    _addDeltaFact(
      facts,
      OpenKatTrendMetric.highFindings,
      highDelta,
      worse,
      better,
    );

    final mediumDelta =
        current.severityCounts['medium']! - previous.severityCounts['medium']!;
    _addDeltaFact(
      facts,
      OpenKatTrendMetric.mediumFindings,
      mediumDelta,
      worse,
      better,
    );

    final affectedDelta = current.affectedSystems - previous.affectedSystems;
    _addDeltaFact(
      facts,
      OpenKatTrendMetric.affectedSystems,
      affectedDelta,
      worse,
      better,
    );

    final controlChanges = <OpenKatTrendFact>[];
    for (final key in {...current.controls.keys, ...previous.controls.keys}) {
      final c = current.controls[key]?.ratio;
      final p = previous.controls[key]?.ratio;
      if (c != null && p != null && (c - p).abs() > 0.01) {
        controlChanges.add(
          OpenKatTrendFact.controlCoverage(
            controlId: key,
            previousRatio: p,
            currentRatio: c,
          ),
        );
      }
    }
    if (controlChanges.isNotEmpty && facts.length < 3) {
      facts.add(controlChanges.first);
    }

    OpenKatTrendDirection direction;
    if (worse.isEmpty && better.isNotEmpty) {
      direction = OpenKatTrendDirection.improved;
    } else if (better.isEmpty && worse.isNotEmpty) {
      direction = OpenKatTrendDirection.worsened;
    } else {
      direction = OpenKatTrendDirection.mixed;
    }

    return TrendConclusion(direction: direction, facts: facts.take(3).toList());
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

  /// De findings die het langst openstaan, oudste eerst.
  ///
  /// Elke finding komt terug mét de rapportagedatum van de meting waarin hij
  /// staat, zodat "hoe lang staat dit al open" tegen dát moment te rekenen is
  /// en niet tegen de klok van vandaag: een deck dat je over een maand opnieuw
  /// opent moet dezelfde getallen tonen als toen het gemaakt werd.
  List<OpenKatOpenFinding> longestOpenFindings(
    List<OpenKatOrganization> organizations, {
    int? limit,
  }) {
    final open = <OpenKatOpenFinding>[];
    for (final org in organizations) {
      final current = org.current;
      if (current == null) continue;
      for (final finding in current.findings) {
        if (finding.openedAt == null) continue;
        open.add(
          OpenKatOpenFinding(finding: finding, reportDate: current.reportDate),
        );
      }
    }
    open.sort((a, b) {
      var cmp = a.finding.openedAt!.compareTo(b.finding.openedAt!);
      if (cmp != 0) return cmp;
      cmp = _severityRank(
        a.finding.severity,
      ).compareTo(_severityRank(b.finding.severity));
      if (cmp != 0) return cmp;
      cmp = (a.finding.systemId ?? '').compareTo(b.finding.systemId ?? '');
      if (cmp != 0) return cmp;
      return a.finding.findingTypeId.compareTo(b.finding.findingTypeId);
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

  /// De stand op elk moment waarop er gemeten is, oplopend in de tijd.
  ///
  /// Organisaties meten niet op dezelfde dag, dus telt op elke datum de
  /// **laatst bekende** meting per organisatie mee. Wie op dat moment nog niet
  /// gemeten had telt niet mee — nul invullen zou een daling tonen die niemand
  /// heeft waargenomen, en dat is precies het soort verzonnen conclusie dat
  /// deze import niet hoort te trekken.
  ///
  /// Het alternatief — alleen de datums waarop iederéén gemeten heeft — is
  /// verworpen: dat laat de grafiek in de praktijk leeg.
  List<OpenKatHistoryPoint> history(List<OpenKatOrganization> organizations) {
    final dates = <DateTime>{
      for (final org in organizations)
        for (final snapshot in org.snapshots) snapshot.reportDate,
    }.toList()..sort();

    return [
      for (final date in dates)
        OpenKatHistoryPoint(
          date: date,
          severityCounts: openKatSeverityCounts([
            for (final org in organizations)
              ...?_latestUpTo(org, date)?.findings,
          ]),
        ),
    ];
  }

  /// De organisaties naast elkaar: hoeveel findings nu, en hoeveel bij de
  /// vorige meting. Grootste bewegers eerst, want dát is waar een
  /// managementoverzicht over gaat; wie geen eerdere meting heeft draagt geen
  /// verschil en sluit de rij.
  List<OpenKatOrganizationComparison> organizationComparison(
    List<OpenKatOrganization> organizations,
  ) {
    final out = <OpenKatOrganizationComparison>[];
    for (final org in organizations) {
      final current = org.current;
      if (current == null) continue;
      out.add(
        OpenKatOrganizationComparison(
          code: org.code,
          name: org.name,
          findings: current.findings.length,
          previousFindings: org.previous?.findings.length,
        ),
      );
    }
    out.sort((a, b) {
      var cmp = _movement(b).compareTo(_movement(a));
      if (cmp != 0) return cmp;
      cmp = b.findings.compareTo(a.findings);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// Hoe hard een organisatie bewoog. Zonder eerdere meting is er geen
  /// beweging te melden: −1 zet die achter een organisatie die aantoonbaar
  /// stilstond, want "onbekend" is minder nieuws dan "gemeten en gelijk".
  int _movement(OpenKatOrganizationComparison c) => c.delta?.abs() ?? -1;

  /// Organisaties gerangschikt voor de actuele managementvraag.
  ///
  /// Dit is bewust geen samengestelde risicoscore: eerst telt de zwaarste
  /// feitelijke ernst, daarna het aantal kwetsbare systemen en pas daarna het
  /// totaal. De presentatie kan daardoor precies uitleggen waarom een
  /// organisatie bovenaan staat.
  List<OpenKatOrganizationAttention> organizationAttention(
    List<OpenKatOrganization> organizations,
  ) {
    final out = <OpenKatOrganizationAttention>[];
    for (final organization in organizations) {
      final current = organization.current;
      if (current == null) continue;
      final counts = openKatSeverityCounts(current.findings);
      final urgentFindings = current.findings.where((finding) {
        final band = openKatSeverityBand(finding.severity);
        return band == 'critical' || band == 'high';
      });
      out.add(
        OpenKatOrganizationAttention(
          code: organization.code,
          name: organization.name,
          critical: counts['critical'] ?? 0,
          high: counts['high'] ?? 0,
          affectedSystems: urgentFindings
              .map((finding) => finding.systemId)
              .whereType<String>()
              .toSet()
              .length,
          totalFindings: current.findings.length,
        ),
      );
    }
    out.sort((a, b) {
      var comparison = b.critical.compareTo(a.critical);
      if (comparison != 0) return comparison;
      comparison = b.high.compareTo(a.high);
      if (comparison != 0) return comparison;
      comparison = b.affectedSystems.compareTo(a.affectedSystems);
      if (comparison != 0) return comparison;
      comparison = b.totalFindings.compareTo(a.totalFindings);
      if (comparison != 0) return comparison;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// De jongste momentopname van [org] op of vóór [date], of null als er toen
  /// nog niet gemeten was.
  OpenKatSnapshot? _latestUpTo(OpenKatOrganization org, DateTime date) {
    OpenKatSnapshot? best;
    for (final snapshot in org.snapshots) {
      if (snapshot.reportDate.isAfter(date)) continue;
      if (best == null || snapshot.reportDate.isAfter(best.reportDate)) {
        best = snapshot;
      }
    }
    return best;
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

  void _addDeltaFact(
    List<OpenKatTrendFact> facts,
    OpenKatTrendMetric metric,
    int delta,
    List<bool> worse,
    List<bool> better,
  ) {
    if (delta == 0) return;
    if (delta > 0) {
      worse.add(true);
    } else {
      better.add(true);
    }
    facts.add(OpenKatTrendFact.delta(metric: metric, delta: delta));
  }

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

  /// Of er findings zijn met een niveau buiten [openKatSeverityBands]. Bepaalt
  /// of de restkolom op een dia verschijnt: een kolom die overal nul is voegt
  /// niets toe, maar zodra hij gevuld is moet hij er staan.
  bool get hasOtherSeverities =>
      (severityCounts[openKatOtherSeverity] ?? 0) > 0;
}

/// De stand op één meetmoment — wat [OpenKatAggregator.history] per datum
/// oplevert.
class OpenKatHistoryPoint {
  final DateTime date;
  final Map<String, int> severityCounts;

  const OpenKatHistoryPoint({required this.date, required this.severityCounts});

  int get totalFindings =>
      severityCounts.values.fold(0, (sum, count) => sum + count);
}

/// Een openstaande finding met het meetmoment waartegen zijn leeftijd telt.
class OpenKatOpenFinding {
  final OpenKatFinding finding;
  final DateTime reportDate;

  const OpenKatOpenFinding({required this.finding, required this.reportDate});

  /// Hoe lang de finding openstond op de rapportagedatum. Nooit negatief: een
  /// bron die een openingsdatum ná het rapport meldt levert 0 op in plaats van
  /// een getal dat niemand kan uitleggen.
  int get daysOpen {
    final opened = finding.openedAt;
    if (opened == null) return 0;
    final days = reportDate.difference(opened).inDays;
    return days < 0 ? 0 : days;
  }
}

/// Eén organisatie in de onderlinge vergelijking.
class OpenKatOrganizationComparison {
  final String code;
  final String name;
  final int findings;

  /// De stand bij de vorige meting, of null als die er niet is — een eerste
  /// meting, of een organisatie die net is toegevoegd.
  final int? previousFindings;

  const OpenKatOrganizationComparison({
    required this.code,
    required this.name,
    required this.findings,
    this.previousFindings,
  });

  int? get delta =>
      previousFindings == null ? null : findings - previousFindings!;
}

/// Eén actuele organisatie in de uitlegbare managementrangorde.
class OpenKatOrganizationAttention {
  final String code;
  final String name;
  final int critical;
  final int high;
  final int affectedSystems;
  final int totalFindings;

  const OpenKatOrganizationAttention({
    required this.code,
    required this.name,
    required this.critical,
    required this.high,
    required this.affectedSystems,
    required this.totalFindings,
  });
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

enum OpenKatTrendDirection { firstMeasurement, improved, worsened, mixed }

enum OpenKatTrendMetric {
  criticalFindings,
  highFindings,
  mediumFindings,
  affectedSystems,
  controlCoverage,
}

/// Eén getypept trendfeit; lokalisatie gebeurt pas in de rapportcomposer.
class OpenKatTrendFact {
  final OpenKatTrendMetric metric;
  final int? delta;
  final String? controlId;
  final double? previousRatio;
  final double? currentRatio;

  const OpenKatTrendFact.delta({required this.metric, required int this.delta})
    : controlId = null,
      previousRatio = null,
      currentRatio = null,
      assert(metric != OpenKatTrendMetric.controlCoverage);

  const OpenKatTrendFact.controlCoverage({
    required String this.controlId,
    required double this.previousRatio,
    required double this.currentRatio,
  }) : metric = OpenKatTrendMetric.controlCoverage,
       delta = null;
}

class TrendConclusion {
  final OpenKatTrendDirection direction;
  final List<OpenKatTrendFact> facts;

  const TrendConclusion({required this.direction, required this.facts});

  /// Nederlandse compatibiliteitsprojectie voor bestaande aanroepers.
  String get label => switch (direction) {
    OpenKatTrendDirection.firstMeasurement => 'Eerste meting',
    OpenKatTrendDirection.improved => 'Beter',
    OpenKatTrendDirection.worsened => 'Slechter',
    OpenKatTrendDirection.mixed => 'Gemengd',
  };

  /// Nederlandse compatibiliteitsprojectie; nieuwe UI gebruikt [facts].
  List<String> get lines {
    if (direction == OpenKatTrendDirection.firstMeasurement) {
      return const ['Eerste meting; nog geen trend beschikbaar'];
    }
    return [for (final fact in facts) _dutchTrendFact(fact)];
  }
}

String _dutchTrendFact(OpenKatTrendFact fact) {
  if (fact.metric == OpenKatTrendMetric.controlCoverage) {
    final direction = fact.currentRatio! > fact.previousRatio!
        ? 'verbeterd'
        : 'verslechterd';
    return '${fact.controlId}-dekking $direction van '
        '${_trendPercentage(fact.previousRatio!)} naar '
        '${_trendPercentage(fact.currentRatio!)}';
  }
  final count = fact.delta!.abs();
  final direction = fact.delta! > 0 ? 'meer' : 'minder';
  final label = switch (fact.metric) {
    OpenKatTrendMetric.criticalFindings => 'kritieke findings',
    OpenKatTrendMetric.highFindings => 'hoge findings',
    OpenKatTrendMetric.mediumFindings => 'medium findings',
    OpenKatTrendMetric.affectedSystems => 'kwetsbare systemen',
    OpenKatTrendMetric.controlCoverage => throw StateError(
      'control coverage is handled above',
    ),
  };
  return '$count $direction $label';
}

String _trendPercentage(double value) => '${(value * 100).round()}%';

class OpenKatIssue {
  final String findingTypeId;
  final String? findingTypeName;
  final Set<String> _affectedSystems = <String>{};
  final Set<String> _affectedOrganizations = <String>{};
  final List<DateTime> _openings = <DateTime>[];

  /// De zwaarste band die onder dit issue is gezien, of null zolang er nog
  /// niets is toegevoegd.
  ///
  /// Was een veld dat op `'low'` begon, en dat loog: een niveau dat wij niet
  /// kennen haalt het nooit van low, dus verscheen een issue met louter
  /// `recommendation`-findings in de tabel als Low — een ernst die in de meting
  /// nergens staat. Ongezet beginnen en op **band** vergelijken laat de eerste
  /// finding de waarde bepalen, wat hij ook is.
  String? _highestSeverity;
  String get highestSeverity => _highestSeverity ?? openKatOtherSeverity;
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
    final band = openKatSeverityBand(finding.severity);
    if (_highestSeverity == null ||
        _severityRank(band) < _severityRank(_highestSeverity!)) {
      _highestSeverity = band;
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

  /// Findings met een niveau buiten [openKatSeverityBands]; zonder deze teller
  /// telde een rij niet op tot [total].
  int other = 0;
  int total = 0;
  final Set<String> findingTypes = <String>{};
  DateTime? oldestOpening;

  OpenKatSystemStats({required this.systemId});

  OpenKatSystemStats _addFinding(OpenKatFinding finding) {
    switch (openKatSeverityBand(finding.severity)) {
      case 'critical':
        critical++;
      case 'high':
        high++;
      case 'medium':
        medium++;
      case 'low':
        low++;
      default:
        other++;
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
