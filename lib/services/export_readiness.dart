import 'classification_policy.dart';
import 'privacy/privacy_export_policy.dart';
import 'quality_export_policy.dart';

/// De ene, samengevatte exportstatus voor de gebruiker. De losse gates
/// (opslaan, classificatie, privacy, kwaliteit) bestaan al; dit vouwt ze tot één
/// duidelijke melding — "Klaar voor export", "Nog opslaan nodig",
/// "TLP blokkeert export", "Privacy blokkeert export" — zodat de laatste stap
/// niet verrast.
enum ExportReadinessStatus {
  /// Alle gates staan open; exporteren kan direct.
  ready,

  /// Alle gates staan open, maar de privacycontrole stond uit — er is dus niet
  /// naar persoonsgegevens gekeken. Exporteren kan direct; alleen de
  /// geruststelling ontbreekt.
  readyPrivacyUnchecked,

  /// Er zijn kwaliteitswaarschuwingen; exporteren kan, na bevestiging.
  qualityWarnings,

  /// Er staan privacybevindingen open waarover de auteur nog geen keuze heeft
  /// gemaakt; exporteren kan, na bevestiging.
  privacyWarnings,

  /// Het deck moet eerst (opnieuw) opgeslagen worden.
  needsSave,

  /// Het classificatiebeleid (TLP) weigert deze export.
  blockedByClassification,

  /// De privacy-gate weigert deze export (gate op "blokkeren", en er staan nog
  /// zekere bevindingen open).
  blockedByPrivacy,

  /// Kwaliteitsfouten blokkeren de export hard (niet te bevestigen).
  blockedByQuality,
}

/// Uitkomst van [evaluateExportReadiness]: status plus de tellingen en de
/// blokkeringsreden die de UI nodig heeft om de melding op te bouwen.
class ExportReadiness {
  final ExportReadinessStatus status;

  /// Aantal kwaliteitsfouten resp. -waarschuwingen (0 buiten de
  /// kwaliteitsstatussen).
  final int errorCount;
  final int warningCount;

  /// Reden van het classificatiebeleid bij [blockedByClassification].
  final String? blockReason;

  /// Aantal privacybevindingen zonder keuze (0 buiten de privacystatussen).
  final int privacyUnresolved;

  const ExportReadiness(
    this.status, {
    this.errorCount = 0,
    this.warningCount = 0,
    this.blockReason,
    this.privacyUnresolved = 0,
  });

  /// Of de exportknop iets zinnigs kan doen (dialoog openen). Alleen bij
  /// "nog opslaan nodig" is er niets te openen: het bestand bestaat nog niet
  /// (of is verouderd) en exports horen naast het deck-bestand te liggen.
  bool get canOpenExport => status != ExportReadinessStatus.needsSave;
}

/// Vouw de bestaande export-gates samen tot één status, in de volgorde waarin
/// de gebruiker ze tegenkomt: eerst opslaan, dan de harde blokkades
/// (classificatie, privacy, kwaliteit), dan wat te bevestigen valt.
///
/// De privacy-gate hoorde hier vanaf het begin bij en ontbrak. Het gevolg was de
/// ergst denkbare vorm van stilte: een deck vol onafgehandelde persoonsgegevens,
/// met een privacy-gate op "blokkeren", toonde in de statusbalk een groen "Klaar
/// voor export". De gate wérkte — hij sloeg pas toe in de exportdialoog — maar
/// tot dat moment beloofde de balk het tegenovergestelde.
///
/// Privacy gaat vóór kwaliteit als beide iets te melden hebben: een IBAN die de
/// deur uit gaat is van een andere orde dan een bullet te veel.
///
/// [privacyChecksEnabled] is de instelling, niet de uitslag. Staat de controle
/// uit, dan levert de scanner een lege uitslag en zijn "niets gevonden" en "niet
/// gekeken" van buitenaf niet meer te onderscheiden — waarna de balk een groen
/// "Klaar voor export" toonde op grond van een controle die nooit gedraaid heeft.
/// Dat is de gevaarlijkste stand van alle: de gebruiker deelt op een
/// geruststelling die niemand heeft gegeven.
ExportReadiness evaluateExportReadiness({
  required bool needsSave,
  required ExportDecision classificationDecision,
  required QualityExportDecision qualityDecision,
  PrivacyExportDecision privacyDecision = const PrivacyExportDecision.allow(),
  bool privacyChecksEnabled = true,
}) {
  if (needsSave) {
    return const ExportReadiness(ExportReadinessStatus.needsSave);
  }
  if (!classificationDecision.allowed) {
    return ExportReadiness(
      ExportReadinessStatus.blockedByClassification,
      blockReason: classificationDecision.reason,
    );
  }
  if (privacyDecision.hardBlocked) {
    return ExportReadiness(
      ExportReadinessStatus.blockedByPrivacy,
      privacyUnresolved: privacyDecision.summary.unresolved,
    );
  }
  if (qualityDecision.hardBlocked) {
    return ExportReadiness(
      ExportReadinessStatus.blockedByQuality,
      errorCount: qualityDecision.errorCount,
      warningCount: qualityDecision.warningCount,
    );
  }
  if (!privacyDecision.allowed) {
    return ExportReadiness(
      ExportReadinessStatus.privacyWarnings,
      privacyUnresolved: privacyDecision.summary.unresolved,
    );
  }
  if (!qualityDecision.allowed) {
    return ExportReadiness(
      ExportReadinessStatus.qualityWarnings,
      errorCount: qualityDecision.errorCount,
      warningCount: qualityDecision.warningCount,
    );
  }
  return ExportReadiness(
    privacyChecksEnabled
        ? ExportReadinessStatus.ready
        : ExportReadinessStatus.readyPrivacyUnchecked,
  );
}
