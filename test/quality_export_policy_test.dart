import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_localization.dart';
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
          severity: MarkdownValidationSeverity.informational,
        ),
      ]);

      expect(policy.evaluate(result).allowed, isTrue);
    });

    test('allows export when there are no issues', () {
      const policy = QualityExportPolicy();
      expect(policy.evaluate(const SlideQualityResult([])).allowed, isTrue);
    });

    test('allows export when only informational tips exist', () {
      const policy = QualityExportPolicy();
      const result = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.missingAltCaption,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.informational,
        ),
      ]);

      expect(policy.evaluate(result).allowed, isTrue);
    });

    test('requires acknowledgement when enabled and warnings exist', () {
      const policy = QualityExportPolicy();
      const result = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.imageContrastUnverified,
          category: SlideQualityCategory.contrast,
          severity: MarkdownValidationSeverity.warning,
        ),
      ]);

      final pending = policy.evaluate(result);
      expect(pending.allowed, isFalse);
      expect(pending.warningCount, 1);
      expect(pending.canAcknowledge, isTrue);
      expect(pending.hardBlocked, isFalse);

      expect(policy.evaluate(result, acknowledged: true).allowed, isTrue);
    });

    test('hard blocks export when blockOnErrors and errors exist', () {
      const policy = QualityExportPolicy(blockOnErrors: true);
      const result = SlideQualityResult([
        SlideQualityIssue(
          slideIndex: 0,
          kind: SlideQualityIssueKind.textDensityCritical,
          category: SlideQualityCategory.textDensity,
          severity: MarkdownValidationSeverity.error,
        ),
      ]);

      final pending = policy.evaluate(result);
      expect(pending.allowed, isFalse);
      expect(pending.hardBlocked, isTrue);
      expect(pending.canAcknowledge, isFalse);
      expect(policy.evaluate(result, acknowledged: true).allowed, isFalse);
    });
  });

  test('formatQualityExportReason is localized', () {
    const result = SlideQualityResult([
      SlideQualityIssue(
        slideIndex: 0,
        kind: SlideQualityIssueKind.imageContrastUnverified,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
      ),
    ]);
    final dutch = formatQualityExportReason(
      const AppLocalizations(Locale('nl')),
      result,
    );
    AppLocalizations.setActiveLanguageCode('en');
    final english = formatQualityExportReason(
      const AppLocalizations(Locale('en')),
      result,
    );
    expect(dutch, contains('kwaliteitsproblemen'));
    expect(english, contains('quality issues'));
    AppLocalizations.setActiveLanguageCode('nl');
  });
}
