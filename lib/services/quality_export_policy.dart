import '../models/slide_quality.dart';

/// Result of the export quality gate: may export proceed without extra steps?
class QualityExportDecision {
  /// Whether [ExportService] may write the file now.
  final bool allowed;

  /// Human-readable reason when [allowed] is false (acknowledgement required).
  final String? reason;

  final int errorCount;
  final int warningCount;

  const QualityExportDecision._({
    required this.allowed,
    this.reason,
    this.errorCount = 0,
    this.warningCount = 0,
  });

  const QualityExportDecision.allow() : this._(allowed: true);

  factory QualityExportDecision.needsAcknowledgement({
    required int errorCount,
    required int warningCount,
    required String reason,
  }) => QualityExportDecision._(
    allowed: false,
    reason: reason,
    errorCount: errorCount,
    warningCount: warningCount,
  );
}

/// Soft export gate for slide quality issues — warns by default, never blocks
/// once the user explicitly acknowledges (see [evaluate]).
class QualityExportPolicy {
  /// When false, quality issues are ignored at export time.
  final bool enabled;

  const QualityExportPolicy({this.enabled = true});

  factory QualityExportPolicy.fromEnabled(bool enabled) =>
      QualityExportPolicy(enabled: enabled);

  bool get isActive => enabled;

  QualityExportDecision evaluate(
    SlideQualityResult result, {
    bool acknowledged = false,
  }) {
    if (!enabled || !result.hasActionableIssues || acknowledged) {
      return const QualityExportDecision.allow();
    }
    return QualityExportDecision.needsAcknowledgement(
      errorCount: result.errorCount,
      warningCount: result.warningCount,
      reason: _buildReason(result),
    );
  }

  String _buildReason(SlideQualityResult result) {
    final parts = <String>[];
    if (result.errorCount > 0) {
      parts.add('${result.errorCount} ernstige probleem(en)');
    }
    if (result.warningCount > 0) {
      parts.add('${result.warningCount} waarschuwing(en)');
    }
    return 'De presentatie heeft kwaliteitsproblemen (${parts.join(', ')}).';
  }
}
