import '../../../l10n/app_localizations.dart';
import '../../../models/openkat/openkat_reporting_models.dart';
import '../../../models/openkat/openkat_wizard_models.dart';

typedef LocalizedOpenKatText = String Function(AppLocalizations l10n);

final Map<OpenKatReportFamilyId, LocalizedOpenKatText>
openKatFamilyTitleRegistry = {
  OpenKatReportFamilyId.organizationsManagement: (l10n) =>
      l10n.d('Welke organisaties vragen aandacht?'),
  OpenKatReportFamilyId.organizationProgress: (l10n) =>
      l10n.d('Wat veranderde er bij één organisatie?'),
  OpenKatReportFamilyId.cves: (l10n) => l10n.d('Wie is geraakt door een CVE?'),
  OpenKatReportFamilyId.dataQuality: (l10n) =>
      l10n.d('Zijn de metingen compleet en actueel?'),
};

final Map<OpenKatReportFamilyId, LocalizedOpenKatText>
openKatFamilyDescriptionRegistry = {
  OpenKatReportFamilyId.organizationsManagement: (l10n) => l10n.d(
    'Vergelijk organisaties en breng portfolio-aandachtspunten in beeld.',
  ),
  OpenKatReportFamilyId.organizationProgress: (l10n) => l10n.d(
    'Bekijk de actuele stand of aantoonbare veranderingen bij één organisatie.',
  ),
  OpenKatReportFamilyId.cves: (l10n) =>
      l10n.d('Onderzoek betrouwbare CVE-koppelingen in de gekozen metingen.'),
  OpenKatReportFamilyId.dataQuality: (l10n) => l10n.d(
    'Leg vast welke metingen en bronbestanden het rapport werkelijk gebruikt.',
  ),
};

String openKatFamilyTitle(AppLocalizations l10n, OpenKatReportFamilyId id) =>
    openKatFamilyTitleRegistry[id]!(l10n);

String openKatFamilyDescription(
  AppLocalizations l10n,
  OpenKatReportFamilyId id,
) => openKatFamilyDescriptionRegistry[id]!(l10n);

final Map<OpenKatWizardScenarioId, LocalizedOpenKatText>
openKatScenarioTitleRegistry = {
  OpenKatWizardScenarioId.portfolio: (l10n) =>
      l10n.d('Wat is het managementbeeld over de gekozen organisaties?'),
  OpenKatWizardScenarioId.organizationComparison: (l10n) =>
      l10n.d('Waar worden de meeste en minste findings waargenomen?'),
  OpenKatWizardScenarioId.portfolioTrend: (l10n) =>
      l10n.d('Hoe ontwikkelt het portfolio zich over de tijd?'),
  OpenKatWizardScenarioId.findingTypePrevalence: (l10n) =>
      l10n.d('Welke problemen komen bij de meeste organisaties voor?'),
  OpenKatWizardScenarioId.severityConcentration: (l10n) =>
      l10n.d('Waar concentreren de ernstigste findings zich?'),
  OpenKatWizardScenarioId.controlCoverage: (l10n) =>
      l10n.d('Welke controls lopen achter?'),
  OpenKatWizardScenarioId.recommendations: (l10n) =>
      l10n.d('Welke maatregelen adviseert OpenKAT het vaakst?'),
  OpenKatWizardScenarioId.organizationOverview: (l10n) =>
      l10n.d('Hoe staat deze organisatie er nu voor?'),
  OpenKatWizardScenarioId.organizationProgress: (l10n) =>
      l10n.d('Wat veranderde er sinds de vorige meting?'),
  OpenKatWizardScenarioId.findingLifecycle: (l10n) =>
      l10n.d('Welke findings zijn nieuw of niet meer waargenomen?'),
  OpenKatWizardScenarioId.findingAge: (l10n) =>
      l10n.d('Welke findings staan het langst open?'),
  OpenKatWizardScenarioId.systemHotspots: (l10n) =>
      l10n.d('Op welke systemen worden de meeste findings waargenomen?'),
  OpenKatWizardScenarioId.systemChanges: (l10n) =>
      l10n.d('Welke systemen verbeterden of verslechterden?'),
  OpenKatWizardScenarioId.controlChanges: (l10n) =>
      l10n.d('Welke controls verbeterden of verslechterden?'),
  OpenKatWizardScenarioId.assetInventory: (l10n) =>
      l10n.d('Welke systemen zijn in de metingen opgenomen?'),
  OpenKatWizardScenarioId.monitoringCoverage: (l10n) =>
      l10n.d('Welke assets zijn aantoonbaar in monitoring?'),
  OpenKatWizardScenarioId.monitoringChanges: (l10n) =>
      l10n.d('Welke monitoringstatussen veranderden?'),
  OpenKatWizardScenarioId.cveExposure: (l10n) =>
      l10n.d('Wie is geraakt door deze CVE?'),
  OpenKatWizardScenarioId.cveLandscape: (l10n) =>
      l10n.d('Welke CVE’s raken de meeste organisaties?'),
  OpenKatWizardScenarioId.cveChanges: (l10n) =>
      l10n.d('Welke CVE’s zijn nieuw of niet meer waargenomen?'),
  OpenKatWizardScenarioId.dataQuality: (l10n) =>
      l10n.d('Welke meetgegevens ontbreken of zijn verouderd?'),
  OpenKatWizardScenarioId.measurementAccountability: (l10n) =>
      l10n.d('Op welke gegevens is dit rapport gebaseerd?'),
};

