import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_report_facts.dart';

/// Beoordeelt bronmogelijkheden op exact de meetmomenten van het verzoek.
class OpenKatReportCapabilityService {
  const OpenKatReportCapabilityService();

  Map<OpenKatReportCapability, OpenKatCapabilityAssessment> assess(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) {
    final selections = facts.selections(request);
    final current = [for (final selection in selections) ?selection.current];
    final selectedSnapshots = [
      for (final selection in selections) ...[
        ?selection.current,
        if (request.previousAsOf != null) ?selection.previous,
      ],
    ];
    final compared = facts
        .comparisonSelections(request)
        .where(
          (selection) =>
              selection.current != null && selection.previous != null,
        )
        .where(
          (selection) => selection.previous!.reportDate.isBefore(
            selection.current!.reportDate,
          ),
        )
        .toList();

    return {
      OpenKatReportCapability.multipleOrganizations: _binary(
        OpenKatReportCapability.multipleOrganizations,
        selections.length > 1,
        {'organizationCount': '${selections.length}'},
      ),
      OpenKatReportCapability.historicalSnapshots: _binary(
        OpenKatReportCapability.historicalSnapshots,
        compared.isNotEmpty,
        {
          'comparedOrganizations': '${compared.length}',
          'organizationCount': '${selections.length}',
        },
      ),
      OpenKatReportCapability.reliableCveReferences: _sourceFeature(
        OpenKatReportCapability.reliableCveReferences,
        selectedSnapshots,
        OpenKatSourceFeature.reliableCveReferences,
      ),
      OpenKatReportCapability.reliableMonitoringStatus: _sourceFeature(
        OpenKatReportCapability.reliableMonitoringStatus,
        selectedSnapshots,
        OpenKatSourceFeature.reliableMonitoringStatus,
        additionalEvidence: (snapshot) =>
            snapshot.systems.every((system) => system.monitoringStatus != null),
      ),
      OpenKatReportCapability.reliableOpenedAt: _sourceFeature(
        OpenKatReportCapability.reliableOpenedAt,
        current,
        OpenKatSourceFeature.reliableOpenedAt,
        additionalEvidence: (snapshot) =>
            snapshot.findings.isNotEmpty &&
            snapshot.findings.every(
              (finding) =>
                  finding.openedAt != null &&
                  !finding.openedAt!.isAfter(snapshot.reportDate),
            ),
      ),
      OpenKatReportCapability.stableAssetIdentity: _binary(
        OpenKatReportCapability.stableAssetIdentity,
        selectedSnapshots.isNotEmpty &&
            selectedSnapshots.every(
              (snapshot) =>
                  snapshot.sourceFeatures.contains(
                    OpenKatSourceFeature.stableAssetIdentity,
                  ) &&
                  snapshot.systems.isNotEmpty &&
                  snapshot.systems.every((system) => system.stableIdentity),
            ),
      ),
      OpenKatReportCapability.comparableMeasurementCoverage: _binary(
        OpenKatReportCapability.comparableMeasurementCoverage,
        selections.isNotEmpty &&
            compared.length == selections.length &&
            compared.every(facts.hasComparableCoverage),
        {
          'comparableOrganizations':
              '${compared.where(facts.hasComparableCoverage).length}',
          'comparedOrganizations': '${compared.length}',
        },
      ),
      OpenKatReportCapability.findingLifecycle: _binary(
        OpenKatReportCapability.findingLifecycle,
        selections.isNotEmpty &&
            compared.length == selections.length &&
            compared.every(
              (selection) =>
                  selection.current!.sourceFeatures.contains(
                    OpenKatSourceFeature.stableFindingIdentity,
                  ) &&
                  selection.previous!.sourceFeatures.contains(
                    OpenKatSourceFeature.stableFindingIdentity,
                  ) &&
                  selection.current!.findings.every(
                    (finding) => finding.stableIdentity,
                  ) &&
                  selection.previous!.findings.every(
                    (finding) => finding.stableIdentity,
                  ),
            ),
      ),
      OpenKatReportCapability.controlsWithDenominator: _binary(
        OpenKatReportCapability.controlsWithDenominator,
        current.isNotEmpty &&
            current.every(
              (snapshot) =>
                  snapshot.controls.isNotEmpty &&
                  snapshot.controls.values.every(
                    (score) => score.ratio != null,
                  ),
            ),
      ),
      OpenKatReportCapability.comparableControlsWithDenominator: _binary(
        OpenKatReportCapability.comparableControlsWithDenominator,
        selections.isNotEmpty &&
            compared.length == selections.length &&
            compared.every(
              (selection) =>
                  _hasControlDenominators(selection.current!) &&
                  _hasControlDenominators(selection.previous!),
            ),
        {
          'comparedOrganizations': '${compared.length}',
          'organizationCount': '${selections.length}',
        },
      ),
      OpenKatReportCapability.sufficientDataFreshness: _freshness(
        facts,
        request,
      ),
    };
  }

  bool _hasControlDenominators(OpenKatSnapshot snapshot) =>
      snapshot.controls.isNotEmpty &&
      snapshot.controls.values.every((score) => score.ratio != null);

  OpenKatCapabilityAssessment _sourceFeature(
    OpenKatReportCapability capability,
    List<OpenKatSnapshot> snapshots,
    OpenKatSourceFeature feature, {
    bool Function(OpenKatSnapshot snapshot)? additionalEvidence,
  }) => _binary(
    capability,
    snapshots.isNotEmpty &&
        snapshots.every(
          (snapshot) =>
              snapshot.sourceFeatures.contains(feature) &&
              (additionalEvidence?.call(snapshot) ?? true),
        ),
  );

  OpenKatCapabilityAssessment _freshness(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) {
    final maximum = request.policy.maximumSnapshotAge;
    if (maximum == null) {
      return const OpenKatCapabilityAssessment(
        capability: OpenKatReportCapability.sufficientDataFreshness,
        status: OpenKatCapabilityStatus.notAssessed,
      );
    }
    final present = facts
        .measurementUsages(request)
        .where((measurement) => !measurement.missing)
        .toList();
    return _binary(
      OpenKatReportCapability.sufficientDataFreshness,
      present.isNotEmpty &&
          present.every((measurement) => measurement.age! <= maximum),
      {'maximumAgeDays': '${maximum.inDays}'},
    );
  }

  OpenKatCapabilityAssessment _binary(
    OpenKatReportCapability capability,
    bool available, [
    Map<String, String> arguments = const {},
  ]) => OpenKatCapabilityAssessment(
    capability: capability,
    status: available
        ? OpenKatCapabilityStatus.available
        : OpenKatCapabilityStatus.unavailable,
    arguments: arguments,
  );
}
