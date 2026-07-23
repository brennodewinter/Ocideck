import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/online_storage_provider.dart';
import '../../../theme/app_theme.dart';

/// De modulekaart voor Online opslag op het tabblad Uitbreidingen (#570).
///
/// Twee redenen om dit een module te maken, en de kaart zegt ze allebei.
/// Stilte: zonder de module ziet iemand die een presentatie komt maken geen
/// drie servertypes vóór de eerste dia er staat. En eerlijkheid over rijpheid:
/// een deel van de remote-opslagpaden heeft nog nooit een echte server gezien
/// (docs/design/VERIFICATION.md), en zo'n pad hoort bewust gekozen te worden —
/// de omschrijving benoemt dat in plaats van het te verzwijgen.
///
/// Anders dan de AI-kaart schrijft deze schakelaar rechtstreeks naar zijn
/// provider, net als de Informatieveiligheid-kaart ernaast: er is geen
/// formulier dat bij Opslaan zou terugschrijven, en een module aanzetten is
/// een handeling op zichzelf.
class OnlineStorageModuleCard extends ConsumerWidget {
  const OnlineStorageModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Op web valt er niets in of uit te schakelen: verbindingen toevoegen is
    // daar sowieso niet mogelijk (`supportsNetworkDeckSources`). Een werkende
    // schakelaar zonder effect is de knop die liegt — dus uitgeschakeld, met
    // de reden ernaast, zoals de AI-kaart hiernaast dat op web ook doet.
    final web = !supportsNetworkDeckSources;
    final enabled = !web && ref.watch(onlineStorageEnabledProvider);
    final revealed = ref.watch(onlineStorageRevealProvider);
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
                : (v) => ref.read(onlineStorageProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Online opslag'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              web
                  ? l10n.d(
                      'Online opslag is alleen beschikbaar in de desktopversie.',
                    )
                  : l10n.d(
                      'Presentaties openen uit en opslaan naar WebDAV, S3 en git-repository’s, met versiebeheer en samenwerken via een forge. Een deel van deze paden is tot nu toe vooral tegen testomgevingen beproefd; kies dit bewust. Zonder de module werkt alles lokaal gewoon: mappen, bestanden en pakketten.',
                    ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.cloud_outlined),
          ),
          if (!enabled && revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                // De vaste regel: uitzetten maakt bestaand werk niet
                // onbereikbaar. Wie verbindingen heeft houdt ze, inclusief het
                // git-menu en wachtend werk in de wachtrij; alleen níéuwe
                // online verbindingen toevoegen kan niet meer.
                l10n.d(
                  'Er staan al online verbindingen ingesteld; die blijven werken, net als wachtend werk in de wachtrij. Uit betekent alleen: geen nieuwe online verbindingen toevoegen.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }
}
