import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/findings_summary_spec.dart';
import '../../services/management_summary.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';

/// Shows the deck's **management summary** (PENTEST_MIAUW §10.3): findings per
/// severity band, the scope-coverage totals and the standards used — all derived
/// live from the deck. The [summary] is computed at the (tab-scoped) call site
/// and passed in, so this dialog stays a plain [StatelessWidget].
class ManagementSummaryDialog extends StatelessWidget {
  const ManagementSummaryDialog({super.key, required this.summary});

  final ManagementSummary summary;

  static Future<void> show(BuildContext context, ManagementSummary summary) =>
      showDialog<void>(
        context: context,
        builder: (_) => ManagementSummaryDialog(summary: summary),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Managementsamenvatting')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${l10n.d('Bevindingen totaal')}: ${summary.findingCount}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final band in FindingsSummarySpec.order)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: FindingSeverityPalette.of(band),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.d(findingsSeverityDutchLabel(band))),
                    ),
                    Text(
                      '${summary.severities.countOf(band)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Text(
              '${summary.scopeTestedCount} / ${summary.scopeObjectCount} '
              '${l10n.d('scope-objecten getest')}',
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${l10n.d('Gebruikte standaarden')}: ',
                    style: TextStyle(color: AppTheme.slate500),
                  ),
                  TextSpan(
                    text: summary.standards.isEmpty
                        ? '—'
                        : summary.standards.join(', '),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }
}
