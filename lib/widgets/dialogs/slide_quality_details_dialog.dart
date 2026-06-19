import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide_quality.dart';

/// Shows slide quality issues grouped by severity with counts per group.
Future<void> showSlideQualityDetailsDialog(
  BuildContext context, {
  required SlideQualityResult result,
  void Function(SlideQualityIssue issue)? onIssueTap,
}) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(l10n.d('Kwaliteitsoverzicht')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatSlideQualityCountSummary(l10n, result),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 14),
                for (final severity in MarkdownValidationSeverity.values)
                  if (result.issuesWithSeverity(severity).isNotEmpty)
                    _SeveritySection(
                      l10n: l10n,
                      severity: severity,
                      issues: result.issuesWithSeverity(severity).toList(),
                      onIssueTap: onIssueTap,
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('close')),
          ),
        ],
      );
    },
  );
}

class _SeveritySection extends StatelessWidget {
  final AppLocalizations l10n;
  final MarkdownValidationSeverity severity;
  final List<SlideQualityIssue> issues;
  final void Function(SlideQualityIssue issue)? onIssueTap;

  const _SeveritySection({
    required this.l10n,
    required this.severity,
    required this.issues,
    this.onIssueTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = slideQualitySeverityColor(severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(slideQualitySeverityIcon(severity), size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                '${slideQualitySeverityLabel(l10n, severity)} (${issues.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: onIssueTap == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        onIssueTap!(issue);
                      },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    issue.isDeckWide
                        ? '${l10n.d('Thema (hele presentatie)')}: '
                              '${formatSlideQualityIssue(l10n, issue)}'
                        : '${l10n.d('Slide')} ${issue.slideIndex + 1} · '
                              '${slideQualityCategoryLabel(l10n, issue.category)}: '
                              '${formatSlideQualityIssue(l10n, issue)}',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
