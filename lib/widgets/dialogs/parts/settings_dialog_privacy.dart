// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (privacy tab); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsPrivacy on _SettingsDialogState {
  Widget _privacyTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PrivacyStatementContent(),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Toestemming')),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.infoSurface,
            border: Border.all(color: AppTheme.userNotesBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d('U hebt al toegestemd in het gebruik van OciDeck.'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.d(
                  'U kunt uw toestemming op elk moment intrekken. Na intrekking moet u deze voorwaarden opnieuw accepteren.',
                ),
                style: const TextStyle(fontSize: 11, color: AppTheme.slate600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _revokeConsent,
            icon: const Icon(Icons.undo, size: 16),
            label: Text(l10n.d('Toestemming intrekken')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  void _revokeConsent() {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('Toestemming intrekken?')),
        content: Text(
          l10n.d(
            'Als u uw toestemming intrekt, moet u deze voorwaarden opnieuw accepteren wanneer u OciDeck opnieuw start.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(consentProvider.notifier).revokeConsent();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[600]),
            child: Text(
              l10n.d('Intrekken'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
