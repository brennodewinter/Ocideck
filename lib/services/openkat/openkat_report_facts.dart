import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_aggregator.dart';

/// Centrale querylaag voor alle selectie- en vergelijkingsdefinities.
///
/// Scenario's krijgen uitsluitend deze laag te zien. Daarmee kan geen scenario
/// stilletjes "vorige week" herdefiniëren als "het op één na nieuwste bestand".
class OpenKatReportFacts {
  final List<OpenKatOrganization> organizations;
  final OpenKatAggregator aggregator;

  OpenKatReportFacts(
    List<OpenKatOrganization> organizations, {
    this.aggregator = const OpenKatAggregator(),
  }) : organizations = List.unmodifiable(organizations);

  OpenKatOrganization? organization(String code) {
    for (final organization in organizations) {
      if (organization.code == code) return organization;
    }
    return null;
  }

  /// Laatste succesvolle, bruikbare meting op of vóór [asOf].
  OpenKatSnapshot? snapshotOnOrBefore(
    OpenKatOrganization organization,
    DateTime asOf,
  ) {
    OpenKatSnapshot? selected;
    for (final snapshot in organization.snapshots) {
      if (!snapshot.usable || snapshot.reportDate.isAfter(asOf)) continue;
      if (selected == null ||
          snapshot.reportDate.isAfter(selected.reportDate)) {
        selected = snapshot;
      }
    }
    return selected;
  }

  List<OpenKatReportSelection> selections(OpenKatReportRequest request) {
    final scoped = switch (request.scope.kind) {
      OpenKatReportScopeKind.portfolio => organizations,
      OpenKatReportScopeKind.organization => [
        ?organization(request.scope.organizationCode!),
      ],
    };
    return [
      for (final organization in scoped) _selectionFor(organization, request),
    ];
  }

  OpenKatReportSelection _selectionFor(
    OpenKatOrganization organization,
    OpenKatReportRequest request,
  ) {
    final current = snapshotOnOrBefore(organization, request.currentAsOf);
    final explicitPrevious = request.previousAsOf;
    final previous = explicitPrevious == null
        ? _snapshotBefore(organization, current?.reportDate)
        : snapshotOnOrBefore(organization, explicitPrevious);
    return OpenKatReportSelection(
      organization: organization,
      currentAsOf: request.currentAsOf,
      previousAsOf: explicitPrevious ?? current?.reportDate,
      current: current,
      previous: previous,
    );
  }

  OpenKatSnapshot? _snapshotBefore(
    OpenKatOrganization organization,
    DateTime? before,
  ) {
    if (before == null) return null;
    OpenKatSnapshot? selected;
    for (final snapshot in organization.snapshots) {
      if (!snapshot.usable || !snapshot.reportDate.isBefore(before)) continue;
      if (selected == null ||
          snapshot.reportDate.isAfter(selected.reportDate)) {
        selected = snapshot;
      }
    }
    return selected;
  }

  List<OpenKatMeasurementUsage> measurementUsages(
    OpenKatReportRequest request,
  ) => [
    for (final selection in selections(request)) ...[
      OpenKatMeasurementUsage(
        organizationCode: selection.organization.code,
        role: OpenKatMeasurementRole.current,
        requestedAsOf: selection.currentAsOf,
        measuredAt: selection.current?.reportDate,
        age: selection.currentAge,
        missing: selection.currentMissing,
      ),
      if (selection.previousAsOf != null)
        OpenKatMeasurementUsage(
          organizationCode: selection.organization.code,
          role: OpenKatMeasurementRole.previous,
          requestedAsOf: selection.previousAsOf!,
          measuredAt: selection.previous?.reportDate,
          age: selection.previousAge,
          missing: selection.previous == null,
        ),
    ],
  ];

  List<OpenKatSourceTrace> sourceTraces(OpenKatReportRequest request) => [
    for (final selection in selections(request)) ...[
      if (selection.current != null)
        _trace(
          selection.organization.code,
          OpenKatMeasurementRole.current,
          selection.current!,
        ),
      if (selection.previous != null)
        _trace(
          selection.organization.code,
          OpenKatMeasurementRole.previous,
          selection.previous!,
        ),
    ],
  ];

  OpenKatSourceTrace _trace(
    String organizationCode,
    OpenKatMeasurementRole role,
    OpenKatSnapshot snapshot,
  ) => OpenKatSourceTrace(
    organizationCode: organizationCode,
    role: role,
    reportDate: snapshot.reportDate,
    sourceFile: snapshot.sourceFile,
    sourceHash: snapshot.sourceHash,
    schema: snapshot.schema,
  );

