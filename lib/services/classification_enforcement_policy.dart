import '../models/deck.dart';
import '../models/settings.dart';
import 'classification_policy.dart';

/// Centrale beslisser voor classificatie-handhaving bij export (Variant A).
///
/// Breidt het bestaande vrijgaveplafond uit met een optioneel **minimumniveau**
/// en een vlag om ongeclassificeerde decks te weigeren. Evaluatie blijft puur
/// Evaluatie blijft puur en fail-closed — de gate hangt aan [ExportService.export].
class ClassificationEnforcementPolicy {
  /// Hoogste TLP-niveau dat geëxporteerd mag worden (vrijgaveplafond).
  final TlpLevel? maxReleaseLevel;

  /// Laagste vereiste deck-classificatie; alles eronder wordt geweigerd.
  final TlpLevel? minRequiredLevel;

  /// Wanneer `true`, mag een deck zonder classificatie ([TlpLevel.none]) niet
  /// exporteren, ook als [minRequiredLevel] niet is ingesteld.
  final bool requireClassification;

  const ClassificationEnforcementPolicy({
    this.maxReleaseLevel,
    this.minRequiredLevel,
    this.requireClassification = false,
  });

  /// Alleen het plafond — backward compatible met [ClassificationPolicy].
  factory ClassificationEnforcementPolicy.fromMaxReleaseKey(String? key) =>
      ClassificationEnforcementPolicy(
        maxReleaseLevel: key == null ? null : TlpLevelX.fromKey(key),
      );

  /// Volledig beleid uit app-instellingen.
  factory ClassificationEnforcementPolicy.fromAppSettings(
    AppSettings settings,
  ) {
    return ClassificationEnforcementPolicy(
      maxReleaseLevel: settings.maxReleaseExportTlpKey == null
          ? null
          : TlpLevelX.fromKey(settings.maxReleaseExportTlpKey!),
      minRequiredLevel: settings.minRequiredExportTlpKey == null
          ? null
          : TlpLevelX.fromKey(settings.minRequiredExportTlpKey!),
      requireClassification: settings.requireClassificationOnExport,
    );
  }

  /// Of er minstens één handhavingsregel actief is.
  bool get hasGate =>
      maxReleaseLevel != null ||
      minRequiredLevel != null ||
      requireClassification;

  /// Beoordeel of een deck met niveau [deckLevel] geëxporteerd mag worden.
  ExportDecision evaluate(TlpLevel deckLevel) {
    // Een reden terug, geen zin. Zie [ExportBlockReason]: proza dat een niveau
    // interpoleert is per definitie onvertaalbaar, en de schil weet wél in
    // welke taal de gebruiker leest.
    if (requireClassification && deckLevel == TlpLevel.none) {
      return const ExportDecision.block(
        ExportBlockReason.classificationMissing,
      );
    }

    final floor = minRequiredLevel;
    if (floor != null && deckLevel.index < floor.index) {
      return ExportDecision.block(
        ExportBlockReason.belowMinimum,
        deckLevel: deckLevel,
        limit: floor,
      );
    }

    final ceiling = maxReleaseLevel;
    if (ceiling != null && deckLevel.index > ceiling.index) {
      return ExportDecision.block(
        ExportBlockReason.aboveCeiling,
        deckLevel: deckLevel,
        limit: ceiling,
      );
    }

    return const ExportDecision.allow();
  }

  /// Het plafond als losse [ClassificationPolicy] (bestaande export-call sites).
  ClassificationPolicy get releasePolicy =>
      ClassificationPolicy(maxReleaseLevel: maxReleaseLevel);
}
