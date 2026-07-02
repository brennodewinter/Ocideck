import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/markdown_safety.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';

/// The "alarm screen" shown when an imported/opened deck is refused because it
/// contains executable content. It is a hard stop: the deck was NOT opened, and
/// the user only acknowledges. The findings are listed verbatim so a curious
/// user can see exactly what was rejected.
class ImportSecurityAlarmDialog {
  ImportSecurityAlarmDialog._();

  static const _alarmRed = Color(0xFFB91C1C);
  static const _alarmBg = Color(0xFFFEE2E2);

  static Future<void> show(BuildContext context, ImportSecurityAlarm alarm) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: _alarmBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.gpp_bad_outlined,
              color: _alarmRed,
              size: 30,
            ),
          ),
          title: Text(
            l10n.d('Onveilige presentatie geblokkeerd'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _alarmRed,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.d(
                      'Deze presentatie is niet geopend. Het bestand bevat inhoud die code kan uitvoeren, en een presentatie hoort alleen gegevens te bevatten — niets uitvoerbaars.',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.d('Gevonden:'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppTheme.slate500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final f in alarm.findings)
                    _FindingRow(l10n: l10n, finding: f),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _alarmRed),
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.t('close')),
            ),
          ],
        );
      },
    );
  }

  static String threatLabel(AppLocalizations l10n, MarkdownThreat kind) {
    switch (kind) {
      case MarkdownThreat.scriptExecution:
        return l10n.d('Scriptuitvoering');
      case MarkdownThreat.embeddedContent:
        return l10n.d('Ingesloten inhoud');
      case MarkdownThreat.unsafeUrl:
        return l10n.d('Onveilige URL');
    }
  }
}

class _FindingRow extends StatelessWidget {
  final AppLocalizations l10n;
  final MarkdownSafetyFinding finding;

  const _FindingRow({required this.l10n, required this.finding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: ImportSecurityAlarmDialog._alarmRed,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${ImportSecurityAlarmDialog.threatLabel(l10n, finding.kind)}'
                  ' · ${l10n.d('Regel')} ${finding.line}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: SelectableText(
              finding.evidence,
              maxLines: 3,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppTheme.slate600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
