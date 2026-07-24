import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/import_module_provider.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor Importeren op het tabblad Uitbreidingen (#772, B1).
///
/// Eén module voor álle bronnen waaruit OciDeck materiaal binnenhaalt. Voor de
/// gebruiker is "ik haal er iets van buiten in" één gedachte, niet een lijst
/// producten — een schakelaar per importeur zou het tabblad laten groeien met
/// keuzes die niemand los wil maken. Wat er vandaag onder valt staat in de
/// omschrijving; wat er als inhoud telt staat in [importerContentProviders].
///
/// De kaart wijst door naar Integraties in plaats van de mapkiezer hier te
/// herhalen: de schakelaar gaat over "hoort dit bij mijn werk", de instellingen
/// per bron over "waar staan mijn bestanden". Twee vragen, twee plekken.
class ImportModuleCard extends ConsumerWidget {
  const ImportModuleCard({super.key, this.onOpenIntegrations});

  /// Brengt de gebruiker naar het tabblad Integraties. Null laat de verwijzing
  /// weg — dan staat er geen knop die nergens heen gaat.
  final VoidCallback? onOpenIntegrations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Op web bestaat de mapkiezer niet en leest de scanner geen map van
    // schijf. Een werkende schakelaar zonder effect is de knop die liegt —
    // dus uitgeschakeld, met de reden ernaast, zoals de kaarten hiernaast.
    final web = !supportsLocalProjectFolders;
    final enabled = !web && ref.watch(importModuleEnabledProvider);
    final hasContent = ref.watch(importHasContentProvider);
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
            value: enabled,
            onChanged: web
                ? null
                : (v) => ref.read(importModuleProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Importeren'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'Importeren leest bestanden van schijf en is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'Materiaal uit andere systemen binnenhalen. Vandaag is dat OpenKAT: een map met rapportages (JSON) wordt één managementoverzicht — systemen, bevindingen per ernst, de langst openstaande punten en de trend over opeenvolgende metingen. Waar de bestanden staan, stelt u per systeem in onder Integraties.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.move_to_inbox_outlined),
          ),
          if (!web)
            _footer(l10n, enabled: enabled, hasContent: hasContent, ref: ref),
        ],
      ),
    );
  }

  Widget _footer(
    AppLocalizations l10n, {
    required bool enabled,
    required bool hasContent,
    required WidgetRef ref,
  }) {
    // Uit, maar er is al inhoud: de vaste regel van dit project in beeld —
    // uitzetten maakt bestaand werk niet onbereikbaar.
    if (!enabled && hasContent) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Text(
          l10n.d(
            'Er staat al een rapportagemap ingesteld; het invoerpunt blijft daarom bereikbaar, zodat een bestaand OpenKAT-deck bij te werken blijft.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
      );
    }
    if (!enabled) return const SizedBox.shrink();
    final directory = ref.watch(openKatDirectoryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              directory ??
                  l10n.d(
                    'Er is nog geen rapportagemap aangewezen; de import vraagt er dan elke keer om.',
                  ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onOpenIntegrations != null)
            TextButton(
              onPressed: onOpenIntegrations,
              child: Text(l10n.d('Naar Integraties')),
            ),
        ],
      ),
    );
  }
}
