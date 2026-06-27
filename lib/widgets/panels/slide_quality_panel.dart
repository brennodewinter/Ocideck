import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../l10n/slide_quality_navigation.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide_quality.dart';
import '../../state/deck_provider.dart';
import '../../state/deck_quality_provider.dart';
import '../../state/image_contrast_provider.dart';
import '../../utils/title_contrast.dart';
import '../dialogs/slide_quality_details_dialog.dart';

class SlideQualityPanel extends ConsumerStatefulWidget {
  const SlideQualityPanel({super.key});

  @override
  ConsumerState<SlideQualityPanel> createState() => _SlideQualityPanelState();
}

class _SlideQualityPanelState extends ConsumerState<SlideQualityPanel> {
  var _expanded = false;
  MarkdownValidationSeverity? _severityFilter;

  void _handleIssueTap(SlideQualityIssue issue) {
    navigateToSlideQualityIssue(context: context, ref: ref, issue: issue);
  }

  /// Applies the recommended contrast fix carried in the issue's args to the
  /// slide, then re-analyses (the providers rebuild automatically).
  void _handleFix(SlideQualityIssue issue) {
    final fix = TitleContrastFix.values.firstWhere(
      (f) => f.name == issue.args['fix'],
      orElse: () => TitleContrastFix.none,
    );
    if (fix == TitleContrastFix.none) return;
    final deck = ref.read(deckProvider).deck;
    if (deck == null ||
        issue.slideIndex < 0 ||
        issue.slideIndex >= deck.slides.length) {
      return;
    }
    final slide = deck.slides[issue.slideIndex];
    ref
        .read(deckProvider.notifier)
        .updateSlide(issue.slideIndex, applyTitleContrastFix(slide, fix));
  }

  List<SlideQualityIssue> _filteredIssues(SlideQualityResult result) {
    if (_severityFilter == null) return result.issues;
    return result.issues
        .where((issue) => issue.severity == _severityFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final syncResult = ref.watch(deckQualityProvider);
    // Image-contrast checks decode the background asynchronously; fold their
    // findings into the same result so counts, summary and dialog include them.
    // Use `.value` (not `.asData?.value`): it retains the previous result while
    // the autoDispose FutureProvider reloads on each deck edit, so the contrast
    // warnings don't blink away on every keystroke.
    final imageIssues =
        ref.watch(imageContrastIssuesProvider).value ?? const [];
    final result = imageIssues.isEmpty
        ? syncResult
        : SlideQualityResult([...syncResult.issues, ...imageIssues]);
    final visibleIssues = _filteredIssues(result);
    final hasErrors = result.errorCount > 0;
    final hasWarnings = result.warningCount > 0;
    final color = !result.hasIssues
        ? const Color(0xFFECFDF5)
        : hasErrors
        ? const Color(0xFFFEE2E2)
        : hasWarnings
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFEFF6FF);
    final iconColor = !result.hasIssues
        ? const Color(0xFF047857)
        : hasErrors
        ? Colors.red.shade700
        : hasWarnings
        ? const Color(0xFF92400E)
        : const Color(0xFF475569);

    final summary = formatSlideQualityCountSummary(l10n, result);

    return Material(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
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
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: iconColor,
                  ),
                ],
              ),
            ),
          ),
          if (!result.hasIssues && _expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.d('Uitgevoerde controles')}:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  for (final check in slideQualityPerformedChecks(l10n))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check, size: 12, color: iconColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  check.title,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: iconColor,
                                  ),
                                ),
                                Text(
                                  check.detail,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: iconColor.withValues(alpha: 0.85),
                                  ),
                                ),
                                Text(
                                  check.params,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: iconColor.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (result.hasIssues) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showSlideQualityDetailsDialog(
                    context,
                    result: result,
                    onIssueTap: _handleIssueTap,
                    onFix: _handleFix,
                  ),
                  icon: const Icon(Icons.list_alt_outlined, size: 13),
                  label: Text(l10n.d('Bekijk meldingen…')),
                  style: TextButton.styleFrom(
                    foregroundColor: iconColor,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
          if (_expanded && result.hasIssues) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: Text(l10n.d('Alle meldingen')),
                    selected: _severityFilter == null,
                    onSelected: (_) => setState(() => _severityFilter = null),
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 10),
                  ),
                  for (final severity in MarkdownValidationSeverity.values)
                    if (result.issuesWithSeverity(severity).isNotEmpty)
                      FilterChip(
                        label: Text(
                          '${slideQualitySeverityLabel(l10n, severity)} '
                          '(${result.issuesWithSeverity(severity).length})',
                        ),
                        selected: _severityFilter == severity,
                        onSelected: (selected) => setState(
                          () => _severityFilter = selected ? severity : null,
                        ),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(fontSize: 10),
                      ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: visibleIssues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final issue = visibleIssues[index];
                  return _QualityIssueTile(
                    issue: issue,
                    onTap: () => _handleIssueTap(issue),
                    showThemeHint: issue.isDeckWide,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QualityIssueTile extends StatelessWidget {
  final SlideQualityIssue issue;
  final VoidCallback? onTap;
  final bool showThemeHint;

  const _QualityIssueTile({
    required this.issue,
    this.onTap,
    this.showThemeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = slideQualitySeverityColor(issue.severity);
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
              slideQualitySeverityIcon(issue.severity),
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
              Icon(
                showThemeHint ? Icons.palette_outlined : Icons.arrow_forward,
                size: 12,
                color: color.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}
