import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// De toestemmingsvraag van de postMessage-browserkoppeling (#2827).
///
/// Een externe website die OciDeck insluit kan een Markdown-tekst
/// aanbieden. Zonder expliciete "Openen" verandert er niets — dezelfde
/// lijn als [ProxyFallbackDialog]: een vertrouwensgrens vraagt om een
/// mens, niet om een automatisme. Het antwoord naar de site bevat alleen
/// de uitkomst, nooit inhoud.
class MarkdownTransferConsentDialog extends StatelessWidget {
  const MarkdownTransferConsentDialog({
    super.key,
    required this.origin,
    this.name,
  });

  /// De origin van de aanbiedende website — de kern van de vraag.
  final String origin;

  /// De voorgestelde bestandsnaam, als de site die meestuurde.
  final String? name;

  static Future<bool> show(
    BuildContext context, {
    required String origin,
    String? name,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => MarkdownTransferConsentDialog(origin: origin, name: name),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      icon: const Icon(Icons.open_in_new_outlined),
      title: Text(l10n.d('Website wil Markdown openen?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n
                .d(
                  'De website {origin} wil een Markdown-tekst in OciDeck openen.',
                )
                .replaceAll('{origin}', origin),
          ),
          if (name != null && name!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.d('Voorgestelde naam: {name}').replaceAll('{name}', name!),
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.d(
              'De tekst wordt geopend alsof je hem zelf had geplakt. De website krijgt alleen te horen of het openen lukte — nooit de inhoud.',
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.d('Weigeren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.d('Openen')),
        ),
      ],
    );
  }
}