  /// Organisaties beperkt tot de gekozen vorige en huidige meetmomenten.
  ///
  /// De bestaande slidecompositie kan zo compatibel blijven, terwijl ook zij
  /// voortaan uitsluitend de centrale peildatumregels gebruikt.
  List<OpenKatOrganization> selectedOrganizations(
    OpenKatReportRequest request,
  ) => [
    for (final selection in selections(request))
      if (selection.current != null)
        selection.organization.copyWith(
          snapshots: [
            if (selection.previous != null) selection.previous!,
            selection.current!,
          ],
        ),
  ];

  bool hasComparableCoverage(OpenKatReportSelection selection) {
    final current = selection.current;
    final previous = selection.previous;
    if (current == null || previous == null) return false;
    final currentScope = current.measurementScopeId;
    final previousScope = previous.measurementScopeId;
    return current.sourceFeatures.contains(
          OpenKatSourceFeature.comparableMeasurementCoverage,
        ) &&
        previous.sourceFeatures.contains(
          OpenKatSourceFeature.comparableMeasurementCoverage,
        ) &&
        currentScope != null &&
        currentScope.isNotEmpty &&
        currentScope == previousScope;
  }

  List<OpenKatFindingLifecycleItem> findingLifecycle(
    OpenKatReportRequest request,
  ) {
    final out = <OpenKatFindingLifecycleItem>[];
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      final currentById = {
        for (final finding in current.findings) finding.id: finding,
      };
      final previousById = {
        for (final finding in previous.findings) finding.id: finding,
      };
      final comparable = hasComparableCoverage(selection);

      for (final entry in currentById.entries) {
        if (previousById.containsKey(entry.key)) continue;
        out.add(
          OpenKatFindingLifecycleItem(
            organizationCode: selection.organization.code,
            finding: entry.value,
            observation:
                _wasSeenBefore(
                  selection.organization,
                  entry.key,
                  previous.reportDate,
                )
                ? OpenKatFindingObservation.reobserved
                : OpenKatFindingObservation.newlyObserved,
            comparableCoverage: comparable,
          ),
        );
      }
      for (final entry in previousById.entries) {
        if (currentById.containsKey(entry.key)) continue;
        out.add(
          OpenKatFindingLifecycleItem(
            organizationCode: selection.organization.code,
            finding: entry.value,
            observation: OpenKatFindingObservation.noLongerObserved,
            comparableCoverage: comparable,
          ),
        );
      }
    }
    return List.unmodifiable(out);
  }

  bool _wasSeenBefore(
    OpenKatOrganization organization,
    String findingId,
    DateTime before,
  ) => organization.snapshots.any(
    (snapshot) =>
        snapshot.usable &&
        snapshot.reportDate.isBefore(before) &&
        snapshot.findings.any((finding) => finding.id == findingId),
  );

  List<OpenKatControlChange> controlChanges(OpenKatReportRequest request) {
    final out = <OpenKatControlChange>[];
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      for (final id in {...current.controls.keys, ...previous.controls.keys}) {
        final currentRatio = current.controls[id]?.ratio;
        final previousRatio = previous.controls[id]?.ratio;
        if (currentRatio == null ||
            previousRatio == null ||
            currentRatio == previousRatio) {
          continue;
        }
        out.add(
          OpenKatControlChange(
            organizationCode: selection.organization.code,
            controlId: id,
            previousRatio: previousRatio,
            currentRatio: currentRatio,
          ),
        );
      }
    }
    return List.unmodifiable(out);
  }

  /// Verbeterde én verslechterde systemen, zonder samengestelde risicoscore.
  ///
  /// Een richting is pas eenduidig wanneer geen ernstteller de andere kant op
  /// beweegt. Tegengestelde mutaties heten `gemengd`; de afzonderlijke tellers
  /// blijven in [OpenKatSystemChange] zichtbaar.
  List<OpenKatSystemChange> systemChanges(OpenKatReportRequest request) {
    final out = <OpenKatSystemChange>[];
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      final currentById = {
        for (final stats in aggregator.systemsWithMostFindings(current))
          stats.systemId: stats,
      };
      final previousById = {
        for (final stats in aggregator.systemsWithMostFindings(previous))
          stats.systemId: stats,
      };
      for (final id in currentById.keys) {
        final oldStats = previousById[id];
        if (oldStats == null) continue;
        final newStats = currentById[id]!;
        final deltas = [
          newStats.critical - oldStats.critical,
          newStats.high - oldStats.high,
          newStats.medium - oldStats.medium,
          newStats.low - oldStats.low,
          newStats.other - oldStats.other,
        ];
        if (deltas.every((delta) => delta == 0)) continue;
        final hasIncrease = deltas.any((delta) => delta > 0);
        final hasDecrease = deltas.any((delta) => delta < 0);
        final classification = switch ((hasIncrease, hasDecrease)) {
          (true, false) => 'verslechterd',
          (false, true) => 'verbeterd',
          _ => 'gemengd',
        };
        out.add(
          OpenKatSystemChange(
            systemId: id,
            oldStats: oldStats,
            newStats: newStats,
            classification: classification,
          ),
        );
      }
    }
    out.sort((a, b) => a.systemId.compareTo(b.systemId));
    return List.unmodifiable(out);
  }

  List<OpenKatCveExposure> cveExposure(
    OpenKatReportRequest request,
    String cveId,
  ) {
    final canonical = cveId.trim().toUpperCase();
    return [
      for (final selection in selections(request))
        if (selection.current != null)
          for (final finding in selection.current!.findings)
            if (finding.cveIds.contains(canonical))
              OpenKatCveExposure(
                organizationCode: selection.organization.code,
                finding: finding,
              ),
    ];
  }

  List<OpenKatMonitoringMutation> monitoringMutations(
    OpenKatReportRequest request,
  ) {
    final out = <OpenKatMonitoringMutation>[];
    for (final selection in selections(request)) {
      final current = selection.current;
      final previous = selection.previous;
      if (current == null || previous == null) continue;
      final currentById = {
        for (final system in current.systems) system.id: system,
      };
      final previousById = {
        for (final system in previous.systems) system.id: system,
      };
      for (final entry in currentById.entries) {
        final wasMonitored =
            previousById[entry.key]?.monitoringStatus ==
            OpenKatMonitoringStatus.monitored;
        if (entry.value.monitoringStatus == OpenKatMonitoringStatus.monitored &&
            !wasMonitored) {
          out.add(
            OpenKatMonitoringMutation(
              organizationCode: selection.organization.code,
              system: entry.value,
              kind: OpenKatMonitoringMutationKind.added,
            ),
          );
        }
      }
      for (final entry in previousById.entries) {
        final isMonitored =
            currentById[entry.key]?.monitoringStatus ==
            OpenKatMonitoringStatus.monitored;
        if (entry.value.monitoringStatus == OpenKatMonitoringStatus.monitored &&
            !isMonitored) {
          out.add(
            OpenKatMonitoringMutation(
              organizationCode: selection.organization.code,
              system: entry.value,
              kind: OpenKatMonitoringMutationKind.removed,
            ),
          );
        }
      }
    }
    return List.unmodifiable(out);
  }

  List<OpenKatFinding> findingsBySeverity(
    OpenKatSnapshot snapshot,
    String severity,
  ) => snapshot.findings
      .where((finding) => openKatSeverityBand(finding.severity) == severity)
      .toList(growable: false);

  Set<String> affectedSystems(OpenKatSnapshot snapshot) => {
    for (final finding in snapshot.findings)
      if (finding.systemId != null) finding.systemId!,
  };

  Map<String, Set<String>> findingTypesAcrossOrganizations(
    OpenKatReportRequest request,
  ) {
    final out = <String, Set<String>>{};
    for (final selection in selections(request)) {
      final current = selection.current;
      if (current == null) continue;
      for (final finding in current.findings) {
        out
            .putIfAbsent(finding.findingTypeId, () => <String>{})
            .add(selection.organization.code);
      }
    }
    return out;
  }

  SnapshotAggregate aggregateSnapshot(OpenKatSnapshot snapshot) =>
      aggregator.aggregateSnapshot(snapshot);

  PortfolioAggregate aggregatePortfolio(
    List<OpenKatOrganization> organizations,
  ) => aggregator.aggregatePortfolio(organizations);

  TrendConclusion compare(
    SnapshotAggregate current,
    SnapshotAggregate? previous,
  ) => aggregator.compare(current, previous);

  List<OpenKatIssue> topIssues(List<OpenKatOrganization> organizations) =>
      aggregator.topIssues(organizations);

  List<OpenKatOpenFinding> longestOpenFindings(
    List<OpenKatOrganization> organizations,
  ) => aggregator.longestOpenFindings(organizations);

  List<OpenKatSystemStats> systemsWithMostFindings(OpenKatSnapshot snapshot) =>
      aggregator.systemsWithMostFindings(snapshot);

  List<OpenKatHistoryPoint> history(List<OpenKatOrganization> organizations) =>
      aggregator.history(organizations);

  List<OpenKatOrganizationComparison> organizationComparison(
    List<OpenKatOrganization> organizations,
  ) => aggregator.organizationComparison(organizations);

  List<OpenKatSystemChange> mostImprovedSystems(
    OpenKatOrganization organization,
  ) => aggregator.mostImprovedSystems(organization);
}
