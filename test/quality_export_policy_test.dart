import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/quality_export_policy.dart';

void main() {
  group('QualityExportPolicy', () {
    test('allows export when disabled even with issues', () {
      const policy = QualityExportPolicy(enabled: false);
      const result = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.missingAltCaption,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.warning,
        ),
      ]);

      expect(policy.evaluate(result).allowed, isTrue);
    });

    test('allows export when there are no issues', () {
      const policy = QualityExportPolicy();
      expect(policy.evaluate(const SlideQualityResult([])).allowed, isTrue);
    });

    test('requires acknowledgement when enabled and issues exist', () {
      const policy = QualityExportPolicy();
      const result = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.missingAltCaption,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.warning,
        ),
      ]);

      final pending = policy.evaluate(result);
      expect(pending.allowed, isFalse);
      expect(pending.warningCount, 1);
      expect(pending.reason, contains('kwaliteitsproblemen'));

      expect(policy.evaluate(result, acknowledged: true).allowed, isTrue);
    });
  });
}
