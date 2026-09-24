import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/integration_registry.dart';
import '../../../state/module_registry.dart';
import '../../../state/ociserve_provider.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'ociserve_module_card.dart';
import 'openkat_integration_panel.dart';
import 'settings_section_title.dart';

/// Het tabblad Integraties: koppelingen met andere systemen, elk met de
/// configuratie van die koppeling (#1158), plus de kaarten voor AI-assistentie
/// en de LibrePlan-connector (#2184) die het instellingenvenster meegeeft —
/// die twee schrijven hun formulier bij Opslaan weg in plaats van direct, dus
/// hun schakelaar en inhoud komen als widget binnen.
///
/// **Aanzetten hoort bij Uitbreidingen** (#2185): de schakelaar op een kaart
/// hier kan een koppeling alleen uitzetten. Staat hij uit, dan is hij
/// grijs met een verwijzing naar Uitbreidingen — een schakelaar die je niet
/// om kunt zetten zonder te zeggen waarom is een doodlopende straat.
///
/// De kaarten staan alfabetisch op hun vertaalde titel (#2187); de titels
/// komen uit `card_titles.dart`, dezelfde bron als de kaarten zelf gebruiken.
///
/// Een losse widget en geen `part` van het instellingenvenster (#631): die
/// klasse zit tegen haar plafond, en dit paneel leest alleen het
/// integratieregister.
class IntegrationsPanel extends ConsumerWidget {
  const IntegrationsPanel({super.key, this.aiCard, this.libreplanCard});

  /// De AI-assistentie-kaart, gebouwd door het venster omdat hij aan het
  /// formulier hangt dat bij Opslaan wordt weggeschreven.
  final Widget? aiCard;

  /// Idem voor de LibrePlan-connector.
  final Widget? libreplanCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final integrations = ref.watch(availableIntegrationsProvider);
    final cards = <({String title, Widget card})>[
      for (final entry in integrations)
        (
          title: integrationCardTitle(entry.id, l10n),
          card: _IntegrationCard(entry: entry),
        ),
      if (aiCard case final card?)
        (title: moduleCardTitle(ModuleId.ai, l10n), card: card),
      if (libreplanCard case final card?)
        (title: moduleCardTitle(ModuleId.libreplan, l10n), card: card),
    ];
    sortCardsByTitle(cards);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('Integraties')),
        Text(
          l10n.d(
            'Koppelingen met andere systemen. Elke koppeling staat standaard uit; aanzetten doet u bij Uitbreidingen, uitzetten kan hier.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 16),
        const _BulkControls(),
        for (final entry in cards) ...[const SizedBox(height: 12), entry.card],
      ],
    );
  }
}

/// De "alles uit"-bediening. Eén knop: aanzetten hoort bij Uitbreidingen
/// (#2185), dus "alles inschakelen" staat hier bewust niet meer. "Alles
/// uitschakelen" is uit zodra alles al uit staat — zo zegt de knop zelf of er
/// nog iets te doen valt.
class _BulkControls extends ConsumerWidget {
  const _BulkControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final integrations = ref.watch(availableIntegrationsProvider);
    final anyOn = ref.watch(anyIntegrationEnabledProvider);
    final eLearningLoading = ref.watch(
      ociServeProvider.select((state) => state.loading),
    );
    final web = isWebPlatform;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      // Een [Wrap]: bij 200% interface-tekst passen het opschrift en de knop
      // niet meer op één regel, dan vallen ze netjes onder elkaar in plaats
      // van de rij te laten overlopen.
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.d('Alle integraties'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate700,
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: !web && !eLearningLoading && anyOn
                ? () => _setAll(ref, integrations, false)
                : null,
            child: Text(l10n.d('Alles uitschakelen')),
          ),
        ],
      ),
    );
  }

  void _setAll(WidgetRef ref, List<IntegrationEntry> integrations, bool value) {
    for (final entry in integrations) {
      entry.setEnabled(ref, value);
    }
  }
}

/// Eén integratie als schakelkaart: de schakelaar met kop bovenaan, en de
/// instellingen eronder zodra de koppeling aan staat of er al inhoud is.
///
/// De schakelaar kan alleen úít: aanzetten hoort bij Uitbreidingen (#2185).
/// Staat de koppeling uit, dan is de schakelaar grijs en legt een regel uit
/// waar hij wel aangaat.
class _IntegrationCard extends ConsumerWidget {
  const _IntegrationCard({required this.entry});

  final IntegrationEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(entry.enabled);
    final revealed = ref.watch(entry.revealed);
    final loading =
        entry.id == IntegrationId.ociServe &&
        ref.watch(ociServeProvider.select((state) => state.loading));
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
            // Alleen uitzetten (#2185): wie aan staat kan hier uitschakelen,
            // wie uit staat vindt de schakelaar bij Uitbreidingen.
            onChanged: web || loading || !enabled
                ? null
                : (v) => entry.setEnabled(ref, v),
            title: Text(
              integrationCardTitle(entry.id, l10n),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _subtitle(l10n, web: web),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: _logo(),
          ),
          if (!web && revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _body(),
            )
          else if (!web && _hasContent(ref))
            // Uit, maar er is al inhoud: de vaste regel van dit project in
            // beeld.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                _contentNote(l10n),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
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
        ],
      ),
    );
  }

  bool _hasContent(WidgetRef ref) => switch (entry.id) {
    IntegrationId.openKat => ref.watch(openKatHasContentProvider),
    IntegrationId.ociServe => false,
  };

  String _subtitle(AppLocalizations l10n, {required bool web}) {
    if (web) {
      return switch (entry.id) {
        IntegrationId.openKat => l10n.d(
          'De OpenKAT-koppeling is alleen beschikbaar in de desktopversie.',
        ),
        IntegrationId.ociServe => l10n.d(
          'eLearning-aanmelding is alleen beschikbaar in de desktop-app, omdat de webversie geen veilige sleutelbos heeft.',
        ),
      };
    }
    return switch (entry.id) {
      IntegrationId.openKat => l10n.d(
        'Lees OpenKAT-rapportages in als één managementoverzicht — vanuit een map of vanaf een server.',
      ),
      IntegrationId.ociServe => l10n.d(
        'Volg opleidingen uit uw eLearning-omgeving. Cursusbestanden openen alleen in afspeelmodus; voortgang wordt alleen na aanmelden gesynchroniseerd.',
      ),
    };
  }

  String _contentNote(AppLocalizations l10n) => switch (entry.id) {
    IntegrationId.openKat => l10n.d(
      'Er staat al een OpenKAT-bron ingesteld; de koppeling blijft daarom bereikbaar, zodat een bestaand OpenKAT-deck bij te werken blijft.',
    ),
    IntegrationId.ociServe => '',
  };

  Widget _logo() => switch (entry.id) {
    IntegrationId.openKat => Image.asset(
      'assets/images/openkat-logo.png',
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
    IntegrationId.ociServe => const Icon(Icons.school_outlined),
  };

  Widget _body() => switch (entry.id) {
    IntegrationId.openKat => const OpenKatIntegrationBody(),
    IntegrationId.ociServe => const OciServeIntegrationBody(),
  };
}
