// De integratiekaart voor AI-assistentie op het tabblad Integraties (#2184).
//
// AI is een koppeling met een backend — lokaal, zelf gehost of cloud — en
// hoort daarom tussen OpenKAT en eLearning, niet als eigen tabblad in de
// zijbalk. De configuratie schrijft bij Opslaan weg via [AiForm], dus de
// schakelaar werkt op de formulierstand en niet rechtstreeks op de
// voorkeuren; [onEnabledChanged] komt uit het venster.
//
// Net als de andere kaarten hier kan deze schakelaar alleen úít (#2185):
// aanzetten hoort bij de modulekaart op Uitbreidingen.
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/module_registry.dart';
import '../../../theme/app_theme.dart';
import 'ai_form.dart';
import 'ai_module_card.dart';
import 'card_titles.dart';
import 'module_card.dart';

/// De AI-kaart op Integraties: schakelaar (alleen uit), de module-uit-melding
/// wanneer hij uit staat, en de backend-configuratie zodra die er is.
class AiIntegrationCard extends StatelessWidget {
  const AiIntegrationCard({
    super.key,
    required this.form,
    required this.onEnabledChanged,
    required this.config,
  });

  /// De invulstand van het venster — niet de opgeslagen instelling.
  final AiForm form;

  /// Zet het formulierveld `enabled` om; alleen aangeroepen bij uitzetten.
  final ValueChanged<bool> onEnabledChanged;

  /// De backend-configuratievelden, gebouwd door het venster
  /// (`_aiConfigSection`): modus, server, model, sleutel en de testknop.
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
            value: !web && form.enabled,
            onChanged: web || !form.enabled ? null : onEnabledChanged,
            title: Text(
              moduleCardTitle(ModuleId.ai, l10n),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'AI-assistentie is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'AI-assistentie is optioneel en staat standaard uit. Er wordt niets verstuurd totdat je dit inschakelt en zelf een backend kiest. Deze functie werkt alleen op de desktopversie.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.auto_awesome_outlined),
          ),
          if (!web && !form.enabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: AiModuleOffNotice(),
            ),
          // De configuratie blijft zichtbaar met de module uit, zolang er een
          // backend staat (#648): de schakelaar maakt bestaand werk nooit
          // onbereikbaar.
          if (!web && form.revealsConfig)
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
