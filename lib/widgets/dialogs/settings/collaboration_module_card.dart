// Module card for "Realtime samenwerken" on Settings → Uitbreidingen
// (SELF_ENCRYPTED_RELAY.md §6). Off by default; the whole route — the Samenwerken
// tab and the host/join actions — appears only once the module is on.
//
// The module is the umbrella; each transport has its own switch beneath it,
// because Jitsi and XMPP are coming. Today that is Matrix, whose switch defaults
// on so enabling the module works out of the box, and which can be turned off on
// its own without leaving the module.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/collaboration_provider.dart';
import '../../../theme/app_theme.dart';

class CollaborationModuleCard extends ConsumerWidget {
  const CollaborationModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(collaborationEnabledProvider);
    final matrixOn = ref.watch(matrixCollabEnabledProvider);
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
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.d('Manieren van verbinden'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate500,
                      letterSpacing: 0.6,
                    ),
                  ),
                  SwitchListTile(
                    value: matrixOn,
                    onChanged: (v) => ref
                        .read(collaborationProvider.notifier)
                        .setMatrixEnabled(v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.d('Matrix'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      l10n.d(
                        'Samenwerken via een Matrix-homeserver als doorgeefluik. Stel het account in bij het tabblad Samenwerken. (Jitsi en XMPP volgen.)',
                      ),
                      style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
