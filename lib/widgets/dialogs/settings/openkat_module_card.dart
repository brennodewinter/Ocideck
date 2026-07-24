import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/openkat_provider.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor OpenKAT op het tabblad Uitbreidingen (#767, #772).
///
/// OpenKAT is een specifiek product en een specifieke werkwijze. Wie een
/// presentatie komt maken heeft er niets aan, en hoort er dus ook geen
/// menu-item van te zien — vandaar een module, standaard uit.
///
/// De kaart wijst door naar Integraties in plaats van de mapkiezer hier te
/// herhalen: de schakelaar gaat over "hoort dit bij mijn werk", de map over
/// "waar staan mijn bestanden". Twee vragen, twee plekken.
class OpenKatModuleCard extends ConsumerWidget {
  const OpenKatModuleCard({super.key, this.onOpenIntegrations});

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
    final enabled = !web && ref.watch(openKatEnabledProvider);
    final directory = ref.watch(openKatDirectoryProvider);
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
                : (v) => ref.read(openKatProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('OpenKAT'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'De OpenKAT-import leest een map van schijf en is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'Leest een map met OpenKAT-rapportages (JSON) en bouwt er één managementoverzicht van: systemen, bevindingen per ernst, de langst openstaande punten en de trend over opeenvolgende metingen. Dezelfde actie op een bestaand OpenKAT-deck werkt het bij en laat uw eigen dia’s staan.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.radar_outlined),
          ),
          if (!web)
            _footer(context, l10n, enabled: enabled, directory: directory),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l10n, {
    required bool enabled,
    required String? directory,
  }) {
    // Uit, maar er staat een map: de vaste regel van dit project in beeld —
    // uitzetten maakt bestaand werk niet onbereikbaar.
    if (!enabled && directory != null) {
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
