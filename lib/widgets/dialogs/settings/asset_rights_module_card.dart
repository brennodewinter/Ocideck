import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/asset_rights_module_provider.dart';
import '../../../theme/app_theme.dart';

class AssetRightsModuleCard extends ConsumerWidget {
  const AssetRightsModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(assetRightsModuleProvider);
    return Material(
      color: AppTheme.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        value: state.enabled,
        onChanged: state.loading
            ? null
            : ref.read(assetRightsModuleProvider.notifier).setEnabled,
        title: Text(
          l10n.d('Afbeeldingsrechten'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l10n.d(
            'Controleert afbeeldingen lokaal op mogelijke auteursrechtelijke risico’s. Nieuwe repositoryafbeeldingen en de volledige assetpool kunnen worden gescand; een beheerder handelt waarschuwingen af. Dit is een signalering, geen juridisch oordeel, en er worden geen afbeeldingen naar derden gestuurd.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        secondary: const Icon(Icons.copyright_outlined),
      ),
    );
  }
}
