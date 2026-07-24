import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../platform/platform_features.dart';
import '../../../state/openkat_provider.dart';
import '../../../state/settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'settings_section_title.dart';

/// Het tabblad Integraties: koppelingen met andere systemen, per systeem een
/// kop. OpenKAT staat voorop en is voorlopig de enige — de kop per systeem is
/// meteen het zoekanker, zodat een tweede integratie erbij zetten geen
/// herindeling vraagt.
///
/// Het tabblad hangt aan de OpenKAT-module (`navItems`): zolang OpenKAT de
/// enige integratie is, is een leeg tabblad "Integraties" geen informatie maar
/// ruis.
///
/// Een losse widget en geen `part` van het instellingenvenster (#631): die
/// klasse zit tegen haar plafond, en dit paneel heeft niets van haar nodig —
/// het leest en schrijft alleen `openKatProvider`.
class OpenKatIntegrationPanel extends ConsumerWidget {
  const OpenKatIntegrationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('OpenKAT')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Keiko, het logo van OpenKAT: in één oogopslag duidelijk over welk
            // systeem deze sectie gaat. Bewust het logo en niet de mascottefoto
            // van Over OciDeck — dáár staan de katten van Brenno, hier staat het
            // merk waar we aan koppelen.
            //
            // `contain` en niet `cover`: dit is lijnwerk met witruimte eromheen,
            // en bijsnijden zou er oren af halen.
            Image.asset(
              'assets/images/openkat-logo.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              // Decoratief naast een kop die het al zegt; een tweede keer
              // "OpenKAT" voorlezen helpt niemand.
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.d(
                  'Wijs de map aan waarin uw OpenKAT-rapportages (JSON) staan. De import leest die map en bouwt er één managementoverzicht van; staat de map hier ingesteld, dan hoeft u hem niet elke keer opnieuw te kiezen.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DirectoryField(),
        const SizedBox(height: 10),
        Text(
          // Zeg wat er met de map gebeurt vóórdat iemand er een aanwijst. De
          // import leest élk .json-bestand in de map en zijn onderliggende
          // mappen; dat is een ander soort toegang dan "één bestand openen".
          l10n.d(
            'De import leest alleen; er wordt niets in deze map gewijzigd of verstuurd. Bestanden die geen OpenKAT-rapportage blijken, worden overgeslagen en in het importverslag benoemd.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
      ],
    );
  }
}

class _DirectoryField extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final directory = ref.watch(openKatDirectoryProvider);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.iceBlue),
            ),
            child: Text(
              directory ?? l10n.d('Geen map gekozen'),
              style: TextStyle(
                fontSize: 12,
                color: directory == null
                    ? AppTheme.slate500
                    : AppTheme.slate800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _pick(context, ref),
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: Text(l10n.d('Map kiezen…')),
        ),
        if (directory != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () =>
                ref.read(openKatProvider.notifier).setReportDirectory(null),
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.d('Map wissen'),
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    // Op web bestaat `getDirectoryPath` niet en geeft het stil null terug
    // (#150). De kaart op Uitbreidingen schakelt de module daar al uit, maar
    // een garantie die elders staat verdwijnt bij de eerstvolgende aanroeper.
    if (!supportsLocalProjectFolders) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    );
    if (result == null) return;
    await ref.read(openKatProvider.notifier).setReportDirectory(result);
  }
}
