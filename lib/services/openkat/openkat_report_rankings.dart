import 'dart:collection';

import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_aggregator.dart';
import 'openkat_report_facts.dart';

/// Gerichte, deterministische rapportfeiten bovenop de centrale peildatumkeuze.
extension OpenKatReportRankings on OpenKatReportFacts {
  List<OpenKatOrganizationRanking> organizationRanking(
    OpenKatReportRequest request,
  ) {
    final ranked = <OpenKatOrganizationRanking>[];
    for (final selection in selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      final counts = openKatSeverityCounts(snapshot.findings);
      final affected = snapshot.findings
          .where((finding) {
            final band = openKatSeverityBand(finding.severity);
            return band == 'critical' || band == 'high';
          })
          .map((finding) => finding.systemId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      ranked.add(
        OpenKatOrganizationRanking(
          code: selection.organization.code,
          name: selection.organization.name,
          measuredAt: snapshot.reportDate,
          critical: counts['critical'] ?? 0,
          high: counts['high'] ?? 0,
          affectedSystems: affected.length,
          totalFindings: snapshot.findings.length,
        ),
      );
    }
    ranked.sort((a, b) {
      var result = b.critical.compareTo(a.critical);
      if (result != 0) return result;
      result = b.high.compareTo(a.high);
      if (result != 0) return result;
      result = b.affectedSystems.compareTo(a.affectedSystems);
      if (result != 0) return result;
      return a.name.compareTo(b.name);
    });
    return List.unmodifiable(ranked);
  }

  List<OpenKatPortfolioHistoryPoint> portfolioTimeline(
    OpenKatReportRequest request, {
    int? maxResults,
  }) {
    _validateRankingLimit(maxResults, 'maxResults');
    if (maxResults == 0) return const [];
    final selected = selections(request);
    final dates = SplayTreeSet<DateTime>();
    for (final selection in selected) {
      for (final snapshot in selection.organization.snapshots) {
        if (!snapshot.usable ||
            snapshot.reportDate.isAfter(request.currentAsOf)) {
          continue;
        }
        dates.add(snapshot.reportDate);
        if (maxResults != null && dates.length > maxResults) {
          dates.remove(dates.first);
        }
      }
    }
    final retainedDates = dates.toList(growable: false);
    final points = [
      for (final date in retainedDates) _PortfolioPointAccumulator(date),
    ];

    for (final selection in selected) {
      if (retainedDates.isEmpty) continue;
      final firstDate = retainedDates.first;
      OpenKatSnapshot? activeBeforeWindow;
      final snapshotsByDate = <DateTime, OpenKatSnapshot>{};
      for (final snapshot in selection.organization.snapshots) {
        if (!snapshot.usable ||
            snapshot.reportDate.isAfter(request.currentAsOf)) {
          continue;
        }
        if (snapshot.reportDate.isBefore(firstDate)) {
          if (activeBeforeWindow == null ||
              snapshot.reportDate.isAfter(activeBeforeWindow.reportDate)) {
            activeBeforeWindow = snapshot;
          }
        } else if (dates.contains(snapshot.reportDate)) {
          snapshotsByDate.putIfAbsent(snapshot.reportDate, () => snapshot);
        }
      }
      var active = activeBeforeWindow;
      OpenKatSnapshot? counted;
      Map<String, int> activeCounts = const {};
      for (
        var pointIndex = 0;
        pointIndex < retainedDates.length;
        pointIndex++
      ) {
        final date = retainedDates[pointIndex];
        active = snapshotsByDate[date] ?? active;
        if (active == null) continue;
        if (!identical(active, counted)) {
          activeCounts = openKatSeverityCounts(active.findings);
          counted = active;
        }
        recordHistoricalSnapshot(selection.organization.code, active);
        points[pointIndex].add(
          activeCounts,
          carriedForward: active.reportDate != date,
        );
      }
    }
    return List.unmodifiable(points.map((point) => point.build()));
  }

  List<OpenKatIssue> findingTypePrevalence(OpenKatReportRequest request) {
    final issues = aggregator.topIssues(selectedOrganizations(request));
    issues.sort((a, b) {
      var result = b.affectedOrganizations.compareTo(a.affectedOrganizations);
      if (result != 0) return result;
      result = b.affectedSystems.compareTo(a.affectedSystems);
      if (result != 0) return result;
      result = b.occurrenceCount.compareTo(a.occurrenceCount);
      if (result != 0) return result;
      return a.findingTypeId.compareTo(b.findingTypeId);
    });
    return List.unmodifiable(issues);
  }

  List<OpenKatSystemHotspot> systemHotspots(OpenKatReportRequest request) {
    final hotspots = <OpenKatSystemHotspot>[];
    for (final selection in selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      final systems = {
        for (final system in snapshot.systems) system.id: system,
      };
      final bySystem = <String, List<OpenKatFinding>>{};
      for (final finding in snapshot.findings) {
        final raw = finding.systemId?.trim();
        final id = raw == null || raw.isEmpty ? 'unknown-system' : raw;
        bySystem.putIfAbsent(id, () => []).add(finding);
      }
      for (final entry in bySystem.entries) {
        final system = systems[entry.key];
        hotspots.add(
          OpenKatSystemHotspot(
            organizationCode: selection.organization.code,
            systemId: entry.key,
            hostname: system?.hostname,
            ip: system?.ip,
            severityCounts: openKatSeverityCounts(entry.value),
            unknownSystem: entry.key == 'unknown-system',
          ),
        );
      }
    }
    hotspots.sort((a, b) {
      if (a.unknownSystem != b.unknownSystem) {
        return a.unknownSystem ? 1 : -1;
      }
      var result = (b.severityCounts['critical'] ?? 0).compareTo(
        a.severityCounts['critical'] ?? 0,
      );
      if (result != 0) return result;
      result = (b.severityCounts['high'] ?? 0).compareTo(
        a.severityCounts['high'] ?? 0,
      );
      if (result != 0) return result;
      result = b.total.compareTo(a.total);
      if (result != 0) return result;
      result = a.organizationCode.compareTo(b.organizationCode);
      if (result != 0) return result;
      return a.systemId.compareTo(b.systemId);
    });
    return List.unmodifiable(hotspots);
  }

  List<OpenKatSystemChangeItem> systemChangeItems(
    OpenKatReportRequest request,
  ) {
    final changes = <OpenKatSystemChangeItem>[];
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      final currentCounts = _systemSeverityCounts(current);
      final previousCounts = _systemSeverityCounts(previous);
      for (final id in currentCounts.keys.toSet().intersection(
        previousCounts.keys.toSet(),
      )) {
        final deltas = {
          for (final band in openKatSeverityOrder)
            band:
                (currentCounts[id]![band] ?? 0) -
                (previousCounts[id]![band] ?? 0),
        };
        if (deltas.values.every((delta) => delta == 0)) continue;
        final increase = deltas.values.any((delta) => delta > 0);
        final decrease = deltas.values.any((delta) => delta < 0);
        changes.add(
          OpenKatSystemChangeItem(
            organizationCode: selection.organization.code,
            systemId: id,
            kind: increase && decrease
                ? OpenKatSystemChangeKind.mixed
                : increase
                ? OpenKatSystemChangeKind.moreObserved
                : OpenKatSystemChangeKind.fewerObserved,
            severityDeltas: Map.unmodifiable(deltas),
          ),
        );
      }
    }
    changes.sort((a, b) {
      var result = a.kind.index.compareTo(b.kind.index);
      if (result != 0) return result;
      result = a.organizationCode.compareTo(b.organizationCode);
      if (result != 0) return result;
      return a.systemId.compareTo(b.systemId);
    });
    return List.unmodifiable(changes);
  }

