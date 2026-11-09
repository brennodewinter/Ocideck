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
        // De kaarten komen letterlijk uit de registers: modulekaarten uit
        // `moduleRegistry` (#570) — een module zonder kaart valt om op de
        // switch hieronder in plaats van stil te ontbreken — plus een
        // inschakelkaart per integratie (#2185: aanzetten hoort hier). De
        // getoonde volgorde is alfabetisch op de vertaalde titel (#2187), uit
        // `card_titles.dart` zodat sleutel en opschrift dezelfde bron delen.
        for (final (index, entry) in _sortedModuleCards(l10n).indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          entry.card,
        ],
      ],
    );
  }

  /// De kaarten op dit tabblad als (titel, kaart)-paren, gesorteerd op de
  /// vertaalde titel.
  List<({String title, Widget card})> _sortedModuleCards(
    AppLocalizations l10n,
  ) {
    final cards = <({String title, Widget card})>[
      for (final entry in moduleRegistry)
        (
          title: moduleCardTitle(entry.id, l10n),
          card: switch (entry.id) {
            ModuleId.ai => _aiAssistCard(l10n),
            ModuleId.onlineStorage => const OnlineStorageModuleCard(),
            ModuleId.imports => const ImportModuleCard(),
            ModuleId.procesverbetering => const ProcesverbeteringModuleCard(),
            ModuleId.collaboration => const CollaborationModuleCard(),
            ModuleId.videoCalls => const VideoCallsModuleCard(),
            ModuleId.assetRights => const AssetRightsModuleCard(),
            ModuleId.managementsysteem => const ManagementsysteemModuleCard(),
            ModuleId.elearning => const ElearningModuleCard(),
            ModuleId.forms => const FormsModuleCard(),
            ModuleId.transcription => const TranscriptionModuleCard(),
            ModuleId.libreplan => LibreplanModuleCard(
              enabled: _libreplanEnabled,
              onChanged: (v) => _rebuild(() => _libreplanEnabled = v),
            ),
          },
        ),
      // De inschakelkaarten van integraties horen bij "aanzetten", dus op
      // Uitbreidingen. Op web zijn ze allemaal desktop-only — daar tonen is
      // dan ruis in plaats van een keuze.
      if (!isWebPlatform)
        for (final entry in integrationRegistry)
          (
            title: integrationCardTitle(entry.id, l10n),
            card: IntegrationModuleCard(entry: entry),
          ),
    ];
    sortCardsByTitle(cards);
    return cards;
  }

  /// De modulekaart voor AI-assistentie (#731) — [AiModuleCard], een losse
  /// widget omdat de dialoogklasse tegen haar plafond zit. De callback raakt
  /// het formulier en niet de voorkeuren; waarom staat op de widget zelf.
  Widget _aiAssistCard(AppLocalizations l10n) {
    return AiModuleCard(
      enabled: _ai.enabled,
      onChanged: (v) => _rebuild(() {
        _ai.enabled = v;
        _ai.testOk = null;
        _ai.testMessage = null;
      }),
    );
  }
}
