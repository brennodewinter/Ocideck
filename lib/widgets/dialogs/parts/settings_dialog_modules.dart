// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Uitbreidingen" / modules tab). Instance
// methods live in an extension on _SettingsDialogState — same library, same
// members. See PENTEST_MIAUW.md §6: a lightweight module framework whose
// enable → provision → reveal pattern future domain extensions reuse.
part of '../settings_dialog.dart';

extension _SettingsModules on _SettingsDialogState {
  Widget _modulesTab() {
    final l10n = context.l10n;
    final module = ref.watch(secModuleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Uitbreidingen')),
        Text(
          l10n.d(
            'Optionele modules. Standaard uit; ze voegen niets toe aan de basis-app tot u ze inschakelt.',
          ),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
        const SizedBox(height: 16),
        _informationSecurityCard(l10n, module),
      ],
    );
  }

  Widget _informationSecurityCard(
    AppLocalizations l10n,
    SecModuleState module,
  ) {
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
            value: module.enabled,
            onChanged: module.busy ? null : (v) => _toggleSecModule(v),
            title: Text(
              l10n.d('Informatieveiligheid'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Pentestrapportage volgens MIAUW. Inschakelen haalt de referentiegegevens eenmalig op; daarna werkt de module offline.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.shield_moon_outlined),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _secModuleStatus(l10n, module),
          ),
        ],
      ),
    );
  }

  Widget _secModuleStatus(AppLocalizations l10n, SecModuleState module) {
    if (module.busy) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              module.revealed ? Icons.check_circle_outline : Icons.info_outline,
              size: 15,
              color: module.revealed ? AppTheme.accent : AppTheme.slate400,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _secModuleStatusText(l10n, module),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
        if (module.provisionedVersion != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(secModuleProvider.notifier).cleanUpCache(),
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: Text(l10n.d('Gegevens opschonen')),
            ),
          ),
        ],
      ],
    );
  }

  String _secModuleStatusText(AppLocalizations l10n, SecModuleState module) {
    if (module.revealed) return l10n.d('Gegevens lokaal beschikbaar');
    switch (module.lastStatus) {
      case SecProvisionStatus.noConsent:
        return l10n.d(
          'Geef eerst toestemming voor uitgaand verkeer bij Licentie en Privacy.',
        );
      case SecProvisionStatus.unsupportedPlatform:
        return l10n.d('Op het web nog niet beschikbaar');
      case SecProvisionStatus.allMirrorsFailed:
      case SecProvisionStatus.hashMismatch:
      case SecProvisionStatus.invalidPack:
        return l10n.d('Ophalen mislukt');
      case SecProvisionStatus.alreadyCached:
      case SecProvisionStatus.fetched:
      case SecProvisionStatus.imported:
      case null:
        return l10n.d('Nog niet opgehaald');
    }
  }

  Future<void> _toggleSecModule(bool enabled) async {
    final notifier = ref.read(secModuleProvider.notifier);
    if (enabled) {
      await notifier.enable();
    } else {
      await notifier.disable();
    }
  }
}
