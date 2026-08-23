import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/management_system.dart';
import '../../../services/management_system_catalog.dart';
import '../../../state/managementsysteem_provider.dart';
import '../../../theme/app_theme.dart';

/// Module card for Managementsysteem on Settings → Uitbreidingen
/// (ISO_MANAGEMENTSYSTEEM §5).
///
/// Off by default. Switching it on reveals the `controlStatus` slide type and
/// its picker tab, so a user can add the first one; a deck that already carries
/// such a slide reveals it regardless (the shared module contract).
class ManagementsysteemModuleCard extends ConsumerWidget {
  const ManagementsysteemModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(managementsysteemEnabledProvider);
    // The bundled ISO index is const data; show how much is on the device, the
    // same shape as the other module cards.
    final controlCount = [
      for (final s in ManagementSystemStandard.values)
        ManagementSystemCatalog.instance.controlsFor(s).length,
    ].fold<int>(0, (a, b) => a + b);
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
            onChanged: (v) =>
                ref.read(managementsysteemProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Managementsysteem'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Rapporteer de voortgang van een ISO-managementsysteem (27001/9001/42001): status per beheersmaatregel en een afgeleid voortgangsoverzicht. Standaard uit; zet de uitbreiding aan om het dia-type te gebruiken.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.fact_check_outlined),
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                l10n
                    .d(
                      'Module aan. De ISO-index is lokaal beschikbaar ({n} beheersmaatregelen over drie normen); alleen de nummers en korte titels, niet de normtekst.',
                    )
                    .replaceAll('{n}', '$controlCount'),
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
        ],
      ),
    );
  }
}
