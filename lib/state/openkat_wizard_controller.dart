import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../models/deck.dart';
import '../models/openkat/openkat_models.dart';
import '../models/openkat/openkat_reporting_models.dart';
import '../models/openkat/openkat_wizard_models.dart';
import '../services/openkat/openkat_wizard_service.dart';
import '../services/openkat/openkat_deck_generator.dart';
import '../utils/log.dart';

class OpenKatWizardController extends ChangeNotifier {
  final OpenKatWizardGateway gateway;
  final Deck? existingDeck;
  final OpenKatWizardRecipe? initialRecipe;
  final DateTime Function() _now;
  final void Function(String operation, Object error, StackTrace stack)
  _logFailure;

  OpenKatWizardScanStatus scanStatus = OpenKatWizardScanStatus.idle;
  OpenKatWizardBuildStatus buildStatus = OpenKatWizardBuildStatus.idle;
  OpenKatWizardStep step = OpenKatWizardStep.scenario;
  OpenKatWizardScan? scan;
  Object? scanError;
  Object? buildError;
  bool get unsafeUpdate => buildError is OpenKatUnsafeUpdateException;
  OpenKatReportFamilyId selectedFamilyId =
      OpenKatReportFamilyId.organizationsManagement;
  OpenKatWizardScenarioId? selectedScenarioId;
  String? selectedOrganizationCode;
  Set<String> selectedOrganizationCodes = {};
  DateTime? currentAsOf;
  DateTime? previousAsOf;
  String? cveId;
  OpenKatReportLanguage language;
  String reportTitle = '';
  bool moreSettingsExpanded = false;
  bool moreRecipesExpanded = false;
  bool updateConfirmationVisible;
  OpenKatWizardBuildResult? result;
  OpenKatReportResult? _previewCache;
  String? _previewKey;

  OpenKatWizardController({
    required this.gateway,
    this.existingDeck,
    this.initialRecipe,
    OpenKatReportLanguage? initialLanguage,
    DateTime Function()? now,
    void Function(String operation, Object error, StackTrace stack)? logFailure,
  }) : _now = now ?? DateTime.now,
       _logFailure = logFailure ?? _defaultLogFailure,
       language = initialLanguage ?? _activeReportLanguage(),
       updateConfirmationVisible = existingDeck != null;

  static OpenKatReportLanguage _activeReportLanguage() =>
      const AppLocalizations(Locale('nl')).languageCode == 'nl'
      ? OpenKatReportLanguage.dutch
      : OpenKatReportLanguage.english;

  static void _defaultLogFailure(
    String operation,
    Object error,
    StackTrace stack,
  ) => logError(operation, error, stack);

  bool get updating => existingDeck != null;
  bool get busy =>
      scanStatus == OpenKatWizardScanStatus.scanning ||
      buildStatus == OpenKatWizardBuildStatus.building;

  OpenKatWizardScenarioAvailability? get selectedScenario {
    final id = selectedScenarioId;
    if (id == null) return null;
    for (final scenario
        in scan?.scenarios ?? const <OpenKatWizardScenarioAvailability>[]) {
      if (scenario.descriptor.id == id) return scenario;
    }
    return null;
  }

  OpenKatWizardRecipe? get recipe {
    final scenario = selectedScenarioId;
    final current = currentAsOf;
    if (scenario == null || current == null) return null;
    final descriptor = selectedScenario?.descriptor;
    if (descriptor == null) return null;
    return OpenKatWizardRecipe(
      scenarioId: scenario,
      organizationCode:
          descriptor.inputs.contains(OpenKatWizardInputKind.organization)
          ? selectedOrganizationCode
          : null,
      organizationCodes:
          descriptor.inputs.contains(OpenKatWizardInputKind.organizations)
          ? selectedOrganizationCodes
          : const {},
      currentAsOf: current,
      previousAsOf:
          descriptor.inputs.contains(OpenKatWizardInputKind.previousAsOf)
          ? previousAsOf
          : null,
      cveId: descriptor.inputs.contains(OpenKatWizardInputKind.cve)
          ? cveId
          : null,
      language: language,
      title: reportTitle,
      maximumSnapshotAge: descriptor.maximumSnapshotAge,
    );
  }

