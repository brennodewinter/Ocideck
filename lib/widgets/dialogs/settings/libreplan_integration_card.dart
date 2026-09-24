// De integratiekaart voor de LibrePlan-connector op Integraties (#2184).
//
// De connector leest projectdata uit een LibrePlan-server en is daarmee een
// integratie, geen eigen tabblad. De configuratie schrijft bij Opslaan weg
// via het vensterformulier, dus [enabled] en [onEnabledChanged] komen uit
// die formulierstand en niet uit de voorkeuren — precies zoals de kaart op
// Uitbreidingen hem ook schakelt.
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/module_registry.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'module_card.dart';

/// De LibrePlan-kaart op Integraties: schakelaar (alleen uit, #2185) en de
/// connectorconfiguratie.
class LibreplanIntegrationCard extends StatelessWidget {
  const LibreplanIntegrationCard({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.config,
  });

  /// De formulierstand van de connector-schakelaar.
  final bool enabled;

  /// Zet het formulierveld om; alleen aangeroepen bij uitzetten.
  final ValueChanged<bool> onEnabledChanged;

  /// De configuratievelden, gebouwd door het venster (`_libreplanForm`):
  /// server, gebruiker, wachtwoord, vertrouwde-server en de testknop.
  final List<Widget> config;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final web = isWebPlatform;
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: !web && enabled,
            onChanged: web || !enabled ? null : onEnabledChanged,
            title: Text(
              moduleCardTitle(ModuleId.libreplan, l10n),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'De LibrePlan-connector is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'LibrePlan-connector is optioneel en staat standaard uit. Er wordt niets opgehaald totdat u dit inschakelt en zelf een server configureert. Alleen-lezen: de connector schrijft niets terug naar LibrePlan. Het wachtwoord wordt in de sleutelhanger van uw besturingssysteem opgeslagen, niet in het deck.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.cloud_download_outlined),
          ),
          if (!web && !enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                l10n.d(
                  'Deze koppeling staat uit. Zet hem aan bij Uitbreidingen.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
          // Anders dan de registerkaarten blijft dit formulier óók zichtbaar
          // als de connector uit staat: dat was zo op het eigen tabblad, en
          // verhuizen mag geen ingesteld werk onbereikbaar maken.
          if (!web)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: config,
              ),
            ),
        ],
      ),
    );
  }
}
