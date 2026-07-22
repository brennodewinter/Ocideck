// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the "Uitbreidingen" / modules tab). Instance
// methods live in an extension on _SettingsDialogState — same library, same
// members. See PENTEST_MIAUW.md §6, but read it against the code: the module's
// reference data ships with the app, so this card is a toggle plus an inventory
// of what is already there — there is nothing to fetch, retry or clean up.
part of '../settings_dialog.dart';

extension _SettingsModules on _SettingsDialogState {
  Widget _modulesTab() {
    final l10n = context.l10n;
    final module = ref.watch(infoSafetyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Uitbreidingen')),
        Text(
          l10n.d(
            'Optionele modules. Standaard uit; ze blijven verborgen tot u ze inschakelt.',
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
    InfoSafetyState module,
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
            onChanged: (v) => _toggleInfoSafety(v),
            title: Text(
              l10n.d('Informatieveiligheid'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Rapportageslides en referentiedata voor informatieveiligheid: bevindingen, checklists, scope-matrices en ondertekening. Gestructureerd volgens MIAUW en breed inzetbaar voor pentests, audits en veiligheidsonderzoek. De referentiegegevens zitten in de app zelf, dus de module werkt meteen en volledig offline.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
            secondary: const Icon(Icons.shield_moon_outlined),
          ),
          if (module.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _infoSafetyStatus(l10n),
            ),
        ],
      ),
    );
  }

  Widget _infoSafetyStatus(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 15,
              color: AppTheme.accentFg,
            ),
            const SizedBox(width: 6),
            Expanded(
              // Selectable so the message can be copied (e.g. to report it)
              // rather than retyped.
              child: SelectableText(
                // Zeg érbij dat het lokaal blijft: dat is de vraag die de
                // gebruiker heeft ("wat is er opgehaald, en gaat er iets naar
                // buiten?"). De aantallen staan eronder.
                l10n.d(
                  'Gegevens lokaal beschikbaar — het opzoeken gebeurt op dit apparaat, er gaat niets naar buiten.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
        // Wát er lokaal ligt, in aantallen. "Gegevens lokaal beschikbaar" zei
        // niets: het liet in het midden of daar een volledige CWE-lijst achter
        // zat of een lege huls.
        const SizedBox(height: 16),
        _infoSafetyInventory(l10n),
      ],
    );
  }

  /// De inhoudsopgave van de referentiegegevens: hoeveel records er per
  /// catalogus daadwerkelijk bediend worden, met versie en herkomst.
  Widget _infoSafetyInventory(AppLocalizations l10n) {
    return FutureBuilder<List<ReferenceCatalog>>(
      future: _referenceInventory,
      builder: (context, snap) => _infoSafetyInventoryCard(
        l10n,
        // Tot de volledige CWE-lijst geladen is telt de snapshot de curated
        // bodem. Dat is een eerlijk tussengetal, geen leugen — en het staat er
        // maar een oogwenk.
        snap.data ?? InfoSafetyReferenceInventory.snapshot(),
      ),
    );
  }

  Widget _infoSafetyInventoryCard(
    AppLocalizations l10n,
    List<ReferenceCatalog> catalogs,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.iceBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Wat er lokaal beschikbaar is'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.slate600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in catalogs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${c.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      l10n.d(c.name),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.standard.isEmpty ? c.source : c.standard,
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

  Future<void> _toggleInfoSafety(bool enabled) async {
    final notifier = ref.read(infoSafetyProvider.notifier);
    if (enabled) {
      await notifier.enable();
    } else {
      await notifier.disable();
    }
  }
}
