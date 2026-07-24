// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// Het tabblad Integraties: koppelingen met andere systemen, per systeem een
// kop. OpenKAT staat voorop en is voorlopig de enige — de kop per systeem is
// meteen het zoekanker, zodat een tweede integratie erbij zetten geen
// herindeling vraagt.
//
// Het tabblad hangt aan de OpenKAT-module (`navItems`): zolang OpenKAT de
// enige integratie is, is een leeg tabblad "Integraties" geen informatie maar
// ruis.
part of '../settings_dialog.dart';

extension _SettingsIntegrations on _SettingsDialogState {
  Widget _integrationsTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('OpenKAT')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hetzelfde beeld als bij de mascottes op Over OciDeck: dit is de
            // kat van OpenKAT, en hij maakt in één oogopslag duidelijk over
            // welk systeem deze sectie gaat.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/cat-keiko.jpg',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                // Decoratief naast een kop die het al zegt; een tweede keer
                // "OpenKAT" voorlezen helpt niemand.
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.d(
                  'Wijs de map aan waarin uw OpenKAT-rapportages (JSON) staan. De import leest die map en bouwt er één managementoverzicht van; staat de map hier ingesteld, dan hoeft u hem niet elke keer opnieuw te kiezen.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _openKatDirectoryField(l10n),
        const SizedBox(height: 10),
        Text(
          // Zeg wat er met de map gebeurt vóórdat iemand er een aanwijst. De
          // import leest élk .json-bestand in de map en zijn onderliggende
          // mappen; dat is een ander soort toegang dan "één bestand openen".
          l10n.d(
            'De import leest alleen; er wordt niets in deze map gewijzigd of verstuurd. Bestanden die geen OpenKAT-rapportage blijken, worden overgeslagen en in het importverslag benoemd.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
      ],
    );
  }

  Widget _openKatDirectoryField(AppLocalizations l10n) {
    final directory = ref.watch(openKatDirectoryProvider);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.iceBlue),
            ),
            child: Text(
              directory ?? l10n.d('Geen map gekozen'),
              style: TextStyle(
                fontSize: 12,
                color: directory == null ? AppTheme.slate500 : AppTheme.slate800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _pickOpenKatDirectory,
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          label: Text(l10n.d('Map kiezen…')),
        ),
        if (directory != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () =>
                ref.read(openKatProvider.notifier).setReportDirectory(null),
            icon: const Icon(Icons.close, size: 18),
            tooltip: l10n.d('Map wissen'),
          ),
        ],
      ],
    );
  }

  Future<void> _pickOpenKatDirectory() async {
    // Op web bestaat `getDirectoryPath` niet en geeft het stil null terug
    // (#150). De kaart op Uitbreidingen schakelt de module daar al uit, maar
    // een garantie die elders staat verdwijnt bij de eerstvolgende aanroeper.
    if (!supportsLocalProjectFolders) return;
    final l10n = context.l10n;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.d('Map met OpenKAT-rapportages kiezen'),
      initialDirectory:
          ref.read(openKatDirectoryProvider) ??
          ref.read(settingsProvider).homeDirectory,
    );
    if (!mounted || result == null) return;
    await ref.read(openKatProvider.notifier).setReportDirectory(result);
  }
}
