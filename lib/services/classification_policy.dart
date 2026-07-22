import '../models/deck.dart';

/// Uitkomst van de export-gate: mag deze export door, en zo niet, waarom niet.
/// Waaróm een export geweigerd is.
///
/// Een reden en geen zin. De dienst bouwde hier tot 2026-07-22 kant-en-klaar
/// Nederlands proza, en dat kón niet vertaald worden: de vertaallaag sleutelt op
/// letterlijke brontekst, en een zin die een niveau interpoleert heeft geen
/// letterlijke vorm om op te sleutelen. Dat trof precies de verkeerde
/// categorie — dit zijn de meldingen die je tegenhouden (#576).
enum ExportBlockReason {
  /// Het beleid eist een classificatie en het deck heeft er geen.
  classificationMissing,

  /// Het deck zit onder het vereiste minimum.
  belowMinimum,

  /// Het deck zit boven het toegestane vrijgaveniveau.
  aboveCeiling,
}

class ExportDecision {
  /// Of de export is toegestaan.
  final bool allowed;

  /// Waarom er geweigerd is (`null` wanneer toegestaan).
  final ExportBlockReason? reason;

  /// Het niveau van het deck, voor de melding. Null bij [allow].
  final TlpLevel? deckLevel;

  /// De grens waar het deck tegenaan liep — het vereiste minimum of het
  /// toegestane plafond, afhankelijk van [reason].
  final TlpLevel? limit;

  const ExportDecision._(this.allowed, this.reason, this.deckLevel, this.limit);

  const ExportDecision.allow() : this._(true, null, null, null);

  const ExportDecision.block(
    ExportBlockReason reason, {
    TlpLevel? deckLevel,
    TlpLevel? limit,
  }) : this._(false, reason, deckLevel, limit);
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
        ExportBlockReason.aboveCeiling,
        deckLevel: deckLevel,
        limit: ceiling,
      );
    }
    return const ExportDecision.allow();
  }
}
