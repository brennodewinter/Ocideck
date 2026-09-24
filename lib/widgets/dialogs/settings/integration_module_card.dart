// De inschakelkaart van een integratie op het tabblad Uitbreidingen (#2185).
//
// Aanzetten hoort bij Uitbreidingen: daar staan alle schakelaars die een
// onderdeel activeren. De koppeling instellen (server, map, aanmelden) doet
// de gebruiker op Integraties — de kaart hier verwijst daarnaar zodra hij
// aan staat. Uitzetten mag op beide plekken: een schakelaar die terug kan is
// nooit een blokkade.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/integration_registry.dart';
import '../../../state/ociserve_provider.dart';
import '../../../theme/app_theme.dart';
import 'card_titles.dart';
import 'module_card.dart';

/// Inschakelkaart voor één integratie uit [integrationRegistry].
class IntegrationModuleCard extends ConsumerWidget {
  const IntegrationModuleCard({super.key, required this.entry});

  final IntegrationEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(entry.enabled);
    final loading =
        entry.id == IntegrationId.ociServe &&
        ref.watch(ociServeProvider.select((s) => s.loading));
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: loading ? null : (v) => entry.setEnabled(ref, v),
            title: Text(
              integrationCardTitle(entry.id, l10n),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _subtitle(l10n),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.hub_outlined),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                l10n.d('Instellen doet u op het tabblad Integraties.'),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(AppLocalizations l10n) => switch (entry.id) {
    IntegrationId.openKat => l10n.d(
      'Lees OpenKAT-rapportages in als één managementoverzicht — vanuit een map of vanaf een server.',
    ),
    IntegrationId.ociServe => l10n.d(
      'Volg opleidingen uit uw eLearning-omgeving. Cursusbestanden openen alleen in afspeelmodus; voortgang wordt alleen na aanmelden gesynchroniseerd.',
    ),
  };
}
