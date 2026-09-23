import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/markdown_validation.dart';
import '../../models/marp_compatibility.dart';
import '../../theme/app_theme.dart';

/// Bevestiging vóór het opslaan van een deck dat Marp niet correct kan
/// weergeven (rode status). Alleen harde fouten komen hier aan de beurt —
/// aandachtspunten slaan zonder vraag op, want daarvoor bestaat de
/// deckbrede acceptatievlag.
///
/// Geeft `true` bij "Toch opslaan", `false` bij "Terug" of sluiten.
Future<bool> confirmMarpIncompatibleSave(
  BuildContext context,
  MarpCompatReport report,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _MarpIncompatibleDialog(report: report),
  );
  return result ?? false;
}

class _MarpIncompatibleDialog extends StatelessWidget {
  final MarpCompatReport report;

  const _MarpIncompatibleDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errors = report.findings
        .where((f) => f.severity == MarkdownValidationSeverity.error)
        .toList();
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.d('Niet Marp-compatibel'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Dit bestand kan Marp niet goed weergeven. In Marp of een andere tool opent het niet zoals bedoeld — controleer de bevindingen of sla toch op.',
              ),
            ),
            const SizedBox(height: 12),
            // De fouten zelf, met regelnummer, zodat "Terug" meteen naar de
            // bron kan — meer dan drie wordt een muur van tekst.
            for (final issue in errors.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.d('Regel')} ${issue.line}',
                      style: TextStyle(fontSize: 12, color: AppTheme.slate400),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (errors.length > 3)
              Text(
                '+${errors.length - 3} ${l10n.d('meer — zie de compatibiliteitsbalk in de markdown-modus')}',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.d('Terug')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.d('Toch opslaan')),
        ),
      ],
    );
  }
}
