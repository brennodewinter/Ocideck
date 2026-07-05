// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (security tab); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsSecurity on _SettingsDialogState {
  Widget _securityTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'Deze instellingen bepalen wat OciDeck vanaf het internet mag laden en welke sporen op dit apparaat achterblijven. Ze staan los van je privacyverklaring en toestemming, die je bij "Licentie en Privacy" vindt.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
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
}
