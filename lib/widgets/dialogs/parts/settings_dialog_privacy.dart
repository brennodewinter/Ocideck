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
        _sectionTitle(l10n.d('Online media')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Online media toestaan'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Sta het live laden toe van afbeeldingen en video\'s via een URL en van YouTube/Vimeo-embeds. Standaard uit voor je privacy en veiligheid.',
            ),
            style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: ref.watch(settingsProvider.select((s) => s.allowRemoteMedia)),
          onChanged: (value) =>
              ref.read(settingsProvider.notifier).setAllowRemoteMedia(value),
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Herstelbestanden')),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.d(
              'Crash-herstelbestanden bevatten de volledige inhoud van je presentaties in platte tekst. Ze worden na 7 dagen automatisch opgeruimd; hier kun je ze direct wissen.',
            ),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _clearRecoveryFiles,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            label: Text(l10n.d('Herstelbestanden nu wissen')),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Toestemming')),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            border: Border.all(color: const Color(0xFFBFDBFE)),
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

  Future<void> _clearRecoveryFiles() async {
    final l10n = context.l10n;
    final removed = await RecoveryService().discardAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? l10n.d('Er waren geen herstelbestanden.')
              : '$removed ${l10n.d('herstelbestand(en) gewist.')}',
        ),
      ),
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
