// De zichtbare vergelijking van de definitieve pass (#2511, contract §3.1).
//
// Een latere modelrun die afwijkt van wat er staat mag nooit stil
// overschrijven — de afwijking kan een handmatige correctie zijn. Dit
// venster legt beide teksten naast elkaar en laat de keuze aan de
// auteur: toepassen of de eigen tekst behouden. `null` terug (verbroken
// venster) telt als behouden — twijfel vernietigt geen tekst.
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// `true` = de binnenkomende tekst toepassen; `false` of `null` = de
/// huidige tekst behouden.
Future<bool?> showTranscriptApplyDialog(
  BuildContext context, {
  required String current,
  required String incoming,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        _TranscriptApplyDialog(current: current, incoming: incoming),
  );
}

class _TranscriptApplyDialog extends StatelessWidget {
  const _TranscriptApplyDialog({required this.current, required this.incoming});

  final String current;
  final String incoming;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Nieuwe transcripttekst')),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'De tekst in het document is handmatig aangepast. Kies welke tekst bewaard blijft; de andere gaat verloren.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pane(context, l10n.d('Huidige tekst'), current),
                  const SizedBox(width: 12),
                  _pane(context, l10n.d('Nieuwe tekst'), incoming),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Huidige tekst behouden')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Nieuwe tekst toepassen')),
        ),
      ],
    );
  }

  Widget _pane(BuildContext context, String label, String text) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.iceBlue),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                text.trim().isEmpty ? '—' : text.trim(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
