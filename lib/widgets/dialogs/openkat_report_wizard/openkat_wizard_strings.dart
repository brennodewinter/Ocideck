import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_reporting_models.dart';
import '../../../models/openkat/openkat_wizard_models.dart';

String openKatScenarioTitle(
  AppLocalizations l10n,
  OpenKatWizardScenarioId id,
) => switch (id) {
  OpenKatWizardScenarioId.portfolio => l10n.d(
    'Welke organisaties vragen aandacht?',
  ),
  OpenKatWizardScenarioId.organizationProgress => l10n.d(
    'Wat veranderde er bij één organisatie?',
  ),
  OpenKatWizardScenarioId.cveExposure => l10n.d('Wie is geraakt door een CVE?'),
  OpenKatWizardScenarioId.dataQuality => l10n.d(
    'Zijn de metingen compleet en actueel?',
  ),
};

String openKatScenarioDescription(
  AppLocalizations l10n,
  OpenKatWizardScenarioId id,
) => switch (id) {
  OpenKatWizardScenarioId.portfolio => l10n.d(
    'Management- en stuurinformatie over meerdere organisaties.',
  ),
  OpenKatWizardScenarioId.organizationProgress => l10n.d(
    'Voortgang ten opzichte van een eerder meetmoment.',
  ),
  OpenKatWizardScenarioId.cveExposure => l10n.d(
    'Getroffen organisaties en systemen rond één kwetsbaarheid.',
  ),
  OpenKatWizardScenarioId.dataQuality => l10n.d(
    'Datakwaliteit, ontbrekende metingen en veroudering.',
  ),
};

String openKatUnavailableReason(
  AppLocalizations l10n,
  OpenKatWizardUnavailableReason reason,
) => switch (reason) {
  OpenKatWizardUnavailableReason.noUsableMeasurements => l10n.d(
    'Er zijn geen bruikbare metingen gevonden.',
  ),
  OpenKatWizardUnavailableReason.oneMeasurement => l10n.d(
    'Voor een vergelijking zijn twee meetmomenten nodig. Er is nu één meting gevonden.',
  ),
  OpenKatWizardUnavailableReason.noReliableCveReferences => l10n.d(
    'Nog niet beschikbaar: deze rapportages bevatten geen betrouwbare CVE-nummers.',
  ),
};

String openKatBlockTitle(AppLocalizations l10n, OpenKatReportBlockKind kind) =>
    switch (kind) {
      OpenKatReportBlockKind.managementOverview => l10n.d(
        'Kerncijfers en aandachtspunten',
      ),
      OpenKatReportBlockKind.measurementAvailability => l10n.d(
        'Dekking en actualiteit van metingen',
      ),
      OpenKatReportBlockKind.findingLifecycle => l10n.d(
        'Nieuwe en verdwenen bevindingen',
      ),
      OpenKatReportBlockKind.cveExposure => l10n.d(
        'Getroffen organisaties en systemen',
      ),
      OpenKatReportBlockKind.monitoringChanges => l10n.d(
        'Veranderingen in monitoring',
      ),
    };

String openKatDiagnosticText(
  AppLocalizations l10n,
  OpenKatReportDiagnostic diagnostic,
) {
  final base = switch (diagnostic.code) {
    OpenKatReportDiagnosticCode.currentSnapshotMissing => l10n.d(
      'Voor een of meer organisaties ontbreekt een bruikbare huidige meting.',
    ),
    OpenKatReportDiagnosticCode.previousSnapshotMissing => l10n.d(
      'Voor een of meer organisaties ontbreekt een bruikbare eerdere meting.',
    ),
    OpenKatReportDiagnosticCode.incompletePortfolio => l10n.d(
      'Niet iedere gekozen organisatie heeft een meting voor deze periode.',
    ),
    OpenKatReportDiagnosticCode.incomparableMeasurementCoverage => l10n.d(
      'De meetdekking verschilt tussen de gekozen meetmomenten; veranderingen zijn daardoor beperkt vergelijkbaar.',
    ),
    OpenKatReportDiagnosticCode.snapshotTooOld => l10n.d(
      'Een of meer metingen zijn ouder dan de gekozen actualiteitsgrens.',
    ),
    OpenKatReportDiagnosticCode.invalidCveId => l10n.d(
      'Kies een CVE die in de rapportages is aangetroffen.',
    ),
    OpenKatReportDiagnosticCode.missingCapability => l10n.d(
      'De gekozen rapportages bevatten niet genoeg betrouwbare gegevens voor dit onderdeel.',
    ),
    OpenKatReportDiagnosticCode.resourceLimitExceeded => l10n.d(
      'Deze selectie bevat te veel gegevens om veilig in één rapport te verwerken.',
    ),
    _ => l10n.d(
      'Dit onderdeel kan niet volledig uit de gekozen rapportages worden opgebouwd.',
    ),
  };
  final arguments = diagnostic.arguments;
  if (diagnostic.code == OpenKatReportDiagnosticCode.incompletePortfolio) {
    final organizations = arguments['missingOrganizations']
        ?.split(',')
        .where((item) => item.isNotEmpty)
        .join(', ');
    if (organizations != null && organizations.isNotEmpty) {
      return '$base (${l10n.d('Organisaties')}: $organizations)';
    }
  }
  if (diagnostic.code == OpenKatReportDiagnosticCode.snapshotTooOld) {
    final organization = arguments['organizationCode'];
    final age = arguments['ageDays'];
    final maximum = arguments['maximumAgeDays'];
    if (organization != null && age != null && maximum != null) {
      return '$base ($organization: $age ${l10n.d('dagen')} > '
          '$maximum ${l10n.d('dagen')})';
    }
  }
  return base;
}
