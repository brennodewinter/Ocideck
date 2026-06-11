import '../models/deck.dart';

/// Uitkomst van de export-gate: mag deze export door, en zo niet, waarom niet.
class ExportDecision {
  /// Of de export is toegestaan.
  final bool allowed;

  /// Reden waarom de export geweigerd is (`null` wanneer toegestaan). Bedoeld om
  /// 1-op-1 aan de gebruiker te tonen.
  final String? reason;

  const ExportDecision._(this.allowed, this.reason);

  const ExportDecision.allow() : this._(true, null);
  const ExportDecision.block(String reason) : this._(false, reason);
}

/// Centrale, pure beslisser voor classificatie bij export.
///
/// Classificeren is **optioneel**: een deck zonder TLP-niveau ([TlpLevel.none])
/// exporteert altijd. Maar zodra een organisatie een vrijgaveplafond instelt, is
/// dit de enige plek die bepaalt of een geclassificeerd deck naar buiten mag.
///
/// De gate hangt aan het export-chokepoint ([ExportService.export]), zodat geen
/// enkel formaat (PDF/PPTX/HTML) eromheen kan. Fail-closed: bij twijfel weigert
/// de gate in plaats van stilletjes te exporteren.
class ClassificationPolicy {
  /// Hoogste TLP-niveau dat geëxporteerd mag worden — het vrijgaveplafond.
  ///
  /// `null` = geen plafond, alles mag (standaard). Een deck dat híérboven is
  /// geclassificeerd wordt geweigerd in plaats van naar buiten gebracht. Let op:
  /// een plafond van [TlpLevel.none] staat alléén ongeclassificeerde decks toe.
  final TlpLevel? maxReleaseLevel;

  const ClassificationPolicy({this.maxReleaseLevel});

  /// Bouw het beleid uit de opgeslagen instelling: een TLP-sleutel (zie
  /// [TlpLevelX.key]) of `null` wanneer er geen plafond is ingesteld.
  factory ClassificationPolicy.fromKey(String? key) => ClassificationPolicy(
    maxReleaseLevel: key == null ? null : TlpLevelX.fromKey(key),
  );

  /// Of er überhaupt een gate actief is.
  bool get hasGate => maxReleaseLevel != null;

  /// Beoordeel of een deck met niveau [deckLevel] geëxporteerd mag worden.
  ExportDecision evaluate(TlpLevel deckLevel) {
    final ceiling = maxReleaseLevel;
    if (ceiling != null && deckLevel.index > ceiling.index) {
      return ExportDecision.block(
        'Export geblokkeerd door classificatiebeleid: dit deck is '
        '${deckLevel.label}, hoger dan het toegestane vrijgaveniveau '
        '${ceiling.label}.',
      );
    }
    return const ExportDecision.allow();
  }
}