  OpenKatReportResult? get reportPreview {
    final prepared = scan;
    final request = recipe;
    if (prepared == null || request == null) return null;
    final key = [
      request.scenarioId.name,
      request.organizationCode ?? '',
      ...(request.organizationCodes.toList()..sort()),
      request.currentAsOf.toIso8601String(),
      request.previousAsOf?.toIso8601String() ?? '',
      request.cveId ?? '',
      request.language.code,
      '${request.maximumSnapshotAge?.inMicroseconds ?? ''}',
    ].join('|');
    if (_previewKey == key) return _previewCache;
    _previewKey = key;
    _previewCache = gateway.preview(prepared, request);
    return _previewCache;
  }

  OpenKatWizardPreviewFacts? get selectedPreviewFacts {
    final prepared = scan;
    if (prepared == null) return null;
    final inputs = selectedScenario?.descriptor.inputs ?? const {};
    final selectedCodes = inputs.contains(OpenKatWizardInputKind.organizations)
        ? selectedOrganizationCodes
        : inputs.contains(OpenKatWizardInputKind.organization)
        ? selectedOrganizationCode == null
              ? const <String>{}
              : {selectedOrganizationCode!}
        : prepared.organizationOptions.map((option) => option.code).toSet();
    final organizations = prepared.organizations
        .where((organization) => selectedCodes.contains(organization.code))
        .toList(growable: false);
    final findings = <String, int>{};
    final sourceHashes = <String>{};
    final measurementDates = <DateTime>{};
    var criticalHigh = 0;
    var systems = 0;
    for (final organization in organizations) {
      final usable =
          organization.snapshots
              .where(
                (snapshot) =>
                    snapshot.usable &&
                    (currentAsOf == null ||
                        !snapshot.reportDate.isAfter(currentAsOf!)),
              )
              .toList()
            ..sort((a, b) => a.reportDate.compareTo(b.reportDate));
      for (final snapshot in usable) {
        sourceHashes.add(snapshot.sourceHash);
        measurementDates.add(snapshot.reportDate);
      }
      final latest = usable.lastOrNull;
      if (latest == null) continue;
      findings[organization.name] = latest.findings.length;
      criticalHigh += latest.findings
          .where(
            (finding) =>
                finding.severity.toLowerCase() == 'critical' ||
                finding.severity.toLowerCase() == 'high',
          )
          .length;
      systems += latest.systems.length;
    }
    final sortedDates = measurementDates.toList()..sort();
    return OpenKatWizardPreviewFacts(
      organizationCount: organizations.length,
      reportCount: sourceHashes.length,
      skippedCount: prepared.preview.skippedCount,
      criticalHighCount: criticalHigh,
      systemCount: systems,
      findingsByOrganization: Map.unmodifiable(findings),
      measurementDates: List.unmodifiable(sortedDates),
      findingTrend: const [],
    );
  }

  bool get canContinue {
    final selected = selectedScenario;
    if (selected == null || !selected.available) return false;
    final inputs = selected.descriptor.inputs;
    if (inputs.contains(OpenKatWizardInputKind.organization) &&
        selectedOrganizationCode == null) {
      return false;
    }
    if (inputs.contains(OpenKatWizardInputKind.organizations) &&
        selectedOrganizationCodes.isEmpty) {
      return false;
    }
    if (inputs.contains(OpenKatWizardInputKind.previousAsOf) &&
        previousAsOf == null) {
      return false;
    }
    if (inputs.contains(OpenKatWizardInputKind.cve) &&
        (cveId == null ||
            !scan!.cveOptions.any((option) => option.id == cveId))) {
      return false;
    }
    return true;
  }