  Map<String, Map<String, int>> _systemSeverityCounts(
    OpenKatSnapshot snapshot,
  ) {
    final bySystem = <String, List<OpenKatFinding>>{};
    for (final finding in snapshot.findings) {
      final id = finding.systemId?.trim();
      if (id == null || id.isEmpty) continue;
      bySystem.putIfAbsent(id, () => []).add(finding);
    }
    return {
      for (final entry in bySystem.entries)
        entry.key: openKatSeverityCounts(entry.value),
    };
  }

  List<OpenKatCveLandscapeItem> cveLandscape(OpenKatReportRequest request) {
    final accumulators = <String, _CveAccumulator>{};
    for (final selection in selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      for (final finding in snapshot.findings) {
        for (final rawCve in finding.cveIds) {
          final cve = rawCve.trim().toUpperCase();
          if (cve.isEmpty) continue;
          final accumulator = accumulators.putIfAbsent(
            cve,
            _CveAccumulator.new,
          );
          accumulator.add(selection.organization.code, finding);
        }
      }
    }
    final result = [
      for (final entry in accumulators.entries)
        OpenKatCveLandscapeItem(
          cveId: entry.key,
          organizationCount: entry.value.organizations.length,
          systemCount: entry.value.systems.length,
          observationCount: entry.value.observations.length,
          severityCounts: Map.unmodifiable(entry.value.severityCounts),
        ),
    ];
    result.sort((a, b) {
      var comparison = b.organizationCount.compareTo(a.organizationCount);
      if (comparison != 0) return comparison;
      comparison = b.systemCount.compareTo(a.systemCount);
      if (comparison != 0) return comparison;
      comparison = b.observationCount.compareTo(a.observationCount);
      if (comparison != 0) return comparison;
      return a.cveId.compareTo(b.cveId);
    });
    return List.unmodifiable(result);
  }

