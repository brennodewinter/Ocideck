// The "unverified device" banner for a live realtime collaboration session
// (COLLABORATION Phase 2 "Blok A"; SELF_ENCRYPTED_RELAY.md §5.3). A clear,
// dismissible-by-verifying prompt above the workspace — never a cryptic "unable
// to decrypt". One tap opens the fingerprint comparison; it disappears once every
// device is pinned as verified.
//
// Self-hiding: it renders nothing unless a Matrix session is active *and* still
// has an unverified or mismatched peer, so a caller can include it
// unconditionally.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../state/collab_session_provider.dart';
import '../theme/app_theme.dart';
import 'dialogs/matrix_collab_dialogs.dart';

/// The provider-driven wrapper: decide whether the banner is warranted, then
/// delegate the look to [CollabVerifyBannerView]. Kept thin so the visible/hidden
/// decision and the presentation can be tested apart.
class CollabVerifyBanner extends ConsumerWidget {
  const CollabVerifyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collab = ref.watch(collabSessionProvider);
    final notifier = ref.read(collabSessionProvider.notifier);
    final visible =
        collab.isMatrix &&
        collab.isActive &&
        notifier.hasUnverifiedParticipants;
    return CollabVerifyBannerView(
      visible: visible,
      onVerify: () => showMatrixParticipantsDialog(
        context,
        AppLocalizations.of(context),
        participants: notifier.matrixParticipants,
        onPin: notifier.pinParticipant,
        onUnpin: notifier.unpinParticipant,
      ),
    );
  }
}

/// The banner's look, decoupled from the session so both states are
/// widget-testable. Renders nothing unless [visible].
class CollabVerifyBannerView extends StatelessWidget {
  const CollabVerifyBannerView({
    super.key,
    required this.visible,
    required this.onVerify,
  });

  final bool visible;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.amber600.withValues(alpha: 0.14),
      child: InkWell(
        onTap: onVerify,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: AppTheme.amber600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d(
                    'Nog niet elk apparaat in deze samenwerking is geverifieerd. Vergelijk de vingerafdrukken om zeker te weten met wie je werkt.',
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.d('Verifiëren'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.amber700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