  bool get hasPrimaryInputs {
    final inputs = selectedScenario?.descriptor.inputs ?? const {};
    return inputs.any(
      (input) =>
          input != OpenKatWizardInputKind.language &&
          input != OpenKatWizardInputKind.title,
    );
  }

  Future<void> prepare(String directory) async {
    if (scanStatus == OpenKatWizardScanStatus.scanning) return;
    final preservedRecipe = recipe;
    scanStatus = OpenKatWizardScanStatus.scanning;
    scan = null;
    scanError = null;
    buildError = null;
    _previewKey = null;
    _previewCache = null;
    notifyListeners();
    try {
      final prepared = await gateway.prepare(directory);
      scan = prepared;
      scanStatus =
          prepared.organizationOptions.isEmpty ||
              prepared.preview.reportCount == 0
          ? OpenKatWizardScanStatus.empty
          : OpenKatWizardScanStatus.ready;
      if (scanStatus == OpenKatWizardScanStatus.ready) {
        _applyDefaults(prepared, preservedRecipe);
      }
    } catch (error, stack) {
      scanStatus = OpenKatWizardScanStatus.failed;
      scanError = error;
      _logFailure(
        'OpenKatWizardController.prepare: scan reports',
        error,
        stack,
      );
    }
    notifyListeners();
  }

  void _applyDefaults(
    OpenKatWizardScan prepared,
    OpenKatWizardRecipe? preservedRecipe,
  ) {
    final remembered = preservedRecipe ?? initialRecipe;
    final inferred = remembered ?? _inferRecipe(prepared);
    final availableIds = prepared.scenarios
        .where((item) => item.available)
        .map((item) => item.descriptor.id)
        .toSet();
    final preferred = inferred?.scenarioId;
    selectedScenarioId = preferred != null && availableIds.contains(preferred)
        ? preferred
        : prepared.scenarios
              .where((item) => item.available)
              .map((item) => item.descriptor.id)
              .firstOrNull;
    selectedFamilyId =
        prepared.scenarios
            .where((item) => item.descriptor.id == selectedScenarioId)
            .map((item) => item.descriptor.family)
            .firstOrNull ??
        OpenKatReportFamilyId.organizationsManagement;
    final availableCodes = prepared.organizationOptions
        .map((item) => item.code)
        .toSet();
    final rememberedOrganization = inferred?.organizationCode;
    selectedOrganizationCode =
        rememberedOrganization != null &&
            availableCodes.contains(rememberedOrganization)
        ? rememberedOrganization
        : prepared.organizationOptions
                  .where((item) => item.measurementCount > 1)
                  .map((item) => item.code)
                  .firstOrNull ??
              prepared.organizationOptions.firstOrNull?.code;
    final rememberedCodes = inferred?.organizationCodes
        .where(availableCodes.contains)
        .toSet();
    selectedOrganizationCodes = rememberedCodes?.isNotEmpty ?? false
        ? rememberedCodes!
        : availableCodes;
    language = inferred?.language ?? language;
    reportTitle = inferred?.title ?? '';
    cveId = inferred?.cveId ?? prepared.cveOptions.firstOrNull?.id;
    _selectDates(prepared, preferred: inferred?.previousAsOf);
    final inputs = selectedScenario?.descriptor.inputs ?? const {};
    if (existingDeck != null &&
        remembered == null &&
        inputs.contains(OpenKatWizardInputKind.organizations)) {
      // Oude decks bevatten geen bewijs van de gekozen portfolioscope. Alle
      // organisaties invullen en meteen bijwerken zou die scope stil verbreden.
      // Laat de gebruiker daarom eerst de keuzes controleren.
      updateConfirmationVisible = false;
    }
  }