  List<OpenKatCveChangeItem> cveChangeItems(OpenKatReportRequest request) {
    final grouped = <String, _CveChangeAccumulator>{};
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      final currentRefs = _cveReferences(current);
      final previousRefs = _cveReferences(previous);
      final earlier = <String>{};
      for (final snapshot in selection.organization.snapshots) {
        if (!snapshot.usable ||
            !snapshot.reportDate.isBefore(previous.reportDate)) {
          continue;
        }
        recordHistoricalSnapshot(selection.organization.code, snapshot);
        earlier.addAll(_cveReferences(snapshot).keys);
      }
      for (final cve in {...currentRefs.keys, ...previousRefs.keys}) {
        final currentSet = currentRefs[cve];
        final previousSet = previousRefs[cve];
        if (currentSet != null && previousSet == null) {
          final observation = earlier.contains(cve)
              ? OpenKatCveObservation.reobserved
              : OpenKatCveObservation.newlyObserved;
          _addCveChange(
            grouped,
            cve,
            observation,
            selection.organization.code,
            currentSet,
          );
        } else if (currentSet == null && previousSet != null) {
          _addCveChange(
            grouped,
            cve,
            OpenKatCveObservation.noLongerObserved,
            selection.organization.code,
            previousSet,
          );
        }
      }
    }
    final result = [
      for (final entry in grouped.entries)
        OpenKatCveChangeItem(
          cveId: entry.value.cveId,
          observation: entry.value.observation,
          organizationCodes: Set.unmodifiable(entry.value.organizations),
          systemIds: Set.unmodifiable(entry.value.systems),
        ),
    ];
    result.sort((a, b) {
      var comparison = a.observation.index.compareTo(b.observation.index);
      if (comparison != 0) return comparison;
      comparison = b.organizationCodes.length.compareTo(
        a.organizationCodes.length,
      );
      if (comparison != 0) return comparison;
      return a.cveId.compareTo(b.cveId);
    });
    return List.unmodifiable(result);
  }

  Map<String, Set<String>> _cveReferences(OpenKatSnapshot snapshot) {
    final references = <String, Set<String>>{};
    for (final finding in snapshot.findings) {
      for (final rawCve in finding.cveIds) {
        final cve = rawCve.trim().toUpperCase();
        if (cve.isEmpty) continue;
        references
            .putIfAbsent(cve, () => <String>{})
            .add(finding.systemId ?? 'unknown-system');
      }
    }
    return references;
  }

  void _addCveChange(
    Map<String, _CveChangeAccumulator> grouped,
    String cve,
    OpenKatCveObservation observation,
    String organizationCode,
    Set<String> systems,
  ) {
    final key = '$cve|${observation.name}';
    final accumulator = grouped.putIfAbsent(
      key,
      () => _CveChangeAccumulator(cve, observation),
    );
    accumulator.organizations.add(organizationCode);
    accumulator.systems.addAll(
      systems.map((system) => '$organizationCode:$system'),
    );
  }

  List<OpenKatRecommendationItem> recommendationItems(
    OpenKatReportRequest request, {
    int? maxResults,
    int maxGroups = OpenKatReportPolicy.maximumTableRowLimit,
  }) {
    _validateRankingLimit(maxResults, 'maxResults');
    _validateRankingLimit(maxGroups, 'maxGroups');
    if (maxResults == 0) return const [];
    final grouped = <String, _RecommendationAccumulator>{};
    for (final selection in selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      for (final finding in snapshot.findings) {
        final recommendation = finding.recommendation?.trim();
        if (recommendation == null || recommendation.isEmpty) continue;
        final key = _recommendationKey(finding, recommendation);
        var accumulator = grouped[key];
        if (accumulator == null) {
          if (grouped.length >= maxGroups) {
            throw StateError('recommendation group limit exceeded: $maxGroups');
          }
          accumulator = _RecommendationAccumulator(finding, recommendation);
          grouped[key] = accumulator;
        }
        accumulator.add(selection.organization.code, finding);
      }
    }
    final result = [for (final item in grouped.values) item.build()];
    result.sort((a, b) {
      var comparison = b.organizationCount.compareTo(a.organizationCount);
      if (comparison != 0) return comparison;
      comparison = b.systemCount.compareTo(a.systemCount);
      if (comparison != 0) return comparison;
      comparison = _severityRank(
        a.highestSeverity,
      ).compareTo(_severityRank(b.highestSeverity));
      if (comparison != 0) return comparison;
      comparison = a.findingTypeId.compareTo(b.findingTypeId);
      if (comparison != 0) return comparison;
      return a.recommendation.compareTo(b.recommendation);
    });
    return List.unmodifiable(
      maxResults == null ? result : result.take(maxResults),
    );
  }

  bool exceedsRecommendationGroupLimit(
    OpenKatReportRequest request,
    int limit,
  ) {
    _validateRankingLimit(limit, 'limit');
    final keys = <String>{};
    for (final selection in selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      for (final finding in snapshot.findings) {
        final recommendation = finding.recommendation?.trim();
        if (recommendation == null || recommendation.isEmpty) continue;
        keys.add(_recommendationKey(finding, recommendation));
        if (keys.length > limit) return true;
      }
    }
    return false;
  }

  String _recommendationKey(OpenKatFinding finding, String recommendation) =>
      '${finding.findingTypeId}\u0000$recommendation';
}