String openKatScenarioTitle(
  AppLocalizations l10n,
  OpenKatWizardScenarioId id,
) => openKatScenarioTitleRegistry[id]!(l10n);

final Map<OpenKatWizardScenarioId, LocalizedOpenKatText>
openKatScenarioDescriptionRegistry = {
  OpenKatWizardScenarioId.portfolio: (l10n) => l10n.d(
    'Vat de huidige stand, gebruikte metingen en belangrijkste aandachtspunten samen.',
  ),
  OpenKatWizardScenarioId.organizationComparison: (l10n) => l10n.d(
    'Laat zien waar de meeste en minste findings zijn gevonden; ontbrekende metingen staan apart.',
  ),
  OpenKatWizardScenarioId.portfolioTrend: (l10n) => l10n.d(
    'Laat zien hoe aantallen findings veranderden en welke organisaties daaraan bijdroegen.',
  ),
  OpenKatWizardScenarioId.findingTypePrevalence: (l10n) => l10n.d(
    'Laat zien welke soorten problemen bij de meeste organisaties en systemen voorkomen.',
  ),
  OpenKatWizardScenarioId.severityConcentration: (l10n) => l10n.d(
    'Laat per organisatie zien hoeveel findings critical of high zijn.',
  ),
  OpenKatWizardScenarioId.controlCoverage: (l10n) => l10n.d(
    'Laat per control zien welk deel voldoet, maar alleen als het totaal bekend is.',
  ),
  OpenKatWizardScenarioId.recommendations: (l10n) => l10n.d(
    'Bundelt de aanbevelingen uit OpenKAT zonder er zelf prioriteit aan te geven.',
  ),
  OpenKatWizardScenarioId.organizationOverview: (l10n) => l10n.d(
    'Een gericht actueel beeld van één organisatie en haar meetdatum.',
  ),
  OpenKatWizardScenarioId.organizationProgress: (l10n) =>
      l10n.d('Vergelijkt twee gekozen meetmomenten binnen één organisatie.'),
  OpenKatWizardScenarioId.findingLifecycle: (l10n) =>
      l10n.d('Laat zien welke findings nieuw, terug of niet meer gezien zijn.'),
  OpenKatWizardScenarioId.findingAge: (l10n) => l10n.d(
    'Laat zien welke findings het langst openstaan als de begindatum bekend is.',
  ),
  OpenKatWizardScenarioId.systemHotspots: (l10n) => l10n.d(
    'Laat zien op welke systemen de meeste en ernstigste findings staan.',
  ),
  OpenKatWizardScenarioId.systemChanges: (l10n) =>
      l10n.d('Laat per systeem zien of het aantal findings steeg of daalde.'),
  OpenKatWizardScenarioId.controlChanges: (l10n) => l10n.d(
    'Vergelijkt controls alleen als beide metingen dezelfde reikwijdte hebben.',
  ),
  OpenKatWizardScenarioId.assetInventory: (l10n) => l10n.d(
    'Geeft de systemen, hostnamen en IP-adressen uit de gekozen meting weer.',
  ),
  OpenKatWizardScenarioId.monitoringCoverage: (l10n) =>
      l10n.d('Scheidt gemonitord, niet gemonitord en onbekend.'),
  OpenKatWizardScenarioId.monitoringChanges: (l10n) =>
      l10n.d('Laat alleen monitoringveranderingen zien die de bron bewijst.'),
  OpenKatWizardScenarioId.cveExposure: (l10n) => l10n.d(
    'Laat zien bij welke organisaties en systemen deze CVE is aangetroffen.',
  ),
  OpenKatWizardScenarioId.cveLandscape: (l10n) => l10n.d(
    'Laat zien welke CVE’s bij de meeste organisaties en systemen voorkomen.',
  ),
  OpenKatWizardScenarioId.cveChanges: (l10n) =>
      l10n.d('Laat zien welke CVE’s nieuw, terug of niet meer gezien zijn.'),
  OpenKatWizardScenarioId.dataQuality: (l10n) =>
      l10n.d('Toont ontbrekende, verouderde en werkelijk gebruikte metingen.'),
  OpenKatWizardScenarioId.measurementAccountability: (l10n) => l10n.d(
    'Toont de gebruikte meetdatums, bronbestanden en technische bronkenmerken.',
  ),
};

