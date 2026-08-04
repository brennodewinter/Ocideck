import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor de LibrePlan-connector op het tabblad Uitbreidingen
/// (#1240). Spiegelt [AiModuleCard]: optioneel, standaard uit, met een
/// netwerkuitgang die je bewust aanzet.
///
/// **De schakelaar zet het formulierveld om, niet de opgeslagen instelling.**
/// Het LibrePlan-tabblad schrijft zijn hele formulier bij Opslaan weg,
/// inclusief `enabled`; zou deze kaart rechtstreeks naar de voorkeuren
/// schrijven, dan draaide die Opslaan het weer terug. Eén schakelaar, één
/// opslagpad — vandaar dat [enabled] en [onChanged] hier binnenkomen in plaats
/// van een provider.
///
/// Desktop-only: op web is de keychain niet veilig (sleutel en ciphertext in
/// dezelfde localStorage), dus de kaart is zichtbaar maar uitgeschakeld, met
/// dezelfde melding die het AI-tabblad op web toont.
class LibreplanModuleCard extends StatelessWidget {
  const LibreplanModuleCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// De formulierstand, niet de voorkeur op schijf.
  final bool enabled;

  /// Wordt op web genegeerd: daar is de kaart zichtbaar maar uitgeschakeld.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final web = isWebPlatform;
    return Material(
      color: AppTheme.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: !web && enabled,
            onChanged: web ? null : onChanged,
            title: Text(
              l10n.d('LibrePlan-connector'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'De LibrePlan-connector is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'Importeer een projectsnapshot van een LibrePlan-instantie als slides: Gantt, WBS, resourcebelasting, timesheet en meer. Alleen-lezen, op verzoek — er gaat niets naar buiten tot u een server configureert en een import start.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.cloud_download_outlined),
          ),
          if (!web && enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                l10n.d(
                  'Configureer de server op het tabblad LibrePlan-connector. Zolang daar niets staat, gebeurt er niets.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }
}
