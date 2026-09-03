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
                style: TextStyle(fontSize: 11, color: AppTheme.slate600),
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
              backgroundColor: AppTheme.danger700,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Classificatie-handhaving hoort bij privacy en classificatie, niet
        // bij Algemeen — wie "TLP" of "classificatie" zoekt landt hier (#1955).
        _sectionTitle(l10n.d('Classificatie-handhaving')),
        _classificationEnforcementSection(l10n),
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
            // Bewust wachten op het wegschrijven vóór het sluiten. Mislukt het,
            // dan blijft de vlag op schijf op "toegestaan" staan: deze sessie
            // gedraagt zich als ingetrokken, maar de volgende start toont de
            // toestemmingspoort NIET meer. Dat stil laten gebeuren is het
            // ergste geval — de gebruiker denkt te hebben ingetrokken.
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final ok = await ref
                  .read(consentProvider.notifier)
                  .revokeConsent();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              navigator.pop();
              if (!ok) {
                showErrorSnackBar(
                  messenger,
                  l10n,
                  l10n.d(
                    'Intrekken is niet vastgelegd. Bij de volgende start geldt uw toestemming weer.',
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger700,
            ),
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
