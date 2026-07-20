import '../models/slide_quality.dart';

/// Result of the export quality gate: may export proceed without extra steps?
class QualityExportDecision {
  /// Whether [ExportService] may write the file now.
  final bool allowed;

  final int errorCount;
  final int warningCount;

  /// When false, export cannot proceed even with user acknowledgement
  /// ([QualityExportPolicy.blockOnErrors] and [errorCount] > 0).
  final bool canAcknowledge;

  const QualityExportDecision._({
    required this.allowed,
    this.errorCount = 0,
    this.warningCount = 0,
    this.canAcknowledge = true,
  });

  const QualityExportDecision.allow() : this._(allowed: true);

  factory QualityExportDecision.needsAcknowledgement({
    required int errorCount,
    required int warningCount,
    bool canAcknowledge = true,
  }) => QualityExportDecision._(
    allowed: false,
    errorCount: errorCount,
    warningCount: warningCount,
    canAcknowledge: canAcknowledge,
  );

  bool get hardBlocked => !allowed && !canAcknowledge;
}

/// Soft export gate for slide quality issues — warns by default, never blocks
/// once the user explicitly acknowledges (see [evaluate]), unless
/// [blockOnErrors] is enabled.
class QualityExportPolicy {
  /// When false, quality issues are ignored at export time.
  final bool enabled;

  /// When true, [MarkdownValidationSeverity.error] issues block export entirely.
  final bool blockOnErrors;

  const QualityExportPolicy({this.enabled = true, this.blockOnErrors = false});

  factory QualityExportPolicy.fromAppSettings({
    required bool warningsEnabled,
    required bool blockOnErrors,
  }) => QualityExportPolicy(
    enabled: warningsEnabled,
    blockOnErrors: blockOnErrors,
  );

  factory QualityExportPolicy.fromEnabled(bool enabled) =>
      QualityExportPolicy(enabled: enabled);

  bool get isActive => enabled;

  QualityExportDecision evaluate(
    SlideQualityResult result, {
    bool acknowledged = false,
  }) {
    // De harde blokkade staat vóór [enabled]. Het zijn twee losse schakelaars
    // in de instellingen, en de bovenste gaat alleen over het bevestigingsvenster
    // ("vraag bevestiging"). Toen de blokkade daaronder hing, zette het
    // wegklikken van die vraag ook de blokkade uit — terwijl de tekst eronder
    // belooft dat export niet mogelijk is zolang er fouten staan.
    if (blockOnErrors && result.errorCount > 0) {
      return QualityExportDecision.needsAcknowledgement(
        errorCount: result.errorCount,
        warningCount: result.warningCount,
        canAcknowledge: false,
      );
    }
    if (!enabled || !result.hasActionableIssues) {
      return const QualityExportDecision.allow();
    }
    if (acknowledged) {
      return const QualityExportDecision.allow();
    }
    return QualityExportDecision.needsAcknowledgement(
      errorCount: result.errorCount,
      warningCount: result.warningCount,
    );
  }
}