String openKatScenarioDescription(
  AppLocalizations l10n,
  OpenKatWizardScenarioId id,
) => openKatScenarioDescriptionRegistry[id]!(l10n);

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
  OpenKatWizardUnavailableReason.noReliableMonitoringStatus => l10n.d(
    'Nog niet beschikbaar: de bron bewijst geen monitoringstatus voor alle assets.',
  ),
  OpenKatWizardUnavailableReason.noReliableOpenedAt => l10n.d(
    'Nog niet beschikbaar: niet iedere finding heeft een betrouwbare eerste waarnemingsdatum.',
  ),
  OpenKatWizardUnavailableReason.noStableFindingIdentity => l10n.d(
    'Nog niet beschikbaar: de bron bewijst geen stabiele identiteit voor alle findings.',
  ),
  OpenKatWizardUnavailableReason.noComparableCoverage => l10n.d(
    'Nog niet beschikbaar: vergelijkbare meetdekking is niet aangetoond.',
  ),
  OpenKatWizardUnavailableReason.noControlDenominators => l10n.d(
    'Nog niet beschikbaar: betrouwbare controlnoemers ontbreken.',
  ),
  OpenKatWizardUnavailableReason.noStableAssetIdentity => l10n.d(
    'Nog niet beschikbaar: stabiele assetidentiteit is niet aangetoond.',
  ),
  OpenKatWizardUnavailableReason.unsupportedScope => l10n.d(
    'Dit rapport ondersteunt de gekozen organisatiescope niet.',
  ),
  OpenKatWizardUnavailableReason.missingRequiredData => l10n.d(
    'De gekozen bron bevat niet genoeg betrouwbare gegevens voor dit rapport.',
  ),
};

final Map<OpenKatReportBlockKind, LocalizedOpenKatText>
openKatBlockTitleRegistry = {
  OpenKatReportBlockKind.managementOverview: (l10n) =>
      l10n.d('Kerncijfers en aandachtspunten'),
  OpenKatReportBlockKind.portfolioSummary: (l10n) =>
      l10n.d('Kerncijfers en gemeten bereik'),
  OpenKatReportBlockKind.organizationComparison: (l10n) =>
      l10n.d('Organisaties vergelijken'),
  OpenKatReportBlockKind.severityConcentration: (l10n) =>
      l10n.d('Concentratie van critical/high findings'),
  OpenKatReportBlockKind.portfolioTrend: (l10n) =>
      l10n.d('Portfolioverloop per meetmoment'),
  OpenKatReportBlockKind.findingTypePrevalence: (l10n) =>
      l10n.d('Meest voorkomende findingtypen'),
  OpenKatReportBlockKind.measurementAvailability: (l10n) =>
      l10n.d('Dekking en actualiteit van metingen'),
  OpenKatReportBlockKind.measurementAccountability: (l10n) =>
      l10n.d('Bron- en meetverantwoording'),
  OpenKatReportBlockKind.findingLifecycle: (l10n) =>
      l10n.d('Nieuwe en niet meer waargenomen findings'),
  OpenKatReportBlockKind.findingAge: (l10n) =>
      l10n.d('Langst waargenomen findings'),
  OpenKatReportBlockKind.systemHotspots: (l10n) =>
      l10n.d('Systemen met de meeste findings'),
  OpenKatReportBlockKind.systemChanges: (l10n) =>
      l10n.d('Veranderingen per systeem'),
  OpenKatReportBlockKind.cveExposure: (l10n) =>
      l10n.d('Blootstelling aan één CVE'),
  OpenKatReportBlockKind.cveLandscape: (l10n) =>
      l10n.d('CVE’s over organisaties'),
  OpenKatReportBlockKind.cveChanges: (l10n) =>
      l10n.d('Nieuwe en niet meer waargenomen CVE’s'),
  OpenKatReportBlockKind.controlCoverage: (l10n) => l10n.d('Controldekking'),
  OpenKatReportBlockKind.controlChanges: (l10n) =>
      l10n.d('Controlveranderingen'),
  OpenKatReportBlockKind.recommendations: (l10n) =>
      l10n.d('Aanbevelingen uit OpenKAT'),
  OpenKatReportBlockKind.assetInventory: (l10n) => l10n.d('Assetinventaris'),
  OpenKatReportBlockKind.monitoringCoverage: (l10n) =>
      l10n.d('Monitoringdekking'),
  OpenKatReportBlockKind.monitoringChanges: (l10n) =>
      l10n.d('Veranderingen in monitoring'),
  OpenKatReportBlockKind.organizationOverview: (l10n) =>
      l10n.d('Actueel organisatiebeeld'),
};

String openKatBlockTitle(AppLocalizations l10n, OpenKatReportBlockKind kind) =>
    openKatBlockTitleRegistry[kind]!(l10n);

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
