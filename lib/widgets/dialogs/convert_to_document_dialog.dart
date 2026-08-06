import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// De bevestigingsdialoog vóór presentatie → document (DOCUMENT_MODE.md §11.3).
///
/// Geruststelling boven waarschuwing: we maken een **kopie** in een nieuw
/// tabblad, de originele presentatie blijft ongewijzigd. Wél expliciet de
/// drop-lijst — een deck deconstrueert naar getypeerde dia's, een document is
/// verbatim tekst, dus dia-structuur, `_class`, thema en het **zegel** reizen
/// niet mee. Het zegel reist NOOIT mee: een verzegeld kopie zou een valse
/// integriteitsclaim zijn.
class ConvertToDocumentDialog extends StatelessWidget {
  const ConvertToDocumentDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (_) => const ConvertToDocumentDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Naar document converteren?')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'We maken een kopie in een nieuw tabblad; je originele bestand blijft ongewijzigd.',
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.d('Wat gaat er verloren bij het converteren:'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            const SizedBox(height: 6),
            _drop(
              l10n.d(
                'De indeling in dia\'s (de tekst loopt door als één document).',
              ),
            ),
            _drop(l10n.d('Het thema en de opmaak per dia (_class).')),
            _drop(
              l10n.d(
                'Het zegel: een geconverteerd bestand is nieuw en draagt geen zegel.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.d('Converteren')),
        ),
      ],
    );
  }

  Widget _drop(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.arrow_right, size: 16, color: AppTheme.slate400),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
