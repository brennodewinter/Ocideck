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
                'Rapportageslides en referentiedata voor informatiebeveiliging: bevindingen, checklists, scope-matrices en ondertekening. Gestructureerd volgens MIAUW en breed inzetbaar voor pentests, audits en beveiligingsonderzoek. Inschakelen haalt de referentiegegevens eenmalig op; daarna werkt de module offline.',
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
    final failed = _secModuleFailed(module);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              module.revealed
                  ? Icons.check_circle_outline
                  : failed
                  ? Icons.error_outline
                  : Icons.info_outline,
              size: 15,
              color: module.revealed
                  ? AppTheme.accent
                  : failed
                  ? AppTheme.amber700
                  : AppTheme.slate400,
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
        // While the module is on but nothing is revealed yet — e.g. no mirror
        // is reachable — offer the two recourses side by side: retry the fetch
        // (network back, or consent just granted) and, as fallback #3
        // (PENTEST_MIAUW §6), the manual local-file import so the module is
        // usable without a live host.
        if (module.enabled && !module.revealed) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              // Retry only makes sense where a fetch could succeed: skip it on
              // the web, which cannot reach a mirror at all.
              if (module.lastStatus != SecProvisionStatus.unsupportedPlatform)
                TextButton.icon(
                  onPressed: () => ref.read(secModuleProvider.notifier).retry(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.d('Opnieuw proberen')),
                ),
              TextButton.icon(
                onPressed: () => _importSecModulePack(),
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: Text(l10n.d('Pakket importeren')),
              ),
            ],
          ),
        ],
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

  /// Manual local-file import (PENTEST_MIAUW §6 fallback #3, the air-gapped
  /// path): pick a pack file and hand its bytes to the notifier, which verifies
  /// them against the pinned hash + inner manifest before caching. No consent is
  /// needed — nothing leaves the device. The status row reflects the outcome
  /// (revealed on success, a distinct failure message otherwise).
  Future<void> _importSecModulePack() async {
    final l10n = context.l10n;
    final picked = await FilePicker.pickFiles(
      dialogTitle: l10n.d('Gegevenspakket kiezen'),
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (!mounted || picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Kon het gekozen bestand niet lezen.'))),
      );
      return;
    }
    await ref.read(secModuleProvider.notifier).provisionFromBytes(bytes);
  }

  /// Whether the last provisioning attempt ended in a genuine failure (as
  /// opposed to a not-yet-tried / needs-consent / unsupported state), so the
  /// status row can flag it with a warning icon.
  bool _secModuleFailed(SecModuleState module) {
    if (module.revealed) return false;
    switch (module.lastStatus) {
      case SecProvisionStatus.allMirrorsFailed:
      case SecProvisionStatus.hashMismatch:
      case SecProvisionStatus.invalidPack:
        return true;
      case SecProvisionStatus.noConsent:
      case SecProvisionStatus.unsupportedPlatform:
      case SecProvisionStatus.alreadyCached:
      case SecProvisionStatus.fetched:
      case SecProvisionStatus.imported:
      case null:
        return false;
    }
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
      // Distinct failure reasons so the user sees what went wrong, not a bare
      // "Ophalen mislukt" (PENTEST_MIAUW §6 fallback chain).
      case SecProvisionStatus.allMirrorsFailed:
        return l10n.d(
          'Geen bron bereikbaar — de referentiegegevens konden bij geen enkele bron worden opgehaald. Probeer het opnieuw of importeer het pakket handmatig.',
        );
      case SecProvisionStatus.hashMismatch:
        return l10n.d(
          'De opgehaalde gegevens kwamen niet overeen met de verwachte vingerafdruk en zijn uit voorzorg geweigerd.',
        );
      case SecProvisionStatus.invalidPack:
        return l10n.d(
          'Het gegevenspakket was beschadigd of ongeldig en is daarom geweigerd.',
        );
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
