// Module card for "Realtime samenwerken" on Settings → Uitbreidingen
// (SELF_ENCRYPTED_RELAY.md §6). Off by default; the whole route — the Samenwerken
// tab and the host/join actions — appears only once the module is on.
//
// The module is the umbrella; each transport has its own switch beneath it,
// because Jitsi and XMPP are coming.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/collaboration_provider.dart';
import '../../../theme/app_theme.dart';
import 'module_card.dart';

class CollaborationModuleCard extends ConsumerWidget {
  const CollaborationModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(collaborationEnabledProvider);
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: enabled,
            onChanged: (v) =>
                ref.read(collaborationProvider.notifier).setEnabled(v),
            title: Text(
              l10n.d('Realtime samenwerken'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Werk live samen aan een presentatie via een versleuteld doorgeefluik. Standaard uit. De inhoud wordt end-to-end versleuteld met OciDecks eigen sleutels; de server ziet alleen versleutelde gegevens.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.groups_outlined),
          ),
        ],
      ),
    );
  }
}
