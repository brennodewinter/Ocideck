import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor AI-assistentie op het tabblad Uitbreidingen (#731).
///
/// AI is optioneel, staat standaard uit en heeft een netwerkuitgang die je
/// bewust aanzet — precies de belofte die dat tabblad bovenaan doet. Als vast
/// tabblad in de zijbalk suggereerde het een vaste functie.
///
/// **De schakelaar zet het formulierveld om, niet de opgeslagen instelling.**
/// Het AI-tabblad schrijft zijn hele formulier bij Opslaan weg, inclusief
/// `enabled`; zou deze kaart rechtstreeks naar de voorkeuren schrijven, dan
/// draaide die Opslaan het weer terug. Eén schakelaar, één opslagpad — vandaar
/// dat [enabled] en [onChanged] hier binnenkomen in plaats van een provider.
///
/// Een eigen widget en geen methode op het instellingenvenster: die klasse zit
/// tegen haar plafond, en een kaart die alleen een waarde en een callback
/// aanraakt hoort er ook niet in.
class AiModuleCard extends StatelessWidget {
  const AiModuleCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  /// De formulierstand van `AiForm.enabled`, niet de voorkeur op schijf.
  final bool enabled;

  /// Wordt op web genegeerd: daar is de kaart zichtbaar maar uitgeschakeld,
  /// met dezelfde melding die het AI-tabblad op web toont.
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
              l10n.d('AI-assistentie'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'AI-assistentie is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'Hulp bij alt-teksten, beschrijvingen en formuleringen. Aanzetten verstuurt nog niets: dat gebeurt pas nadat je zelf een backend hebt gekozen en, bij een clouddienst, uitdrukkelijk hebt bevestigd. Een lokale backend verlaat je computer niet.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.auto_awesome_outlined),
          ),
          if (!web && enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                l10n.d(
                  'Kies de backend op het tabblad AI-assistentie. Zolang daar niets staat, gebeurt er niets.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wat er op het AI-tabblad boven de configuratie staat wanneer de module uit
/// staat.
///
/// Zonder deze regel leest het tabblad als een werkende instelling terwijl er
/// niets gebeurt — en dat is precies de knop die liegt. Ze wijst naar de plek
/// waar de schakelaar wél zit.
class AiModuleOffNotice extends StatelessWidget {
  const AiModuleOffNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.amber700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.l10n.d(
                'De module AI-assistentie staat uit, dus hier gebeurt niets. Zet hem aan bij Uitbreidingen. Wat je hieronder hebt ingesteld blijft staan.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.amber700),
            ),
          ),
        ],
      ),
    );
  }
}
