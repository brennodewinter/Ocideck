import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/meeting_session_provider.dart';
import '../../../theme/app_theme.dart';

/// The Uitbreidingen-tab card for the optional video-calls module
/// (`docs/design/NATIVE_CALLS.md` §7). Same toggle shape as the other module
/// cards. Off by default; joining a meeting is added with the provider adapter in
/// a later step, so the copy says so plainly rather than promising a working call.
class VideoCallsModuleCard extends ConsumerWidget {
  const VideoCallsModuleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(videoCallsModuleProvider);
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
            : ref.read(videoCallsModuleProvider.notifier).setEnabled,
        title: Text(
          l10n.d('Videovergaderingen'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          l10n.d(
            'Neem deel aan videovergaderingen en presenteer vanuit OciDeck met een eigen interface: deelnemers naast uw slide, niet in het venster van een andere app. Bring-your-own-server (Jitsi of Matrix); OciDeck host niets en houdt de gespreksgegevens buiten AI. De aansluiting op een vergaderdienst volgt in een volgende versie.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        secondary: const Icon(Icons.video_camera_front_outlined),
      ),
    );
  }
}
