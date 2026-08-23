import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide_quality.dart';
import '../panels/slide_quality_actions.dart';
import '../../theme/app_theme.dart';

/// Shows slide quality issues grouped by severity with counts per group.
/// [actionsFor] supplies the assistant's quick-fix buttons per issue
/// ("Splits slide", "Verhoog contrast", "Voeg alt-tekst toe", …); running
/// an action closes the dialog first so the result is visible.
Future<void> showSlideQualityDetailsDialog(
  BuildContext context, {
  required SlideQualityResult result,
  void Function(SlideQualityIssue issue)? onIssueTap,
  List<SlideQualityAction> Function(SlideQualityIssue issue)? actionsFor,
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
                  style: TextStyle(fontSize: 13, color: AppTheme.slate700),
                ),
                const SizedBox(height: 14),
                for (final severity in MarkdownValidationSeverity.values)
                  if (result.issuesWithSeverity(severity).isNotEmpty)
                    _SeveritySection(
                      l10n: l10n,
                      severity: severity,
                      issues: result.issuesWithSeverity(severity).toList(),
                      onIssueTap: onIssueTap,
                      actionsFor: actionsFor,
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
  final List<SlideQualityAction> Function(SlideQualityIssue issue)? actionsFor;

  const _SeveritySection({
    required this.l10n,
    required this.severity,
    required this.issues,
    this.onIssueTap,
    this.actionsFor,
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
              Flexible(
                child: Text(
                  '${slideQualitySeverityLabel(l10n, severity)} (${issues.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  for (final action
                      in actionsFor?.call(issue) ??
                          const <SlideQualityAction>[])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          action.run();
                        },
                        icon: Icon(action.icon, size: 14),
                        label: Text(action.label),
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
