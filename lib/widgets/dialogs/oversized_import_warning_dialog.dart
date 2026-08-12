import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/import/utils/archive_utils.dart';
import '../../theme/app_theme.dart';

/// Toont een waarschuwing vóór het importeren van een presentatie die groter
/// is dan de aanbevolen limiet ([limit] bytes). Geeft `true` als de gebruiker
/// er expliciet voor kiest om toch te importeren.
///
/// De 512 MiB-limiet uit [ImportBudget.standard] is een *zachte* grens: een
/// legitiem grote presentatie mag er niet op stuklopen, mits de gebruiker
/// begrijpt wat hij kiest. De harde grenzen (uitgepakt totaal, aantal
/// archiefonderdelen) blijven gehandhaafd — die beschermen tegen een zip-bom,
/// en daar mag geen bevestiging overheen.
///
/// Geen "niet meer tonen": deze waarschuwing hoort bij elk bestand dat de
/// grens haalt, want de gevolgen (traag, geheugen) verschillen per apparaat
/// en per bestand. Een vinkje zou de volgende keer dat iemand een groot
/// bestand kiest stilletjes wegblijven — precies dan wanneer het wél telt.
Future<bool> showOversizedImportWarning(
  BuildContext context, {
  required int fileSize,
  required int limit,
}) async {
  final sizeLabel = humanBytes(fileSize);
  final limitLabel = humanBytes(limit);

  String fill(String template) => template
      .replaceAll('{grootte}', sizeLabel)
      .replaceAll('{limiet}', limitLabel);

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_outlined, color: AppTheme.dangerFg),
            const SizedBox(width: 8),
            Flexible(child: Text(l10n.d('Groot bestand'))),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(
            fill(
              l10n.d(
                'Dit bestand is {grootte} groot. Dat is meer dan de aanbevolen limiet van {limiet}. Importeren kan traag zijn en veel geheugen vragen — op een kleiner apparaat kan de app vastlopen.',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.d('Toch importeren')),
          ),
        ],
      );
    },
  );
  return result == true;
}