  OpenKatWizardRecipe? _inferRecipe(OpenKatWizardScan prepared) {
    final deck = existingDeck;
    if (deck == null) return null;
    final markerText = deck.slides.map((slide) => slide.notes).join('\n');
    final scenario = OpenKatWizardScenarioId.values.firstWhere(
      (candidate) =>
          markerText.contains('report.${candidate.reportScenarioId}.'),
      orElse: () => OpenKatWizardScenarioId.portfolio,
    );
    String? organizationCode;
    final inferredDescriptor = prepared.scenarios
        .where((item) => item.descriptor.id == scenario)
        .map((item) => item.descriptor)
        .firstOrNull;
    if (inferredDescriptor?.inputs.contains(
          OpenKatWizardInputKind.organization,
        ) ??
        false) {
      for (final option in prepared.organizationOptions) {
        final safe = option.code.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '-',
        );
        if (markerText.contains('org.$safe.')) {
          organizationCode = option.code;
          break;
        }
      }
    }
    final cveMatch = RegExp(r'CVE-[0-9]{4}-[0-9]{4,}').firstMatch(
      deck.slides.map((slide) => '${slide.id} ${slide.title}').join(),
    );
    return OpenKatWizardRecipe(
      scenarioId: scenario,
      organizationCode: organizationCode,
      organizationCodes: prepared.organizationOptions
          .map((item) => item.code)
          .toSet(),
      currentAsOf: prepared.latestMeasurement!,
      cveId: cveMatch?.group(0)?.toUpperCase(),
      language: deck.language == 'en'
          ? OpenKatReportLanguage.english
          : OpenKatReportLanguage.dutch,
      title: deck.title,
    );
  }

  void _selectDates(OpenKatWizardScan prepared, {DateTime? preferred}) {
    currentAsOf = (selectedScenario?.descriptor.currentAsOfUsesClock ?? false)
        ? _now().toUtc()
        : prepared.latestMeasurement!;
    final inputs = selectedScenario?.descriptor.inputs ?? const {};
    if (!inputs.contains(OpenKatWizardInputKind.previousAsOf)) {
      previousAsOf = null;
      return;
    }
    if (!inputs.contains(OpenKatWizardInputKind.organization)) {
      final dates = prepared.preview.measurementDates;
      final candidates = dates.where((date) => date.isBefore(currentAsOf!));
      previousAsOf = preferred != null && candidates.contains(preferred)
          ? preferred
          : candidates.lastOrNull;
      return;
    }
    final organization = prepared.organizations
        .where((item) => item.code == selectedOrganizationCode)
        .firstOrNull;
    final history =
        organization?.snapshots.where((item) => item.usable).toList() ??
        <OpenKatSnapshot>[];
    history.sort((a, b) => a.reportDate.compareTo(b.reportDate));
    final candidates = history
        .map((snapshot) => snapshot.reportDate)
        .where((date) => date.isBefore(currentAsOf!));
    previousAsOf = preferred != null && candidates.contains(preferred)
        ? preferred
        : candidates.lastOrNull;
  }

  void chooseScenario(OpenKatWizardScenarioId id) {
    final availability = scan?.scenarios
        .where((item) => item.descriptor.id == id)
        .firstOrNull;
    if (availability == null || !availability.available || busy) return;
    selectedScenarioId = id;
    selectedFamilyId = availability.descriptor.family;
    final prepared = scan;
    if (prepared != null) _selectDates(prepared);
    buildError = null;
    notifyListeners();
  }

  void chooseFamily(OpenKatReportFamilyId family) {
    if (busy || selectedFamilyId == family) return;
    selectedFamilyId = family;
    final familyScenarios =
        scan?.scenarios
            .where((item) => item.descriptor.family == family)
            .toList() ??
        const <OpenKatWizardScenarioAvailability>[];
    final preferred =
        familyScenarios
            .where((item) => item.available && item.descriptor.recommended)
            .firstOrNull ??
        familyScenarios.where((item) => item.available).firstOrNull ??
        familyScenarios
            .where((item) => item.descriptor.recommended)
            .firstOrNull ??
        familyScenarios.firstOrNull;
    selectedScenarioId = preferred?.descriptor.id;
    final prepared = scan;
    if (prepared != null) _selectDates(prepared);
    moreRecipesExpanded = false;
    buildError = null;
    notifyListeners();
  }

  void chooseOrganization(String? code) {
    if (code == null || busy) return;
    selectedOrganizationCode = code;
    final prepared = scan;
    if (prepared != null) _selectDates(prepared);
    buildError = null;
    notifyListeners();
  }

  void choosePreviousDate(DateTime? date) {
    if (date == null || busy) return;
    previousAsOf = date;
    buildError = null;
    notifyListeners();
  }

  void toggleOrganization(String code) {
    if (busy) return;
    final next = Set<String>.of(selectedOrganizationCodes);
    if (!next.remove(code)) next.add(code);
    if (next.isEmpty) return;
    selectedOrganizationCodes = next;
    buildError = null;
    notifyListeners();
  }

  void chooseCve(String value) {
    cveId = value.trim().toUpperCase();
    buildError = null;
    notifyListeners();
  }

  void chooseLanguage(OpenKatReportLanguage value) {
    language = value;
    notifyListeners();
  }

  void setTitle(String value) {
    reportTitle = value;
    notifyListeners();
  }

  void toggleMoreSettings() {
    moreSettingsExpanded = !moreSettingsExpanded;
    notifyListeners();
  }

  void toggleMoreRecipes() {
    moreRecipesExpanded = !moreRecipesExpanded;
    notifyListeners();
  }

  void changeUpdateChoices() {
    updateConfirmationVisible = false;
    notifyListeners();
  }

  void next() {
    if (!canContinue || busy) return;
    step = switch (step) {
      OpenKatWizardStep.scenario when !hasPrimaryInputs =>
        OpenKatWizardStep.review,
      OpenKatWizardStep.scenario => OpenKatWizardStep.inputs,
      OpenKatWizardStep.inputs => OpenKatWizardStep.review,
      OpenKatWizardStep.review => OpenKatWizardStep.review,
    };
    notifyListeners();
  }

  void back() {
    if (busy) return;
    step = switch (step) {
      OpenKatWizardStep.review when !hasPrimaryInputs =>
        OpenKatWizardStep.scenario,
      OpenKatWizardStep.review => OpenKatWizardStep.inputs,
      OpenKatWizardStep.inputs => OpenKatWizardStep.scenario,
      OpenKatWizardStep.scenario => OpenKatWizardStep.scenario,
    };
    notifyListeners();
  }

  Future<OpenKatWizardBuildResult?> build({bool asNew = false}) async {
    if (buildStatus == OpenKatWizardBuildStatus.building) return null;
    final prepared = scan;
    final request = recipe;
    if (scanStatus != OpenKatWizardScanStatus.ready ||
        prepared == null ||
        request == null ||
        !canContinue) {
      return null;
    }
    buildStatus = OpenKatWizardBuildStatus.building;
    buildError = null;
    notifyListeners();
    // Gun Flutter één frame om de voortgangsindicator te schilderen.
    await Future<void>.delayed(Duration.zero);
    try {
      final built = gateway.build(
        prepared,
        request,
        existing: asNew ? null : existingDeck,
      );
      if (!built.report.generated) {
        throw OpenKatWizardBuildException(built.report.diagnostics);
      }
      result = built;
      buildStatus = OpenKatWizardBuildStatus.succeeded;
      notifyListeners();
      return built;
    } catch (error, stack) {
      buildStatus = OpenKatWizardBuildStatus.failed;
      buildError = error;
      _logFailure(
        'OpenKatWizardController.build: generate report',
        error,
        stack,
      );
      notifyListeners();
      return null;
    }
  }
}

class OpenKatWizardBuildException implements Exception {
  final List<OpenKatReportDiagnostic> diagnostics;

  const OpenKatWizardBuildException(this.diagnostics);
}