class _PortfolioPointAccumulator {
  final DateTime date;
  final Map<String, int> severityCounts = {
    for (final band in openKatSeverityOrder) band: 0,
  };
  int contributingOrganizations = 0;
  int carriedForwardOrganizations = 0;

  _PortfolioPointAccumulator(this.date);

  void add(Map<String, int> counts, {required bool carriedForward}) {
    contributingOrganizations++;
    if (carriedForward) carriedForwardOrganizations++;
    for (final band in openKatSeverityOrder) {
      severityCounts[band] = severityCounts[band]! + (counts[band] ?? 0);
    }
  }

  OpenKatPortfolioHistoryPoint build() => OpenKatPortfolioHistoryPoint(
    date: date,
    severityCounts: Map.unmodifiable(severityCounts),
    contributingOrganizations: contributingOrganizations,
    carriedForwardOrganizations: carriedForwardOrganizations,
  );
}

class _CveAccumulator {
  final Set<String> organizations = {};
  final Set<String> systems = {};
  final Set<String> observations = {};
  final Map<String, int> severityCounts = {
    for (final band in openKatSeverityOrder) band: 0,
  };

  void add(String organizationCode, OpenKatFinding finding) {
    final observationKey =
        '$organizationCode|${finding.systemId ?? 'unknown-system'}|${finding.id}';
    if (!observations.add(observationKey)) return;
    organizations.add(organizationCode);
    systems.add('$organizationCode|${finding.systemId ?? 'unknown-system'}');
    final band = openKatSeverityBand(finding.severity);
    severityCounts[band] = severityCounts[band]! + 1;
  }
}

class _CveChangeAccumulator {
  final String cveId;
  final OpenKatCveObservation observation;
  final Set<String> organizations = {};
  final Set<String> systems = {};

  _CveChangeAccumulator(this.cveId, this.observation);
}

class _RecommendationAccumulator {
  final String findingTypeId;
  final String findingTypeName;
  final String recommendation;
  final Set<String> organizations = {};
  final Set<String> systems = {};
  String highestSeverity;

  _RecommendationAccumulator(OpenKatFinding finding, this.recommendation)
    : findingTypeId = finding.findingTypeId,
      findingTypeName = finding.findingTypeName ?? finding.findingTypeId,
      highestSeverity = openKatSeverityBand(finding.severity);

  void add(String organizationCode, OpenKatFinding finding) {
    organizations.add(organizationCode);
    if (finding.systemId != null && finding.systemId!.isNotEmpty) {
      systems.add('$organizationCode|${finding.systemId}');
    }
    final severity = openKatSeverityBand(finding.severity);
    if (_severityRank(severity) < _severityRank(highestSeverity)) {
      highestSeverity = severity;
    }
  }

  OpenKatRecommendationItem build() => OpenKatRecommendationItem(
    findingTypeId: findingTypeId,
    findingTypeName: findingTypeName,
    recommendation: recommendation,
    organizationCount: organizations.length,
    systemCount: systems.length,
    highestSeverity: highestSeverity,
  );
}

int _severityRank(String severity) {
  final index = openKatSeverityOrder.indexOf(severity);
  return index < 0 ? openKatSeverityOrder.length : index;
}

void _validateRankingLimit(int? value, String name) {
  if (value == null || value >= 0) return;
  throw ArgumentError.value(value, name, 'moet nul of positief zijn');
}
