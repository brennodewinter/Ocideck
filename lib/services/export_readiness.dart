import 'classification_policy.dart';
import 'quality_export_policy.dart';

/// De ene, samengevatte exportstatus voor de gebruiker. De losse gates
/// (opslaan, classificatie, kwaliteit) bestaan al; dit vouwt ze tot één
/// duidelijke melding — "Klaar voor export", "Nog opslaan nodig",
/// "TLP blokkeert export" — zodat de laatste stap niet verrast.
enum ExportReadinessStatus {
  /// Alle gates staan open; exporteren kan direct.
  ready,

  /// Er zijn kwaliteitswaarschuwingen; exporteren kan, na bevestiging.
  qualityWarnings,

  /// Het deck moet eerst (opnieuw) opgeslagen worden.
  needsSave,

  /// Het classificatiebeleid (TLP) weigert deze export.
  blockedByClassification,

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

  const ExportReadiness(
    this.status, {
    this.errorCount = 0,
    this.warningCount = 0,
    this.blockReason,
  });

  /// Of de exportknop iets zinnigs kan doen (dialoog openen). Alleen bij
  /// "nog opslaan nodig" is er niets te openen: het bestand bestaat nog niet
  /// (of is verouderd) en exports horen naast het deck-bestand te liggen.
  bool get canOpenExport => status != ExportReadinessStatus.needsSave;
}

/// Vouw de bestaande export-gates samen tot één status, in de volgorde
/// waarin de gebruiker ze tegenkomt: eerst opslaan, dan het
/// classificatiebeleid (hard), dan kwaliteit (hard of te bevestigen).
ExportReadiness evaluateExportReadiness({
  required bool needsSave,
  required ExportDecision classificationDecision,
  required QualityExportDecision qualityDecision,
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
  if (qualityDecision.hardBlocked) {
    return ExportReadiness(
      ExportReadinessStatus.blockedByQuality,
      errorCount: qualityDecision.errorCount,
      warningCount: qualityDecision.warningCount,
    );
  }
  if (!qualityDecision.allowed) {
    return ExportReadiness(
      ExportReadinessStatus.qualityWarnings,
      errorCount: qualityDecision.errorCount,
      warningCount: qualityDecision.warningCount,
    );
  }
  return const ExportReadiness(ExportReadinessStatus.ready);
}
