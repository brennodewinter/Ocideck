import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_report_capabilities.dart';
import 'openkat_report_composer.dart';
import 'openkat_report_facts.dart';
import 'openkat_report_scenarios.dart';

/// Pure, headless toegangspunt van canonieke OpenKAT-feiten naar OciDeck.
class OpenKatReportEngine {
  final OpenKatReportScenarioRegistry registry;
  final OpenKatReportCapabilityService capabilityService;

  OpenKatReportEngine({
    OpenKatReportScenarioRegistry? registry,
    this.capabilityService = const OpenKatReportCapabilityService(),
  }) : registry = registry ?? OpenKatReportScenarioRegistry();

  OpenKatReportResult generate(
    List<OpenKatOrganization> organizations,
    OpenKatReportRequest request, {
    String? outputPath,
  }) {
    final facts = OpenKatReportFacts(organizations);
    final measurements = facts.measurementUsages(request);
    final traces = facts.sourceTraces(request);
    final diagnostics = <OpenKatReportDiagnostic>[];
    final missing = <OpenKatReportCapability>{};
    final scenario = registry.find(request.scenarioId);

    if (scenario == null) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.unknownScenario,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {'scenarioId': request.scenarioId},
        ),
      );
      return _failure(request, measurements, diagnostics, missing, traces);
    }

    final descriptor = scenario.descriptor;
    _validateRequest(facts, request, descriptor, diagnostics);
    final assessments = capabilityService.assess(facts, request);
    for (final capability in descriptor.requiredCapabilities) {
      if (assessments[capability]?.isAvailable ?? false) continue;
      missing.add(capability);
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.missingCapability,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {'capability': capability.name},
        ),
      );
    }
    for (final capability in descriptor.optionalCapabilities) {
      final assessment = assessments[capability];
      if (assessment == null ||
          assessment.status != OpenKatCapabilityStatus.unavailable) {
        continue;
      }
      missing.add(capability);
    }
    _addSelectionDiagnostics(
      request,
      measurements,
      assessments,
      descriptor,
      diagnostics,
    );

    if (diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == OpenKatReportDiagnosticSeverity.error,
    )) {
      return _failure(request, measurements, diagnostics, missing, traces);
    }

    final composedPlan = scenario.compose(facts, request);
    final plan = _validatedPlan(
      facts,
      composedPlan,
      descriptor,
      request,
      assessments,
      diagnostics,
      missing,
    );
    if (plan == null) {
      return _failure(request, measurements, diagnostics, missing, traces);
    }
    final deck = OpenKatReportComposer(
      facts,
      language: request.language,
    ).compose(request, plan, outputPath: outputPath);
    return OpenKatReportResult(
      deck: deck,
      plan: plan,
      scenarioId: descriptor.id,
      scope: request.scope,
      measurements: measurements,
      diagnostics: List.unmodifiable(diagnostics),
      missingCapabilities: Set.unmodifiable(missing),
      sourceTraces: traces,
    );
  }

  void _validateRequest(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
    OpenKatScenarioDescriptor descriptor,
    List<OpenKatReportDiagnostic> diagnostics,
  ) {
    if (!descriptor.scopes.contains(request.scope.kind)) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.unsupportedScope,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {
            'scenarioId': descriptor.id,
            'scope': request.scope.kind.name,
          },
        ),
      );
    }
    final organizationCode = request.scope.organizationCode;
    if (organizationCode != null &&
        facts.organization(organizationCode) == null) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.organizationNotFound,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {'organizationCode': organizationCode},
        ),
      );
    }
    if (descriptor.requiresPreviousAsOf && request.previousAsOf == null) {
      diagnostics.add(
        const OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.previousSnapshotMissing,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {'reason': 'previousAsOfRequired'},
        ),
      );
    }
    final previousAsOf = request.previousAsOf;
    if (previousAsOf != null && !previousAsOf.isBefore(request.currentAsOf)) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.invalidSnapshotChronology,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {
            'previousAsOf': previousAsOf.toIso8601String(),
            'currentAsOf': request.currentAsOf.toIso8601String(),
          },
        ),
      );
    }
    if (descriptor.requiresCveId && !_isCanonicalCve(request.cveId)) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.invalidCveId,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {'cveId': request.cveId ?? ''},
        ),
      );
    }
    _validatePolicy(request.policy, diagnostics);
  }

  void _validatePolicy(
    OpenKatReportPolicy policy,
    List<OpenKatReportDiagnostic> diagnostics,
  ) {
    _validatePolicyLimit(
      diagnostics,
      field: 'tableRowLimit',
      value: policy.tableRowLimit,
      maximum: OpenKatReportPolicy.maximumTableRowLimit,
    );
    _validatePolicyLimit(
      diagnostics,
      field: 'historicalFindingWorkLimit',
      value: policy.historicalFindingWorkLimit,
      maximum: OpenKatReportPolicy.maximumHistoricalFindingWorkLimit,
    );
  }

  void _validatePolicyLimit(
    List<OpenKatReportDiagnostic> diagnostics, {
    required String field,
    required int value,
    required int maximum,
  }) {
    if (value > 0 && value <= maximum) return;
    diagnostics.add(
      OpenKatReportDiagnostic(
        code: OpenKatReportDiagnosticCode.invalidPolicy,
        severity: OpenKatReportDiagnosticSeverity.error,
        arguments: {
          'field': field,
          'value': '$value',
          'minimum': '1',
          'maximum': '$maximum',
        },
      ),
    );
  }

  bool _isCanonicalCve(String? value) =>
      value != null &&
      RegExp(r'^CVE-[0-9]{4}-[0-9]{4,}$').hasMatch(value.trim().toUpperCase());

  OpenKatReportPlan? _validatedPlan(
    OpenKatReportFacts facts,
    OpenKatReportPlan plan,
    OpenKatScenarioDescriptor descriptor,
    OpenKatReportRequest request,
    Map<OpenKatReportCapability, OpenKatCapabilityAssessment> assessments,
    List<OpenKatReportDiagnostic> diagnostics,
    Set<OpenKatReportCapability> missing,
  ) {
    if (plan.scenarioId != descriptor.id) {
      _invalidPlan(
        diagnostics,
        reason: 'scenarioIdMismatch',
        arguments: {
          'expectedScenarioId': descriptor.id,
          'actualScenarioId': plan.scenarioId,
        },
      );
    }
    if (plan.blocks.isEmpty) {
      _invalidPlan(diagnostics, reason: 'emptyPlan');
    }

    final blockIds = <String>{};
    final blockKinds = <OpenKatReportBlockKind>{};
    final applicableBlocks = <OpenKatReportBlock>[];
    for (final block in plan.blocks) {
      if (block.id.trim().isEmpty) {
        _invalidPlan(diagnostics, reason: 'emptyBlockId');
      } else if (!blockIds.add(block.id)) {
        _invalidPlan(
          diagnostics,
          reason: 'duplicateBlockId',
          arguments: {'blockId': block.id},
        );
      }
      if (!blockKinds.add(block.kind)) {
        _invalidPlan(
          diagnostics,
          reason: 'duplicateBlockKind',
          arguments: {'blockKind': block.kind.name},
        );
      }

      final preconditions = block.preconditions;
      if (preconditions.requiresPreviousAsOf && request.previousAsOf == null) {
        diagnostics.add(
          OpenKatReportDiagnostic(
            code: OpenKatReportDiagnosticCode.previousSnapshotMissing,
            severity: OpenKatReportDiagnosticSeverity.error,
            arguments: {
              'reason': 'blockRequiresPreviousAsOf',
              'blockId': block.id,
            },
          ),
        );
      }
      if (preconditions.requiresCveId && !_isCanonicalCve(request.cveId)) {
        diagnostics.add(
          OpenKatReportDiagnostic(
            code: OpenKatReportDiagnosticCode.invalidCveId,
            severity: OpenKatReportDiagnosticSeverity.error,
            arguments: {'cveId': request.cveId ?? '', 'blockId': block.id},
          ),
        );
      }

      final unavailable = preconditions.capabilities
          .where(
            (capability) => !(assessments[capability]?.isAvailable ?? false),
          )
          .toSet();
      missing.addAll(unavailable);
      final optionalUnavailable = unavailable.every(
        descriptor.optionalCapabilities.contains,
      );
      final mayOmit = preconditions.omitWhenUnavailable && optionalUnavailable;
      if (unavailable.isNotEmpty && !mayOmit) {
        for (final capability in unavailable) {
          diagnostics.add(
            OpenKatReportDiagnostic(
              code: OpenKatReportDiagnosticCode.missingCapability,
              severity: OpenKatReportDiagnosticSeverity.error,
              arguments: {'capability': capability.name, 'blockId': block.id},
            ),
          );
        }
      } else if (unavailable.isEmpty) {
        applicableBlocks.add(block);
      }
    }

    if (applicableBlocks.isEmpty && plan.blocks.isNotEmpty) {
      _invalidPlan(diagnostics, reason: 'noApplicableBlocks');
    }
    if (applicableBlocks.any(
          (block) => block.kind == OpenKatReportBlockKind.findingLifecycle,
        ) &&
        facts.exceedsHistoricalFindingWorkLimit(
          request,
          request.policy.historicalFindingWorkLimit,
        )) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.resourceLimitExceeded,
          severity: OpenKatReportDiagnosticSeverity.error,
          arguments: {
            'resource': 'historicalFindings',
            'maximum': '${request.policy.historicalFindingWorkLimit}',
          },
        ),
      );
    }
    if (diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == OpenKatReportDiagnosticSeverity.error,
    )) {
      return null;
    }
    return OpenKatReportPlan(
      scenarioId: plan.scenarioId,
      blocks: List.unmodifiable(applicableBlocks),
    );
  }

  void _invalidPlan(
    List<OpenKatReportDiagnostic> diagnostics, {
    required String reason,
    Map<String, String> arguments = const {},
  }) {
    diagnostics.add(
      OpenKatReportDiagnostic(
        code: OpenKatReportDiagnosticCode.invalidReportPlan,
        severity: OpenKatReportDiagnosticSeverity.error,
        arguments: {'reason': reason, ...arguments},
      ),
    );
  }

  void _addSelectionDiagnostics(
    OpenKatReportRequest request,
    List<OpenKatMeasurementUsage> measurements,
    Map<OpenKatReportCapability, OpenKatCapabilityAssessment> assessments,
    OpenKatScenarioDescriptor descriptor,
    List<OpenKatReportDiagnostic> diagnostics,
  ) {
    final current = measurements
        .where(
          (measurement) => measurement.role == OpenKatMeasurementRole.current,
        )
        .toList();
    final missingCurrent = current
        .where((measurement) => measurement.missing)
        .toList();
    if (current.isEmpty || missingCurrent.length == current.length) {
      diagnostics.add(
        const OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.currentSnapshotMissing,
          severity: OpenKatReportDiagnosticSeverity.error,
        ),
      );
    } else if (missingCurrent.isNotEmpty) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.incompletePortfolio,
          severity: OpenKatReportDiagnosticSeverity.warning,
          arguments: {
            'missingOrganizations': missingCurrent
                .map((measurement) => measurement.organizationCode)
                .join(','),
          },
        ),
      );
    }
    final missingPrevious = measurements
        .where(
          (measurement) =>
              measurement.role == OpenKatMeasurementRole.previous &&
              measurement.missing,
        )
        .toList();
    if (missingPrevious.isNotEmpty) {
      diagnostics.add(
        OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.incompletePortfolio,
          severity: OpenKatReportDiagnosticSeverity.warning,
          arguments: {
            'missingOrganizations': missingPrevious
                .map((measurement) => measurement.organizationCode)
                .join(','),
            'role': OpenKatMeasurementRole.previous.name,
          },
        ),
      );
    }

    final maximumAge = request.policy.maximumSnapshotAge;
    if (maximumAge != null) {
      for (final measurement in measurements) {
        final age = measurement.age;
        if (age == null || age <= maximumAge) continue;
        diagnostics.add(
          OpenKatReportDiagnostic(
            code: OpenKatReportDiagnosticCode.snapshotTooOld,
            severity: OpenKatReportDiagnosticSeverity.warning,
            arguments: {
              'organizationCode': measurement.organizationCode,
              'role': measurement.role.name,
              'ageDays': '${age.inDays}',
              'maximumAgeDays': '${maximumAge.inDays}',
            },
          ),
        );
      }
    }

    final comparison =
        assessments[OpenKatReportCapability.comparableMeasurementCoverage];
    if (descriptor.optionalCapabilities.contains(
          OpenKatReportCapability.comparableMeasurementCoverage,
        ) &&
        comparison?.status == OpenKatCapabilityStatus.unavailable &&
        comparison?.arguments['comparedOrganizations'] != '0') {
      diagnostics.add(
        const OpenKatReportDiagnostic(
          code: OpenKatReportDiagnosticCode.incomparableMeasurementCoverage,
          severity: OpenKatReportDiagnosticSeverity.warning,
        ),
      );
    }
  }

  OpenKatReportResult _failure(
    OpenKatReportRequest request,
    List<OpenKatMeasurementUsage> measurements,
    List<OpenKatReportDiagnostic> diagnostics,
    Set<OpenKatReportCapability> missing,
    List<OpenKatSourceTrace> traces,
  ) => OpenKatReportResult(
    deck: null,
    plan: null,
    scenarioId: request.scenarioId,
    scope: request.scope,
    measurements: measurements,
    diagnostics: List.unmodifiable(diagnostics),
    missingCapabilities: Set.unmodifiable(missing),
    sourceTraces: traces,
  );
}
