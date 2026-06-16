import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide_quality.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/editor_provider.dart';

class SlideQualityPanel extends ConsumerStatefulWidget {
  const SlideQualityPanel({super.key});

  @override
  ConsumerState<SlideQualityPanel> createState() => _SlideQualityPanelState();
}

class _SlideQualityPanelState extends ConsumerState<SlideQualityPanel> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = ref.watch(deckQualityProvider);
    final hasErrors = result.errorCount > 0;
    final color = !result.hasIssues
        ? const Color(0xFFECFDF5)
        : hasErrors
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFFEF3C7);
    final iconColor = !result.hasIssues
        ? const Color(0xFF047857)
        : hasErrors
        ? Colors.red.shade700
        : const Color(0xFF92400E);

    final summary = result.hasIssues
        ? '${result.errorCount} ${l10n.d('fout(en),')} '
              '${result.warningCount} ${l10n.d('waarschuwing(en)')}'
        : l10n.d('Geen kwaliteitsproblemen gevonden');

    return Material(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: result.hasIssues ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    result.hasIssues
                        ? Icons.accessibility_new_outlined
                        : Icons.check_circle_outline,
                    size: 14,
                    color: iconColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l10n.d('Slidekwaliteit')}: $summary',
                      style: TextStyle(fontSize: 11, color: iconColor),
                    ),
                  ),
                  if (result.hasIssues)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: iconColor,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && result.hasIssues)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: result.issues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final issue = result.issues[index];
                  return _QualityIssueTile(
                    issue: issue,
                    onTap: issue.isDeckWide
                        ? null
                        : () {
                            ref
                                .read(editorProvider.notifier)
                                .select(issue.slideIndex);
                          },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _QualityIssueTile extends StatelessWidget {
  final SlideQualityIssue issue;
  final VoidCallback? onTap;

  const _QualityIssueTile({required this.issue, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isError = issue.severity == MarkdownValidationSeverity.error;
    final color = isError ? Colors.red.shade700 : const Color(0xFF92400E);
    final location = issue.isDeckWide
        ? l10n.d('Thema (hele presentatie)')
        : '${l10n.d('Slide')} ${issue.slideIndex + 1}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$location · ${slideQualityCategoryLabel(l10n, issue.category)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    formatSlideQualityIssue(l10n, issue),
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.arrow_forward, size: 12, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
