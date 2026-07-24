import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';

/// De voorkeursleutel: eenmaal weggeklikt met "niet meer tonen" blijft de
/// waarschuwing weg. Nooit hernoemen.
const _dismissedKey = 'presentationImportWarningDismissed';

/// Toont vóór een presentatie-import de eenmalige waarschuwing dat de conversie
/// best-effort is en geen één-op-één-kopie (#772). Geeft `true` als de import
/// mag doorgaan.
///
/// Glashelder zijn is hier de bedoeling: OciDeck heeft een bewust eenvoudiger
/// diamodel dan PowerPoint, dus er gáát iets verloren, en de gebruiker hoort
/// dat te weten vóór hij begint — niet het achteraf te ontdekken. De tip over
/// een aparte map hoort erbij: geïmporteerd materiaal verschilt in kwaliteit
/// van eigen werk, en apart houden voorkomt verrassingen.
Future<bool> showPresentationImportWarning(BuildContext context) async {
  if (await _dismissed()) return true;
  if (!context.mounted) return false;

  var dontShowAgain = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.d('Presentatie importeren')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d(
                    'Importeren is best-effort en geen één-op-één-kopie: OciDeck heeft een eenvoudiger diamodel dan PowerPoint. Wat niet past, komt op een “niet overgenomen”-notitie te staan; controleer het resultaat na afloop.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.d(
                    'Tip: bewaar geïmporteerde presentaties in een aparte map. De kwaliteit verschilt per bron, en zo blijft geïmporteerd materiaal gescheiden van uw eigen werk.',
                  ),
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: dontShowAgain,
                  onChanged: (v) => setState(() => dontShowAgain = v ?? false),
                  title: Text(l10n.d('Niet meer tonen')),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.d('Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.d('Importeren')),
            ),
          ],
        ),
      );
    },
  );

  if (result != true) return false;
  if (dontShowAgain) await _setDismissed();
  return true;
}

Future<bool> _dismissed() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissedKey) ?? false;
  } catch (e, s) {
    // Onleesbare voorkeuren: toon de waarschuwing dan liever wél (de veilige
    // kant), maar laat de import niet hangen.
    logError('showPresentationImportWarning: read dismissed', e, s);
    return false;
  }
}

Future<void> _setDismissed() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  } catch (e, s) {
    logError('showPresentationImportWarning: persist dismissed', e, s);
  }
}
